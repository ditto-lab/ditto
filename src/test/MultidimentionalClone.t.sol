// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract MultidimensionalCloneTest is TestBase {

    uint256 nftId;
    constructor() {}

    function setUp() public override {
        super.setUp();

        vm.startPrank(eoaSeller);
        nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa2, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa3, MIN_AMOUNT_FOR_NEW_CLONE);
        currency.mint(eoa4, MIN_AMOUNT_FOR_NEW_CLONE);
    }

    function testMultiClones() public {
        // mint clone at head
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 cloneId0, uint256 protoId0) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(dm.protoIdToDepth(protoId0), 1);

        // mint clone at depth 1
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 1);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone
        (uint256 cloneId1, uint256 protoId1) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);


        // mint clone at depth 2
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 3);
        // mint clone
        (uint256 cloneId2, uint256 protoId2) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 2);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);


        assertEq(dm.protoIdToIndexHead(protoId2), 0);

        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(dm.protoIdToIndexHead(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 2);


        vm.startPrank(eoa1);
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(dm.protoIdToIndexHead(protoId2), 2);
        assertEq(dm.protoIdToDepth(protoId2), 1);


        vm.startPrank(eoa2);
        nft.safeTransferFrom(eoa2, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(dm.protoIdToIndexHead(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);
    }

    function testMultiFloors() public {
        // mint clone at head
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 cloneId0, uint256 protoId0) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(dm.protoIdToDepth(protoId0), 1);


        // mint clone at depth 1
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 1);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 2);
        // mint clone
        (uint256 cloneId1, uint256 protoId1) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 1);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);


        // mint clone at depth 2
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 2);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 3);
        // mint clone
        (uint256 cloneId2, uint256 protoId2) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 2);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);


        assertEq(dm.protoIdToIndexHead(protoId2), 0);

        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, true));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(dm.protoIdToIndexHead(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 2);


        vm.startPrank(eoa1);
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, true));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(dm.protoIdToIndexHead(protoId2), 2);
        assertEq(dm.protoIdToDepth(protoId2), 1);


        vm.startPrank(eoa2);
        nft.safeTransferFrom(eoa2, dmAddr, nftId, abi.encode(currencyAddr, true));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(dm.protoIdToIndexHead(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);
    }

    function testMultiDissolve() public {
        // mint clone at head
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        uint256 index0 = 0;
        (uint256 cloneId0, uint256 protoId0) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, index0);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(dm.protoIdToDepth(protoId0), 1);
        uint256 cloneId0Subsidy = MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM;
        assertEq(dm.cloneIdToSubsidy(cloneId0), cloneId0Subsidy);


        // mint clone at depth 1
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 1);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 2);
        // mint clone
        uint256 index1 = 1;
        (uint256 cloneId1, uint256 protoId1) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, index1);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);
        uint256 cloneId1Subsidy = dm.cloneIdToSubsidy(cloneId1);


        // mint clone at depth 2
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 2);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, true, 3);
        // mint clone
        uint256 index2 = 2;
        (uint256 cloneId2, uint256 protoId2) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, index2);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);
        uint256 cloneId2Subsidy = dm.cloneIdToSubsidy(cloneId2);


        vm.startPrank(eoa1);
        dm.dissolve(protoId0, cloneId0);
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(dm.protoIdToIndexHead(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 2);
        assertEq(dm.cloneIdToSubsidy(cloneId0), 0);

        // subsidy is passed to the next clone in the linked list.
        assertEq(dm.cloneIdToSubsidy(cloneId1), cloneId0Subsidy + cloneId1Subsidy);
        cloneId1Subsidy = dm.cloneIdToSubsidy(cloneId1);


        vm.startPrank(eoa3);
        dm.dissolve(protoId2, cloneId2);
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        // this dissolve should not move the index head
        assertEq(dm.protoIdToIndexHead(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 1);

        uint256 cloneId3 = uint256(keccak256(abi.encodePacked(protoId2,uint256(3))));
        // subsidy is passed to the next clone in the linked list, even if it's not minted yet.
        assertEq(dm.cloneIdToSubsidy(cloneId3), cloneId2Subsidy);


        vm.startPrank(eoa2);
        dm.dissolve(protoId1, cloneId1);
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(dm.protoIdToIndexHead(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);
        assertEq(dm.cloneIdToSubsidy(cloneId2), 0);

        // since cloneId2 has already been burnt,
        // index corresponding to cloneId3 comes after index1 in the linked list instead of index2.
        // hence, the cloneId1's subsidy is passed to cloneId3.
        assertEq(dm.cloneIdToSubsidy(cloneId3), cloneId2Subsidy + cloneId1Subsidy);
    }

    function testMultiNFTSellsAfterDissolve() public {
        // mint clone at head
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 cloneId0, uint256 protoId0) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(dm.protoIdToDepth(protoId0), 1);


        // mint clone at depth 1
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 1);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone
        uint256 index1 = 1;
        (uint256 cloneId1, uint256 protoId1) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index1);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);


        // mint clone at depth 2
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 3);
        // mint clone
        (uint256 cloneId2, uint256 protoId2) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 2);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);


        // dissolve middle clone sibling
        vm.startPrank(eoa2);
        dm.dissolve(protoId1, cloneId1);
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(dm.protoIdToIndexHead(protoId2), 0);
        assertEq(dm.protoIdToDepth(protoId2), 2);


        // sell nft to first clone sibling holder
        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(dm.protoIdToIndexHead(protoId2), 2);
        assertEq(dm.protoIdToDepth(protoId2), 1);


        vm.startPrank(eoa1);
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(dm.protoIdToIndexHead(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);
    }

    function testMultiCannotMintCloneAtPrevIndex() public {
        // mint clone at head
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 cloneId0, uint256 protoId0) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId0), eoa1);
        assertEq(dm.protoIdToDepth(protoId0), 1);


        // mint clone at depth 1
        vm.startPrank(eoa2);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 1);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone
        (uint256 cloneId1, uint256 protoId1) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId1), eoa2);
        assertEq(protoId1, protoId0);
        assertEq(dm.protoIdToDepth(protoId1), 2);


        // mint clone at depth 2
        vm.startPrank(eoa3);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // mint clone with invalid amount
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 2);
        // mint clone with invalid depth
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE+1, false, 3);
        // mint clone
        (uint256 cloneId2, uint256 protoId2) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 2);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId2), eoa3);
        assertEq(protoId2, protoId1);
        assertEq(dm.protoIdToDepth(protoId2), 3);


        assertEq(dm.protoIdToIndexHead(protoId2), 0);

        vm.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId0), address(0));
        assertEq(nft.ownerOf(nftId), eoa1);
        assertEq(dm.protoIdToIndexHead(protoId2), 1);
        assertEq(dm.protoIdToDepth(protoId2), 2);


        vm.startPrank(eoa1);
        nft.safeTransferFrom(eoa1, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId1), address(0));
        assertEq(nft.ownerOf(nftId), eoa2);
        assertEq(dm.protoIdToIndexHead(protoId2), 2);
        assertEq(dm.protoIdToDepth(protoId2), 1);


        vm.startPrank(eoa2);
        nft.safeTransferFrom(eoa2, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(dm.ownerOf(cloneId2), address(0));
        assertEq(nft.ownerOf(nftId), eoa3);
        assertEq(dm.protoIdToIndexHead(protoId2), 3);
        assertEq(dm.protoIdToDepth(protoId2), 0);


        vm.startPrank(eoa4);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        //connot mint clone at previous indices
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        //
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.IndexInvalid.selector));
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 2);

        (uint256 cloneId3, uint256 protoId3) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 3);
        vm.stopPrank();
        // check successful mint
        assertEq(dm.ownerOf(cloneId3), eoa4);
        assertEq(dm.protoIdToIndexHead(protoId3), 3);
        assertEq(dm.protoIdToDepth(protoId0), 1);
    }
}
