// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract FloorTest is TestBase {

    constructor() {}

    function testFloorCloneSetsNewClonePrice() public {
        uint256 nftId = nft.mint();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 floorId, /*uint256 flotoId*/) = dm.duplicate(eoa1, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 0);
        vm.stopPrank();

        uint256 cloneId = uint256(keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(nftAddr, nftId, currencyAddr, false)),
            uint256(0)
        )));
        assertEq(dm.ownerOf(cloneId), address(0));
        assertEq(dm.ownerOf(floorId), eoa1);

        vm.startPrank(eoa2);

        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        uint128 floorWorth = getCloneShape(floorId).worth;
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        // expect revert with amount less than floor clone worth
        dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, floorWorth-1, false, 0);

        (uint256 cId, /*uint256 flotoId*/) = dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, false, 0);
        assertEq(cId, cloneId);
        vm.stopPrank();

        uint256 floorMinAmount = dm.getMinAmountForCloneTransfer(floorId);
        uint256 cloneMinAmount = dm.getMinAmountForCloneTransfer(cloneId);
        assertEq(floorMinAmount, cloneMinAmount);

        floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);
    }

    function testFloorCloneSetsExistingClonePrice() public {
        uint256 nftId = nft.mint();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 3);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        vm.roll(block.number+1); // vm.roll will preserve behaviour previous to the block refund mechanism

        uint256 clonePrice = dm.getMinAmountForCloneTransfer(cloneId);
        assertEq(
            // MIN_AMOUNT_FOR_NEW_CLONE + (MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM), // if within a block
            MIN_AMOUNT_FOR_NEW_CLONE * 2 + ((MIN_AMOUNT_FOR_NEW_CLONE * 2) * MIN_FEE / DNOM), // if block has passed
            clonePrice
        );

        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 3);

        (uint256 floorId, /*uint256 protoId*/) = dm.duplicate(eoa2, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 3, true, 0);
        vm.stopPrank();

        uint128 newClonePrice = dm.getMinAmountForCloneTransfer(cloneId);

        currency.mint(eoa1, newClonePrice);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, newClonePrice);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, newClonePrice - 1, false, 0);

        clonePrice = dm.getMinAmountForCloneTransfer(cloneId);
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, newClonePrice, false, 0);
        vm.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);
    }

    function testFloorSellUnderlyingForFloor() public {
        // test selling nft when only floor clone exits
        vm.startPrank(eoaSeller);
        uint256 nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId1, ) = dm.duplicate(eoaBidder, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 subsidy1 = dm.cloneIdToSubsidy(cloneId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth, currency.balanceOf(dmAddr) - subsidy1);

        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), shape1.worth + subsidy1);
        assertEq(currency.balanceOf(dmAddr), 0);
    }

    function testFloorSellUnderlyingForCloneWhileFloorExists() public {
        // test selling nft when floor clone is worth is same as the nft clone
        // should sell to clone owner with true passed throughnft.safeTransferFrom
        vm.startPrank(eoaSeller);
        uint256 nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*/) = dm.duplicate(eoa1, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        vm.stopPrank();

        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);

        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(cloneId), address(0));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa2);
    }

    function testFloorSellUnderlyingForFloorWhileCloneExists() public {
        // test selling nft when floor clone's worth is same as the nft clone
        // should sell to floor owner with true passed through nft.safeTransferFrom
        vm.startPrank(eoaSeller);
        uint256 nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*/) = dm.duplicate(eoa1, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        assertEq(dm.ownerOf(floorId), eoa1);
        vm.stopPrank();

        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa2);
        vm.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);

        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        assertEq(dm.ownerOf(floorId), address(0));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
    }

    function testFloorSellUnderlyingForFloorWithCheaperClone() public {
        // test selling nft when floor clone is worth more than nft clone
        // should sell to floor owner whenever the floor is worth more
        vm.startPrank(eoaSeller);
        uint256 nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        // eoa2 purchases nft clone for cheaper
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        // eoa1 purchase floor clone for higher price
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 floorId, /*uint256 protoId*/) = dm.duplicate(eoa1, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 0);
        vm.stopPrank();

        // eoaSeller sells nft specifying floor clone as recipient
        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE * 2);

        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        dm.duplicate(eoa3, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 1);
        vm.stopPrank();

        vm.startPrank(eoa1);
        //make sure if seller sets "floor" to "false" contract will still sell to floor clone if it is worth more
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(floorId), address(0));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(currency.balanceOf(eoa1), MIN_AMOUNT_FOR_NEW_CLONE * 2);
    }

    function testFloorSellUnderlyingForCloneWithCheaperFloor() public {
        // test selling nft when floor clone is worth less than nft clone
        // should sell to clone if "floor" is set to "false" in safeTransferFrom
        // should sell to floor if "floor" is set to "true" in safeTransferFrom
        vm.startPrank(eoaSeller);
        uint256 nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        // eoa1 purchases floor clone for cheap
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*/) = dm.duplicate(eoa1, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        vm.stopPrank();

        // eoa2 purchases nft clone for higher price
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 cloneId, /*uint256 protoId*/) = dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, false, 0);
        vm.stopPrank();

        // eoaSeller sells nft, specifying floor clone as recipient
        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        assertEq(dm.ownerOf(floorId), address(0));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE);

        // eoa3 purchases another floor clone
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        dm.duplicate(eoa3, nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 1);
        vm.stopPrank();

        // eoa1 sells nft for nft clone
        vm.startPrank(eoa1);
        //make sure if sellr sets "floor" to "false" contract will still sell to floor clone if it is worth more
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(cloneId), address(0));
        vm.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(currency.balanceOf(eoa1), MIN_AMOUNT_FOR_NEW_CLONE * 2);
    }
}
