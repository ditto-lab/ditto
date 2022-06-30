// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract BlockRefundTest is TestBase {

    constructor() {}

    function setUp() public override {
        super.setUp();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 2);
    }

    // test first owner is fully refunded within the block
    function testBlockRefund() public {
        uint256 nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        vm.stopPrank();

    }

    // test funder is not fully refunded outside of the block

    // test heat is not increased within the block, but increases properly after 

}
