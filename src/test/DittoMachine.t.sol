// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "../DittoMachine.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {Bidder, DittoMachine} from "./Bidder.sol";
import {BidderWithEjector, BidderWithBadEjector, BidderWithGassyEjector} from "./BidderWithEjector.sol";
import {ERC721, IERC2981, UnderlyingNFTWithRoyalties, UnderlyingNFT, UnderlyingNFT1155} from "./UnderlyingNFTWithRoyalties.sol";


contract Currency is ERC20 {
    constructor() ERC20("Currency", "CRY", 18) {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

interface CheatCodes {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert(bytes calldata) external;
    function warp(uint256) external;
}

contract ContractTest is DSTest, DittoMachine {
    uint256 constant INIT_TIME = 1644911858;
    CheatCodes constant cheats = CheatCodes(HEVM_ADDRESS);

    DittoMachine dm;
    address dmAddr;

    UnderlyingNFT nft;
    address nftAddr;

    UnderlyingNFT1155 nft1155;
    address nft1155Addr;

    UnderlyingNFTWithRoyalties nftWR;
    address nftWRAddr;

    Currency currency;
    address currencyAddr;

    uint256 nftTokenId = 0;
    uint256 nftTokenId1155 = 0;

    Bidder immutable bidder;
    BidderWithEjector immutable bidderWithEjector;
    BidderWithBadEjector immutable bidderWithBadEjector;
    BidderWithGassyEjector immutable bidderWithGassyEjector;

    constructor() {
        dm = new DittoMachine();

        bidder = new Bidder();
        bidderWithEjector = new BidderWithEjector();
        bidderWithBadEjector = new BidderWithBadEjector();
        bidderWithGassyEjector = new BidderWithGassyEjector();
    }

    function setUp() public {
        cheats.warp(INIT_TIME); // bring timestamp to a realistic number

        dm = new DittoMachine();
        dmAddr = address(dm);

        nft = new UnderlyingNFT();
        nftAddr = address(nft);

        nft1155 = new UnderlyingNFT1155();
        nft1155Addr = address(nft1155);

        nftWR = new UnderlyingNFTWithRoyalties(generateAddress("royaltyReceiver"));
        nftWRAddr = address(nftWR);

        currency = new Currency();
        currencyAddr = address(currency);
    }

    function generateAddress(bytes memory str) internal pure returns (address) {
        return address(bytes20(keccak256(str)));
    }

    function mintNft() internal returns (uint256) {
        address nftOwner = generateAddress(bytes(Strings.toString(nftTokenId)));
        nft.mint(nftOwner, nftTokenId);

        return nftTokenId++;
    }

    function mintNft1155() internal returns (uint256) {
        address nftOwner = generateAddress(bytes(Strings.toString(nftTokenId1155)));
        nft1155.mint(nftOwner, nftTokenId1155, 1);

        return nftTokenId1155++;
    }

    function getCloneShape(uint256 cloneId) internal view returns (CloneShape memory) {
        (uint256 tokenId, uint256 worth, address ERC721Contract,
            address ERC20Contract, uint8 heat, bool floor, uint256 term) = dm.cloneIdToShape(cloneId);

        CloneShape memory shape = CloneShape(tokenId, worth, ERC721Contract, ERC20Contract, heat, floor, term);
        return shape;
    }

    function testNameAndSymbol() public {
        assertEq(dm.name(), "Ditto");
        assertEq(dm.symbol(), "DTO");
    }

    function testTokenUri() public {
        uint256 nftId721 = mintNft();
        string memory uri721 = nft.tokenURI(nftId721);
        currency.mint(address(this), MIN_AMOUNT_FOR_NEW_CLONE);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 clone0Id, , ) = dm.duplicate(nftAddr, nftId721, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(uri721, dm.tokenURI(clone0Id));
    }

    function testTokenUri1155() public {
        uint256 nftId1155 = mintNft1155();
        string memory uri1155 = nft1155.uri(nftId1155);
        currency.mint(address(this), MIN_AMOUNT_FOR_NEW_CLONE);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        (uint256 clone1Id, , ) = dm.duplicate(nft1155Addr, nftId1155, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(uri1155, dm.tokenURI(clone1Id));
    }

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
        uint256 nftId = mintNft();
        address eoa = generateAddress("eoa");
        currency.mint(eoa, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoa);

        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalidMin.selector));
        // MIN_AMOUNT_FOR_NEW_CLONE is the minimum amount for a clone
        dm.duplicate(nftAddr, nftId, currencyAddr, 1, false, 0);

        cheats.stopPrank();
        // TODO: test revert when clone has been minted.
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, _currAmount, true, 0);
    }

    // test that a floor clone is minted
    function testDuplicateMintFloor() public {
        mintNft();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, uint256 protoId, /*uint256 index*/) = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true, 0);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            protoId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                FLOOR_ID,
                currencyAddr,
                true
            )))
        );
        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(protoId, dm.protoIdToIndex(protoId))))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.protoIdToSubsidy(protoId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);
        assertEq(dm.protoIdToCumulativePrice(protoId), 0);
        assertEq(dm.protoIdToTimestampLast(protoId), INIT_TIME);
    }

    // test that a non-floor clone is minted
    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, uint256 protoId, uint256 index)  = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            protoId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(0),
                currencyAddr,
                false
            )))
        );
        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(protoId, index)))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.protoIdToSubsidy(protoId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);
        assertEq(dm.protoIdToCumulativePrice(protoId), 0);
        assertEq(dm.protoIdToTimestampLast(protoId), INIT_TIME);
    }

    // test a clone is correctly transferred
    function testDuplicateTransfer() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId1, uint256 protoId1, /*uint256 index1*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId1), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId1), 0);
        assertEq(dm.protoIdToTimestampLast(protoId1), INIT_TIME);

        uint256 subsidy1 = dm.protoIdToSubsidy(protoId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth + subsidy1, currency.balanceOf(dmAddr));

        cheats.stopPrank();

        // increment time so that clone's term is in past
        cheats.warp(block.timestamp + BASE_TERM);
        assertEq(shape1.term, block.timestamp);
        address eoa2 = generateAddress("eoa2");

        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId1);
        uint256 minAmountWithoutSubsidy = shape1.worth;
        assertEq(minAmountToBuyClone, minAmountWithoutSubsidy + (minAmountWithoutSubsidy * (MIN_FEE*2) / DNOM));

        currency.mint(eoa2, minAmountToBuyClone);
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, minAmountToBuyClone);

        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.AmountInvalid.selector));
        // this reverts as we pass lower than minimum purchase amount
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone - 1, false, 0);

        (uint256 cloneId2, uint256 protoId2, /*uint256 index2*/) = dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId2), eoa2);

        // ensure that a clone is transferred, not minted
        assertEq(cloneId1, cloneId2);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId2), shape1.worth * BASE_TERM);
        assertEq(dm.protoIdToTimestampLast(protoId2), block.timestamp);

        CloneShape memory shape2 = getCloneShape(cloneId2);
        uint256 subsidy2 = dm.protoIdToSubsidy(protoId2);

        // ensure complete purchase amount is taken from `eoa2`
        assertEq(currency.balanceOf(eoa2), 0);

        uint256 subsidyFundsToDitto = subsidy2 - subsidy1;
        uint256 subsidyFundsToEoa1 = currency.balanceOf(eoa1) - shape1.worth;

        // ensure the difference between bid amount and clone's worth is distributed
        // between subsidy and `eoa1` (from which the clone was taken)
        assertEq(subsidyFundsToDitto + subsidyFundsToEoa1, minAmountToBuyClone - shape2.worth);
        // ensure DittoMachine's complete erc20 balance is accounted for
        assertEq(currency.balanceOf(dmAddr), subsidy2 + shape2.worth);
        // ensure every erc20 token is accounted for
        assertEq(
            currency.balanceOf(eoa1),
            currency.totalSupply() - currency.balanceOf(dmAddr) - currency.balanceOf(eoa2)
        );

        // TODO: test clone transfer when clone's term is in future
        // TODO: test clone transfer when it's worth is less than the floor's worth
    }

    function testDissolve() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, type(uint256).max);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, type(uint256).max);

        // mint a clone
        (uint256 cloneId, uint256 protoId, uint256 index) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        // eoa1 should be able to dissolve the clone it owns
        dm.dissolve(cloneId);
        // ensure the clone is burned
        assertEq(dm.ownerOf(cloneId), address(0));
        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId), 0);
        assertEq(dm.protoIdToTimestampLast(protoId), INIT_TIME);

        cheats.warp(block.timestamp + 100);
        // mint another clone with the same `cloneId` since we are passing the same arguments as before

        (cloneId, protoId, index) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId), 0);
        assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

        CloneShape memory shape = getCloneShape(cloneId);

        cheats.stopPrank();
        address eoa2 = generateAddress("eoa2");

        cheats.startPrank(eoa2);
        // eoa2 should not able to dissolve someeone else's clone
        cheats.expectRevert(abi.encodeWithSelector(DittoMachine.NotAuthorized.selector));
        dm.dissolve(cloneId);
        cheats.stopPrank();

        cheats.prank(eoa1);
        dm.approve(eoa2, cloneId);

        cheats.prank(eoa2);
        cheats.warp(block.timestamp + 100);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for `cloneId`
        dm.dissolve(cloneId);
        assertEq(dm.ownerOf(cloneId), address(0));

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId), shape.worth * 100);
        assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

        uint lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
        shape = getCloneShape(cloneId);

        cheats.startPrank(eoa1);
        cheats.warp(block.timestamp + 200);
        (cloneId, protoId, index) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * 200));
        assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

        lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
        shape = getCloneShape(cloneId);

        dm.setApprovalForAll(eoa2, true);
        cheats.stopPrank();

        cheats.prank(eoa2);
        cheats.warp(block.timestamp + 10);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for all the clones it owns
        dm.dissolve(cloneId);
        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * 10));
        assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);
        assertEq(dm.ownerOf(cloneId), address(0));
    }

    function testgetMinAmountForCloneTransfer() public {
        assertEq(dm.getMinAmountForCloneTransfer(0), MIN_AMOUNT_FOR_NEW_CLONE);

        // TODO: test with existing clone and different timeLeft values
    }

    function testSellUnderlying() public {
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
        (uint256 cloneId1, uint256 protoId1, /*uint256 index1*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
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

    function testSellUnderlying1155() public {
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nft1155.mint(eoaSeller, nftTokenId1155, 1);
        uint256 nftId = nftTokenId1155++;
        assertEq(nft1155.balanceOf(eoaSeller, nftId), 1);
        cheats.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId1, uint256 protoId1, /*uint256 index1*/) = dm.duplicate(nft1155Addr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
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
        nft1155.safeTransferFrom(eoaSeller, dmAddr, nftId, 1, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), shape1.worth + subsidy1);
        assertEq(currency.balanceOf(dmAddr), 0);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId1), shape.worth * 100);
        assertEq(dm.protoIdToTimestampLast(protoId1), block.timestamp);
    }

    function testSellUnderlying1155Batch() public {
        address eoaSeller = generateAddress("eoaSeller");
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i; i < nftIds.length; i++) {
            nft1155.mint(eoaSeller, nftTokenId1155, 1);
            nftIds[i] = nftTokenId1155++;
            assertEq(nft1155.balanceOf(eoaSeller, nftIds[i]), 1);
        }

        address eoaBidder = generateAddress("eoaBidder");
        cheats.startPrank(eoaBidder);

        // buy a clone using the minimum purchase amount
        uint256[] memory cloneIds = new uint256[](nftIds.length);
        uint256[] memory protoIds = new uint256[](nftIds.length);
        uint256[] memory indices = new uint256[](nftIds.length);
        uint256[] memory amounts = new uint256[](nftIds.length);
        CloneShape[] memory shapes = new CloneShape[](nftIds.length);
        for (uint256 j; j < cloneIds.length; j++) {
            currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
            currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

            (cloneIds[j], protoIds[j], indices[j]) = dm.duplicate(nft1155Addr, nftIds[j], currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
            shapes[j] = getCloneShape(cloneIds[j]);
            assertEq(dm.ownerOf(cloneIds[j]), eoaBidder);
            amounts[j] = 1;
        }

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE * cloneIds.length);

        uint256 subsidy1 = dm.protoIdToSubsidy(protoIds[0]);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneIds[0]);
        assertEq(shape1.worth, MIN_AMOUNT_FOR_NEW_CLONE - subsidy1);

        cheats.stopPrank();

        cheats.warp(block.timestamp + 100);
        cheats.startPrank(eoaSeller);

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
        cheats.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), (shape1.worth + subsidy1)*5);
        assertEq(currency.balanceOf(dmAddr), 0);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoIds[0]), shapes[0].worth * 100);
        assertEq(dm.protoIdToTimestampLast(protoIds[0]), block.timestamp);
    }

    function testSellUnderlyingWithRoyalties() public {
        address eoaSeller = generateAddress("eoaSeller");
        cheats.startPrank(eoaSeller);
        nftWR.mint(eoaSeller, nftTokenId);
        uint256 nftId = nftTokenId++;
        assertEq(nftWR.ownerOf(nftId), eoaSeller);
        cheats.stopPrank();

        address eoaBidder = generateAddress("eoaBidder");
        currency.mint(eoaBidder, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoaBidder);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId1, uint256 protoId1, /*uint256 index1*/) = dm.duplicate(nftWRAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
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
        nftWR.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();

        uint256 royaltyAmount = (MIN_AMOUNT_FOR_NEW_CLONE - (MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM)) * 10 / 100;
        assertEq(currency.balanceOf(nftWR.royaltyReceiver()), royaltyAmount);
        assertEq(currency.balanceOf(eoaSeller), (shape1.worth + subsidy1) - royaltyAmount);

        // ensure correct oracle related values
        assertEq(dm.protoIdToCumulativePrice(protoId1), shape1.worth * 100);
        assertEq(dm.protoIdToTimestampLast(protoId1), block.timestamp);
    }

    function testHeatIncrease() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId, /*uint256 index*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        cheats.stopPrank();

        for (uint256 i = 1; i < 221; i++) {
            // after 221 overflow error

            cheats.warp(block.timestamp + i);
            cheats.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * i));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1+i);

            cheats.stopPrank();
        }
    }

    function testHeatStatic() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId, /*uint256 index*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        cheats.stopPrank();

        for (uint256 i = 1; i < 256; i++) {
            cheats.warp(block.timestamp + (BASE_TERM-1) + shape.heat**2);

            cheats.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * ((BASE_TERM-1) + shape.heat**2)));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);

            shape = getCloneShape(cloneId);
            assertEq(shape.heat, 1);
            assertEq(shape.term, block.timestamp + (BASE_TERM-1) + shape.heat**2);

            cheats.stopPrank();
        }
    }

    function testHeatDuplicatePrice(uint16 time) public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        (uint256 cloneId, uint256 protoId, /*uint256 index*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        CloneShape memory shape = getCloneShape(cloneId);
        assertEq(shape.heat, 1);

        cheats.stopPrank();

        for (uint256 i = 1; i < 30; i++) {
            cheats.warp(block.timestamp + uint256(time));

            cheats.startPrank(eoa1);

            uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
            currency.mint(eoa1, minAmountToBuyClone);
            currency.approve(dmAddr, minAmountToBuyClone);

            uint256 timeLeft = shape.term > block.timestamp ? shape.term - block.timestamp : 0;
            uint256 termStart = shape.term - ((BASE_TERM-1) + uint256(shape.heat)**2);
            uint256 termLength = shape.term - termStart;

            uint256 auctionPrice = shape.worth + (shape.worth * timeLeft / termLength);

            assertEq(minAmountToBuyClone, (auctionPrice + (auctionPrice * MIN_FEE * (1+shape.heat) / DNOM)), "price");

            uint256 lastCumulativePrice = dm.protoIdToCumulativePrice(protoId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);

            // ensure correct oracle related values
            assertEq(dm.protoIdToCumulativePrice(protoId), lastCumulativePrice + (shape.worth * time));
            assertEq(dm.protoIdToTimestampLast(protoId), block.timestamp);
            shape = getCloneShape(cloneId);

            cheats.stopPrank();
        }
    }

    function testEjector() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWithEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(address(bidderWithEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        cheats.stopPrank();

        uint256 ejections = bidderWithEjector.ejections();
        assertEq(ejections, 1);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }

    function testEjectorWithRevert() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWithBadEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(address(bidderWithBadEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        cheats.stopPrank();

        uint256 ejections = bidderWithBadEjector.ejections();
        assertEq(ejections, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }

    function testEjectorWithOOG() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWithGassyEjector), MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(address(bidderWithGassyEjector));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        (uint256 cloneId, /*uint256 protoId*/, /*uint256 protoId*/) = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        cheats.stopPrank();

        address eoa1 = generateAddress("eoa1");
        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId);
        currency.mint(eoa1, minAmountToBuyClone);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, minAmountToBuyClone);
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false, 0);
        cheats.stopPrank();

        uint256 ejections = bidderWithGassyEjector.ejections();
        assertEq(ejections, 0);
        assertEq(dm.ownerOf(cloneId), eoa1);
    }

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
