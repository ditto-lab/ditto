// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./TestBase.sol";

contract ContractTest is TestBase {

    constructor() {}



    function testTokenUri() public {
        uint256 nftId721 = mintNft();
        string memory uri721 = nft.tokenURI(nftId721);
        emit log(uri721);
        // currency.mint(address(this), MIN_AMOUNT_FOR_NEW_CLONE);
        // currency.approve(dmAddr, MIN_AMOUNT_FOR_NEW_CLONE);
        // uint256 clone0Id = dm.duplicate(nftAddr, nftId721, currencyAddr, MIN_AMOUNT_FOR_NEW_CLONE, false);
        // assertEq(uri721, dm.tokenURI(clone0Id));
    }
}
