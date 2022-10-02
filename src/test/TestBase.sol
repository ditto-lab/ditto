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

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestBase is Test, DittoMachine {
    uint256 constant INIT_TIME = 1644911858;

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

    Bidder immutable bidder;
    BidderWithEjector immutable bidderWithEjector;
    BidderWithBadEjector immutable bidderWithBadEjector;
    BidderWithGassyEjector immutable bidderWithGassyEjector;

    address eoaSeller;
    address eoa0;
    address eoa1;
    address eoa2;
    address eoa3;
    address eoa4;

    constructor() {
        dm = new DittoMachine();

        bidder = new Bidder();
        bidderWithEjector = new BidderWithEjector();
        bidderWithBadEjector = new BidderWithBadEjector();
        bidderWithGassyEjector = new BidderWithGassyEjector();
    }

    function setUp() public virtual {
        vm.warp(INIT_TIME); // bring timestamp to a realistic number

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

        eoaSeller = generateAddress("eoaSeller");
        eoa0 = generateAddress("eoa0");
        eoa1 = generateAddress("eoa1");
        eoa2 = generateAddress("eoa2");
        eoa3 = generateAddress("eoa3");
        eoa4 = generateAddress("eoa3");
    }

    function generateAddress(bytes memory str) internal pure returns (address) {
        return address(bytes20(keccak256(str)));
    }

    function getCloneShape(uint256 cloneId) internal view returns (CloneShape memory) {
        (uint256 tokenId, address ERC721Contract,
            address ERC20Contract, uint128 worth, uint128 term, uint8 heat, bool floor) = dm.cloneIdToShape(cloneId);

        CloneShape memory shape = CloneShape(tokenId, ERC721Contract, ERC20Contract, worth, term, heat, floor);
        return shape;
    }
}
