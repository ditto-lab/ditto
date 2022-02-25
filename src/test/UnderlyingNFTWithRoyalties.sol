pragma solidity ^0.8.4;

import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC721, UnderlyingNFT} from "./UnderlyingNFT.sol";

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
