// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract FloorTest is TestBase {

    constructor() {}

    function testFloorCloneSetsNewClonePrice() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 floorId, /*uint256 flotoId*/, /*uint256 flotoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 0);
        cheats.stopPrank();

        uint256 cloneId = uint256(keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(nftAddr, nftId, currencyAddr, false)),
            uint256(0)
        )));
        assertEq(dm.ownerOf(cloneId), address(0));
        assertEq(dm.ownerOf(floorId), eoa1);

        cheats.startPrank(eoa2);

        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        uint256 floorWorth = getCloneShape(floorId).worth;
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        // expect revert with amount less than floor clone worth
        dm.duplicate(nftAddr, nftId, currencyAddr, floorWorth-1, false, 0);

        (uint256 cId, /*uint256 flotoId*/, /*uint256 flotoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, false, 0);
        assertEq(cId, cloneId);
        cheats.stopPrank();

        uint256 floorMinAmount = dm.getMinAmountForCloneTransfer(floorId);
        uint256 cloneMinAmount = dm.getMinAmountForCloneTransfer(cloneId);
        assertEq(floorMinAmount, cloneMinAmount);

        floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);
    }

    function testFloorCloneSetsExistingClonePrice() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 3);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        uint256 clonePrice = dm.getMinAmountForCloneTransfer(cloneId);
        assertEq(
            MIN_AMOUNT_FOR_NEW_CLONE * 2 + ((MIN_AMOUNT_FOR_NEW_CLONE * 2) * MIN_FEE / DNOM),
            clonePrice
        );

        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 3);

        (uint256 floorId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 3, true, 0);
        cheats.stopPrank();

        uint256 newClonePrice = dm.getMinAmountForCloneTransfer(cloneId);

        currency.mint(eoa1, newClonePrice);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, newClonePrice);

        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, newClonePrice - 1, false, 0);

        clonePrice = dm.getMinAmountForCloneTransfer(cloneId);
        dm.duplicate(nftAddr, nftId, currencyAddr, newClonePrice, false, 0);
        cheats.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);
    }

    function testFloorSellUnderlyingForFloor() public {
        // test selling nft when only floor clone exits
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nft.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId1, uint256 protoId1, /*uint256 cloneIndex1*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        CloneShape memory shape = getCloneShape(cloneId1);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 subsidy1 = dm.protoIdToSubsidy(protoId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth, currency.balanceOf(dmAddr) - subsidy1);

        cheats.stopPrank();

        cheats.warp(block.timestamp + 100);
        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), shape1.worth + subsidy1);
        assertEq(currency.balanceOf(dmAddr), 0);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId1), shape.worth * 100);
        assertEq(dm.protoIdToTimestampLast(protoId1), block.timestamp);
    }

    function testFloorSellUnderlyingForCloneWhileFloorExists() public {
        // test selling nft when floor clone is worth is same as the nft clone
        // should sell to clone owner with true passed throughnft.safeTransferFrom
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nft.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*/, /*uint256 flotoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        cheats.stopPrank();

        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);

        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(cloneId), address(0));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa2);
    }

    function testFloorSellUnderlyingForFloorWhileCloneExists() public {
        // test selling nft when floor clone's worth is same as the nft clone
        // should sell to floor owner with true passed through nft.safeTransferFrom
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nft.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*/, /*uint256 flotoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        assertEq(dm.ownerOf(floorId), eoa1);
        cheats.stopPrank();

        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa2);
        cheats.stopPrank();

        uint256 floorWorth = getCloneShape(floorId).worth;
        uint256 cloneWorth = getCloneShape(cloneId).worth;
        assertEq(floorWorth, cloneWorth);

        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        assertEq(dm.ownerOf(floorId), address(0));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
    }

    function testFloorSellUnderlyingForFloorWithCheaperClone() public {
        // test selling nft when floor clone is worth more than nft clone
        // should sell to floor owner whenever the floor is worth more
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nft.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");
        address eoa3 = generateAddress("eoa3");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        // eoa2 purchases nft clone for cheaper
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        // eoa1 purchase floor clone for higher price
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 floorId, /*uint256 flotoId*//*uint256 protoId*/, /*uint256 flotoId*//*uint256 protoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 0);
        cheats.stopPrank();

        // eoaSeller sells nft specifying floor clone as recipient
        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE * 2);

        cheats.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, true, 0);
        cheats.stopPrank();

        cheats.startPrank(eoa1);
        //make sure if seller sets "floor" to "false" contract will still sell to floor clone if it is worth more
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(floorId), address(0));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(currency.balanceOf(eoa1), MIN_AMOUNT_FOR_NEW_CLONE * 2);
    }

    function testFloorSellUnderlyingForCloneWithCheaperFloor() public {
        // test selling nft when floor clone is worth less than nft clone
        // should sell to clone if "floor" is set to "false" in safeTransferFrom
        // should sell to floor if "floor" is set to "true" in safeTransferFrom
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nft.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        address eoa2 = generateAddress("eoa2");
        address eoa3 = generateAddress("eoa3");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE * 2);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        // eoa1 purchases floor clone for cheap
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 floorId, /*uint256 flotoId*//*uint256 flotoId*//*uint256 protoId*/, /*uint256 flotoId*//*uint256 flotoId*//*uint256 protoId*/) = dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        cheats.stopPrank();

        // eoa2 purchases nft clone for higher price
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 cloneIndex*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE * 2, false, 0);
        cheats.stopPrank();

        // eoaSeller sells nft, specifying floor clone as recipient
        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        assertEq(dm.ownerOf(floorId), address(0));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE);

        // eoa3 purchases another floor clone
        cheats.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        dm.duplicate(nftAddr, 0, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        cheats.stopPrank();

        // eoa1 sells nft for nft clone
        cheats.startPrank(eoa1);
        //make sure if sellr sets "floor" to "false" contract will still sell to floor clone if it is worth more
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        assertEq(dm.ownerOf(cloneId), address(0));
        cheats.stopPrank();

        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(currency.balanceOf(eoa1), MIN_AMOUNT_FOR_NEW_CLONE * 2);
    }
}
