// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {DittoMachine, IERC1155TokenEjector} from "../DittoMachine.sol";

contract BidderWithEjector is IERC1155TokenEjector {

    uint public ejections;

    constructor() {}

    function onERC1155Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        ++ejections;
        return this.onERC1155Ejected.selector;
    }
}

contract BidderWithBadEjector is IERC1155TokenEjector {

    uint public ejections;

    constructor() {}

    function onERC1155Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        revert();
        ++ejections;
        return this.onERC1155Ejected.selector;
    }
}

contract BidderWithGassyEjector is IERC1155TokenEjector {

    uint public ejections;
    uint[] public stored;

    constructor() {}

    function onERC1155Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        uint gas = gasleft();
        while (stored.length <= gas) {
            stored.push(gas**gasleft());
        }
        ++ejections;
        return this.onERC1155Ejected.selector;
    }
}
