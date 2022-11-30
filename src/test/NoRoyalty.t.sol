// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./DittoTestBase.sol";
import {
    UnderlyingNFTWithRevert1,
    UnderlyingNFTWithRevert2,
    UnderlyingNFTWithZeroReceiver,
    UnderlyingNFTWithFullRoyalty,
    UnderlyingNFTWithHigherRoyalty
} from "./UnderlyingNFTMalicious.sol";

contract NoRoyaltyTest is DittoTestBase {

    UnderlyingNFTWithRevert1 r1;
    UnderlyingNFTWithRevert2 r2;
    UnderlyingNFTWithZeroReceiver r0;
    UnderlyingNFTWithFullRoyalty r100;
    UnderlyingNFTWithHigherRoyalty r101;

    constructor() {}

    function setUp() public override {
        super.setUp();

        r1 = new UnderlyingNFTWithRevert1();
        r2 = new UnderlyingNFTWithRevert2();
        r0 = new UnderlyingNFTWithZeroReceiver();
        r100 = new UnderlyingNFTWithFullRoyalty();
        r101 = new UnderlyingNFTWithHigherRoyalty();
    }

    function assertNoRoyalty(UnderlyingNFT _nft) internal {
        vm.startPrank(eoaSeller);
        uint _nftId = _nft.mint(eoaSeller);
        vm.stopPrank();

        currency.mint(eoa1, MIN_AMOUNT_FOR_NEW_CLONE);
        vm.startPrank(eoa1);
        currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);

        // buy a clone using the minimum purchase amount
        dm.duplicate(eoa1, address(_nft), _nftId, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false, 0);
        vm.stopPrank();

        vm.startPrank(eoaSeller);
        _nft.safeTransferFrom(eoaSeller, dmAddr, _nftId, abi.encode(currencyAddr, false));
        vm.stopPrank();
        assertEq(currency.balanceOf(eoaSeller), MIN_AMOUNT_FOR_NEW_CLONE);
        assertEq(currency.balanceOf(dmAddr), 0);
    }

    function testDuplicateOnNoRoyalty() public {
        assertNoRoyalty(nft);
    }
    function testDuplicateNoRoyaltyInterfaceRevert() public {
        assertNoRoyalty(UnderlyingNFT(address(r0)));
    }

    function testDuplicateOnRoyaltyInfoRevert() public {
        assertNoRoyalty(UnderlyingNFT(address(r1)));
    }

    function testDuplicateOnZeroReceiver() public {
        assertNoRoyalty(UnderlyingNFT(address(r0)));
    }

    function testDuplicateOnFullRoyalty() public {
        assertNoRoyalty(UnderlyingNFT(address(r100)));
    }

    function testDuplicateOnHigherRoyalty() public {
        assertNoRoyalty(UnderlyingNFT(address(r101)));
    }
}
