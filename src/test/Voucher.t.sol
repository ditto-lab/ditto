// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./DittoTestBase.sol";

contract TestVoucher is DittoTestBase {

    function testVoucher(
        uint64 time,
        uint128 smallAmount,
        uint128 largeAmount
    ) public {
        vm.assume(smallAmount >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(smallAmount < 2**105);
        vm.assume(largeAmount < 2**105);

        uint nftId = nft.mint();

        currency.mint(eoa1, smallAmount);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, smallAmount);

        uint128 startTime = uint128(block.timestamp);
        (uint cloneId, ) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, smallAmount, false, 0);
        uint128 worth = getCloneShape(cloneId).worth;

        vm.stopPrank();

        vm.warp(block.timestamp + time);

        uint newMinAmount = dm.getMinAmountForCloneTransfer(cloneId);
        vm.assume(largeAmount > newMinAmount);

        currency.mint(eoa2, largeAmount);

        vm.startPrank(eoa2);
        currency.approve(dmAddr, largeAmount);

        uint8 heat = getCloneShape(cloneId).heat;
        uint128 issueTime = uint128(block.timestamp);
        dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, largeAmount, false, 0);
        uint128 value = getCloneShape(cloneId).worth;

        vm.stopPrank();

        uint voucherHash = uint(keccak256(
            abi.encodePacked(
                true,
                cloneId,
                eoa1,
                heat,
                worth,
                value,
                startTime,
                issueTime
            )
        ));

        assertTrue(!dm.voucherValidity(0));
        assertTrue(dm.voucherValidity(voucherHash));
    }
}
