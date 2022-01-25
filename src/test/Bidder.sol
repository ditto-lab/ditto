// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../DittoMachine.sol";

contract Bidder {

    DittoMachine immutable dm;
    constructor(address dmAddr) {
        dm = DittoMachine(dmAddr);
    }
}
