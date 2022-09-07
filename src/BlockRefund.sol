pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

abstract contract BlockRefund {

    mapping(uint256 => mapping(uint256 => uint256)) public blockToCloneToFeeRefund;

    function _setBlockRefund(
        uint256 cloneId,
        uint256 fullFee
    ) internal {
        // assign new info
        blockToCloneToFeeRefund[block.number][cloneId] = fullFee;

    }

    function _getBlockRefund(
        uint256 cloneId
    ) public view returns(uint256) {
        return blockToCloneToFeeRefund[block.number][cloneId];
    }

}
