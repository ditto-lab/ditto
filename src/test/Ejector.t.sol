// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract EjectorTest is TestBase {

    constructor() {}

    function testEjector() public {
        uint256 nftId = nft.mint();
        currency.mint(address(bidderWithEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(address(bidderWithEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(address(bidderWithEjector), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        vm.stopPrank();

        uint256 ejections = bidderWithEjector.ejections();
        assertEq(ejections, 1);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }

    function testEjectorWithRevert() public {
        uint256 nftId = nft.mint();
        currency.mint(address(bidderWithBadEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(address(bidderWithBadEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(address(bidderWithBadEjector), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        vm.stopPrank();

        uint256 ejections = bidderWithBadEjector.ejections();
        assertEq(ejections, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }

    function testEjectorWithOOG() public {
        uint256 nftId = nft.mint();
        currency.mint(address(bidderWithGassyEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(address(bidderWithGassyEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(address(bidderWithGassyEjector), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        vm.stopPrank();

        uint256 ejections = bidderWithGassyEjector.ejections();
        assertEq(ejections, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }
}
