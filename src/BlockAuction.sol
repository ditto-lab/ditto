pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract BlockAuction {

    struct BlockInfo {
        uint256 amount;
        uint256 fee;
        address addr;
    }

    mapping(uint256 => mapping(uint256 => BlockInfo)) public blockToCloneToLeader;
    mapping(uint256 => mapping(uint256 => BlockInfo)) public blockToCloneToRefund;

    function checkBlockInfo(
        uint256 cloneId,
        uint256 amount,
        uint256 fee,
        address bidder
    ) internal returns(uint256) {
        if (amount <= blockToCloneToLeader[block.number][cloneId].amount) {
            return 0;
        } else {
            // assign refund
            blockToCloneToRefund[block.number][cloneId].amount = blockToCloneToLeader[block.number][cloneId].amount;
            blockToCloneToRefund[block.number][cloneId].addr = blockToCloneToLeader[block.number][cloneId].addr;
            blockToCloneToRefund[block.number][cloneId].fee = blockToCloneToLeader[block.number][cloneId].fee;
            // assign new leader
            blockToCloneToLeader[block.number][cloneId].amount = amount;
            blockToCloneToLeader[block.number][cloneId].addr = bidder;
            blockToCloneToLeader[block.number][cloneId].fee = fee;

            return blockToCloneToRefund[block.number][cloneId].fee;
        }

    }

    function refundBlock(
        uint256 cloneId,
        address ERC20Contract
    ) internal returns(bool) {
        if (blockToCloneToRefund[block.number][cloneId].amount > 0) {
            SafeTransferLib.safeTransfer(
                ERC20(ERC20Contract),
                blockToCloneToRefund[block.number][cloneId].addr,
                blockToCloneToRefund[block.number][cloneId].amount
            );
            return true;
        }
        return false;
    }

}
