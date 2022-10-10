// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {DittoMachine, IERC721TokenEjector} from "../DittoMachine.sol";

contract BidderWithEjector is IERC721TokenEjector {

    uint public ejections;

    constructor() {}

    function onERC721Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}

contract BidderWithBadEjector is IERC721TokenEjector {

    uint public ejections;

    constructor() {}

    function onERC721Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        revert();
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}

contract BidderWithGassyEjector is IERC721TokenEjector {

    uint public ejections;
    uint[] public stored;

    constructor() {}

    function onERC721Ejected(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external returns (bytes4) {
        uint gas = gasleft();
        while (stored.length <= gas) {
            stored.push(gas**gasleft());
        }
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}
