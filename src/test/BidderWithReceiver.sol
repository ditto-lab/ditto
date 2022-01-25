// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../DittoMachine.sol";
import "./Bidder.sol";
import {ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";

contract BidderWithReceiver is Bidder, ERC721TokenReceiver {

    uint256 public receiveCounter = 0;

    constructor(address dmAddr) Bidder(dmAddr) {}

    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        receiveCounter++;
        return this.onERC721Received.selector;
    }
}
