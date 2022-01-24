// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../DittoMachine.sol";
import "./Bidder.sol";
import "./BidderWithReceiver.sol";

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
}

contract ContractTest is DSTest {
    CheatCodes constant cheats = CheatCodes(HEVM_ADDRESS);

    DittoMachine dm;
    address dmAddr;

    UnderlyingNFT nft;
    address nftAddr;

    Currency curr;
    address currAddr;

    uint256 nftTokenId = 0;

    Bidder bidder;
    BidderWithReceiver bidderWR;

    function setUp() public {
        dm = new DittoMachine();
        dmAddr = address(dm);

        nft = new UnderlyingNFT();
        nftAddr = address(nft);

        curr = new Currency();
        currAddr = address(curr);

        bidder = new Bidder(dmAddr);
        bidderWR = new BidderWithReceiver(dmAddr);
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

        dm.duplicate(nftAddr, nftId, currAddr, 1, true);
    }

    function testFailWhenBidderDoesNotImplementOnErc721Received() public {
        curr.mint(address(this), dm.DNOM());
        curr.approve(dmAddr, dm.DNOM());

        dm.duplicate(
            nftAddr,
            uint256(dm.FLOOR_HASH()),
            currAddr,
            dm.DNOM(),
            true
        );
    }

    function testDuplicateMintFloor() public {
        uint256 nftId = mintNft();
        curr.mint(address(bidderWR), dm.DNOM());
        cheats.startPrank(address(bidderWR));
        curr.approve(dmAddr, dm.DNOM());

        uint256 cloneId = dm.duplicate(
            nftAddr,
            uint256(dm.FLOOR_HASH()),
            currAddr,
            dm.DNOM(),
            true
        );

        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(dm.FLOOR_HASH()),
                currAddr,
                true
            )))
        );

        string memory dmTokenURI = dm.tokenURI(cloneId);
        string memory nftTokenURI = nft.tokenURI(nftId);

        // TODO ensure this is the expected behavior
        assert(keccak256(abi.encode(dmTokenURI)) != keccak256(abi.encode(nftTokenURI)));
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currAddr, _currAmount, true);
    }

    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        curr.mint(address(bidderWR), dm.DNOM());
        cheats.startPrank(address(bidderWR));
        curr.approve(dmAddr, dm.DNOM());

        uint256 cloneId = dm.duplicate(
            nftAddr,
            0,
            currAddr,
            dm.DNOM(),
            false
        );

        assertEq(
            cloneId,
            uint256(keccak256(abi.encodePacked(
                nftAddr,
                uint256(0),
                currAddr,
                false
            )))
        );

        string memory dmTokenURI = dm.tokenURI(cloneId);
        string memory nftTokenURI = nft.tokenURI(nftId);

        // TODO ensure this is the expected behavior
        assertEq(dmTokenURI, nftTokenURI);
    }
}