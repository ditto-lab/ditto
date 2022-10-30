// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {DittoMachine} from "../DittoMachine.sol";

contract Bidder {

    constructor() {}

    function onERC1155Received(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

}
