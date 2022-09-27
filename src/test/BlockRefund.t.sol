// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract BlockRefundTest is TestBase {

    constructor() {}

    // test first owner is fully refunded within the block
    function testRefund() public {
        uint256 nftId = nft.mint();

        for (uint256 i = 0; i<10; ++i) {
            console.log(i);
            // vm.roll(block.number+1);
            // vm.warp(block.timestamp + BASE_TERM + TimeCurve.calc(i+1));

            address testEoa = generateAddress(bytes(Strings.toString(i)));

            currency.mint(testEoa, MIN_AMOUNT_FOR_NEW_CLONE * (i+1));

            vm.startPrank(testEoa);
            currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * (i+1));

            // buy a clone using the minimum purchase amount
            (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * (i+1), false, 0);

            assertEq(dm.ownerOf(cloneId), testEoa);
            assertEq(currency.balanceOf(testEoa), 0);
            vm.stopPrank();

            assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE * (i+1), "dm balance");
            if (i > 0) {
                address prevEoa = generateAddress(bytes(Strings.toString(i-1)));
                assertEq(currency.balanceOf(prevEoa), (MIN_AMOUNT_FOR_NEW_CLONE * (i+1)) - MIN_AMOUNT_FOR_NEW_CLONE, "eoa");

            }
            CloneShape memory shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1);

            console.log(currency.balanceOf(dmAddr));
            console.log((shape.worth + dm.cloneIdToSubsidy(cloneId)));
            assertEq((shape.worth + dm.cloneIdToSubsidy(cloneId)), currency.balanceOf(dmAddr));

            // console.log(dm.cloneIdToSubsidy(cloneId));

        }
    }

    function testRefundFuzz(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount1 < 2**240);
        vm.assume(amount0 < amount1);

        // amount1 can be assumed to fit because it is greater tha  amount0

        uint256 nftId = nft.mint();

        // eoa0 enters clone position
        address eoa0 = generateAddress("eoa0");
        currency.mint(eoa0, amount0);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount0);

        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, amount0, false, 0);

        assertEq(dm.ownerOf(cloneId), eoa0);
        assertEq(currency.balanceOf(eoa0), 0);
        vm.stopPrank();


        // eoa1 takes clone position in same block
        address eoa1 = generateAddress("eoa1");
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

    function testRefundSelf() public {
        uint256 nftId = nft.mint();

        address eoa0 = generateAddress("eoa0");
        currency.mint(eoa0, MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // open initial clone position
        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        uint256 sub1 = dm.cloneIdToSubsidy(cloneId);
        console.log(sub1);

        uint256 minAmountToBuyClone = MIN_AMOUNT_FOR_NEW_CLONE*2;
        currency.mint(eoa0, minAmountToBuyClone);
        currency.approve(dmAddr, minAmountToBuyClone);

        CloneShape memory shape = getCloneShape(cloneId);
        console.log(shape.worth);
        console.log(currency.balanceOf(dmAddr));

        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        uint256 sub2 = dm.cloneIdToSubsidy(cloneId);
        console.log(sub2);

        shape = getCloneShape(cloneId);
        console.log(shape.worth);

        uint256 balance = currency.balanceOf(eoa0);
        // console.log(MIN_AMOUNT_FOR_NEW_CLONE);
        // console.log(balance);
        console.log("balance:");
        console.log(currency.balanceOf(dmAddr));

        console.log("shape worth + subsidy:");
        console.log(shape.worth + sub2);

        assertEq(balance, MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(shape.worth + sub2, currency.balanceOf(dmAddr), "worth + sub, dm balance");

        vm.stopPrank();
    }

    function testRefundSelfFuzz(uint256 amount) public {
        vm.assume(amount >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount < 2**235); // math will overflow error if amount is too large

        uint256 nftId = nft.mint();

        address eoa0 = generateAddress("eoa0");
        currency.mint(eoa0, amount);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount);
        // open initial clone position
        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, amount, false, 0);

        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa0, minAmountToBuyClone);
        currency.approve(dmAddr, minAmountToBuyClone);

        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

        uint256 balance = currency.balanceOf(eoa0);
        console.log(amount);
        console.log(balance);
        assertEq(balance, amount);

        vm.stopPrank();
    }

}