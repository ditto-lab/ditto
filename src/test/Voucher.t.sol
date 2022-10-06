// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract TestVoucher is TestBase {

    function testVoucher(
        uint64 time,
        uint128 smallAmount,
        uint128 largeAmount
    ) public {
        vm.assume(smallAmount >= MIN_AMOUNT_FOR_NEW_CLONE);
        vm.assume(smallAmount < 2**105);
        vm.assume(largeAmount < 2**105);

        uint256 nftId = nft.mint();

        currency.mint(eoa1, smallAmount);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, smallAmount);

        uint128 startTime = uint128(block.timestamp);
        (uint256 cloneId, uint256 protoId) = dm.duplicate(nftAddr, nftId, currencyAddr, smallAmount, false, 0);
        uint128 worth = getCloneShape(cloneId).worth;

        vm.stopPrank();

        vm.warp(block.timestamp + time);
        vm.roll(block.number + (time/12));

        uint256 newMinAmount = dm.getMinAmountForCloneTransfer(cloneId);
        vm.assume(largeAmount > newMinAmount);

        currency.mint(eoa2, largeAmount);

        vm.startPrank(eoa2);
        currency.approve(dmAddr, largeAmount);

        uint8 heat = getCloneShape(cloneId).heat;
        uint128 issueTime = uint128(block.timestamp);
        dm.duplicate(nftAddr, nftId, currencyAddr, largeAmount, false, 0);
        uint128 value = getCloneShape(cloneId).worth;

        vm.stopPrank();

        uint256 voucherHash = uint256(keccak256(
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
