pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {ERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {ERC1155} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from 'base64-sol/base64.sol';

contract DittoMachineSvg {
    ////////////// CONSTANT VARIABLES //////////////

    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    uint256 internal constant FLOOR_ID = uint256(0xfddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9);

    ////////////// STATE VARIABLES //////////////

    // variables essential to calculating auction/price information for each cloneId
    struct CloneShape {
        uint256 tokenId;
        address ERC721Contract;
        address ERC20Contract;
        uint8 heat;
        bool floor;
        uint128 worth;
        uint128 term;
    }

    // hash protoId with the index placement to get cloneId
    mapping(uint256 => CloneShape) public cloneIdToShape;

    constructor() {}

    ///////////////////////////////////////////
    ////////////// URI FUNCTIONS //////////////
    ///////////////////////////////////////////

    function tokenURI(uint256 id, address token, address nft, address owner, uint nftId, bool floor) public view returns (string memory) {

        if (!floor) {
            // if clone is not a floor return underlying token uri
            try ERC721(nft).tokenURI(nftId) returns (string memory uri) {
                return uri;
            } catch {
                return ERC1155(nft).uri(nftId);
            }
        } else {

            string memory _name = string(abi.encodePacked('Ditto Floor #', Strings.toString(id)));

            string memory description = string(abi.encodePacked(
                'This Ditto represents the floor price of tokens at ',
                Strings.toHexString(uint160(nft), 20)
            ));

            string memory image = Base64.encode(bytes(generateSVGofTokenById(id)));

            return string(abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                           '{"name":"',
                            _name,
                           '", "description":"',
                           description,
                           '", "attributes": [{"trait_type": "Underlying NFT", "value": "',
                           Strings.toHexString(uint160(nft), 20),
                           '"},{"trait_type": "tokenId", "value": ',
                           Strings.toString(nftId),
                           '}], "owner":"',
                           Strings.toHexString(uint160(owner), 20),
                           '", "image": "',
                           'data:image/svg+xml;base64,',
                           image,
                           '"}'
                        )
                    )
                )
            ));
        }
    }

    function generateSVGofTokenById(uint256 _tokenId) internal pure returns (string memory) {
        string memory svg = string(abi.encodePacked(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">',
            renderTokenById(_tokenId),
          '</svg>'
        ));

        return svg;
    }

    // Visibility is `public` to enable it being called by other contracts for composition.
    function renderTokenById(uint256 _tokenId) public pure returns (string memory) {
        string memory hexColor = toHexString(uint24(_tokenId), 3);
        return string(abi.encodePacked(
            '<rect width="100" height="100" rx="15" style="fill:#', hexColor, '" />',
            '<g id="face" transform="matrix(0.531033,0,0,0.531033,-279.283,-398.06)">',
              '<g transform="matrix(0.673529,0,0,0.673529,201.831,282.644)">',
                '<circle cx="568.403" cy="815.132" r="3.15"/>',
              '</g>',
              '<g transform="matrix(0.673529,0,0,0.673529,272.214,282.644)">',
                '<circle cx="568.403" cy="815.132" r="3.15"/>',
              '</g>',
              '<g transform="matrix(1,0,0,1,0.0641825,0)">',
                '<path d="M572.927,854.4C604.319,859.15 635.71,859.166 667.102,854.4" style="fill:none;stroke:black;stroke-width:0.98px;"/>',
              '</g>',
            '</g>'
        ));
    }

    // same as inspired from @openzeppelin/contracts/utils/Strings.sol except that it doesn't add "0x" as prefix.
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);

        unchecked {
            for (uint256 i = 2 * length; i > 0; --i) {
                buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
                value >>= 4;
            }
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

}