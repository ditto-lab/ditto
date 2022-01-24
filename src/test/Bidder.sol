// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "../DittoMachine.sol";

contract Bidder {

    DittoMachine immutable dm;
    constructor(address dmAddr) {
        dm = DittoMachine(dmAddr);
    }

    function bid(
        address _ERC721Contract,
        uint256 _tokenId,
        address _ERC20Contract,
        uint256 _amont,
        bool floor
    ) public returns (uint256) {
        return dm.duplicate(
           _ERC721Contract,
            _tokenId,
            _ERC20Contract,
            _amont,
            floor
        );
    }
}