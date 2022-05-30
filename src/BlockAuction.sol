pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract BlockAuction {

    mapping(uint256 => mapping(uint256 => address)) private blockToCloneToReceiver;

    function _setBlockReceiver(
        uint256 cloneId,
        address receiver,
        address token,
        uint256 fee
    ) internal {
        address oldReceiver = blockToCloneToReceiver[block.number][cloneId];
        // assign new info
        // store clone's owner in previous block
        blockToCloneToReceiver[block.number][cloneId] = receiver;

        // transfer fee to clone's owner from previous block
        // reduce incentive for front running inside the block
        if (oldReceiver != address(0)) {
            SafeTransferLib.safeTransfer(
                ERC20(token),
                oldReceiver,
                fee
            );
        }
    }

    function _getBlockReceiver(
        uint256 cloneId
    ) public view returns(address) {
        return blockToCloneToReceiver[block.number][cloneId];
    }

}
