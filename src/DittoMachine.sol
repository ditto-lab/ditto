pragma solidity ^0.8.4;
//SPDX-License-Identifier: MIT

import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

    bytes32 public constant FLOOR_HASH = hex'fddc260aecba8a66725ee58da4ea3cbfcf4ab6c6ad656c48345a575ca18c45c9';
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
        uint16 heat;
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
        // might be neat to have some generative art?
        // or just return the the tokenURI of the original as below
        return ERC721(cloneIdToShape[id].ERC721Contract).tokenURI(cloneIdToShape[id].tokenId);
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
        require(_amount >= DNOM, "DM:duplicate:_amount.invalid");

        _tokenId = floor ? uint256(FLOOR_HASH): _tokenId;

        // calculate cloneId by hashing identifiying information
        uint256 cloneId = uint256(keccak256(abi.encodePacked(
            _ERC721Contract,
            _tokenId,
            _ERC20Contract,
            floor
        )));
        uint256 floorId = uint256(keccak256(abi.encodePacked(
            _ERC721Contract,
            uint256(FLOOR_HASH),
            _ERC20Contract,
            true
        )));

        uint256 value;
        uint256 subsidy;

        if (ownerOf[floorId] == address(0) && ownerOf[cloneId] == address(0)) {
            subsidy = (_amount * MIN_FEE / DNOM).toUint128();
            value = _amount.toUint128() - subsidy;
            cloneIdToShape[cloneId] = CloneShape(
                floor ? uint256(FLOOR_HASH): _tokenId,
                value,
                _ERC721Contract,
                _ERC20Contract,
                1,
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
            // if a clone has already been made
            CloneShape memory cloneShape;
            // use specific clone values if floor clone does not exist
            // or or if specified clone is worth more than the floor clone
            if (
                ownerOf[floorId] == address(0) || // may be able to get rid of this check
                cloneIdToShape[cloneId].worth > cloneIdToShape[floorId].worth // and only use this one
            ) {
                cloneShape = cloneIdToShape[cloneId];
            } else {
                cloneShape = cloneIdToShape[floorId];
            }
            value = cloneShape.worth;

            // calculate time until auction ends
            int128 timeLeft = (cloneShape.term - block.timestamp).toInt256().toInt128();
            uint256 minAmount = timeLeft > 0 ?
                value * uint128(timeLeft) / uint128((timeLeft << 64).sqrt() >> 64) :
                value + (value * MIN_FEE / DNOM);

            // calculate protocol fees, subsidy and worth values
            uint16 heat = cloneShape.heat;
            subsidy = minAmount * MIN_FEE * uint256(heat) / DNOM;
            value = _amount - subsidy; // will be applied to cloneShape.worth
            require(value >= minAmount, "DM:duplicate:_amount.invalid");

            // calculate new heat and clone term values
            if (timeLeft > 0) {
                heat = uint256(int256(timeLeft)) >= DNOM ?
                    type(uint16).max :
                    (heat * uint128(timeLeft) / uint128((timeLeft << 64).sqrt() >> 64)).toUint16();
            } else {
                heat = uint128(-timeLeft) > uint128(heat) ?
                    0 :
                    heat - uint128(-timeLeft).toUint16() ;
            }

            cloneIdToShape[cloneId] = CloneShape(
                _tokenId,
                value,
                cloneShape.ERC721Contract,
                cloneShape.ERC20Contract,
                heat,
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
            FLOOR_HASH,
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
