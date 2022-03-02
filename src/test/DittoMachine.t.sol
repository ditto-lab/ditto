// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "../DittoMachine.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {Bidder, DittoMachine} from "./Bidder.sol";
import {ERC721, IERC2981, UnderlyingNFTWithRoyalties, UnderlyingNFT} from "./UnderlyingNFTWithRoyalties.sol";


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

    UnderlyingNFTWithRoyalties nftWR;
    address nftWRAddr;

    Currency currency;
    address currencyAddr;

    uint256 nftTokenId = 0;

    Bidder immutable bidder;

    constructor() {
        dm = new DittoMachine();

        bidder = new Bidder(dmAddr);
    }

    function setUp() public {
        cheats.warp(INIT_TIME); // bring timestamp to a realistic number

        dm = new DittoMachine();
        dmAddr = address(dm);

        nft = new UnderlyingNFT();
        nftAddr = address(nft);

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

    // DittoMachine should revert when ether is sent to it
    function testSendEther() public {
        assertEq(dmAddr.balance, 0);
        (bool success, ) = dmAddr.call{value: 10}("");
        assert(!success);
        assertEq(dmAddr.balance, 0);
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
        dm.duplicate(nftAddr, nftId, currencyAddr, 1, false);

        cheats.stopPrank();
        // TODO: test revert when clone has been minted.
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, _currAmount, true);
    }

    // test that a floor clone is minted
    function testDuplicateMintFloor() public {
        mintNft();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 cloneId = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                FLOOR_ID,
                currencyAddr,
                true
            )))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);
        assertEq(dm.cloneIdToCumulativePrice(cloneId), 0);
        assertEq(dm.cloneIdToTimestampLast(cloneId), INIT_TIME);
    }

    // test that a non-floor clone is minted
    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidder));
        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(0),
                currencyAddr,
                false
            )))
        );
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(dm.cloneIdToSubsidy(cloneId), MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);
        assertEq(dm.cloneIdToCumulativePrice(cloneId), 0);
        assertEq(dm.cloneIdToTimestampLast(cloneId), INIT_TIME);
    }

    // test a clone is correctly transferred
    function testDuplicateTransfer() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint256 cloneId1 = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        assertEq(dm.ownerOf(cloneId1), eoa1);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoa1), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId1), 0);
        assertEq(dm.cloneIdToTimestampLast(cloneId1), INIT_TIME);

        uint256 subsidy1 = dm.cloneIdToSubsidy(cloneId1);
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
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone - 1, false);

        uint256 cloneId2 = dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId2), eoa2);

        // ensure that a clone is transferred, not minted
        assertEq(cloneId1, cloneId2);

        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId1), shape1.worth * BASE_TERM);
        assertEq(dm.cloneIdToTimestampLast(cloneId1), block.timestamp);

        CloneShape memory shape2 = getCloneShape(cloneId2);
        uint256 subsidy2 = dm.cloneIdToSubsidy(cloneId2);

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
        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        // eoa1 should be able to dissolve the clone it owns
        dm.dissolve(cloneId);
        // ensure the clone is burned
        assertEq(dm.ownerOf(cloneId), address(0));
        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId), 0);
        assertEq(dm.cloneIdToTimestampLast(cloneId), INIT_TIME);

        cheats.warp(block.timestamp + 100);
        // mint another clone with the same `cloneId` since we are passing the same arguments as before
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId), 0);
        assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);

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
        assertEq(dm.cloneIdToCumulativePrice(cloneId), shape.worth * 100);
        assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);

        uint lastCumulativePrice = dm.cloneIdToCumulativePrice(cloneId);
        shape = getCloneShape(cloneId);

        cheats.startPrank(eoa1);
        cheats.warp(block.timestamp + 200);
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);

        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId), lastCumulativePrice + (shape.worth * 200));
        assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);

        lastCumulativePrice = dm.cloneIdToCumulativePrice(cloneId);
        shape = getCloneShape(cloneId);

        dm.setApprovalForAll(eoa2, true);
        cheats.stopPrank();

        cheats.prank(eoa2);
        cheats.warp(block.timestamp + 10);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for all the clones it owns
        dm.dissolve(cloneId);
        // ensure correct oracle related values
        assertEq(dm.cloneIdToCumulativePrice(cloneId), lastCumulativePrice + (shape.worth * 10));
        assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);
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
        uint256 cloneId1 = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        CloneShape memory shape = getCloneShape(cloneId1);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 subsidy1 = dm.cloneIdToSubsidy(cloneId1);
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
        assertEq(dm.cloneIdToCumulativePrice(cloneId1), shape.worth * 100);
        assertEq(dm.cloneIdToTimestampLast(cloneId1), block.timestamp);
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
        uint256 cloneId1 = dm.duplicate(nftWRAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 subsidy1 = dm.cloneIdToSubsidy(cloneId1);
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
        assertEq(dm.cloneIdToCumulativePrice(cloneId1), shape1.worth * 100);
        assertEq(dm.cloneIdToTimestampLast(cloneId1), block.timestamp);
    }

    function testHeatIncrease() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
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

            uint256 lastCumulativePrice = dm.cloneIdToCumulativePrice(cloneId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);

            // ensure correct oracle related values
            assertEq(dm.cloneIdToCumulativePrice(cloneId), lastCumulativePrice + (shape.worth * i));
            assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);

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
        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
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

            uint256 lastCumulativePrice = dm.cloneIdToCumulativePrice(cloneId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);

            // ensure correct oracle related values
            assertEq(dm.cloneIdToCumulativePrice(cloneId), lastCumulativePrice + (shape.worth * ((BASE_TERM-1) + shape.heat**2)));
            assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);

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
        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
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

            uint256 lastCumulativePrice = dm.cloneIdToCumulativePrice(cloneId);
            dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);

            // ensure correct oracle related values
            assertEq(dm.cloneIdToCumulativePrice(cloneId), lastCumulativePrice + (shape.worth * time));
            assertEq(dm.cloneIdToTimestampLast(cloneId), block.timestamp);
            shape = getCloneShape(cloneId);

            cheats.stopPrank();
        }
    }
}
