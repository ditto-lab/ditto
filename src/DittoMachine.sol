pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {ERC721, ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {ERC1155, ERC1155TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base64} from 'base64-sol/base64.sol';
import {CloneList} from "./CloneList.sol";
import {TimeCurve} from "./TimeCurve.sol";
import {BlockRefund} from "./BlockRefund.sol";

/**
 * @title NFT derivative exchange inspired by the SALSA concept.
 * @author calvbore
 * @notice A user may self assess the price of an NFT and purchase a token representing
 * the right to ownership when it is sold via this contract. Anybody may buy the
 * token for a higher price and force a transfer from the previous owner to the new buyer.
 */
contract DittoMachine is ERC721, ERC721TokenReceiver, ERC1155TokenReceiver, CloneList, BlockRefund {
    /**
     * @notice Insufficient bid for purchasing a clone.
     * @dev thrown when the number of erc20 tokens sent is lower than
     *      the number of tokens required to purchase a clone.
     */
    error AmountInvalid();
    error AmountInvalidMin();
    error InvalidFloorId();
    error CloneNotFound();
    error FromInvalid();
    error IndexInvalid();
    error NFTNotReceived();
    error NotAuthorized();

    ////////////// CONSTANT VARIABLES //////////////

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    uint256 public constant FLOOR_ID = uint256(0xfddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9);

    // ensure that CloneShape can always be casted to int128.
    // change the type to ensure this?
    uint256 public constant BASE_TERM = 2**18;
    uint256 public constant MIN_FEE = 32;
    uint256 public constant DNOM = 2**16 - 1;
    uint256 public constant MIN_AMOUNT_FOR_NEW_CLONE = BASE_TERM + (BASE_TERM * MIN_FEE / DNOM);

    ////////////// STATE VARIABLES //////////////

    // variables essential to calculating auction/price information for each cloneId
    struct CloneShape {
        uint256 tokenId;
        uint256 worth;
        address ERC721Contract;
        address ERC20Contract;
        uint8 heat;
        bool floor;
        uint256 term;
    }

    // tracks balance of subsidy for a specific cloneId
    mapping(uint256 => uint256) public cloneIdToSubsidy;

    // protoId cumulative price for TWAP
    mapping(uint256 => uint256) public protoIdToCumulativePrice;
    // lat timestamp recorded for protoId TWAP
    mapping(uint256 => uint256) public protoIdToTimestampLast;

    // hash protoId with the index placement to get cloneId
    mapping(uint256 => CloneShape) public cloneIdToShape;

    // maps clone to the index it is placed at in a linked list
    mapping(uint256 => uint256) public cloneIdToIndex;

    constructor() ERC721("Ditto", "DTO") { }

    ///////////////////////////////////////////
    ////////////// URI FUNCTIONS //////////////
    ///////////////////////////////////////////

    function tokenURI(uint256 id) public view override returns (string memory) {
        CloneShape memory cloneShape = cloneIdToShape[id];

        if (!cloneShape.floor) {
            // if clone is not a floor return underlying token uri
            try ERC721(cloneShape.ERC721Contract).tokenURI(cloneShape.tokenId) returns (string memory uri) {
                return uri;
            } catch {
                return ERC1155(cloneShape.ERC721Contract).uri(cloneShape.tokenId);
            }
        } else {

            string memory _name = string(abi.encodePacked('Ditto Floor #', Strings.toString(id)));

            string memory description = string(abi.encodePacked(
                'This Ditto represents the floor price of tokens at ',
                Strings.toHexString(uint160(cloneIdToShape[id].ERC721Contract), 20)
            ));

            string memory image = Base64.encode(bytes(generateSVGofTokenById(id)));

            return string(abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                           '{"name":"',
                            _name,
                           '", "description":"',
                           description,
                           '", "attributes": [{"trait_type": "Underlying NFT", "value": "',
                           Strings.toHexString(uint160(cloneIdToShape[id].ERC721Contract), 20),
                           '"},{"trait_type": "tokenId", "value": ',
                           Strings.toString(cloneShape.tokenId),
                           '}], "owner":"',
                           Strings.toHexString(uint160(ownerOf[id]), 20),
                           '", "image": "',
                           'data:image/svg+xml;base64,',
                           image,
                           '"}'
                        )
                    )
                )
            ));
        }
    }

    function generateSVGofTokenById(uint256 _tokenId) internal pure returns (string memory) {
        string memory svg = string(abi.encodePacked(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">',
            renderTokenById(_tokenId),
          '</svg>'
        ));

        return svg;
    }

    // Visibility is `public` to enable it being called by other contracts for composition.
    function renderTokenById(uint256 _tokenId) public pure returns (string memory) {
        string memory hexColor = toHexString(uint24(_tokenId), 3);
        return string(abi.encodePacked(
            '<rect width="100" height="100" rx="15" style="fill:#', hexColor, '" />',
            '<g id="face" transform="matrix(0.531033,0,0,0.531033,-279.283,-398.06)">',
              '<g transform="matrix(0.673529,0,0,0.673529,201.831,282.644)">',
                '<circle cx="568.403" cy="815.132" r="3.15"/>',
              '</g>',
              '<g transform="matrix(0.673529,0,0,0.673529,272.214,282.644)">',
                '<circle cx="568.403" cy="815.132" r="3.15"/>',
              '</g>',
              '<g transform="matrix(1,0,0,1,0.0641825,0)">',
                '<path d="M572.927,854.4C604.319,859.15 635.71,859.166 667.102,854.4" style="fill:none;stroke:black;stroke-width:0.98px;"/>',
              '</g>',
            '</g>'
        ));
    }

    // same as inspired from @openzeppelin/contracts/utils/Strings.sol except that it doesn't add "0x" as prefix.
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);

        for (uint256 i = 2 * length; i > 0; --i) {
            buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /////////////////////////////////////////////////
    //////////////// CLONE FUNCTIONS ////////////////
    /////////////////////////////////////////////////

    /**
     * @notice open or buy out a future on a particular NFT or floor perp.
     * @notice fees will be taken from purchases and set aside as a subsidy to encourage sellers.
     * @param _ERC721Contract address of selected NFT smart contract.
     * @param _tokenId selected NFT token id.
     * @param _ERC20Contract address of the ERC20 contract used for purchase.
     * @param _amount address of ERC20 tokens used for purchase.
     * @param floor selector determining if the purchase is for a floor perp.
     * @dev creates an ERC721 representing the specified future or floor perp, reffered to as clone.
     * @dev a clone id is calculated by hashing ERC721Contract, _tokenId, _ERC20Contract, and floor params.
     * @dev if floor == true, FLOOR_ID will replace _tokenId in cloneId calculation.
     */
    function duplicate(
        address _ERC721Contract,
        uint256 _tokenId,
        address _ERC20Contract,
        uint256 _amount,
        bool floor,
        uint256 index // index at which to mint the clone
    ) external returns (
        uint256, // cloneId
        uint256 // protoId
    ) {
        // ensure enough funds to do some math on
        if (_amount < MIN_AMOUNT_FOR_NEW_CLONE) {
            revert AmountInvalidMin();
        }

        if (floor && _tokenId != FLOOR_ID) {
            revert InvalidFloorId();
        }

        // calculate protoId by hashing identifiying information, precursor to cloneId
        uint256 protoId = uint256(keccak256(abi.encodePacked(
            _ERC721Contract,
            _tokenId,
            _ERC20Contract,
            floor
        )));
        // hash protoId and index to get cloneId
        uint256 cloneId = uint256(keccak256(abi.encodePacked(protoId, index)));

        _updatePrice(protoId);

        if (ownerOf[cloneId] == address(0)) {
            // check that index references have been set
            if (!validIndex(protoId, index)) {
                // if references have not been set by a previous clone this clone cannot be minted
                revert IndexInvalid();
            }
            uint256 floorId = uint256(keccak256(abi.encodePacked(
                _ERC721Contract,
                FLOOR_ID,
                _ERC20Contract,
                true
            )));
            floorId = uint256(keccak256(abi.encodePacked(floorId, index)));

            uint256 subsidy = (_amount * MIN_FEE / DNOM); // with current constants subsidy <= _amount
            uint256 value = _amount - subsidy;

            if (cloneId != floorId && ownerOf[floorId] != address(0)) {
                // check price of floor clone to get price floor
                uint256 minAmount = cloneIdToShape[floorId].worth;
                if (value < minAmount) {
                    revert AmountInvalid();
                }
            }
            if (index != protoIdToIndexHead[protoId]) { // check cloneId at prior index
                // prev <- index
                uint256 elderId = uint256(keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index])));
                if (value > cloneIdToShape[elderId].worth) {
                    revert AmountInvalid(); // check value is less than clone closer to the index head
                }
            }

            _mint(msg.sender, cloneId);

            cloneIdToShape[cloneId] = CloneShape(
                _tokenId,
                value,
                _ERC721Contract,
                _ERC20Contract,
                1,
                floor,
                block.timestamp + BASE_TERM
            );
            pushListTail(protoId, index);
            cloneIdToIndex[cloneId] = index;
            cloneIdToSubsidy[cloneId] += subsidy;
            _setBlockRefund(cloneId, subsidy);

            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );

        } else {

            CloneShape memory cloneShape = cloneIdToShape[cloneId];
            uint256 heat = cloneShape.heat;

            uint256 feeRefund = _getBlockRefund(cloneId); // check if bids have occured within the current block
            uint256 minAmount = _getMinAmount(cloneShape, feeRefund != 0);
            // calculate subsidy and worth values
            uint256 subsidy = (_amount * (MIN_FEE * ((feeRefund == 0 ? 1 : 0) + heat))) / DNOM;

            // scoping to prevent "stack too deep" errors
            {
                uint256 value = _amount - subsidy; // will be applied to cloneShape.worth
                if (index != protoIdToIndexHead[protoId]) { // check cloneId at prior index
                    // prev <- index
                    uint256 elderId = uint256(keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index])));
                    if (value > cloneIdToShape[elderId].worth) {
                        revert AmountInvalid();
                    }
                }
                if (value < minAmount) {
                    revert AmountInvalid();
                }

                // reduce heat relative to amount of time elapsed by auction
                if (feeRefund == 0) { // if call is in same block as another keep the current heat
                    if (cloneShape.term > block.timestamp) {
                        uint256 termLength = BASE_TERM + TimeCurve.calc(heat);
                        uint256 elapsed = block.timestamp - (cloneShape.term - termLength); // current time - time when the current term started
                        // add 1 to current heat so heat is not stuck at low value with anything but extreme demand for a clone
                        uint256 cool = (heat+1) * elapsed / termLength;
                        heat = (cool > heat) ? 1 : Math.min(heat - cool + 1, type(uint8).max);
                    } else {
                        heat = 1;
                    }
                }
                // calculate new clone term values
                cloneIdToShape[cloneId].worth = value;
                cloneIdToShape[cloneId].heat = uint8(heat); // does not inherit heat of floor id
                cloneIdToShape[cloneId].term = block.timestamp + BASE_TERM + TimeCurve.calc(heat);
            }

            // paying required funds to this contract
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );
            // buying out the previous clone owner

            address curOwner = ownerOf[cloneId];

            // subtract subsidy refund from subsidy pool
            cloneIdToSubsidy[cloneId] -= feeRefund;

            {
                _setBlockRefund(cloneId, subsidy);
            }
            // half of fee goes into subsidy pool, half to previous clone owner
            // if in same block subsidy is not split and replaces refunded fees
            cloneIdToSubsidy[cloneId] += feeRefund == 0 ? (subsidy >> 1) : subsidy;

            SafeTransferLib.safeTransfer( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                curOwner,
                // previous clone value + half of subsidy sent to prior clone owner
                // clone's worth is refunded here
                // fees are completely refunded if in same block as another bid
                (cloneShape.worth + (feeRefund == 0 ? ((subsidy >> 1) + (subsidy & 1)) : feeRefund) )
            );
            // force transfer from current owner to new highest bidder
            forceTransferFrom(curOwner, msg.sender, cloneId); // EXTERNAL CALL
        }

        return (cloneId, protoId);
    }

    /**
     * @notice unwind a position in a clone.
     * @param protoId specifies the clone to be burned.
     * @dev will refund funds held in a position, subsidy will remain for sellers in the future.
     */
    function dissolve(uint256 protoId, uint256 cloneId) external {
        uint256 index = cloneIdToIndex[cloneId];
        if (!(msg.sender == ownerOf[cloneId]
                || msg.sender == getApproved[cloneId]
                || isApprovedForAll[ownerOf[cloneId]][msg.sender])) {
            revert NotAuthorized();
        }

        // move its subsidy to the next clone in the linked list even if it's not minted yet.
        uint256 nextCloneId = uint256(keccak256(abi.encodePacked(protoId, protoIdToIndexToAfter[protoId][index])));
        // invariant: cloneId != nextCloneId
        cloneIdToSubsidy[nextCloneId] += cloneIdToSubsidy[cloneId];
        delete cloneIdToSubsidy[cloneId];

        CloneShape memory cloneShape = cloneIdToShape[cloneId];

        _updatePrice(protoId);

        popListIndex(protoId, index);

        address owner = ownerOf[cloneId];

        delete cloneIdToShape[cloneId];

        _burn(cloneId);
        SafeTransferLib.safeTransfer( // EXTERNAL CALL
            ERC20(cloneShape.ERC20Contract),
            owner,
            cloneShape.worth
        );
    }

    function getMinAmountForCloneTransfer(uint256 cloneId) external view returns (uint256) {
        if(ownerOf[cloneId] == address(0)) {
            return MIN_AMOUNT_FOR_NEW_CLONE;
        }
        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        bool intraBlock = _getBlockRefund(cloneId) != 0;
        uint256 _minAmount = _getMinAmount(cloneShape, intraBlock);
        // calculate fee ultiplier with heat, if in active bidding block do not add 1.
        uint256 minFeeHeat = (MIN_FEE * ((intraBlock ? 0:1) + cloneShape.heat));
        // calculate fee needed from min value. Do not devide my DNOM as to not loose percision.
        uint256 feePercent = _minAmount * minFeeHeat;
        // calculate inverse percentage of fee amount
        uint256 feePortion = (feePercent * DNOM) / (DNOM - minFeeHeat) / DNOM;
        return _minAmount + feePortion;
    }

    /**
     * @notice computes the minimum amount required to buy a clone.
     * @notice it does not take into account the protocol fee or the subsidy.
     * @param cloneShape clone for which to compute the minimum amount.
     * @dev only use it for a minted clone.
     */
    function _getMinAmount(CloneShape memory cloneShape, bool intraBlock) internal view returns (uint256) {
        uint256 floorId = uint256(keccak256(abi.encodePacked(
            cloneShape.ERC721Contract,
            FLOOR_ID,
            cloneShape.ERC20Contract,
            true
        )));
        floorId = uint256(keccak256(abi.encodePacked(floorId, protoIdToIndexHead[floorId])));
        uint256 floorPrice = cloneIdToShape[floorId].worth;

        if (intraBlock) {
            // return clone or floor worth without dutch auction pricing if there has been a bid in the current blcok
            return floorPrice > cloneShape.worth ? floorPrice : cloneShape.worth;
        }

        uint256 timeLeft = 0;
        unchecked {
            if (cloneShape.term > block.timestamp) {
                timeLeft = cloneShape.term - block.timestamp;
            }
        }
        uint256 termLength = BASE_TERM + TimeCurve.calc(cloneShape.heat);
        uint256 clonePrice = cloneShape.worth + (cloneShape.worth * timeLeft / termLength);
        // return floor price if greater than clone auction price
        return floorPrice > clonePrice ? floorPrice : clonePrice;
    }

    ////////////////////////////////////////////////
    ////////////// RECEIVER FUNCTIONS //////////////
    ////////////////////////////////////////////////

    function onTokenReceived(
        address from,
        address tokenContract,
        uint256 id,
        address ERC20Contract,
        bool floor,
        bool isERC1155
    ) private {
        uint256 protoId = uint256(keccak256(abi.encodePacked(
            tokenContract, // ERC721 or ERC1155 Contract address
            id,
            ERC20Contract,
            false
        )));
        uint256 cloneId = uint256(keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId])));

        uint256 flotoId = uint256(keccak256(abi.encodePacked( // floorId + protoId = flotoId
            tokenContract,
            FLOOR_ID,
            ERC20Contract,
            true
        )));
        uint256 floorId = uint256(keccak256(abi.encodePacked(flotoId, protoIdToIndexHead[flotoId])));

        if (
            floor ||
            ownerOf[cloneId] == address(0) ||
            cloneIdToShape[floorId].worth > cloneIdToShape[cloneId].worth
        ) {
            // if cloneId is not active, check floor clone
            cloneId = floorId;
            protoId = flotoId;
        }
        // if no cloneId is active, revert
        if (ownerOf[cloneId] == address(0)) {
            revert CloneNotFound();
        }

        _updatePrice(protoId);

        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        uint256 subsidy = cloneIdToSubsidy[cloneId];
        address owner = ownerOf[cloneId];
        delete cloneIdToShape[cloneId];
        delete cloneIdToSubsidy[cloneId];
        _burn(cloneId);
        // token can only be sold to the clone at the index head
        popListHead(protoId);

        if (isERC1155) {
            if (ERC1155(tokenContract).balanceOf(address(this), id) < 1) {
                revert NFTNotReceived();
            }
            ERC1155(tokenContract).safeTransferFrom(address(this), owner, id, 1, "");
        } else {
            if (ERC721(tokenContract).ownerOf(id) != address(this)) {
                revert NFTNotReceived();
            }
            ERC721(tokenContract).safeTransferFrom(address(this), owner, id);
        }

        if (IERC165(tokenContract).supportsInterface(_INTERFACE_ID_ERC2981)) {
            (address receiver, uint256 royaltyAmount) = IERC2981(tokenContract).royaltyInfo(
                cloneShape.tokenId,
                cloneShape.worth
            );
            if (royaltyAmount > 0) {
                cloneShape.worth -= royaltyAmount;
                SafeTransferLib.safeTransfer(
                    ERC20(ERC20Contract),
                    receiver,
                    royaltyAmount
                );
            }
        }
        SafeTransferLib.safeTransfer(
            ERC20(ERC20Contract),
            from,
            cloneShape.worth + subsidy
        );
    }

    /**
     * @dev will allow NFT sellers to sell by safeTransferFrom-ing directly to this contract.
     * @param data will contain ERC20 address that the seller wishes to sell for
     * allows specifying selling for the floor price
     * @return returns received selector
     */
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        (address ERC20Contract, bool floor) = abi.decode(data, (address, bool));

        onTokenReceived(from, msg.sender /*ERC721 contract address*/, id, ERC20Contract, floor, false);

        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes4) {
        if (amount != 1) {
            revert AmountInvalid();
        }
        // address ERC1155Contract = msg.sender;
        (address ERC20Contract, bool floor) = abi.decode(data, (address, bool));

        onTokenReceived(from, msg.sender /*ERC1155 contract address*/, id, ERC20Contract, floor, true);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external returns (bytes4) {
        for (uint256 i=0; i < amounts.length; i++) {
            if (amounts[i] != 1) {
                revert AmountInvalid();
            }
        }
        // address[] memory ERC20Contracts = new address[](ids.length);
        // bool[] memory floors = new bool[](ids.length);
        (address[] memory ERC20Contracts, bool[] memory floors) = abi.decode(data, (address[], bool[]));

        for (uint256 i=0; i < ids.length; i++) {
            onTokenReceived(from, msg.sender /*ERC1155 contract address*/, ids[i], ERC20Contracts[i], floors[i], true);
        }

        return this.onERC1155BatchReceived.selector;
    }

    ///////////////////////////////////////////////
    ////////////// PRIVATE FUNCTIONS //////////////
    ///////////////////////////////////////////////

    /**
     * @notice transfer clone without owner/approval checks.
     * @param from current clone owner.
     * @param to transfer recipient.
     * @param id clone id.
     * @dev if the current clone owner implements ERC721Ejected, we call it.
     *    we will still transfer the clone if that call reverts.
     *    only to be called from `duplicate()` function to transfer to the next bidder.
     *    `to` != address(0) is assumed and is not explicitly check.
     *    `onERC721Received` is not called on the receiver, the bidder is responsible for accounting.
     */
    function forceTransferFrom(
        address from,
        address to,
        uint256 id
    ) private {
        // no ownership or approval checks cause we're forcing a change of ownership
        if (from != ownerOf[id]) {
            revert FromInvalid();
        }

        unchecked {
            balanceOf[from]--;
            balanceOf[to]++;
        }

        ownerOf[id] = to;

        delete getApproved[id];
        emit Transfer(from, to, id);

        // give contracts the option to account for a forced transfer.
        // if they don't implement the ejector we're stll going to move the token.
        if (from.code.length != 0) {
            // not sure if this is exploitable yet?
            try IERC721TokenEjector(from).onERC721Ejected{gas: 30000}(address(this), to, id, "") {} // EXTERNAL CALL
            catch {}
        }
    }

    // @dev: this function is not prod ready
    function _updatePrice(uint256 protoId) internal {
        uint256 cloneId = uint256(keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId])));
        uint256 timeElapsed = block.timestamp - protoIdToTimestampLast[protoId];
        if (timeElapsed > 0) {
            unchecked  {
                protoIdToCumulativePrice[protoId] += cloneIdToShape[cloneId].worth * timeElapsed;
            }
        }
        protoIdToTimestampLast[protoId] = block.timestamp;
    }

}

/**
 * @title A funtion to support token ejection
 * @notice function is called if a contract must do accounting on a forced transfer
 */
interface IERC721TokenEjector {

    function onERC721Ejected(
        address operator,
        address to,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);

}
