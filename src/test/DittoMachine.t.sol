// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "../DittoMachine.sol";
import "./Bidder.sol";
import "./BidderWithReceiver.sol";
import "./BidderWithWrongReceiver.sol";

contract UnderlyingNFT is ERC721 {
    constructor() ERC721("Underlying", "UNDER") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string(abi.encodePacked("id: ", Strings.toString(id)));
    }
}

contract UnderlyingNFTWithRoyalties is UnderlyingNFT, IERC2981 {

    address immutable public royaltyReceiver;

    constructor(address _receiver) {
        royaltyReceiver = _receiver;
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        receiver = royaltyReceiver;
        royaltyAmount = _salePrice * 10 / 100;
    }

    function supportsInterface(bytes4 interfaceId) public pure override(ERC721, IERC165) returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f || // ERC165 Interface ID for ERC721Metadata
            interfaceId == 0x2a55205a; // ERC165 Interface ID for ERC2981
    }

}

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
    BidderWithReceiver immutable bidderWR;
    BidderWithWrongReceiver immutable bidderWWR;

    constructor() {
        dm = new DittoMachine();

        bidder = new Bidder(dmAddr);
        bidderWR = new BidderWithReceiver(dmAddr);
        bidderWWR = new BidderWithWrongReceiver(dmAddr);
    }

    function setUp() public {
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
        return address(bytes20(uint160(uint256(keccak256(str)))));
    }

    function mintNft() internal returns (uint256) {
        address nftOwner = generateAddress(bytes(Strings.toString(nftTokenId)));
        nft.mint(nftOwner, nftTokenId);

        return nftTokenId++;
    }

    function getCloneShape(uint256 cloneId) internal view returns (CloneShape memory) {
        (uint256 tokenId, uint256 worth, address ERC721Contract,
            address ERC20Contract, bool floor, uint256 term) = dm.cloneIdToShape(cloneId);

        CloneShape memory shape = CloneShape(
            tokenId,
            worth,
            ERC721Contract,
            ERC20Contract,
            floor,
            term
        );

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
        // when amount < BASE_TERM
        uint256 nftId = mintNft();
        address eoa = generateAddress("eoa");
        currency.mint(eoa, MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(eoa);

        cheats.expectRevert("DM:duplicate:_amount.invalid.min");
        // BASE_TERM is the minimum amount for a clone
        dm.duplicate(nftAddr, nftId, currencyAddr, 1, false);

        cheats.stopPrank();

        // when bidder is a contract which does not implement `onERC721Received()`
        currency.mint(address(bidder), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.expectRevert(bytes(""));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true);
        cheats.stopPrank();

        // when bidder is a contract with `onERC721Received()`
        // which doesn't return the function selector
        currency.mint(address(bidderWWR), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidderWWR));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        cheats.expectRevert(bytes("UNSAFE_RECIPIENT"));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true);
        cheats.stopPrank();
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, _currAmount, true);
    }

    // test that a floor clone is minted
    function testDuplicateMintFloor() public {
        mintNft();
        currency.mint(address(bidderWR), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 cloneId = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, true);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidderWR));
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
    }

    // test that a non-floor clone is minted
    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWR), MIN_AMOUNT_FOR_NEW_CLONE);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId), address(bidderWR));
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
        assertEq(minAmountToBuyClone, minAmountWithoutSubsidy + (minAmountWithoutSubsidy * MIN_FEE / DNOM));

        currency.mint(eoa2, minAmountToBuyClone);
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, minAmountToBuyClone);

        cheats.expectRevert(bytes("DM:duplicate:_amount.invalid.min"));
        // this reverts as we pass lower than minimum purchase amount
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone - 1, false);

        uint256 cloneId2 = dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId2), eoa2);

        // ensure that a clone is transferred, not minted
        assertEq(cloneId1, cloneId2);

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

        // mint another clone with the same `cloneId` since we are passing the same arguments as before
        dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        cheats.stopPrank();
        address eoa2 = generateAddress("eoa2");

        cheats.startPrank(eoa2);
        // eoa2 should not able to dissolve someeone else's clone
        cheats.expectRevert("NOT_AUTHORIZED");
        dm.dissolve(cloneId);
        cheats.stopPrank();

        cheats.prank(eoa1);
        dm.approve(eoa2, cloneId);

        cheats.prank(eoa2);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for `cloneId`
        dm.dissolve(cloneId);
        assertEq(dm.ownerOf(cloneId), address(0));

        cheats.startPrank(eoa1);
        cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        dm.setApprovalForAll(eoa2, true);
        cheats.stopPrank();

        cheats.prank(eoa2);
        // eoa2 should be able to dissolve the clone when it's owner has given approval for all the clones it owns
        dm.dissolve(cloneId);
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
        assertEq(dm.ownerOf(cloneId1), eoaBidder);

        // ensure erc20 balances
        assertEq(currency.balanceOf(eoaBidder), 0);
        assertEq(currency.balanceOf(dmAddr), MIN_AMOUNT_FOR_NEW_CLONE);

        uint256 subsidy1 = dm.cloneIdToSubsidy(cloneId1);
        assertEq(subsidy1, MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM);

        CloneShape memory shape1 = getCloneShape(cloneId1);
        assertEq(shape1.worth, currency.balanceOf(dmAddr) - subsidy1);

        cheats.stopPrank();


        cheats.startPrank(eoaSeller);
        nft.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), shape1.worth + subsidy1);
        assertEq(currency.balanceOf(dmAddr), 0);
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

        cheats.startPrank(eoaSeller);
        nftWR.safeTransferFrom(eoaSeller, dmAddr, nftId, abi.encode(currencyAddr, false));
        cheats.stopPrank();

        uint256 royaltyAmount = (MIN_AMOUNT_FOR_NEW_CLONE - (MIN_AMOUNT_FOR_NEW_CLONE * MIN_FEE / DNOM)) * 10 / 100;
        assertEq(currency.balanceOf(nftWR.royaltyReceiver()), royaltyAmount);
        assertEq(currency.balanceOf(eoaSeller), (shape1.worth + subsidy1) - royaltyAmount);
    }
}
