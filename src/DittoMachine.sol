pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {ERC721, ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from 'base64-sol/base64.sol';

/**
 * @title NFT derivative exchange inspired by the SALSA concept
 * @author calvbore
 * @notice A user may self assess the price of an NFT and purchase a token representing
 * the right to ownership when it is sold via this contract. Anybody may buy the
 * token for a higher price and force a transfer from the previous owner to the new buyer
 */
contract DittoMachine is ERC721, ERC721TokenReceiver {

    ////////////// LIBS //////////////

    using SafeCast for *;
    using ABDKMath64x64 for int128;

    ////////////// CONSTANT VARIABLES //////////////

    uint256 public constant FLOOR_ID = uint256(0xfddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9);

    // ensure that CloneShape can always be casted to int128.
    // change the type to ensure this?
    uint256 public constant BASE_TERM = 2**18;
    uint256 public constant MIN_FEE = 32;
    uint256 public constant DNOM = 2**16;

    ////////////// STATE VARIABLES //////////////

    // variables essential to calculating auction/price information for each cloneId
    struct CloneShape {
        uint256 tokenId;
        uint256 worth;
        address ERC721Contract;
        address ERC20Contract;
        bool floor;
        uint256 term;
    }

    mapping(uint256 => CloneShape) public cloneIdToShape;
    mapping(uint256 => uint256) public cloneIdToSubsidy;

    constructor() ERC721("Ditto", "DTO") { }

    fallback() external {
        revert();
    }

    ////////////// PUBLIC FUNCTIONS //////////////

    function tokenURI(uint256 id) public view override returns (string memory) {
        CloneShape memory cloneShape = cloneIdToShape[id];

        string memory _name = string(abi.encodePacked('Ditto #', Strings.toString(id)));
        string memory nftTokenId = cloneShape.floor ? "Floor" : Strings.toString(cloneShape.tokenId);

        string memory description = string(abi.encodePacked(
            'This Ditto gives you a chance to buy ',
            ERC721(cloneIdToShape[id].ERC721Contract).name(),
            ' #', nftTokenId,
            '(', Strings.toHexString(uint160(cloneIdToShape[id].ERC721Contract), 20), ')'
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
                       Strings.toHexString(uint160(cloneIdToShape[id].ERC721Contract), 20),
                       '"},{"trait_type": "tokenId", "value": ',
                       Strings.toString(cloneShape.tokenId),
                       '}], "owner":"',
                       Strings.toHexString(uint160(ownerOf[id]), 20),
                       '", "image": "',
                       'data:image/svg+xml;base64,',
                       image,
                       '"}'
                    )
                )
            )
        ));
    }

    /**
     * @notice open or buy out a future on a particular NFT or floor perp
     * @notice fees will be taken from purchases and set aside as a subsidy to encourage sellers
     * @param _ERC721Contract address of selected NFT smart contract
     * @param _tokenId selected NFT token id
     * @param _ERC20Contract address of the ERC20 contract used for purchase
     * @param _amount address of ERC20 tokens used for purchase
     * @param floor selector determining if the purchase is for a floor perp
     * @dev creates an ERC721 representing the specified future or floor perp, reffered to as clone
     * @dev a clone id is calculated by hashing ERC721Contract, _tokenId, _ERC20Contract, and floor params
     * @dev if floor == true FLOOR_HASH will replace _tokenId in cloneId calculation
     */
    function duplicate(
        address _ERC721Contract,
        uint256 _tokenId,
        address _ERC20Contract,
        uint256 _amount,
        bool floor
    ) public returns (uint256) {
        // _tokenId has to be set to FLOOR_ID to purchase the floor perp
        require(!floor || (_tokenId == FLOOR_ID), "DM:duplicate:_tokenId.invalid");

        // ensure enough funds to do some math on
        require(_amount >= BASE_TERM, "DM:duplicate:_amount.invalid");

        _tokenId = floor ? FLOOR_ID : _tokenId;

        // calculate cloneId by hashing identifiying information
        uint256 cloneId = uint256(keccak256(abi.encodePacked(
            _ERC721Contract,
            _tokenId,
            _ERC20Contract,
            floor
        )));

        uint256 value;
        uint256 subsidy;

        if (ownerOf[cloneId] == address(0)) {
            subsidy = _amount * MIN_FEE / DNOM; // with current constants subsidy <= _amount
            value = _amount - subsidy;
            cloneIdToShape[cloneId] = CloneShape(
                _tokenId,
                value,
                _ERC721Contract,
                _ERC20Contract,
                floor,
                block.timestamp + BASE_TERM
            );
            cloneIdToSubsidy[cloneId] += subsidy;
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );
            _safeMint(msg.sender, cloneId); // EXTERNAL CALL
        } else {
            uint256 floorId = uint256(keccak256(abi.encodePacked(
                _ERC721Contract,
                FLOOR_ID,
                _ERC20Contract,
                true
            )));

            // if a clone has already been made
            CloneShape memory cloneShape;

            if (cloneIdToShape[cloneId].worth > cloneIdToShape[floorId].worth) {
                // clone's worth is more than the floor perp or the floor perp does not exist
                cloneShape = cloneIdToShape[cloneId];
            } else {
                cloneShape = cloneIdToShape[floorId];
            }
            value = cloneShape.worth;

            // calculate time until auction ends
            uint256 minAmount = getMinAmount(value, cloneShape.term);

            // calculate protocol fees, subsidy and worth values
            subsidy = minAmount * MIN_FEE / DNOM;
            value = _amount - subsidy; // will be applied to cloneShape.worth
            require(value >= minAmount, "DM:duplicate:_amount.invalid");

            // calculate new clone term values
            cloneIdToShape[cloneId] = CloneShape(
                _tokenId,
                value,
                cloneShape.ERC721Contract,
                cloneShape.ERC20Contract,
                floor,
                // figure out auction time increase or decrease?
                block.timestamp + BASE_TERM
            );
            cloneIdToSubsidy[cloneId] += subsidy;
            // buying out the previous clone owner
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                ownerOf[cloneId],
                (cloneShape.worth + (subsidy/2 + subsidy%2))
            );
            // paying required funds to this contract
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                (value + (subsidy/2))
            );
            // force transfer from current owner to new highest bidder
            forceSafeTransferFrom(ownerOf[cloneId], msg.sender, cloneId); // EXTERNAL CALL
            assert((cloneShape.worth + (subsidy/2 + subsidy%2)) + (value + (subsidy/2)) == _amount);
        }

        return cloneId;
    }

    /**
     * @notice unwind a position in a clone
     * @param owner of the selected token
     * @param _cloneId selected
     * @dev will refund funds held in a position, subsidy will remain for sellers in the future
     */
    function dissolve(address owner, uint256 _cloneId) public {
        require(owner == ownerOf[_cloneId], "WRONG_OWNER");

        require(
            msg.sender == owner || msg.sender == getApproved[_cloneId] || isApprovedForAll[owner][msg.sender],
            "NOT_AUTHORIZED"
        );

        CloneShape memory cloneShape = cloneIdToShape[_cloneId];
        delete cloneIdToShape[_cloneId];

        _burn(_cloneId);
        SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
            ERC20(cloneShape.ERC20Contract),
            msg.sender,
            owner,
            cloneShape.worth
        );
    }

    function getMinAmount(uint256 _value, uint256 _term) public view returns(uint256) {
        uint256 timeLeft = _term > block.timestamp ? _term - block.timestamp : 0;

        return (_value
            + (_value * timeLeft / BASE_TERM)
            + (_value * MIN_FEE / DNOM));
    }

    // Visibility is `public` to enable it being called by other contracts for composition.
    function renderTokenById(uint256 id) public view returns (string memory) {
        CloneShape memory cloneShape = cloneIdToShape[id];
        string memory nftTokenId = cloneShape.floor ? "Floor" : Strings.toString(cloneShape.tokenId);

        string memory render = string(abi.encodePacked(
            '<g>',
                '<style>',
                    '.small { font: italic 13px sans-serif; }',
                    '.Rrrrr { font: italic 40px serif; fill: red; }',
                '</style>',
                '<text x="20" y="35" class="small">',Strings.toHexString(uint160(cloneIdToShape[id].ERC721Contract), 20),'</text>',
                '<text x="55" y="65" class="Rrrrr">',ERC721(cloneShape.ERC721Contract).name(),'</text>',
                '<text x="250" y="70" class="small">',nftTokenId,'</text>',
            '</g>'
        ));

      return render;
    }

    ////////////// EXTERNAL FUNCTIONS //////////////

    /**
     * @dev will allow NFT sellers to sell by safeTransferFrom-ing directly to this contract
     * @param data will contain ERC20 address that the seller wishes to sell for
     * allows specifying selling for the floor price
     * @return returns received selector
     */
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4) {
        address ERC721Contract = msg.sender;
        (address ERC20Contract, bool floor) = abi.decode(data, (address, bool));

        uint256 cloneId = uint256(keccak256(abi.encodePacked(
            ERC721Contract,
            id,
            ERC20Contract,
            false
        )));

        uint256 floorId = uint256(keccak256(abi.encodePacked(
            ERC721Contract,
            FLOOR_ID,
            ERC20Contract,
            true
        )));

        if (
            floor == true ||
            ownerOf[cloneId] == address(0) ||
            cloneIdToShape[floorId].worth > cloneIdToShape[cloneId].worth // could remove this and just let seller specify
        ) {
            // if cloneId is not active, check floor clone
            cloneId = floorId;
            // if no cloneId is active revert
            require(ownerOf[cloneId] != address(0), "DM:onERC721Received:!cloneId");
        }

        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        uint256 subsidy = cloneIdToSubsidy[cloneId];
        address owner = ownerOf[cloneId];
        delete cloneIdToShape[cloneId];
        delete cloneIdToSubsidy[cloneId];
        _burn(cloneId);

        require(
            ERC721(ERC721Contract).ownerOf(id) == address(this),
            "DM:onERC721Received:!received"
        );
        ERC721(ERC721Contract).safeTransferFrom(address(this), owner, id);
        SafeTransferLib.safeTransferFrom(
            ERC20(ERC20Contract),
            address(this),
            from,
            cloneShape.worth + subsidy
        );
        return this.onERC721Received.selector;
    }

    ////////////// INTERNAL FUNCTIONS //////////////
    function generateSVGofTokenById(uint256 id) internal view returns (string memory) {

        string memory svg = string(abi.encodePacked(
          '<svg viewBox="0 0 340 310" xmlns="http://www.w3.org/2000/svg">',
            renderTokenById(id),
          '</svg>'
        ));

        return svg;
    }

    ////////////// PRIVATE FUNCTIONS //////////////

    /**
     * @notice transfer without owner/approval checks
     * @param from current token owner
     * @param to transfer recepient
     * @param id token id
     */
    function forceTransferFrom(
        address from,
        address to,
        uint256 id
    ) private {
        // no ownership or approval checks cause we're forcing a change of ownership
        require(from == ownerOf[id], "WRONG_FROM");
        require(to != address(0), "INVALID_RECIPIENT");

        unchecked {
            balanceOf[from]--;

            balanceOf[to]++;
        }

        ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    /**
     * @notice forces safeTransferFrom without owner/approval checks
     * @param from current token owner
     * @param to transfer recepient
     * @param id token id
     * @dev if a contract holds a clone and implements ERC721Ejected we call it
     * @dev we will force the transfer in any case
     */
    function forceSafeTransferFrom(
        address from,
        address to,
        uint256 id
    ) private {
        forceTransferFrom(from, to, id);
        // give contracts the option to account for a forced transfer
        // if they don't implement the ejector we're stll going to move the token.
        if (to.code.length != 0) {
            // not sure if this is exploitable yet?
            try ERC721TokenEjector(from).onERC721Ejected(address(this), to, id, "") {} // EXTERNAL CALL
            catch {}
        }

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") == // EXTERNAL CALL
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

}

/**
 * @title A funtion to support token ejection
 * @notice function is called if a contract must do accounting on a forced transfer
 */
interface ERC721TokenEjector {

    function onERC721Ejected(
        address operator,
        address to,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);

}
