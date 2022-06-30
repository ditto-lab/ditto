pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract BlockAuction {

    mapping(uint256 => mapping(uint256 => address)) private blockToCloneToReceiver;
    mapping(uint256 => mapping(uint256 => uint256)) private blockToCloneToFeeRefund;
    mapping(uint256 => mapping(uint256 => uint256)) private blockToCloneToSubRefund;

    function _setBlockReceiver(
        uint256 cloneId,
        address receiver,
        address token,
        uint256 fullFee,
        uint256 subsidy
    ) internal {
        address oldReceiver = blockToCloneToReceiver[block.number][cloneId];
        uint256 oldFee = blockToCloneToFeeRefund[block.number][cloneId];
        // uint256 oldSub = blockToCloneToSubRefund[block.number][cloneId];

        // assign new info
        // store clone's owner in previous block
        blockToCloneToReceiver[block.number][cloneId] = receiver;
        blockToCloneToFeeRefund[block.number][cloneId] = fullFee;
        blockToCloneToSubRefund[block.number][cloneId] = subsidy;

        // transfer fee to clone's owner from previous block
        // reduce incentive for front running inside the block
        if (oldReceiver != address(0)) {
            SafeTransferLib.safeTransfer(
                ERC20(token),
                oldReceiver,
                fullFee - oldFee
            );
        }
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
