pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {ERC721, ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {ERC1155, ERC1155TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC1155D} from "./ERC1155D.sol";
import {ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

interface IDittoMachine {
    function bumpSubsidy(address nft, uint id, address ERC20Contract, bool floor, uint128 amount) external;
}
contract FallbackReceiver {
    event Received721(address nft, uint id, address owner, address token, uint index);
    event Received1155(address nft, uint id, address owner, address token, uint index);

    IDittoMachine internal immutable ditto;
    mapping(bytes32 => uint) public claimDeadline;

    constructor(address _ditto) {
        ditto = IDittoMachine(_ditto);
    }

    /////// RECEIVER FUNCTIONS ////////
    /// No ERC1155 batch receiver ////

    function onERC721Received(
        address,
        address from,
        uint id,
        bytes calldata data
    ) external returns (bytes4) {
        require(from == address(ditto));

        (address ERC20Contract,, uint index, address owner,,) = abi.decode(
            data,
            (address, bool, uint, address, uint128, uint)
        );
        claimDeadline[keccak256(abi.encodePacked(msg.sender, id, owner, ERC20Contract, index))] = block.timestamp + 7 days;

        emit Received721(msg.sender, id, owner, ERC20Contract, index);

        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address from,
        uint id,
        uint amount,
        bytes calldata data
    ) external returns (bytes4) {
        require(amount == 1);
        require(from == address(ditto));
        (address ERC20Contract,, uint index, address owner,,) = abi.decode(
            data,
            (address, bool, uint, address, uint128, uint)
        );

        claimDeadline[keccak256(abi.encodePacked(msg.sender, id, owner, ERC20Contract, index))] = block.timestamp + 7 days;

        emit Received1155(msg.sender, id, owner, ERC20Contract, index);

        return this.onERC1155Received.selector;
    }

    function claim(address nft, uint id, bool isERC721, address owner, address ERC20Contract, uint index) external {
        bytes32 key = keccak256(abi.encodePacked(nft, id, owner, ERC20Contract, index));
        require(claimDeadline[key] > block.timestamp, "C");
        delete claimDeadline[key];
        if (isERC721) {
            ERC721(nft).safeTransferFrom(address(this), owner, id);
        } else {
            ERC1155(nft).safeTransferFrom(address(this), owner, id, 1, "");
        }
    }

    function sell(address nft, uint id, bool isERC721, address owner, address ERC20Contract, uint index) external {
        bytes32 key = keccak256(abi.encodePacked(nft, id, owner, ERC20Contract, index));
        require(claimDeadline[key] < block.timestamp);
        delete claimDeadline[key];

        bytes memory data = abi.encode(ERC20Contract, false);

        if (isERC721) {
            ERC721(nft).safeTransferFrom(address(this), address(ditto), id, data);
        } else {
            ERC1155(nft).safeTransferFrom(address(this), address(ditto), id, 1, data);
        }

        uint bal = ERC20(ERC20Contract).balanceOf(address(this));
        ERC20(ERC20Contract).approve(address(ditto), 0);
        ERC20(ERC20Contract).approve(address(ditto), bal);
        ditto.bumpSubsidy(nft, id, ERC20Contract, false, SafeCast.toUint128(bal));
    }
}