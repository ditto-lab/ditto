// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract BlockRefundTest is TestBase {

    constructor() {}

    // test first owner is fully refunded within the block
    function testRefund() public {
        uint256 nftId = nft.mint();

        for (uint128 i = 0; i<10; ++i) {
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
        }
    }

    function testRefundFuzz(uint128 amount0, uint128 amount1) public {
        vm.assume(amount0 >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount1 < 2**123);
        vm.assume(amount0 < amount1);

        // amount1 can be assumed to fit because it is greater tha  amount0

        uint256 nftId = nft.mint();

        // eoa0 enters clone position
        currency.mint(eoa0, amount0);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount0);

        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, amount0, false, 0);

        assertEq(dm.ownerOf(cloneId), eoa0);
        assertEq(currency.balanceOf(eoa0), 0);
        vm.stopPrank();


        // eoa1 takes clone position in same block
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
    }

    function testRefundSelf() public {
        uint256 nftId = nft.mint();

        currency.mint(eoa0, MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // open initial clone position
        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);

        uint128 minAmountToBuyClone = MIN_AMOUNT_FOR_NEW_CLONE*2;
        currency.mint(eoa0, minAmountToBuyClone);
        currency.approve(dmAddr, minAmountToBuyClone);

        CloneShape memory shape = getCloneShape(cloneId);
        console.log(shape.worth);
        console.log(currency.balanceOf(dmAddr));

        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        uint128 sub2 = dm.cloneIdToSubsidy(cloneId);

        shape = getCloneShape(cloneId);

        uint256 balance = currency.balanceOf(eoa0);

        assertEq(balance, MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(shape.worth + sub2, currency.balanceOf(dmAddr), "worth + sub, dm balance");

        vm.stopPrank();
    }

    function testRefundSelfFuzz(uint128 amount) public {
        vm.assume(amount >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount < 2**105); // math will overflow error if amount is too large

        uint256 nftId = nft.mint();

        currency.mint(eoa0, amount);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount);
        // open initial clone position
        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, amount, false, 0);

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
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
