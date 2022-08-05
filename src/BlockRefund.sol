pragma solidity ^0.8.4;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract BlockRefund {

    mapping(uint256 => mapping(uint256 => uint256)) public blockToCloneToFeeRefund;
    mapping(uint256 => mapping(uint256 => uint256)) public blockToCloneToSubRefund;

    function _setBlockRefund(
        uint256 cloneId,
        uint256 fullFee,
        uint256 subsidy
    ) internal {
        // assign new info
        blockToCloneToFeeRefund[block.number][cloneId] = fullFee;
        blockToCloneToSubRefund[block.number][cloneId] = subsidy;

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
