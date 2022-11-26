pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC1155D, IERC1155, IERC1155Receiver} from "./ERC1155D.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
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
contract DittoMachine is ERC1155D, IERC721Receiver, IERC1155Receiver, CloneList, BlockRefund, Oracle {
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

    constructor() {}

    ///////////////////////////////////////////
    ////////////// URI FUNCTIONS //////////////
    ///////////////////////////////////////////

    function uri(uint id) public view override returns (string memory) {
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
     * @param _amount amount of ERC20 tokens used for purchase.
     * @param floor selector determining if the purchase is for a floor perp.
     * @param index index at which to mint the clone.
     * @dev creates an ERC721 representing the specified future or floor perp, referred to as clone.
     * @dev a clone id is calculated by hashing ERC721Contract, _tokenId, _ERC20Contract, and floor params.
     * @dev if floor == true, _tokenId has to be FLOOR_ID, otherwise it reverts.
     */
    function duplicate(
        address receiver,
        address _ERC721Contract,
        uint _tokenId,
        address _ERC20Contract,
        uint128 _amount,
        bool floor,
        uint index
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
        // cloneId = keccak256(abi.encodePacked(protoId, index))
        assembly ("memory-safe") {
            mstore(0, protoId)
            mstore(0x20, index)
            cloneId := keccak256(0, 0x40)
        }

        bool isIndexHead = index == protoIdToIndexHead[protoId];
        if (isIndexHead) {
            Oracle.write(protoId, cloneIdToShape[cloneId].worth);
        }

        address curOwner = ownerOf[cloneId];

        if (curOwner == address(0)) {
            // check that index references have been set
            if (!validIndex(protoId, index)) {
                // if references have not been set by a previous clone this clone cannot be minted
                revert IndexInvalid();
            }

            uint128 subsidy = (_amount * MIN_FEE / DNOM); // with current constants subsidy <= _amount
            uint128 value = _amount - subsidy;

            if (!floor) {
                // computing floorId
                uint floorId = uint(keccak256(abi.encodePacked(
                    _ERC721Contract,
                    FLOOR_ID,
                    _ERC20Contract,
                    true
                )));
                // floorId = keccak256(abi.encodePacked(floorId, index))
                assembly ("memory-safe") {
                    mstore(0, floorId)
                    mstore(0x20, index)
                    floorId := keccak256(0, 0x40)
                }

                if (ownerOf[floorId] != address(0)) {
                    // check price of floor clone to get price floor
                    uint128 minAmount = cloneIdToShape[floorId].worth;
                    if (value < minAmount) revert AmountInvalid();
                }
            }
            if (!isIndexHead) { // check cloneId at prior index
                // prev <- index
                // elderId = keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index]))
                uint elderId = protoIdToIndexToPrior[protoId][index];
                assembly ("memory-safe") {
                    mstore(0, protoId)
                    mstore(0x20, elderId)
                    elderId := keccak256(0, 0x40)
                }
                // check value is less than clone closer to the index head
                if (value > cloneIdToShape[elderId].worth) revert AmountInvalid();
            }


            cloneIdToShape[cloneId] = CloneShape({
                tokenId: _tokenId,
                ERC721Contract: _ERC721Contract,
                ERC20Contract: _ERC20Contract,
                worth: value,
                term: uint128(block.timestamp) + BASE_TERM,
                heat: 1,
                floor: floor
            });
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
            _mintSingle(receiver, cloneId); // EXTERNAL CALL

        } else {

            CloneShape memory cloneShape = cloneIdToShape[cloneId];
            uint128 heat = cloneShape.heat;

            uint128 feeRefund = _getBlockRefund(cloneId); // check if bids have occured within the current block

            // scoping to prevent "stack too deep" errors
            {
                // calculate subsidy and worth values
                uint128 subsidy = (_amount * (MIN_FEE * ((feeRefund == 0 ? 1 : 0) + heat))) / DNOM;
                uint128 value = _amount - subsidy; // will be applied to cloneShape.worth
                if (!isIndexHead) { // check cloneId at prior index
                    // prev <- index
                    // elderId = keccak256(abi.encodePacked(protoId, protoIdToIndexToPrior[protoId][index]));
                    uint elderId = protoIdToIndexToPrior[protoId][index];
                    assembly ("memory-safe") {
                        mstore(0, protoId)
                        mstore(0x20, elderId)
                        elderId := keccak256(0, 0x40)
                    }
                    if (value > cloneIdToShape[elderId].worth) revert AmountInvalid();
                }
                uint128 termLength = BASE_TERM + TimeCurve.calc(heat);
                if (value < _getMinAmount(cloneShape, termLength, feeRefund != 0)) revert AmountInvalid();

                // reduce heat relative to amount of time elapsed by auction
                if (feeRefund == 0) { // if call is in same block as another keep the current heat
                    feeRefund = subsidy >> 1;
                    if (cloneShape.term > block.timestamp) {
                        uint128 elapsed = uint128(block.timestamp) - (cloneShape.term - termLength); // current time - time when the current term started
                        // add 1 to current heat so heat is not stuck at low value with anything but extreme demand for a clone
                        uint128 cool = (heat+1) * elapsed / termLength;
                        heat = (cool > heat) ? 1 : uint128(Math.min(heat - cool + 1, type(uint8).max));
                    } else {
                        heat = 1;
                    }
                    termLength = BASE_TERM + TimeCurve.calc(heat);
                }

                _setBlockRefund(cloneId, subsidy);
                // half of fee goes into subsidy pool, half to previous clone owner
                // if in same block subsidy is not split and replaces refunded fees
                cloneIdToSubsidy[cloneId] += subsidy - feeRefund;

                issueVoucher(curOwner, cloneId, cloneShape, termLength, isIndexHead, value);

                // calculate new clone term values
                cloneIdToShape[cloneId].heat = uint8(heat); // does not inherit heat of floor id
                cloneIdToShape[cloneId].worth = value;
                cloneIdToShape[cloneId].term = uint128(block.timestamp) + termLength;
            }

            // paying required funds to this contract
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );

            SafeTransferLib.safeTransfer( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                curOwner,
                // previous clone value + half of subsidy sent to prior clone owner
                // clone's worth is refunded here
                // fees are completely refunded if in same block as another bid
                cloneShape.worth + feeRefund
            );
            // force transfer from current owner to new highest bidder
            forceSafeTransferFrom(curOwner, receiver, cloneId); // EXTERNAL CALL
        }
    }

    /**
     * @notice unwind a position in a clone.
     * @param protoId specifies the clone to be burned.
     * @dev will refund funds held in a position, subsidy will remain for sellers in the future.
     */
    function dissolve(uint protoId, uint cloneId) external returns (bool) {
        uint index = cloneIdToIndex[cloneId];
        address owner = ownerOf[cloneId];
        if (!(msg.sender == owner
                || isApprovedForAll[owner][msg.sender])) {
            revert NotAuthorized();
        }

        // move its subsidy to the next clone in the linked list even if it's not minted yet.
        // nextCloneId = keccak256(abi.encodePacked(protoId, protoIdToIndexToAfter[protoId][index]))
        uint nextCloneId = protoIdToIndexToAfter[protoId][index];
        assembly ("memory-safe") {
            mstore(0, protoId)
            mstore(0x20, nextCloneId)
            nextCloneId := keccak256(0, 0x40)
        }
        // invariant: cloneId != nextCloneId
        cloneIdToSubsidy[nextCloneId] += cloneIdToSubsidy[cloneId];
        delete cloneIdToSubsidy[cloneId];

        uint128 worth = cloneIdToShape[cloneId].worth;

        if (index == protoIdToIndexHead[protoId]) {
            Oracle.write(protoId, worth);
        }

        popListIndex(protoId, index);

        delete cloneIdToShape[cloneId];
        delete cloneIdToIndex[cloneId];

        _burn(owner, cloneId);
        SafeTransferLib.safeTransfer( // EXTERNAL CALL
            ERC20(cloneIdToShape[cloneId].ERC20Contract),
            owner,
            worth
        );
        return true;
    }

    function getMinAmountForCloneTransfer(uint cloneId) external view returns (uint128) {
        if(ownerOf[cloneId] == address(0)) {
            return MIN_AMOUNT_FOR_NEW_CLONE;
        }
        bool intraBlock = _getBlockRefund(cloneId) != 0;
        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        uint128 termLength = BASE_TERM + TimeCurve.calc(cloneShape.heat);
        uint128 _minAmount = _getMinAmount(cloneShape, termLength, intraBlock);
        // calculate fee multiplier with heat, if in active bidding block do not add 1.
        uint128 minFeeHeat = (MIN_FEE * ((intraBlock ? 0:1) + cloneShape.heat));
        // calculate fee needed from min value. Do not devide my DNOM as to not loose percision.
        uint128 feePercent = _minAmount * minFeeHeat;
        // calculate inverse percentage of fee amount
        uint128 feePortion = (feePercent * DNOM) / (DNOM - minFeeHeat) / DNOM;
        return _minAmount + feePortion;
    }

    function observe(uint protoId, uint128[] calldata secondsAgos) external view returns (uint128[] memory cumulativePrices) {
        // cloneId = keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId]))
        uint cloneId = protoIdToIndexHead[protoId];
        assembly ("memory-safe") {
            mstore(0, protoId)
            mstore(0x20, cloneId)
            cloneId := keccak256(0, 0x40)
        }

        return Oracle.observe(protoId, secondsAgos, cloneIdToShape[cloneId].worth);
    }

    /**
     * @notice computes the minimum amount required to buy a clone.
     * @notice it does not take into account the protocol fee or the subsidy.
     * @param cloneShape clone for which to compute the minimum amount.
     * @dev only use it for a minted clone.
     */
    function _getMinAmount(CloneShape memory cloneShape, uint128 termLength, bool intraBlock) internal view returns (uint128) {
        uint floorId = uint(keccak256(abi.encodePacked(
            cloneShape.ERC721Contract,
            FLOOR_ID,
            cloneShape.ERC20Contract,
            true
        )));
        {
            uint head = protoIdToIndexHead[floorId];
            // floorId = keccak256(abi.encodePacked(floorId, head))
            assembly ("memory-safe") {
                mstore(0, floorId)
                mstore(0x20, head)
                floorId := keccak256(0, 0x40)
            }
        }
        uint128 floorPrice = cloneIdToShape[floorId].worth;

        if (intraBlock) {
            // return clone or floor worth without dutch auction pricing if there has been a bid in the current blcok
            return floorPrice > cloneShape.worth ? floorPrice : cloneShape.worth;
        }

        uint128 clonePrice = cloneShape.worth;
        if (cloneShape.term > block.timestamp) {
            uint128 timeLeft;
            unchecked {
                timeLeft = cloneShape.term - uint128(block.timestamp);
            }
            clonePrice += clonePrice * timeLeft / termLength;
        }
        // return floor price if greater than clone auction price
        return floorPrice > clonePrice ? floorPrice : clonePrice;
    }

    function issueVoucher(address to, uint cloneId, CloneShape memory shape, uint128 termLength, bool isIndexHead, uint128 value) private {

        uint voucher = uint(keccak256(abi.encodePacked(
            isIndexHead,
            cloneId, // encodes: protoId (nft contract, token id, erc20 contract, if floor), index
            to,
            shape.heat,
            shape.worth, // old value of the clone
            value, // new value of the clone
            shape.term - termLength,
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
        bool floor
    ) private returns (address, bytes memory) {
        uint protoId = uint(keccak256(abi.encodePacked(
            msg.sender, // ERC721 or ERC1155 Contract address
            id,
            ERC20Contract,
            false
        )));
        // cloneId = keccak256(abi.encodePacked(protoId, protoIdToIndexHead[protoId]))
        uint cloneId = protoIdToIndexHead[protoId];
        assembly ("memory-safe") {
            mstore(0, protoId)
            mstore(0x20, cloneId)
            cloneId := keccak256(0, 0x40)
        }

        {
            uint flotoId = uint(keccak256(abi.encodePacked( // floorId + protoId = flotoId
                msg.sender,
                FLOOR_ID,
                ERC20Contract,
                true
            )));
            // floorId = keccak256(abi.encodePacked(flotoId, protoIdToIndexHead[flotoId]))
            uint floorId = protoIdToIndexHead[flotoId];
            assembly ("memory-safe") {
                mstore(0, flotoId)
                mstore(0x20, floorId)
                floorId := keccak256(0, 0x40)
            }

            if (
                floor ||
                ownerOf[cloneId] == address(0) ||
                cloneIdToShape[floorId].worth > cloneIdToShape[cloneId].worth
            ) {
                // if cloneId is not active, check floor clone
                cloneId = floorId;
                protoId = flotoId;
            }
        }
        address owner = ownerOf[cloneId];
        // if no cloneId is active, revert
        if (owner == address(0)) revert CloneNotFound();

        uint128 worth = cloneIdToShape[cloneId].worth;
        Oracle.write(protoId, worth);

        uint subsidy = cloneIdToSubsidy[cloneId];
        delete cloneIdToShape[cloneId];
        delete cloneIdToSubsidy[cloneId];
        _burn(owner, cloneId);

        // token can only be sold to the clone at the index head
        popListHead(protoId);

        try IERC165(msg.sender).supportsInterface(_INTERFACE_ID_ERC2981) returns (bool isRoyalty) {
            if (isRoyalty) {
                try IERC2981(msg.sender).royaltyInfo(id, worth) returns (address receiver, uint royaltyAmount) {
                    if (receiver != address(0) && royaltyAmount > 0 && royaltyAmount < worth) {
                        worth -= uint128(royaltyAmount);
                        SafeTransferLib.safeTransfer(
                            ERC20(ERC20Contract),
                            receiver,
                            royaltyAmount
                        );
                    }
                } catch {}
            }
        } catch {}

        SafeTransferLib.safeTransfer(
            ERC20(ERC20Contract),
            from,
            worth + subsidy
        );

        // send useful data along with safe transfer to sontracts
        bytes memory data = abi.encode(
            // NFT contract address is sent as msg.sender with function call
            // NFT ID is sent with function call
            ERC20Contract,
            floor,
            protoIdToIndexHead[protoId], // index
            owner,
            worth,
            subsidy
        );

        return (owner, data);
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

        (address owner, bytes memory retData) = onTokenReceived(from, id, ERC20Contract, floor);

        // no need to check if ditto is the owner of `id`,
        // as transfer fails in that case.
        IERC721(msg.sender).safeTransferFrom(address(this), owner, id, retData);
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

        (address owner, bytes memory retData) = onTokenReceived(from, id, ERC20Contract, floor);

        // no need to check if ditto is the owner of `id`,
        // as transfer fails in that case.
        IERC1155(msg.sender).safeTransferFrom(address(this), owner, id, 1, retData);

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

        for (uint i=0; i < ids.length;) {
            if (amounts[i] != 1) revert AmountInvalid();
            (address owner, bytes memory retData) = onTokenReceived(from, ids[i], ERC20Contracts[i], floors[i]);
            IERC1155(msg.sender).safeTransferFrom(address(this), owner, ids[i], 1, retData);
            unchecked { ++i; }
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
    function forceSafeTransferFrom(
        address from,
        address to,
        uint id
    ) private {
        // no ownership or approval checks cause we're forcing a change of ownership
        if (from != ownerOf[id]) revert FromInvalid();

        ownerOf[id] = to;

        emit TransferSingle(address(this), from, to, id, 1);

        // require statement copied from solmate ERC721 safeTransferFrom()
        require(
            to.code.length == 0 ||
                IERC1155Receiver(to).onERC1155Received(msg.sender, from, id, 1, "") ==
                IERC1155Receiver.onERC1155Received.selector,
            "UNSAFE_RECIPIENT"
        );

        // give contracts the option to account for a forced transfer.
        // if they don't implement the ejector we're stll going to move the token.
        if (from.code.length != 0) {
            // not sure if this is exploitable yet?
            try IERC1155TokenEjector(from).onERC1155Ejected{gas: 30000}(address(this), to, id, 1, "") {} // EXTERNAL CALL
            catch {}
        }
    }

}

/**
 * @title A funtion to support token ejection
 * @notice function is called if a contract must do accounting on a forced transfer
 */
interface IERC1155TokenEjector {

    function onERC1155Ejected(
        address operator,
        address to,
        uint id,
        uint amount,
        bytes calldata data
    ) external returns (bytes4);

}
