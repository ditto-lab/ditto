pragma solidity ^0.8.4;

import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC721, UnderlyingNFT, UnderlyingNFT1155} from "./UnderlyingNFT.sol";

// reverts on supportsInterface().
contract UnderlyingNFTWithRevert1 is UnderlyingNFT, IERC2981 {

    function royaltyInfo(
        uint /*_tokenId*/,
        uint /*_salePrice*/
    ) external view returns (
        address receiver,
        uint royaltyAmount
    ) {}

    function supportsInterface(bytes4) public pure override(ERC721, IERC165) returns (bool) {
        revert();
    }
}

// reverts on royaltyInfo
contract UnderlyingNFTWithRevert2 is UnderlyingNFT, IERC2981 {

    function royaltyInfo(
        uint /*_tokenId*/,
        uint /*_salePrice*/
    ) external view returns (
        address receiver,
        uint royaltyAmount
    ) {
        revert();
    }

    function supportsInterface(bytes4) public pure override(ERC721, IERC165) returns (bool) {
        return true;
    }
}

// reverts on royaltyInfo
contract UnderlyingNFTWithZeroReceiver is UnderlyingNFT, IERC2981 {

    function royaltyInfo(
        uint /*_tokenId*/,
        uint /*_salePrice*/
    ) external view returns (
        address receiver,
        uint royaltyAmount
    ) {}

    function supportsInterface(bytes4) public pure override(ERC721, IERC165) returns (bool) {
        return true;
    }
}

contract UnderlyingNFTWithFullRoyalty is UnderlyingNFT, IERC2981 {

    function royaltyInfo(
        uint /*_tokenId*/,
        uint _salePrice
    ) external view returns (
        address receiver,
        uint royaltyAmount
    ) {
        royaltyAmount = _salePrice;
    }

    function supportsInterface(bytes4) public pure override(ERC721, IERC165) returns (bool) {
        return true;
    }
}

contract UnderlyingNFTWithHigherRoyalty is UnderlyingNFT, IERC2981 {

    function royaltyInfo(
        uint /*_tokenId*/,
        uint _salePrice
    ) external view returns (
        address receiver,
        uint royaltyAmount
    ) {
        royaltyAmount = _salePrice+1;
    }

    function supportsInterface(bytes4) public pure override(ERC721, IERC165) returns (bool) {
        return true;
    }
}