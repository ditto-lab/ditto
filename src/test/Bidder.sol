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

contract BidderOnReceiveRevert {
    bool isRevert = false;
    constructor() {}

    function setRevert(bool b) external {
        isRevert = b;
    }

    function onERC1155Received(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        require(!isRevert);
        return this.onERC1155Received.selector;
    }

    function onERC721Received(
        address /*data*/,
        address /*data*/,
        uint /*data*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        require(!isRevert);
        return this.onERC721Received.selector;
    }
}
