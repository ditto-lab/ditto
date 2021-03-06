// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract HeatTest is TestBase {

    constructor() {}

    function setUp() public override {
        super.setUp();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
    }

    function testHeatIncrease() public {
        uint256 nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        vm.stopPrank();

        for (uint256 i = 1; i < 215; i++) {
            // after 215 worth*timleft will overflow error when calculating fees

            vm.warp(block.timestamp + i);
            vm.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * i));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1+i);

            vm.stopPrank();
        }
    }

    function testHeatStatic() public {
        uint256 nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        vm.stopPrank();

        for (uint256 i = 1; i < 256; i++) {
            vm.warp(block.timestamp + (BASE_TERM) + TimeCurve.calc(shape.heat));

            vm.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * ((BASE_TERM-1) + shape.heat**2)));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1);
            assertEq(shape.term, block.timestamp + (BASE_TERM-1) + shape.heat**2);

            vm.stopPrank();
        }
    }

    function testHeatDuplicatePrice(uint16 time) public {
        uint256 nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        vm.stopPrank();

        for (uint256 i = 1; i < 50; i++) {
            vm.warp(block.timestamp + uint256(time));

            vm.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 timeLeft = shape.term > block.timestamp ? shape.term - block.timestamp : 0;
            uint256 termStart = shape.term - ((BASE_TERM) + TimeCurve.calc(shape.heat));
            uint256 termLength = shape.term - termStart;

            uint256 auctionPrice = shape.worth + (shape.worth * timeLeft / termLength);

            assertEq(minAmountToBuyClone, (auctionPrice + (auctionPrice * MIN_FEE * (1+shape.heat) / DNOM)), "price");

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * time));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);
            shape = getCloneShape(cloneId);

            vm.stopPrank();
        }
    }
}
