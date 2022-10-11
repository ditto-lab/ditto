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
        uint nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });
        (uint cloneId, uint protoId) = dm.duplicate(eoa1, protoShape, MIN_AMOUNT_FOR_NEW_CLONE, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);
        // console.log(dm.cloneIdToSubsidy(cloneId));

        for (uint i = 1; i < 83; i++) {
            // after 83 price calculation will overflow error when calculating fees

            vm.roll(block.number+1);
            vm.warp(block.timestamp + i);

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(protoId, cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint fee = minAmountToBuyClone * MIN_FEE * (1 + shape.heat) / DNOM;
            console.log(fee);
            console.log(minAmountToBuyClone);
            console.log(minAmountToBuyClone - fee);
            // console.log(dm._getMinAmount(shape, false));

            dm.duplicate(eoa1, protoShape, minAmountToBuyClone, 0);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1+i);
            console.log(shape.worth);
        }
        vm.stopPrank();
    }

    function testHeatStatic() public {
        uint nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });
        (uint cloneId, uint protoId) = dm.duplicate(eoa1, protoShape, MIN_AMOUNT_FOR_NEW_CLONE, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        vm.stopPrank();

        for (uint i = 1; i < 256; i++) {
            vm.warp(block.timestamp + (BASE_TERM) + TimeCurve.calc(shape.heat));

            vm.startPrank(eoa1);

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(protoId, cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            dm.duplicate(eoa1, protoShape, minAmountToBuyClone, 0);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1);
            assertEq(shape.term, block.timestamp + (BASE_TERM-1) + shape.heat**2);

            vm.stopPrank();
        }
    }

    function testHeatDuplicatePrice(uint16 time) public {
        uint nftId = nft.mint();
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });
        (uint cloneId, uint protoId) = dm.duplicate(eoa1, protoShape, MIN_AMOUNT_FOR_NEW_CLONE, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        for (uint i = 1; i < 50; i++) {
            console.log(i);
            vm.roll(block.number+1);
            vm.warp(block.timestamp + uint(time));

            bool sameBlock = dm._getBlockRefund(cloneId) != 0;

            uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(protoId, cloneId);
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

            dm.duplicate(eoa1, protoShape, minAmountToBuyClone, 0);
            shape = getCloneShape(cloneId);
        }
        vm.stopPrank();
    }
}
