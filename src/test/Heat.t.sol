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
        // console.log(dm.cloneIdToSubsidy(cloneId));

        vm.stopPrank();

        for (uint256 i = 1; i < 210; i++) {
            // after 210 price calculation will overflow error when calculating fees

            vm.roll(block.number+1);
            vm.warp(block.timestamp + i);
            vm.startPrank(eoa1);

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 fee = minAmountToBuyClone * MIN_FEE * (1 + shape.heat) / DNOM;
            console.log(fee);
            console.log(minAmountToBuyClone);
            console.log(minAmountToBuyClone - fee);
            // console.log(dm._getMinAmount(shape, false));

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * i));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);
            // console.log(dm.cloneIdToSubsidy(cloneId));

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1+i);
            console.log(shape.worth);

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

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
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
        (uint256 cloneId, ) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        for (uint256 i = 1; i < 50; i++) {
            console.log(i);
            vm.roll(block.number+1);
            vm.warp(block.timestamp + uint256(time));

            bool sameBlock = dm._getBlockRefund(cloneId) != 0;

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint128 timeLeft = shape.term > block.timestamp ? shape.term - uint128(block.timestamp) : 0;
            uint128 termStart = shape.term - (BASE_TERM + TimeCurve.calc(shape.heat));
            uint128 termLength = shape.term - termStart;

            uint128 auctionPrice = shape.worth + (shape.worth * timeLeft / termLength);

            assertEq(
                minAmountToBuyClone,
                (sameBlock ?
                    (shape.worth + ((shape.worth * (MIN_FEE * (shape.heat))) * DNOM) / (DNOM - (MIN_FEE * shape.heat)) / DNOM):
                    (auctionPrice + ((auctionPrice * (MIN_FEE * (1+shape.heat))) * DNOM) / (DNOM - (MIN_FEE * (1+shape.heat))) / DNOM) ),
                "price"
            );

            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
            shape = getCloneShape(cloneId);
        }
        vm.stopPrank();
    }
}
