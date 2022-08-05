pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract BlockRefund {

    mapping(uint256 => mapping(uint256 => address)) public blockToCloneToReceiver;
    // mapping(uint256 => mapping(uint256 => address)) private blockToCloneToRefundee;
    mapping(uint256 => mapping(uint256 => uint256)) public blockToCloneToFeeRefund;
    mapping(uint256 => mapping(uint256 => uint256)) public blockToCloneToSubRefund;

    function _setBlockReceiver(
        uint256 cloneId,
        address receiver,
        uint256 fullFee,
        uint256 subsidy
    ) internal {
        // assign new info
        // store clone's owner in previous block
        blockToCloneToReceiver[block.number][cloneId] = receiver;

        blockToCloneToFeeRefund[block.number][cloneId] = fullFee;
        blockToCloneToSubRefund[block.number][cloneId] = subsidy;

    }

    function _getBlockReceiver(
        uint256 cloneId
    ) public view returns(address) {
        return blockToCloneToReceiver[block.number][cloneId];
    }

    function _getBlockRefund(
        uint256 cloneId
    ) public view returns(uint256) {
        return blockToCloneToFeeRefund[block.number][cloneId];
    }

    function _getBlockSubRefund(
        uint256 cloneId
    ) public view returns(uint256) {
        return blockToCloneToSubRefund[block.number][cloneId];
    }

}
