// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract BlockRefundTest is TestBase {

    constructor() {}

    // test first owner is fully refunded within the block
    function testRefund() public {
        uint nftId = nft.mint();

        for (uint128 i = 0; i<10; ++i) {
            address testEoa = generateAddress(bytes(Strings.toString(i)));

            currency.mint(testEoa, MIN_AMOUNT_FOR_NEW_CLONE * (i+1));

            vm.startPrank(testEoa);
            currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * (i+1));

            // buy a clone using the minimum purchase amount
            ProtoShape memory protoShape = ProtoShape({
                tokenId: nftId,
                ERC721Contract: nftAddr,
                ERC20Contract: currencyAddr,
                floor: false
            });
            (uint cloneId, ) = dm.duplicate(testEoa, protoShape, MIN_AMOUNT_FOR_NEW_CLONE * (i+1), 0);

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

        uint nftId = nft.mint();

        // eoa0 enters clone position
        currency.mint(eoa0, amount0);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount0);

        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });

        (uint cloneId, ) = dm.duplicate(eoa0, protoShape, amount0, 0);

        assertEq(dm.ownerOf(cloneId), eoa0);
        assertEq(currency.balanceOf(eoa0), 0);
        vm.stopPrank();


        // eoa1 takes clone position in same block
        currency.mint(eoa1, amount1);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, amount1);

        dm.duplicate(eoa1, protoShape, amount1, 0);

        assertEq(dm.ownerOf(cloneId), eoa1);
        assertEq(currency.balanceOf(eoa1), 0);
        vm.stopPrank();

        // check eoa0 is full refunded
        assertEq(currency.balanceOf(eoa0), amount0, "eoa0 refund");
        assertEq(currency.balanceOf(dmAddr), amount1, "dm balance");
    }

    function testRefundSelf() public {
        uint nftId = nft.mint();

        currency.mint(eoa0, MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // open initial clone position
        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });
        (uint cloneId, ) = dm.duplicate(eoa0, protoShape, MIN_AMOUNT_FOR_NEW_CLONE, 0);

        uint128 minAmountToBuyClone = MIN_AMOUNT_FOR_NEW_CLONE*2;
        currency.mint(eoa0, minAmountToBuyClone);
        currency.approve(dmAddr, minAmountToBuyClone);

        CloneShape memory shape = getCloneShape(cloneId);
        console.log(shape.worth);
        console.log(currency.balanceOf(dmAddr));

        dm.duplicate(eoa0, protoShape, minAmountToBuyClone, 0);
        uint128 sub2 = dm.cloneIdToSubsidy(cloneId);

        shape = getCloneShape(cloneId);

        uint balance = currency.balanceOf(eoa0);

        assertEq(balance, MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(shape.worth + sub2, currency.balanceOf(dmAddr), "worth + sub, dm balance");

        vm.stopPrank();
    }

    function testRefundSelfFuzz(uint128 amount) public {
        vm.assume(amount >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(amount < 2**105); // math will overflow error if amount is too large

        uint nftId = nft.mint();

        currency.mint(eoa0, amount);

        vm.startPrank(eoa0);
        currency.approve(dmAddr, amount);
        // open initial clone position
        ProtoShape memory protoShape = ProtoShape({
            tokenId: nftId,
            ERC721Contract: nftAddr,
            ERC20Contract: currencyAddr,
            floor: false
        });
        (uint cloneId, uint protoId) = dm.duplicate(eoa0, protoShape, amount, 0);

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(protoId, cloneId);
        currency.mint(eoa0, minAmountToBuyClone);
        currency.approve(dmAddr, minAmountToBuyClone);

        dm.duplicate(eoa0, protoShape, minAmountToBuyClone, 0);

        uint balance = currency.balanceOf(eoa0);
        console.log(amount);
        console.log(balance);
        assertEq(balance, amount);

        vm.stopPrank();
    }

}
