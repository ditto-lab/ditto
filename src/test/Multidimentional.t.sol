// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract MultidimensionalTest is TestBase {

    constructor() {}

    function testMultiClones() public {
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
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE);

        // min clone at head
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 cloneId0, uint256 protoId0, uint256 index0) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();
        // check succesful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(index0, 0);
        assertEq(dm.protoIdToDepth(protoId0), 1);


        // mint clone at depth 1
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 1);
        // mint clone with invalid depth
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone
        (uint256 cloneId1, uint256 protoId1, uint256 index1) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        cheats.stopPrank();
        // check succesful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(index1, 1);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);


        // mint clone at depth 2
        cheats.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone with invalid depth
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 3);
        // mint clone
        (uint256 cloneId2, uint256 protoId2, uint256 index2) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 2);
        cheats.stopPrank();
        // check succesful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(index2, 2);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);


        assertEq(dm.protoIdToIndex(protoId2), 0);

        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(dm.protoIdToIndex(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 2);


        cheats.startPrank(eoa1);
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(dm.protoIdToIndex(protoId2), 2);
        assertEq(dm.protoIdToDepth(protoId2), 1);


        cheats.startPrank(eoa2);
        nft.safeTransferFrom(eoa2, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(dm.protoIdToIndex(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);
    }

}
