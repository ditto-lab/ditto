pragma solidity ^0.8.4;

import {ERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {ERC1155} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UnderlyingNFT is ERC721 {
    constructor() ERC721("Underlying", "UNDER") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string(abi.encodePacked("id: ", Strings.toString(id)));
    }
}

contract UnderlyingNFT1155 is ERC1155 {
    constructor() {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
    function uri(uint256 id) public pure override returns (string memory) {
        return string(abi.encodePacked("id: ", Strings.toString(id)));
    }
}
