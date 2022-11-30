// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./DittoTestBase.sol";
import {BidderOnReceiveRevert} from "./Bidder.sol";
import {FallbackReceiver} from "../FallbackReceiver.sol";

contract FallbackReceiverTest is DittoTestBase {
    BidderOnReceiveRevert b;
    FallbackReceiver f;
    event Received721(address nft, uint id, address owner, address token, uint index);
    event Received1155(address nft, uint id, address owner, address token, uint index);

    constructor() {}

    function setUp() public virtual override {
        super.setUp();
        b = new BidderOnReceiveRevert();
        vm.label(address(b), "BidderOnReceiveRevert");
        f = FallbackReceiver(dm.fallbackReceiver());
        vm.label(address(f), "FallbackReceiver");
    }

    function testClaim721() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint index = 0;
        (uint cloneId, ) = dm.duplicate(address(b), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        assertEq(dm.ownerOf(cloneId), address(b), "F0");
        vm.stopPrank();

        b.setRevert(true);

        vm.startPrank(eoaSeller);
        vm.expectEmit(false, false, false, true, dm.fallbackReceiver());
        emit Received721(nftAddr, nftId, address(b), currencyAddr, index);
        nft.safeTransferFrom(eoaSeller, address(dm), nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(0), "F1");
        assertEq(nft.ownerOf(nftId), dm.fallbackReceiver(), "F2");
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE, "F3");

        vm.expectRevert();
        f.claim(nftAddr, nftId, true, address(b), currencyAddr, 0);

        b.setRevert(false);

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert();
        f.claim(nftAddr, nftId, true, address(b), currencyAddr, 0);

        vm.warp(block.timestamp - 2 days);
        f.claim(nftAddr, nftId, true, address(b), currencyAddr, 0);
    }

    function testClaim1155() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft1155.mint(eoaSeller, 1);
        assertEq(nft1155.balanceOf(eoaSeller, nftId), 1);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint index = 0;
        (uint cloneId, ) = dm.duplicate(address(b), nft1155Addr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        assertEq(dm.ownerOf(cloneId), address(b), "F0");
        vm.stopPrank();

        b.setRevert(true);

        vm.startPrank(eoaSeller);
        vm.expectEmit(false, false, false, true, dm.fallbackReceiver());
        emit Received1155(nft1155Addr, nftId, address(b), currencyAddr, index);
        nft1155.safeTransferFrom(eoaSeller, address(dm), nftId, 1, abi.encode(currencyAddr, false));
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(0), "F1");
        assertEq(nft1155.balanceOf(dm.fallbackReceiver(), nftId), 1, "F2");
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE, "F3");

        vm.expectRevert();
        f.claim(nft1155Addr, nftId, false, address(b), currencyAddr, 0);

        b.setRevert(false);

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert();
        f.claim(nft1155Addr, nftId, false, address(b), currencyAddr, 0);

        vm.warp(block.timestamp - 2 days);
        f.claim(nft1155Addr, nftId, false, address(b), currencyAddr, 0);
    }

    function testSell721() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft.mint(eoaSeller);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint index = 0;
        (uint cloneId, uint protoId) = dm.duplicate(address(b), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        assertEq(dm.ownerOf(cloneId), address(b), "F0");
        vm.stopPrank();

        b.setRevert(true);

        vm.startPrank(eoaSeller);
        vm.expectEmit(false, false, false, true, dm.fallbackReceiver());
        emit Received721(nftAddr, nftId, address(b), currencyAddr, index);
        nft.safeTransferFrom(eoaSeller, address(dm), nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(0), "F1");
        assertEq(nft.ownerOf(nftId), dm.fallbackReceiver(), "F2");
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE, "F3");

        b.setRevert(false);

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (cloneId, ) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        assertEq(dm.ownerOf(cloneId), eoa1, "F0");
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert();
        f.sell(nftAddr, nftId, true, address(b), currencyAddr, 0);

        assertEq(currency.balanceOf(dm.fallbackReceiver()), 0, "f9");

        uint beforeDmBal = currency.balanceOf(dmAddr);
        vm.warp(block.timestamp + 7 days);
        f.sell(nftAddr, nftId, true, address(b), currencyAddr, 0);

        assertEq(dm.ownerOf(cloneId), address(0));
        assertEq(nft.ownerOf(nftId), eoa1, "F1");
        assertEq(currency.balanceOf(dm.fallbackReceiver()), 0, "f10");
        assertEq(currency.balanceOf(dmAddr) - beforeDmBal, 0, "f11");

        cloneId = uint(keccak256(abi.encodePacked(protoId, dm.protoIdToIndexHead(protoId))));
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE, "f12");
    }

    function testSell1155() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft1155.mint(eoaSeller, 1);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint index = 0;
        (uint cloneId, uint protoId) = dm.duplicate(address(b), nft1155Addr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        assertEq(dm.balanceOf(address(b), cloneId), 1, "F0");
        vm.stopPrank();

        b.setRevert(true);

        vm.startPrank(eoaSeller);
        vm.expectEmit(false, false, false, true, dm.fallbackReceiver());
        emit Received1155(nft1155Addr, nftId, address(b), currencyAddr, index);
        nft1155.safeTransferFrom(eoaSeller, address(dm), nftId, 1, abi.encode(currencyAddr, false));
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(0), "F1");
        assertEq(nft1155.balanceOf(address(f), nftId), 1, "F2");
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE, "F3");

        b.setRevert(false);

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (cloneId, ) = dm.duplicate(eoa1, nft1155Addr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 1);
        assertEq(dm.ownerOf(cloneId), eoa1, "F0");
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert();
        f.sell(nft1155Addr, nftId, false, address(b), currencyAddr, 0);

        assertEq(currency.balanceOf(dm.fallbackReceiver()), 0, "f9");

        uint beforeDmBal = currency.balanceOf(dmAddr);
        vm.warp(block.timestamp + 7 days);
        f.sell(nft1155Addr, nftId, false, address(b), currencyAddr, 0);

        assertEq(dm.ownerOf(cloneId), address(0));
        assertEq(nft1155.balanceOf(eoa1, nftId), 1, "F1");
        assertEq(currency.balanceOf(dm.fallbackReceiver()), 0, "f10");
        assertEq(currency.balanceOf(dmAddr) - beforeDmBal, 0, "f11");

        cloneId = uint(keccak256(abi.encodePacked(protoId, dm.protoIdToIndexHead(protoId))));
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE, "f12");
    }
}
