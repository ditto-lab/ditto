pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {Oracle} from "../Oracle.sol";

contract OracleWrapper is Oracle {
    function writeWrapper(uint256 protoId, uint128 price) external {
        Oracle.write(protoId, price);
    }

    function observeWrapper(
        uint256 protoId,
        uint128[] calldata secondsAgos,
        uint128 curWorth
    ) external view returns (uint128[] memory cumulativePrices) {
        return Oracle.observe(protoId, secondsAgos, curWorth);
    }
}
