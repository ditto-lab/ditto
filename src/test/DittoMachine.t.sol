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

    uint256 immutable FLOOR_ID;
    uint256 immutable DNOM;
    uint256 immutable BASE_TERM;
    uint256 immutable MIN_FEE;

    constructor() {
        dm = new DittoMachine();
        FLOOR_ID = dm.FLOOR_ID();
        DNOM = dm.DNOM();
        BASE_TERM = dm.BASE_TERM();
        MIN_FEE = dm.MIN_FEE();

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
    function testDuplicateReverts() public {
        // when amount < BASE_TERM
        uint256 nftId = mintNft();
        address eoa = generateAddress("eoa");
        currency.mint(eoa, BASE_TERM);
        cheats.startPrank(eoa);

        cheats.expectRevert("DM:duplicate:_amount.invalid");
        dm.duplicate(nftAddr, nftId, currencyAddr, 1, false);

        cheats.stopPrank();

        // when bidder is a contract which does not implement `onERC721Received()`
        currency.mint(address(bidder), BASE_TERM);
        cheats.startPrank(address(bidder));
        currency.approve(dmAddr, BASE_TERM);

        cheats.expectRevert(bytes(""));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, BASE_TERM, true);
        cheats.stopPrank();

        // when bidder is a contract with `onERC721Received()`
        // which doesn't return the function selector
        currency.mint(address(bidderWWR), BASE_TERM);
        cheats.startPrank(address(bidderWWR));
        currency.approve(dmAddr, BASE_TERM);

        cheats.expectRevert(bytes("UNSAFE_RECIPIENT"));
        dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, BASE_TERM, true);
        cheats.stopPrank();
    }

    function testFailProveDuplicateForFloor(uint256 _currAmount) public {
        uint256 nftId = mintNft();

        dm.duplicate(nftAddr, nftId, currencyAddr, _currAmount, true);
    }

    function testDuplicateMintFloor() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWR), BASE_TERM);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, BASE_TERM);

        uint256 cloneId = dm.duplicate(nftAddr, FLOOR_ID, currencyAddr, BASE_TERM, true);
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
    }

    function testDuplicateMintClone() public {
        uint256 nftId = mintNft();
        currency.mint(address(bidderWR), BASE_TERM);
        cheats.startPrank(address(bidderWR));
        currency.approve(dmAddr, BASE_TERM);

        uint256 cloneId = dm.duplicate(nftAddr, nftId, currencyAddr, BASE_TERM, false);
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
    }

    function testDuplicateTransfer() public {
        uint256 nftId = mintNft();
        address eoa1 = generateAddress("eoa1");
        currency.mint(eoa1, BASE_TERM);
        cheats.startPrank(eoa1);
        currency.approve(dmAddr, BASE_TERM);

        uint256 cloneId1 = dm.duplicate(nftAddr, nftId, currencyAddr, BASE_TERM, false);
        assertEq(dm.ownerOf(cloneId1), eoa1);
        assertEq(currency.balanceOf(dmAddr), BASE_TERM);
        cheats.stopPrank();

        address eoa2 = generateAddress("eoa2");
        uint256 minAmountToBuyClone = dm.getMinAmountForCloneTransfer(cloneId1);
        currency.mint(eoa2, minAmountToBuyClone);
        cheats.startPrank(eoa2);
        currency.approve(dmAddr, minAmountToBuyClone);

        cheats.expectRevert(bytes("DM:duplicate:_amount.invalid"));
        dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone - 1, false);

        uint256 cloneId2 = dm.duplicate(nftAddr, nftId, currencyAddr, minAmountToBuyClone, false);
        cheats.stopPrank();

        assertEq(dm.ownerOf(cloneId2), eoa2);
        assertEq(cloneId1, cloneId2);

        // TODO: test clone transfer after some time passes
    }

    function testgetMinAmountForCloneTransfer() public {
        assertEq(dm.getMinAmountForCloneTransfer(0), MIN_FEE / DNOM);

        // TODO: test with existing clone and different timeLeft values
    }
}
