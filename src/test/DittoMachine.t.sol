// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
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

}

contract ContractTest is DSTest {
    CheatCodes constant cheats = CheatCodes(HEVM_ADDRESS);

    DittoMachine dm;
    address dmAddr;

    UnderlyingNFT nft;
    address nftAddr;

    Currency currency;
    address currencyAddr;

    uint256 nftTokenId = 0;

    Bidder immutable bidder;
    BidderWithReceiver immutable bidderWR;
    BidderWithWrongReceiver immutable bidderWWR;

    bytes32 immutable FLOOR_HASH;
    uint256 immutable DNOM;

    constructor() {
        dm = new DittoMachine();
        FLOOR_HASH = dm.FLOOR_HASH();
        DNOM = dm.DNOM();

        bidder = new Bidder(dmAddr);
        bidderWR = new BidderWithReceiver(dmAddr);
        bidderWWR = new BidderWithWrongReceiver(dmAddr);
    }

    function setUp() public {
        dm = new DittoMachine();
        dmAddr = address(dm);

        nft = new UnderlyingNFT();
        nftAddr = address(nft);

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

    function testNameAndSymbol() public {
        assertEq(dm.name(), "Ditto");
        assertEq(dm.symbol(), "DTO");
    }

    // DittoMachine should not accept any ether sent to it
    function testSendEther() public {
        assertEq(dmAddr.balance, 0);
        (bool success, ) = dmAddr.call{value: 10}("");
        assert(!success);
        assertEq(dmAddr.balance, 0);
    }

    // DNOM is the minimum amount for a clone
    function testFailDuplicateForLowAmount() public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, 1, true);
    }

    function testWhenBidderDoesNotImplementOnErc721Received() public {
        currency.mint(address(bidder), DNOM);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, DNOM);

        cheats.expectRevert(bytes(""));
        dm.duplicate(
            nftAddr,
            uint256(FLOOR_HASH),
            currencyAddr,
            DNOM,
            true
        );
    }

    function testWhenBidderImplementsWrongOnErc721Received() public {
        currency.mint(address(bidderWWR), DNOM);
        cheats.startPrank(address(bidderWWR));
        currency.approve(dmAddr, DNOM);

        cheats.expectRevert(bytes("UNSAFE_RECIPIENT"));
        dm.duplicate(
            nftAddr,
            uint256(FLOOR_HASH),
            currencyAddr,
            DNOM,
            true
        );
    }

    function testDuplicateMintFloor() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWR), DNOM);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, DNOM);

        uint256 cloneId = dm.duplicate(
            nftAddr,
            uint256(FLOOR_HASH),
            currencyAddr,
            DNOM,
            true
        );

        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(FLOOR_HASH),
                currencyAddr,
                true
            )))
        );

        cheats.stopPrank();
        assertEq(dm.ownerOf(cloneId), address(bidderWR));
        string memory dmTokenURI = dm.tokenURI(cloneId);
        string memory nftTokenURI = nft.tokenURI(nftId);

        // TODO ensure this is the expected behavior
        assert(keccak256(abi.encode(dmTokenURI)) != keccak256(abi.encode(nftTokenURI)));
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, _currAmount, true);
    }

    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWR), DNOM);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, DNOM);

        uint256 cloneId = dm.duplicate(
            nftAddr,
            0,
            currencyAddr,
            DNOM,
            false
        );

        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(0),
                currencyAddr,
                false
            )))
        );

        string memory dmTokenURI = dm.tokenURI(cloneId);
        string memory nftTokenURI = nft.tokenURI(nftId);

        // TODO ensure this is the expected behavior
        assertEq(dmTokenURI, nftTokenURI);
    }
}