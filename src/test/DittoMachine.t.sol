// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./DittoTestBase.sol";

contract ContractTest is DittoTestBase {

    constructor() {}

    // function testNameAndSymbol() public {
    //     assertEq(dm.name(), "Ditto");
    //     assertEq(dm.symbol(), "DTO");
    // }

    // function testTokenUri() public {
    //     uint nftId721 = nft.mint();
    //     string memory uri721 = nft.tokenURI(nftId721);
    //     currency.mint(address(this), MIN_AMOUNT_FOR_NEW_CLONE);
    //     currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
    //     (uint cloneId0, ) = dm.duplicate(address(this), nftAddr, nftId721, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
    //     assertEq(uri721, dm.uri(cloneId0));
    // }

    // function testTokenUri1155() public {
    //     uint nftId1155 = nft1155.mint(eoaSeller, 1);
    //     string memory uri1155 = nft1155.uri(nftId1155);
    //     currency.mint(address(this), MIN_AMOUNT_FOR_NEW_CLONE);
    //     currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
    //     (uint cloneId1, ) = dm.duplicate(address(this), nft1155Addr, nftId1155, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
    //     assertEq(uri1155, dm.uri(cloneId1));
    // }

    // DittoMachine should revert when ether is sent to it
    function testSendEther() public {
        assertEq(dmAddr.balance, 0);
        (bool success, ) = dmAddr.call{value: 10}("");
        assert(!success);
        assertEq(dmAddr.balance, 0);
    }

    function testNoFallback() public {
        // fallback() should revert
        (bool success, ) = dmAddr.call("0x12345678");
        assert(!success);
    }

    // test obvious reverts in `duplicate()`
    function testDuplicateReverts() public {
        // when amount < MIN_AMOUNT_FOR_NEW_CLONE
        uint nftId = nft.mint();
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoa1);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalidMin.selector));
        // MIN_AMOUNT_FOR_NEW_CLONE is the minimum amount for a clone
        dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, 1, false, 0);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.InvalidFloorId.selector));
        dm.duplicate(eoa1, nftAddr, 1, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.ZeroAddress.selector));
        dm.duplicate(address(0), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);

        vm.stopPrank();
        // TODO: test revert when clone has been minted.
    }

    function testFailDuplicateForFloor(uint128 _currAmount) public {
        dm.duplicate(address(this), nftAddr, FLOOR_ID, currencyAddr, _currAmount, true, 0);
    }

    // test that a floor clone is minted
    function testDuplicateMintFloor() public {
        nft.mint();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint cloneId, uint protoId) = dm.duplicate(address(bidder), nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            protoId,
            uint(keccak256(abi.encodePacked(
                nftAddr,
                FLOOR_ID,
                currencyAddr,
                true
            )))
        );
        assertEq(
            cloneId,
            uint(keccak256(abi.encodePacked(protoId, dm.protoIdToIndexHead(protoId))))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        // oracle assertions
        uint128[] memory secondsAgos = new uint128[](1);
        secondsAgos[0] = 0;
        uint128[] memory obs = dm.observe(protoId, secondsAgos);
        assertEq(obs.length, 1);
        assertEq(obs[0], 0);

        vm.warp(block.timestamp+10);
        obs = dm.observe(protoId, secondsAgos);
        assertEq(obs[0], getCloneShape(cloneId).worth*10);
    }

    // test that a non-floor clone is minted
    function testDuplicateMintClone() public {
        uint nftId = nft.mint();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        uint index = 0;
        (uint cloneId, uint protoId)  = dm.duplicate(address(bidder), nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            protoId,
            uint(keccak256(abi.encodePacked(
                nftAddr,
                uint(0),
                currencyAddr,
                false
            )))
        );
        assertEq(
            cloneId,
            uint(keccak256(abi.encodePacked(protoId, index)))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        // oracle assertions
        uint128[] memory secondsAgos = new uint128[](1);
        secondsAgos[0] = 0;
        uint128[] memory obs = dm.observe(protoId, secondsAgos);
        assertEq(obs.length, 1);
        assertEq(obs[0], 0);

        vm.warp(block.timestamp+10);
        obs = dm.observe(protoId, secondsAgos);
        assertEq(obs[0], getCloneShape(cloneId).worth*10);
    }

    // test a clone is correctly transferred
    function testDuplicateTransfer() public {
        uint nftId = nft.mint();
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint cloneId1, uint protoId1) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId1), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint subsidy1 = dm.cloneIdToSubsidy(cloneId1);
        console.log(subsidy1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth + subsidy1, currency.balanceOf(dmAddr));

        // ensure correct oracle related values
        {
            uint128[] memory secondsAgos = new uint128[](1);
            secondsAgos[0] = 0;
            uint128[] memory obs = dm.observe(protoId1, secondsAgos);
            assertEq(obs.length, 1);
            assertEq(obs[0], 0);

            vm.warp(block.timestamp+10);
            obs = dm.observe(protoId1, secondsAgos);
            assertEq(obs[0], shape1.worth*10);
        }

        // increment time so that clone's term is in past
        vm.roll(block.number+1);
        vm.warp(block.timestamp + BASE_TERM-10); // -10 to account for oracle section above

        assertEq(shape1.term, block.timestamp);

        uint128 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId1);
        uint128 minAmountWithoutSubsidy = shape1.worth;
        assertEq(minAmountToBuyClone, minAmountWithoutSubsidy + (minAmountWithoutSubsidy * (MIN_FEE*2) / DNOM));

        currency.mint(eoa2, minAmountToBuyClone);
        vm.startPrank(eoa2);
        currency.approve(dmAddr, minAmountToBuyClone);

        vm.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        // this reverts as we pass lower than minimum purchase amount
        dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, minAmountToBuyClone - 1, false, 0);

        (uint cloneId2, ) = dm.duplicate(eoa2, nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        vm.stopPrank();

        assertEq(dm.ownerOf(cloneId2), eoa2);

        // ensure that a clone is transferred, not minted
        assertEq(cloneId1, cloneId2);

        CloneShape memory shape2 = getCloneShape(cloneId2);

        // ensure correct oracle related values
        {
            uint128[] memory secondsAgos = new uint128[](1);
            secondsAgos[0] = 0;
            uint128[] memory obs1 = dm.observe(protoId1, secondsAgos);
            assertEq(obs1.length, 1);
            assertEq(obs1[0], shape1.worth*BASE_TERM, "obs1[0]!=shape1.worth");

            vm.warp(block.timestamp+10);
            uint128[] memory obs2 = dm.observe(protoId1, secondsAgos);
            assertEq(obs2[0], obs1[0]+(shape2.worth*10), "obs2[0], obs1[0]+(shape2.worth*10)");
        }

        uint subsidy2 = dm.cloneIdToSubsidy(cloneId2);

        // ensure complete purchase amount is taken from `eoa2`
        assertEq(currency.balanceOf(eoa2), 0);

        uint subsidyFundsToEoa1 = currency.balanceOf(eoa1) - shape1.worth;

        {
            uint subsidyFundsToDitto = subsidy2 - subsidy1;

            // ensure the difference between bid amount and clone's worth is distributed
            // between subsidy and `eoa1` (from which the clone was taken)
            assertEq(subsidyFundsToDitto + subsidyFundsToEoa1, minAmountToBuyClone - shape2.worth, "subsidy");
        }
        // ensure DittoMachine's complete erc20 balance is accounted for
        assertEq(currency.balanceOf(dmAddr), subsidy2 + shape2.worth, "ditto machine balance");
        // ensure every erc20 token is accounted for
        assertEq(
            currency.balanceOf(eoa1),
            currency.totalSupply() - currency.balanceOf(dmAddr) - currency.balanceOf(eoa2)
        );

        // TODO: test clone transfer when clone's term is in future
        // TODO: test clone transfer when it's worth is less than the floor's worth
    }

    function testDissolve() public {
        uint nftId = nft.mint();
        currency.mint(eoa1, type(uint).max);

        vm.startPrank(eoa1);
        currency.approve(dmAddr, type(uint).max);

        // mint a clone
        uint index = 0;
        (uint cloneId, uint protoId) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, index);
        vm.warp(block.timestamp+10);
        CloneShape memory shape1 = getCloneShape(cloneId);

        vm.expectRevert(); // revert with invalid cloneId
        dm.dissolve(protoId, 0);

        vm.expectRevert(); // revert with invalid protoId
        dm.dissolve(0, cloneId);

        vm.expectRevert(); // revert with unminted cloneId
        dm.dissolve(protoId, uint(keccak256(abi.encodePacked(protoId, index+1))) );

        uint subsidy = uint(dm.cloneIdToSubsidy(cloneId));
        // eoa1 should be able to dissolve the clone it owns
        dm.dissolve(protoId, cloneId);
        assertEq(currency.balanceOf(dmAddr), subsidy, "testDissolve_e1");
        assertEq(currency.balanceOf(eoa1), type(uint).max - subsidy, "testDissolve_e2");
        // ensure the clone is burned
        assertEq(dm.ownerOf(cloneId), address(0));
        {
            uint128[] memory secondsAgos = new uint128[](1);
            secondsAgos[0] = 0;
            uint128[] memory obs1 = dm.observe(protoId, secondsAgos);
            assertEq(obs1.length, 1);
            assertEq(obs1[0], shape1.worth*10, "obs1[0]!=shape1.worth");
        }

        vm.warp(block.timestamp + 100);

        (cloneId, protoId) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, ++index);
        {
            uint128[] memory secondsAgos = new uint128[](1);
            secondsAgos[0] = 0;
            uint128[] memory obs1 = dm.observe(protoId, secondsAgos);
            assertEq(obs1.length, 1);
            assertEq(obs1[0], shape1.worth*10, "obs1[0]!=shape1.worth");
        }

        CloneShape memory shape = getCloneShape(cloneId);

        vm.stopPrank();

        vm.startPrank(eoa2);
        // eoa2 should not able to dissolve someeone else's clone
        vm.expectRevert(abi.encodeWithSelector(DittoMachine.NotAuthorized.selector));
        dm.dissolve(protoId, cloneId);
        vm.stopPrank();

        vm.prank(eoa1);
        dm.setApprovalForAll(eoa2, true);

        vm.prank(eoa2);
        vm.warp(block.timestamp + 100);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for `cloneId`
        dm.dissolve(protoId, cloneId);
        assertEq(dm.ownerOf(cloneId), address(0));
        {
            uint128[] memory secondsAgos = new uint128[](1);
            secondsAgos[0] = 0;
            uint128[] memory obs1 = dm.observe(protoId, secondsAgos);
            assertEq(obs1.length, 1);
            assertEq(obs1[0], (shape1.worth*10)+(shape.worth*100), "obs1[0]!=shape1.worth");
        }

        shape = getCloneShape(cloneId);

        vm.startPrank(eoa1);
        vm.warp(block.timestamp + 200);
        (cloneId, protoId) = dm.duplicate(eoa1, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, ++index);

        shape = getCloneShape(cloneId);

        dm.setApprovalForAll(eoa2, true);
        vm.stopPrank();

        vm.prank(eoa2);
        vm.warp(block.timestamp + 10);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for all the clones it owns
        dm.dissolve(protoId, cloneId);
        assertEq(dm.ownerOf(cloneId), address(0));
    }

    function testGetMinAmountForCloneTransfer() public {
        assertEq(dm.getMinAmountForCloneTransfer(0), MIN_AMOUNT_FOR_NEW_CLONE);

        // TODO: test with existing clone and different timeLeft values
    }

    function testSellUnderlying() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft.mint(eoaSeller);
        assertEq(nft.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint cloneId1, ) = dm.duplicate(eoaBidder, nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint subsidy1 = dm.cloneIdToSubsidy(cloneId1);
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

    function testSellUnderlying1155() public {
        vm.startPrank(eoaSeller);
        uint nftId = nft1155.mint(eoaSeller, 1);
        assertEq(nft1155.balanceOf(eoaSeller, nftId), 1);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint cloneId1, ) = dm.duplicate(eoaBidder, nft1155Addr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint subsidy1 = dm.cloneIdToSubsidy(cloneId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth, currency.balanceOf(dmAddr) - subsidy1);

        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.startPrank(eoaSeller);
        nft1155.safeTransferFrom(eoaSeller, dmAddr, nftId, 1, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), shape1.worth + subsidy1);
        assertEq(currency.balanceOf(dmAddr), 0);
    }

    function testSellUnderlying1155Batch() public {
        uint[] memory nftIds = new uint[](5);
        for (uint i; i < nftIds.length; i++) {
            nftIds[i] = nft1155.mint(eoaSeller, 1);
            assertEq(nft1155.balanceOf(eoaSeller, nftIds[i]), 1);
        }

        address eoaBidder = generateAddress("eoaBidder");
        vm.startPrank(eoaBidder);

        // buy a clone using the minimum purchase amount
        uint[] memory cloneIds = new uint[](nftIds.length);
        uint[] memory protoIds = new uint[](nftIds.length);
        uint[] memory amounts = new uint[](nftIds.length);
        CloneShape[] memory shapes = new CloneShape[](nftIds.length);
        for (uint j; j < cloneIds.length; j++) {
            currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
            currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

            (cloneIds[j], protoIds[j]) = dm.duplicate(eoaBidder, nft1155Addr, nftIds[j], currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
            shapes[j] = getCloneShape(cloneIds[j]);
            assertEq(dm.ownerOf(cloneIds[j]), eoaBidder);
            amounts[j] = 1;
        }

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE * cloneIds.length);

        uint subsidy1 = dm.cloneIdToSubsidy(cloneIds[0]);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneIds[0]);
        assertEq(shape1.worth, MIN_AMOUNT_FOR_NEW_CLONE - subsidy1);

        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.startPrank(eoaSeller);

        address[] memory currencyAddrArray = new address[](5);
        for (uint i=0;i<5;i++) {
            currencyAddrArray[i] = currencyAddr;
        }
        bool[] memory floorArray = new bool[](5);
        for (uint i=0;i<5;i++) {
            floorArray[i] = false;
        }
        nft1155.safeBatchTransferFrom(
            eoaSeller,
            dmAddr,
            nftIds,
            amounts,
            abi.encode(
                currencyAddrArray,
                floorArray
            )
        );
        vm.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), (shape1.worth + subsidy1)*5);
        assertEq(currency.balanceOf(dmAddr), 0);
    }

    function testSellUnderlyingWithRoyalties() public {
        vm.startPrank(eoaSeller);
        uint nftId  =nftWR.mint(eoaSeller);
        assertEq(nftWR.ownerOf(nftId), eoaSeller);
        vm.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint cloneId1, ) = dm.duplicate(eoaBidder, nftWRAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint subsidy1 = dm.cloneIdToSubsidy(cloneId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth, currency.balanceOf(dmAddr) - subsidy1);

        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        vm.startPrank(eoaSeller);
        nftWR.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();

        uint royaltyAmount = (MIN_AMOUNT_FOR_NEW_CLONE - (MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM)) * 10 / 100;
        assertEq(currency.balanceOf(nftWR.royaltyReceiver()), royaltyAmount);
        assertEq(currency.balanceOf(eoaSeller), (shape1.worth + subsidy1) - royaltyAmount);
    }
}
