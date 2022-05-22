pragma solidity ^0.8.4;

import {ERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {ERC1155} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UnderlyingNFT is ERC721 {
    uint256 id = 0;
    constructor() ERC721("Underlying", "UNDER") {}

    function mint() external returns (uint256) {
        _mint(msg.sender, id);
        return id++;
    }

    function mint(address to) external returns (uint256) {
        _mint(to, id);
        return id++;
    }

    function tokenURI(uint256 _id) public pure override returns (string memory) {
        return string(abi.encodePacked("id: ", Strings.toString(_id)));
    }
}

contract UnderlyingNFT1155 is ERC1155 {
    uint256 id = 0;
    constructor() {}

    function mint(uint256 amount) external returns (uint256) {
        _mint(msg.sender, id, amount, "");
        return id++;
    }

    function mint(address to, uint256 amount) external returns (uint256) {
        _mint(to, id, amount, "");
        return id++;
    }

    function uri(uint256 _id) public pure override returns (string memory) {
        return string(abi.encodePacked("id: ", Strings.toString(_id)));
    }
}
