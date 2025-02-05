// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./QuoteV1.sol";

contract QuoteV15 is QuoteV1, IQuote {
    using ECDSAUpgradeable for bytes32;
    using ERC165CheckerUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// @dev Maps quote IDs to integrator IDs.
    mapping(uint256 => uint256) internal _quoteIntegrators;

    /// @dev Maps integrator IDs to quote metadata contracts. If a mapping is not present
    ///   for a given integrator ID, the default `quoteMetadata` contract is used.
    mapping(uint256 => IQuoteMetadata) internal _integratorQuoteMetadata;

    /// @dev Maps a quote ID to a list of covered addresses which may be different from the sender address.
    mapping(uint256 => address[]) internal _quoteCoveredAddresses;

    // =========================================================================
    // ERC721EnumerableUpgradeable
    // =========================================================================

    /// @dev Dynamically generates metadata with an embedded SVG image using
    ///      properties of the given `tokenId` identifying a submitted quote.
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireMinted(tokenId);

        uint256 integratorId = _quoteIntegrators[tokenId];

        IQuoteMetadata selectedQuoteMetadata = _integratorQuoteMetadata[integratorId];
        if (selectedQuoteMetadata == IQuoteMetadata(address(0))) {
            selectedQuoteMetadata = quoteMetadata;
        }

        (string memory name_, string memory description, string memory image) =
            selectedQuoteMetadata.generateQuoteMetadata(
                quotes[tokenId],
                quoteStatus(tokenId),
                tokenId
            );

        // Build metadata conforming to the ERC721 Metadata JSON schema.
        // See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md.
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64Upgradeable.encode(
                    abi.encodePacked(
                        '{"name":"', name_, '",',
                        '"description":"', description, '",',
                        '"image":"', image, '"}'
                    )
                )
            )
        );
    }

    // =========================================================================
    // QuoteV1
    // =========================================================================

    /// @dev Removed in V1.5. Stub optimised for code space.
    function previewQuote(QuoteSubmission calldata)
        external
        pure
        override (QuoteV1, IQuoteV1)
        returns (string memory)
    {
        assembly {
            let ptr := mload(0x40) // Load free memory pointer.
            mstore(ptr, 0) // Store 0 at the pointer.
            return(ptr, 0x20) // Return 32 bytes from pointer (empty string).
        }
    }

    /// @inheritdoc IQuoteV1
    function submitQuote(QuoteSubmission calldata quote, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override (QuoteV1, IQuoteV1)
        whenNotPaused
        nonReentrant
        requireQuoteMetadata
        returns (uint256)
    {
        address signer = keccak256(abi.encode(quote))
            .toEthSignedMessageHash()
            .recover(v, r, s);

        if (!hasRole(OPERATOR_ROLE, signer)) revert InvalidSignature();

        // There's no concept of separate covered addresses in V1. Pass an empty array.
        address[] memory coveredAddresses = new address[](0);

        return _submitQuote(quote, coveredAddresses, 0, _msgSender());
    }

    // =========================================================================
    // QuoteV15
    // =========================================================================

    /// @inheritdoc IQuoteV15
    function submitQuoteV15(
        QuoteSubmission calldata quote,
        address[] memory coveredAddresses,
        uint256 integratorId,
        address mintTo,
        uint8 v, bytes32 r, bytes32 s
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        requireQuoteMetadata
        returns (uint256)
    {
        address signer = keccak256(abi.encode(quote, coveredAddresses, integratorId, mintTo))
            .toEthSignedMessageHash()
            .recover(v, r, s);

        if (!hasRole(OPERATOR_ROLE, signer)) revert InvalidSignature();

        return _submitQuote(quote, coveredAddresses, integratorId, mintTo);
    }

    function _submitQuote(
        QuoteSubmission calldata quote,
        address[] memory coveredAddresses,
        uint256 integratorId,
        address mintTo
    )
        internal
        returns (uint256 quoteId)
    {
        // Mint proof of cover to the sender if not specified.
        if (mintTo == address(0)) mintTo = _msgSender();

        // Make sure all covered addresses are valid.
        for (uint256 i = 0; i < coveredAddresses.length; i++) {
            if (coveredAddresses[i] == address(0)) revert InvalidAddress();
        }

        (address paymentAssetAddress, uint256 totalPayment) = _requireValidQuote(quote);

        // Check if payment amount is correct in native coin
        if (_isNativeCoin(paymentAssetAddress)) {
            if (msg.value != totalPayment) revert InvalidPaymentAmount();
        } else {
            // Transfer ERC20 to contract from quote owner.
            IERC20Upgradeable(paymentAssetAddress).safeTransferFrom(_msgSender(), address(this), totalPayment);
        }

        pendingAmounts[paymentAssetAddress] += totalPayment;

        // Quote is valid, store it.
        quoteId = _quoteIds.current();

        quotes[quoteId] = quote;
        _quoteCoveredAddresses[quoteId] = coveredAddresses;
        _quoteIntegrators[quoteId] = integratorId;
        _quoteSettlements[quoteId] = QuoteSettlement({
            isSettled : false,
            isRefunded : false,
            submittedAt : block.timestamp,
            // Actual values set as part of quote settlement.
            settledAt : 0,
            coverExpiresAt : 0,
            txHash : bytes32(0)
        });

        // Issue proof NFT.
        _safeMint(mintTo, quoteId);
        _quoteIds.increment();

        emit QuoteSubmitted(quoteId, _msgSender());
    }

    /// @inheritdoc IQuoteV15
    function setIntegratorQuoteMetadata(uint256 integratorId, address quoteMetadata_)
        external
        override
        onlyRole(ADMINISTRATOR_ROLE)
    {
        // Validate quote metadata contract address.
        if (address(quoteMetadata_) == address(0)
            || !quoteMetadata_.supportsInterface(type(IQuoteMetadataV1).interfaceId)
        ) {
            revert InvalidAddress();
        }

        _integratorQuoteMetadata[integratorId] = IQuoteMetadata(quoteMetadata_);
    }

    /// @inheritdoc IQuoteV15
    function quoteIntegrators(uint256 quoteId)
        external
        view
        returns (uint256)
    {
        return _quoteIntegrators[quoteId];
    }

    /// @inheritdoc IQuoteV15
    function quoteCoveredAddresses(uint256 quoteId)
        external
        view
        returns (address[] memory)
    {
        return _quoteCoveredAddresses[quoteId];
    }
}
