// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract BlockRefundTest is TestBase {

    constructor() {}

    // test first owner is fully refunded within the block
    function testRefund() public {
        uint256 nftId = nft.mint();

        for (uint256 i = 0; i<5; ++i) {
            // vm.roll(block.number+1);
            // vm.warp(block.timestamp + BASE_TERM + TimeCurve.calc(i+1));

            address testEoa = generateAddress(bytes(Strings.toString(i)));

            currency.mint(testEoa, MIN_AMOUNT_FOR_NEW_CLONE + i);

            vm.startPrank(testEoa);
            currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE + i);

            // buy a clone using the minimum purchase amount
            (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE + i, false, 0);

            assertEq(dm.ownerOf(cloneId), testEoa);
            assertEq(currency.balanceOf(testEoa), 0);
            vm.stopPrank();

            assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE + i);
            if (i > 0) {
                address prevEoa = generateAddress(bytes(Strings.toString(i-1)));
                assertEq(currency.balanceOf(prevEoa), MIN_AMOUNT_FOR_NEW_CLONE + i - 1);
            }

            ( , , , ,uint8 heat, , ) = dm.cloneIdToShape(cloneId);
            assertEq(heat, 1);

            // console.log(dm.cloneIdToSubsidy(cloneId));

        }
    }

    function testRefundFuzz(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount1 < 2**250);
        vm.assume(amount0 < amount1);

        // amount1 can be assumed to fit because it is greater tha  amount0

        uint256 nftId = nft.mint();

        // eoa0 enters clone position
        address eoa0 = generateAddress("eoa00");
        currency.mint(eoa0, amount0);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount0);

        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, amount0, false, 0);

        assertEq(dm.ownerOf(cloneId), eoa0);
        assertEq(currency.balanceOf(eoa0), 0);
        vm.stopPrank();


        // eoa1 takes clone position in same block
        address eoa1 = generateAddress("eoa01");
        currency.mint(eoa1, amount1);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, amount1);

        dm.duplicate(nftAddr, nftId, currencyAddr, amount1, false, 0);

        assertEq(dm.ownerOf(cloneId), eoa1);
        assertEq(currency.balanceOf(eoa1), 0);
        vm.stopPrank();

        // check eoa0 is full refunded
        assertEq(currency.balanceOf(eoa0), amount0, "eoa0 refund");
        assertEq(currency.balanceOf(dmAddr), amount1, "dm balance");

        // console.log(eoa0);
        // console.log(eoa1);
    }

}
