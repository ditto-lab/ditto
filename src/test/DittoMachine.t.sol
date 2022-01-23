// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "ds-test/test.sol";
import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../DittoMachine.sol";

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
}

contract ContractTest is DSTest {
    DittoMachine dm;
    address dmAddr;

    UnderlyingNFT nft;
    address nftAddr;

    Currency curr;
    address currAddr;

    function setUp() public {
        dm = new DittoMachine();
        dmAddr = address(dm);

        nft = new UnderlyingNFT();
        nftAddr = address(nft);

        curr = new Currency();
        currAddr = address(curr);
    }

    function generateAddress(bytes memory str) internal pure returns (address) {
        return address(bytes20(uint160(uint256(keccak256(str)))));
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
        address nftOwner = generateAddress("nft owner");
        uint256 nftId = 5;
        nft.mint(nftOwner, 5);

        dm.duplicate(nftAddr, nftId, currAddr, 1, true);
    }
}