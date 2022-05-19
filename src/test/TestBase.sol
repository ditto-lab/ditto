// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
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

contract TestBase is Test, DittoMachine {
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
            address ERC20Contract, uint8 heat, bool floor, uint256 term, uint256 start) = dm.cloneIdToShape(cloneId);

        CloneShape memory shape = CloneShape(tokenId, worth, ERC721Contract, ERC20Contract, heat, floor, term, start);
        return shape;
    }
}
