pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {DittoMachine} from "../../DittoMachine.sol";
import {UnderlyingNFT} from "../UnderlyingNFT.sol";
import {Currency} from "../TestBase.sol";

contract DittoMachineEchidna {

    DittoMachine public dm;
    UnderlyingNFT nft;
    Currency cry;

    constructor() {

        dm = new DittoMachine();
        nft = new UnderlyingNFT();
        cry = new Currency();

        cry.mint(address(this), type(uint).max);
        cry.approve(address(dm), type(uint).max);
    }

    function duplicate(uint256 _tokenId, uint256 _amount, bool floor, uint256 index) external {
        dm.duplicate(address(nft), _tokenId, address(cry), _amount, floor, index);
    }

    function dissolve(uint256 _tokenId, bool floor, uint256 index) external {
        uint256 protoId = uint256(keccak256(abi.encodePacked(
            address(nft),
            _tokenId,
            address(cry),
            floor
        )));
        dm.dissolve(protoId, index);
    }

}