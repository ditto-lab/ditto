// SPDX-License-Identifier: MIT
// Donkeverse Contracts v0.0.1
// https://github.com/DonkeVerse/ERC1155D

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155
 * Originally based on code by Enjin: https://github.com/enjin/erc-1155
 *
 * _Available since v3.1._
 */
contract ERC1155D is ERC165, IERC1155, IERC1155MetadataURI {
    // error CallerNotOwnerNorApproved();
    // error TransferToZeroAddress();
    // error IdsAmountLengthMismatch();
    // error InsufficientBalance();
    mapping (uint => address) public ownerOf;

    // Mapping from account to operator approvals
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor() {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155MetadataURI-uri}.
     *
     * This implementation returns the same URI for *all* token types. It relies
     * on the token type ID substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * Clients calling this function must replace the `\{id\}` substring with the
     * actual token type ID.
     */
    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        return ownerOf[id] == account ? 1 : 0;
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "!len");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length;) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
            unchecked { ++i; }
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public virtual override {
        require(
            from == msg.sender || isApprovedForAll[from][msg.sender],
            "!approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external virtual override {
        require(
            from == msg.sender || isApprovedForAll[from][msg.sender],
            "!approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) internal virtual {
        require(to != address(0), "ZERO_ADDRESS");
        require(ownerOf[id] == from && amount < 2, "!balance");

        // The ERC1155 spec allows for transfering zero tokens, but we are still expected
        // to run the other checks and emit the event. But we don't want an ownership change
        // in that case
        if (amount == 1) {
            ownerOf[id] = to;
        }

        address operator = msg.sender;
        emit TransferSingle(operator, from, to, id, amount);

        if (to.code.length != 0) {
            require(IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data)
                    == IERC1155Receiver.onERC1155Received.selector, "UNSAFE_RECIPIENT");
        }
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) internal virtual {
        require(to != address(0), "ZERO_ADDRESS");
        require(ids.length == amounts.length, "!length");

        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];

            require(ownerOf[id] == from && amounts[i] < 2, "!balance");

            if (amounts[i] == 1) {
                ownerOf[id] = to;
            }
            unchecked { ++i; }
        }

        address operator = msg.sender;
        emit TransferBatch(operator, from, to, ids, amounts);

        if (to.code.length != 0) {
            require(IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data)
                    == IERC1155Receiver.onERC1155BatchReceived.selector, "UNSAFE_RECIPIENT");
        }
    }

    /**
     * @dev Creates `amount` tokens of token type `id`, and assigns them to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `id` must be less than MAX_SUPPLY;
     * This does not implement smart contract checks according to ERC1155 so it exists as a separate function
     */

    function _mintSingle(address to, uint256 id) internal virtual {
        // can be removed since we mint only when ownerOf[id] is always 0.
        // require(ownerOf[id] == address(0), "ERC1155D: supply exceeded");

        ownerOf[id] = to;

        if (to.code.length != 0) {
            require(IERC1155Receiver(to).onERC1155Received(msg.sender, address(0), id, 1, "")
                    == IERC1155Receiver.onERC1155Received.selector, "UNSAFE_RECIPIENT");
        }
        emit TransferSingle(to, address(0), to, id, 1);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `from`
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens of token type `id`.
     */
    function _burn(
        address from,
        uint256 id
    ) internal virtual {
        // these 2 checks are always true in our case.
        // require(from != address(0), "ERC1155: burn from the zero address");
        // require(ownerOf[id] == from, "ERC1155: burn amount exceeds balance");
        ownerOf[id] = address(0);

        // msg.sender is the operator
        emit TransferSingle(msg.sender, from, address(0), id, 1);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits a {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "self");
        isApprovedForAll[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }
}
