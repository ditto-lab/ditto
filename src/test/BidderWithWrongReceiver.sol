// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Bidder, DittoMachine} from "./Bidder.sol";
import {ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";

contract BidderWithWrongReceiver is Bidder, ERC721TokenReceiver {

    uint256 public receiveCounter = 0;

    constructor(address dmAddr) Bidder(dmAddr) {}

    function add(uint8 a, uint8 b) external pure returns (uint8) {
        return a+b;
    }
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        receiveCounter++;
        return this.add.selector;
    }
}
