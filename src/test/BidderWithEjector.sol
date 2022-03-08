// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {DittoMachine, IERC721TokenEjector} from "../DittoMachine.sol";

contract BidderWithEjector is IERC721TokenEjector {

    uint256 public ejections;

    DittoMachine immutable dm;
    constructor(address dmAddr) {
        dm = DittoMachine(dmAddr);
    }

    function onERC721Ejected(
        address operator,
        address to,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}

contract BidderWithBadEjector is IERC721TokenEjector {

    uint256 public ejections;

    DittoMachine immutable dm;
    constructor(address dmAddr) {
        dm = DittoMachine(dmAddr);
    }

    function onERC721Ejected(
        address operator,
        address to,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        revert();
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}

contract BidderWithGassyEjector is IERC721TokenEjector {

    uint256 public ejections;
    uint256[] public stored;

    DittoMachine immutable dm;
    constructor(address dmAddr) {
        dm = DittoMachine(dmAddr);
    }

    function onERC721Ejected(
        address operator,
        address to,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        uint256 gas = gasleft();
        while (stored.length <= gas) {
            stored.push(gas**gasleft());
        }
        ++ejections;
        return this.onERC721Ejected.selector;
    }
}
