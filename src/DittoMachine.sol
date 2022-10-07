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
import {Oracle} from "./Oracle.sol";
import {DittoMachineSvg} from "./DittoMachineSvg.sol";

/**
 * @title NFT derivative exchange inspired by the SALSA concept.
 * @author calvbore
 * @notice A user may self assess the price of an NFT and purchase a token representing
 * the right to ownership when it is sold via this contract. Anybody may buy the
 * token for a higher price and force a transfer from the previous owner to the new buyer.
 */
contract DittoMachine is ERC721, ERC721TokenReceiver, ERC1155TokenReceiver, CloneList, BlockRefund, Oracle {
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

    uint internal constant FLOOR_ID = uint(0xfddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9);

    // ensure that CloneShape can always be casted to int128.
    // change the type to ensure this?
    uint128 internal constant BASE_TERM = 2**18; // 262144
    uint128 internal constant MIN_FEE = 32;
    uint128 internal constant DNOM = 2**16 - 1; // 65535
    uint128 internal constant MIN_AMOUNT_FOR_NEW_CLONE = BASE_TERM + (BASE_TERM * MIN_FEE / DNOM); // 262272

    ////////////// STATE VARIABLES //////////////

    // variables essential to calculating auction/price information for each cloneId
    struct CloneShape {
        uint tokenId;
        address ERC721Contract;
        address ERC20Contract;
        uint8 heat;
        bool floor;
        uint128 worth;
        uint128 term;
    }

    // tracks balance of subsidy for a specific cloneId
    mapping(uint => uint128) public cloneIdToSubsidy;

    // hash protoId with the index placement to get cloneId
    mapping(uint => CloneShape) public cloneIdToShape;

    // maps clone to the index it is placed at in a linked list
    mapping(uint => uint) public cloneIdToIndex;

    // non transferrable vouchers for reward tokens
    mapping(uint => bool) public voucherValidity;

    constructor() ERC721("Ditto", "DTO") {}

    ///////////////////////////////////////////
    ////////////// URI FUNCTIONS //////////////
    ///////////////////////////////////////////

    function tokenURI(uint id) public view override returns (string memory) {
        require(ownerOf[id] != address(0), "!owner");
        CloneShape memory shape = cloneIdToShape[id];

        return DittoMachineSvg.tokenURI(id, shape.ERC20Contract, shape.ERC721Contract, ownerOf[id], shape.tokenId, shape.floor);
    }

    // Visibility is `public` to enable it being called by other contracts for composition.
    function renderTokenById(uint _tokenId) public pure returns (string memory) {
        return DittoMachineSvg.renderTokenById(_tokenId);
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
        uint _tokenId,
        address _ERC20Contract,
        uint128 _amount,
        bool floor,
        uint index // index at which to mint the clone
    ) external returns (uint cloneId, uint protoId) {
        // ensure enough funds to do some math on
        if (_amount < MIN_AMOUNT_FOR_NEW_CLONE) revert AmountInvalidMin();
        if (floor && _tokenId != FLOOR_ID) revert InvalidFloorId();

        // calculate protoId by hashing identifiying information, precursor to cloneId
        protoId = uint(keccak256(abi.encodePacked(
            _ERC721Contract,
            _tokenId,
            _ERC20Contract,
            floor
        )));

        // hash protoId and index to get cloneId
        cloneId = uint(keccak256(abi.encodePacked(protoId, index)));

        uint protoIdHead = protoIdToIndexHead[protoId];
        if (index == protoIdHead) {
            Oracle.write(protoId, cloneIdToShape[cloneId].worth);
        }

        address curOwner = ownerOf[cloneId];

        if (curOwner == address(0)) {
            // check that index references have been set
            if (!validIndex(protoId, index)) {
                // if references have not been set by a previous clone this clone cannot be minted
                revert IndexInvalid();
            }
            uint floorId = uint(keccak256(abi.encodePacked(
                _ERC721Contract,
                FLOOR_ID,
                _ERC20Contract,
                true
            )));
            floorId = uint(keccak256(abi.encodePacked(floorId, index)));

            uint128 subsidy = (_amount * MIN_FEE / DNOM); // with current constants subsidy <= _amount
            uint128 value = _amount - subsidy;

            if (!(cloneId == floorId || ownerOf[floorId] == address(0))) {
                // check price of floor clone to get price floor
                uint128 minAmount = cloneIdToShape[floorId].worth;
                if (value < minAmount) revert AmountInvalid();
            }
            if (index != protoIdHead) { // check cloneId at prior index
                // prev <- index
                uint elderId = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index])));
                // check value is less than clone closer to the index head
                if (value > cloneIdToShape[elderId].worth) revert AmountInvalid();
            }

            _mint(msg.sender, cloneId);

            cloneIdToShape[cloneId] = CloneShape({
                tokenId: _tokenId,
                ERC721Contract: _ERC721Contract,
                ERC20Contract: _ERC20Contract,
                worth: value,
                term: uint128(block.timestamp) + BASE_TERM,
                heat: 1,
                floor: floor
            });
            CloneList.pushListTail(protoId, index);
            cloneIdToIndex[cloneId] = index;
            cloneIdToSubsidy[cloneId] += subsidy;
            BlockRefund._setBlockRefund(cloneId, subsidy);

            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );

        } else {

            CloneShape memory cloneShape = cloneIdToShape[cloneId];

            uint128 feeRefund = BlockRefund._getBlockRefund(cloneId); // check if bids have occured within the current block
            bool isFeeRefundZero = feeRefund == 0;
            uint128 minAmount = _getMinAmount(cloneShape, !isFeeRefundZero);
            // calculate subsidy and worth values
            uint128 subsidy = (_amount * (MIN_FEE * ((isFeeRefundZero ? 1 : 0) + cloneShape.heat))) / DNOM;

            // scoping to prevent "stack too deep" errors
            {
                uint128 value = _amount - subsidy; // will be applied to cloneShape.worth
                if (index != protoIdHead) { // check cloneId at prior index
                    // prev <- index
                    uint elderId = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index])));
                    if (value > cloneIdToShape[elderId].worth) revert AmountInvalid();
                }
                if (value < minAmount) revert AmountInvalid();

                // reduce heat relative to amount of time elapsed by auction
                if (isFeeRefundZero) { // if call is in same block as another keep the current heat
                    if (cloneShape.term > block.timestamp) {
                        uint128 termLength;
                        unchecked{ termLength = BASE_TERM + TimeCurve.calc(cloneShape.heat); }
                        uint128 elapsed = uint128(block.timestamp) - (cloneShape.term - termLength); // current time - time when the current term started
                        // add 1 to current heat so heat is not stuck at low value with anything but extreme demand for a clone
                        uint128 cool = (cloneShape.heat+1) * elapsed / termLength;
                        unchecked {
                            cloneShape.heat = (cool > cloneShape.heat) ? 1 : uint8(Math.min(cloneShape.heat - cool + 1, type(uint8).max));
                        }
                    } else {
                        cloneShape.heat = 1;
                    }
                }
                issueVoucher(curOwner, cloneId, protoId, value);

                // calculate new clone term values
                CloneShape storage shapeS = cloneIdToShape[cloneId];
                shapeS.heat = cloneShape.heat; // does not inherit heat of floor id
                shapeS.worth = value;
                unchecked {
                    shapeS.term = uint128(block.timestamp) + BASE_TERM + TimeCurve.calc(cloneShape.heat);
                }
            }

            // paying required funds to this contract
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );

            BlockRefund._setBlockRefund(cloneId, subsidy);
            // half of fee goes into subsidy pool, half to previous clone owner
            // if in same block subsidy is not split and replaces refunded fees.
            // subtract subsidy refund from subsidy pool.
            cloneIdToSubsidy[cloneId] += (isFeeRefundZero ? (subsidy >> 1) : subsidy) - feeRefund;

            SafeTransferLib.safeTransfer( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                curOwner,
                // previous clone value + half of subsidy sent to prior clone owner
                // clone's worth is refunded here
                // fees are completely refunded if in same block as another bid
                (cloneShape.worth + (isFeeRefundZero ? ((subsidy >> 1) + (subsidy & 1)) : feeRefund) )
            );
            // force transfer from current owner to new highest bidder
            forceTransferFrom(curOwner, msg.sender, cloneId); // EXTERNAL CALL
        }
    }

    /**
     * @notice unwind a position in a clone.
     * @param protoId specifies the clone to be burned.
     * @dev will refund funds held in a position, subsidy will remain for sellers in the future.
     */
    function dissolve(uint protoId, uint cloneId) external {
        uint index = cloneIdToIndex[cloneId];
        address owner = ownerOf[cloneId];
        if (!(msg.sender == owner
                || msg.sender == getApproved[cloneId]
                || isApprovedForAll[owner][msg.sender])) {
            revert NotAuthorized();
        }

        // move its subsidy to the next clone in the linked list even if it's not minted yet.
        uint nextCloneId = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexToAfter[protoId][index])));
        // invariant: cloneId != nextCloneId
        cloneIdToSubsidy[nextCloneId] += cloneIdToSubsidy[cloneId];
        delete cloneIdToSubsidy[cloneId];

        uint128 worth = cloneIdToShape[cloneId].worth;
        address ERC20Contract = cloneIdToShape[cloneId].ERC20Contract;

        if (index == protoIdToIndexHead[protoId]) {
            Oracle.write(protoId, worth);
        }

        popListIndex(protoId, index);

        delete cloneIdToShape[cloneId];
        delete cloneIdToIndex[cloneId];

        _burn(cloneId);
        SafeTransferLib.safeTransfer( // EXTERNAL CALL
            ERC20(ERC20Contract),
            owner,
            worth
        );
    }

    function getMinAmountForCloneTransfer(uint cloneId) external view returns (uint128) {
        if(ownerOf[cloneId] == address(0)) {
            return MIN_AMOUNT_FOR_NEW_CLONE;
        }
        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        bool intraBlock = BlockRefund._getBlockRefund(cloneId) != 0;
        uint128 _minAmount = _getMinAmount(cloneShape, intraBlock);
        // calculate fee multiplier with heat, if in active bidding block do not add 1.
        uint128 minFeeHeat = (MIN_FEE * ((intraBlock ? 0:1) + cloneShape.heat));
        // calculate fee needed from min value. Do not devide my DNOM as to not loose percision.
        uint128 feePercent = _minAmount * minFeeHeat;
        // calculate inverse percentage of fee amount
        uint128 feePortion = (feePercent * DNOM) / (DNOM - minFeeHeat) / DNOM;
        return _minAmount + feePortion;
    }

    function observe(uint protoId, uint128[] calldata secondsAgos) external view returns (uint128[] memory cumulativePrices) {
        uint cloneId = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId])));
        return Oracle.observe(protoId, secondsAgos, cloneIdToShape[cloneId].worth);
    }

    /**
     * @notice computes the minimum amount required to buy a clone.
     * @notice it does not take into account the protocol fee or the subsidy.
     * @param cloneShape clone for which to compute the minimum amount.
     * @dev only use it for a minted clone.
     */
    function _getMinAmount(CloneShape memory cloneShape, bool intraBlock) internal view returns (uint128) {
        uint floorId = uint(keccak256(abi.encodePacked(
            cloneShape.ERC721Contract,
            FLOOR_ID,
            cloneShape.ERC20Contract,
            true
        )));
        floorId = uint(keccak256(abi.encodePacked(floorId, protoIdToIndexHead[floorId])));
        uint128 floorPrice = cloneIdToShape[floorId].worth;

        if (intraBlock) {
            // return clone or floor worth without dutch auction pricing if there has been a bid in the current blcok
            return floorPrice > cloneShape.worth ? floorPrice : cloneShape.worth;
        }

        uint128 timeLeft = 0;
        unchecked {
            if (cloneShape.term > block.timestamp) {
                timeLeft = cloneShape.term - uint128(block.timestamp);
            }
        }
        uint128 termLength;
        unchecked { termLength = BASE_TERM + TimeCurve.calc(cloneShape.heat); }
        uint128 clonePrice = cloneShape.worth + (cloneShape.worth * timeLeft / termLength);
        // return floor price if greater than clone auction price
        return floorPrice > clonePrice ? floorPrice : clonePrice;
    }

    function issueVoucher(address to, uint cloneId, uint protoId, uint128 value) private {
        uint8 heat = cloneIdToShape[cloneId].heat;
        uint128 worth = cloneIdToShape[cloneId].worth;
        uint128 term = cloneIdToShape[cloneId].term;
        uint128 termLength;
        unchecked { termLength = BASE_TERM + TimeCurve.calc(heat); }

        bool isIndexHead = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId]))) == cloneId;
        uint voucher = uint(keccak256(abi.encodePacked(
            isIndexHead,
            cloneId, // encodes: protoId (nft contract, token id, erc20 contract, if floor), index
            to,
            heat,
            worth, // old value of the clone
            value, // new value of the clone
            term - termLength,
            uint128(block.timestamp)
        )));

        voucherValidity[voucher] = true;
    }

    ////////////////////////////////////////////////
    ////////////// RECEIVER FUNCTIONS //////////////
    ////////////////////////////////////////////////

    // NOTE: msg.sender is the underlying ERC721/ERC1155 contract
    // i.e. the contract of the token being received.
    function onTokenReceived(
        address from,
        uint id,
        address ERC20Contract,
        bool floor,
        bool isERC1155
    ) private {
        uint protoId = uint(keccak256(abi.encodePacked(
            msg.sender, // ERC721 or ERC1155 Contract address
            id,
            ERC20Contract,
            false
        )));
        uint cloneId = uint(keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId])));

        uint flotoId = uint(keccak256(abi.encodePacked( // floorId + protoId = flotoId
            msg.sender,
            FLOOR_ID,
            ERC20Contract,
            true
        )));
        uint floorId = uint(keccak256(abi.encodePacked(flotoId, protoIdToIndexHead[flotoId])));

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
        if (ownerOf[cloneId] == address(0)) revert CloneNotFound();

        Oracle.write(protoId, cloneIdToShape[cloneId].worth);

        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        uint subsidy = cloneIdToSubsidy[cloneId];
        address owner = ownerOf[cloneId];
        delete cloneIdToShape[cloneId];
        delete cloneIdToSubsidy[cloneId];
        _burn(cloneId);

        // send useful data along with safe transfer to sontracts
        bytes memory data = abi.encode(
            // NFT contract address is sent as msg.sender with function call
            // NFT ID is sent with function call
            ERC20Contract,
            floor,
            protoIdToIndexHead[protoId], // index
            owner,
            cloneShape.worth,
            subsidy
        );

        // token can only be sold to the clone at the index head
        popListHead(protoId);

        if (isERC1155) {
            if (ERC1155(msg.sender).balanceOf(address(this), id) < 1) revert NFTNotReceived();
            ERC1155(msg.sender).safeTransferFrom(address(this), owner, id, 1, data);
        } else {
            if (ERC721(msg.sender).ownerOf(id) != address(this)) revert NFTNotReceived();
            ERC721(msg.sender).safeTransferFrom(address(this), owner, id, data);
        }

        if (IERC165(msg.sender).supportsInterface(_INTERFACE_ID_ERC2981)) {
            (address receiver, uint royaltyAmount) = IERC2981(msg.sender).royaltyInfo(
                cloneShape.tokenId,
                cloneShape.worth
            );
            if (royaltyAmount > 0 && royaltyAmount < type(uint128).max) {
                cloneShape.worth -= uint128(royaltyAmount);
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
        uint id,
        bytes calldata data
    ) external returns (bytes4) {
        (address ERC20Contract, bool floor) = abi.decode(data, (address, bool));

        onTokenReceived(from, id, ERC20Contract, floor, false);

        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address from,
        uint id,
        uint amount,
        bytes calldata data
    ) external returns (bytes4) {
        if (amount != 1) revert AmountInvalid();
        // address ERC1155Contract = msg.sender;
        (address ERC20Contract, bool floor) = abi.decode(data, (address, bool));

        onTokenReceived(from, id, ERC20Contract, floor, true);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint[] calldata ids,
        uint[] calldata amounts,
        bytes calldata data
    ) external returns (bytes4) {
        (address[] memory ERC20Contracts, bool[] memory floors) = abi.decode(data, (address[], bool[]));
        require(ERC20Contracts.length == amounts.length);
        require(floors.length == amounts.length);
        unchecked {
            for (uint i=0; i < amounts.length; ++i) {
                if (amounts[i] != 1) revert AmountInvalid();
                onTokenReceived(from, ids[i], ERC20Contracts[i], floors[i], true);
            }
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
        uint id
    ) private {
        // no ownership or approval checks cause we're forcing a change of ownership
        if (from != ownerOf[id]) revert FromInvalid();

        unchecked {
            --balanceOf[from];
            ++balanceOf[to];
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

}

/**
 * @title A funtion to support token ejection
 * @notice function is called if a contract must do accounting on a forced transfer
 */
interface IERC721TokenEjector {

    function onERC721Ejected(
        address operator,
        address to,
        uint id,
        bytes calldata data
    ) external returns (bytes4);

}
