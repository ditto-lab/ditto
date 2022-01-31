pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import {ERC721, ERC721TokenReceiver} from "@rari-capital/solmate/src/tokens/ERC721.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Base64} from 'base64-sol/base64.sol';

/**
 * @title NFT derivative exchange inspired by the SALSA concept
 * @author calvbore
 * @notice A user may self assess the price of an NFT and purchase a token representing
 * the right to ownership when it is sold via this contract. Anybody may buy the
 * token for a higher price and force a transfer from the previous owner to the new buyer
 */
contract DittoMachine is ERC721, ERC721TokenReceiver {
    /**
     * @notice Insufficient bid for purchasing a clone.
     * @dev thrown when the number of erc20 tokens sent is lower than
     *      the number of tokens required to purchase a clone.
     */
    error AmountInvalid();
    error FromInvalid();
    // error RecipientInvalid();
    error NFTNotReceived();
    error NotAuthorized();

    ////////////// CONSTANT VARIABLES //////////////

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    uint256 public constant FLOOR_ID = uint256(0xfddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9);

    // ensure that CloneShape can always be casted to int128.
    // change the type to ensure this?
    uint256 public constant BASE_TERM = 2**18;
    uint256 public constant MIN_FEE = 32;
    uint256 public constant DNOM = 2**16 - 1;
    uint256 public constant MIN_AMOUNT_FOR_NEW_CLONE = BASE_TERM + (BASE_TERM * MIN_FEE / DNOM);

    ////////////// STATE VARIABLES //////////////

    // variables essential to calculating auction/price information for each cloneId
    struct CloneShape {
        uint256 tokenId;
        uint256 worth;
        address ERC721Contract;
        address ERC20Contract;
        // uint16 heat;
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
        // ensure enough funds to do some math on
        if (_amount < MIN_AMOUNT_FOR_NEW_CLONE) {
            revert AmountInvalid();
        }

        if (floor) {
            _tokenId = FLOOR_ID;
        }

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

            CloneShape memory cloneShape;

            if (cloneIdToShape[cloneId].worth > cloneIdToShape[floorId].worth) {
                // clone's worth is more than the floor perp or the floor perp does not exist
                cloneShape = cloneIdToShape[cloneId];
            } else {
                cloneShape = cloneIdToShape[floorId];
            }

            uint256 minAmount = _getMinAmount(cloneShape);

            // calculate subsidy and worth values
            subsidy = minAmount * MIN_FEE / DNOM;
            value = _amount - subsidy; // will be applied to cloneShape.worth
            if (value < minAmount) {
                revert AmountInvalid();
            }

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
            cloneIdToSubsidy[cloneId] += (subsidy >> 1);

            // paying required funds to this contract
            SafeTransferLib.safeTransferFrom( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                msg.sender,
                address(this),
                _amount
            );
            // buying out the previous clone owner
            SafeTransferLib.safeTransfer( // EXTERNAL CALL
                ERC20(_ERC20Contract),
                ownerOf[cloneId],
                (cloneShape.worth + (subsidy >> 1) + (subsidy & 1))
            );
            // force transfer from current owner to new highest bidder
            forceSafeTransferFrom(ownerOf[cloneId], msg.sender, cloneId); // EXTERNAL CALL
        }

        return cloneId;
    }

    /**
     * @notice unwind a position in a clone
     * @param _cloneId specifies the clone to burn
     * @dev will refund funds held in a position, subsidy will remain for sellers in the future
     */
    function dissolve(uint256 _cloneId) public {
        if (!(msg.sender == ownerOf[_cloneId]
                || msg.sender == getApproved[_cloneId]
                || isApprovedForAll[ownerOf[_cloneId]][msg.sender])) {
            revert NotAuthorized();
        }

        address owner = ownerOf[_cloneId];
        CloneShape memory cloneShape = cloneIdToShape[_cloneId];

        delete cloneIdToShape[_cloneId];

        _burn(_cloneId);
        SafeTransferLib.safeTransfer( // EXTERNAL CALL
            ERC20(cloneShape.ERC20Contract),
            owner,
            cloneShape.worth
        );
    }

    function getMinAmountForCloneTransfer(uint256 cloneId) public view returns (uint256) {
        if(ownerOf[cloneId] == address(0)) {
            return MIN_AMOUNT_FOR_NEW_CLONE;
        }

        uint256 _minAmount = _getMinAmount(cloneIdToShape[cloneId]);
        return _minAmount + (_minAmount * MIN_FEE / DNOM);
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
            cloneIdToShape[floorId].worth > cloneIdToShape[cloneId].worth
        ) {
            // if cloneId is not active, check floor clone
            cloneId = floorId;
        }
        // if no cloneId is active revert
        require(ownerOf[cloneId] != address(0), "DM:onERC721Received:!cloneId");

        CloneShape memory cloneShape = cloneIdToShape[cloneId];
        uint256 subsidy = cloneIdToSubsidy[cloneId];
        address owner = ownerOf[cloneId];
        delete cloneIdToShape[cloneId];
        delete cloneIdToSubsidy[cloneId];
        _burn(cloneId);

        if (ERC721(ERC721Contract).ownerOf(id) != address(this)) {
            revert NFTNotReceived();
        }
        ERC721(ERC721Contract).safeTransferFrom(address(this), owner, id);

        if (IERC165(ERC721Contract).supportsInterface(_INTERFACE_ID_ERC2981) == true) {
            (address receiver, uint256 royaltyAmount) = IERC2981(ERC721Contract).royaltyInfo(
                cloneShape.tokenId,
                cloneShape.worth
            );
            if (royaltyAmount > 0) {
                cloneShape.worth -= royaltyAmount;
                SafeTransferLib.safeTransfer(
                    ERC20(ERC20Contract),
                    receiver,
                    royaltyAmount
                );
            }
        }
        SafeTransferLib.safeTransfer(
            ERC20(ERC20Contract),
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
        if (from != ownerOf[id]) {
            revert FromInvalid();
        }

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
        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") == // EXTERNAL CALL
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
        forceTransferFrom(from, to, id);
        // give contracts the option to account for a forced transfer
        // if they don't implement the ejector we're stll going to move the token.
        if (to.code.length != 0) {
            // not sure if this is exploitable yet?
            try ERC721TokenEjector(from).onERC721Ejected(address(this), to, id, "") {} // EXTERNAL CALL
            catch {}
        }
    }

    /**
     * @notice computes the minimum amount required to buy a clone.
     * @notice it does not take into account the protocol fee or the subsidy
     * @param cloneShape clone for which to compute the minimum amount
     * @dev only use it for a minted clone
     */
    function _getMinAmount(CloneShape memory cloneShape) internal view returns (uint256) {
        uint256 timeLeft = (cloneShape.term > block.timestamp) ? (cloneShape.term - block.timestamp) : 0;

        return cloneShape.worth
            + (cloneShape.worth * timeLeft / BASE_TERM);
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
