// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./interface/IQuote.sol";
import "./interface/IQuoteMetadata.sol";

/// @title OpenCover quotes on L2.
contract Quote is
    Initializable,
    ContextUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721EnumerableUpgradeable,
    IQuote
{
    using ECDSAUpgradeable for bytes32;
    using ERC165CheckerUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// @notice Owner of the contract, it can upgrade the implementation.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    /// @notice Administrator of the contract, it can configure the contract and trigger emergency operations.
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    /// @notice Operator of the contract, used for BAU operations.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Quote metadata contract used to generate dynamic image and description.
    IQuoteMetadata quoteMetadata;
    /// @dev Maps quote IDs to quote data.
    mapping(uint256 => QuoteSubmission) public quotes;
    /// @dev Amount of premium/fee payments pending settlement.
    mapping(address => uint256) public pendingAmounts;
    /// @dev Fee collector address.
    address payable public collector;

    /// @dev Maps provider IDs to provider data.
    mapping(uint32 => Provider) internal _providers;
    /// @dev Maps provider IDs to asset IDs to asset data.
    mapping(uint32 => mapping(uint32 => Asset)) internal _assets;
    /// @dev Maps provider IDs to products IDs to product data.
    mapping(uint32 => mapping(uint32 => Product)) internal _products;
    /// @dev Maps quote IDs to quote settlements.
    mapping(uint256 => QuoteSettlement) internal _quoteSettlements;

    CountersUpgradeable.Counter private _quoteIds;

    modifier requireQuoteMetadata {
        if (address(quoteMetadata) == address(0)) revert InvalidAddress();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        if (_lockImplementation()) {
            _disableInitializers();
        }
    }

    /// @notice Initializes the Quote contract.
    function initialize(
        string memory name_,
        string memory symbol_
    )
        public
        initializer
    {
        __Context_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();

        _grantRole(OWNER_ROLE, _msgSender());
        _setRoleAdmin(ADMINISTRATOR_ROLE, OWNER_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, OWNER_ROLE);
    }

    // =========================================================================
    // UUPSUpgradeable
    // =========================================================================

    /// @dev This function should revert when `msg.sender` is not authorized to
    ///      upgrade the contract.
    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    // =========================================================================
    // ERC165
    // =========================================================================

    /// @dev Returns true if this contract implements the interface defined
    ///      by `interfaceId`.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override (ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IQuoteV1).interfaceId
            || ERC721EnumerableUpgradeable.supportsInterface(interfaceId)
            || AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    // =========================================================================
    // ERC721EnumerableUpgradeable
    // =========================================================================

    /// @dev Dynamically generates metadata with an embedded SVG image using
    ///      properties of the given `tokenId` identifying a submitted quote.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        QuoteStatus status = quoteStatus(tokenId);

        (string memory name_, string memory description, string memory image) =
            quoteMetadata.generateQuoteMetadata(
                quotes[tokenId],
                status,
                tokenId
            );

        // Build metadata conforming to the ERC721 Metadata JSON schema.
        // See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md.
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64Upgradeable.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"', name_, '",',
                            '"description":"', description, '",',
                            '"image":"', image, '"}'
                        )
                    )
                )
            )
        );
    }

    /// @dev Prevents transferring quote NFTs making them soulbound.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    )
        internal
        override (ERC721EnumerableUpgradeable)
    {
        // Allow mint and burn.
        if (from != address(0) && to != address(0)) revert QuoteSoulbound();

        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    // =========================================================================
    // Quote
    // =========================================================================

    /// @inheritdoc IQuoteV1
    function previewQuote(QuoteSubmission calldata quote)
        external
        override
        view
        requireQuoteMetadata
        returns (string memory image)
    {
        // Check if the supplied quote is valid.
        _requireValidQuote(quote);

        (,, image) = quoteMetadata.generateQuoteMetadata(quote, QuoteStatus.NONE, 0);
    }

    /// @inheritdoc IQuoteV1
    function submitQuote(QuoteSubmission calldata quote, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
        whenNotPaused
        nonReentrant
        requireQuoteMetadata
        returns (uint256 quoteId)
    {
        address signer = keccak256(abi.encode(quote))
            .toEthSignedMessageHash()
            .recover(v, r, s);

        if (!hasRole(OPERATOR_ROLE, signer)) revert InvalidSignature();

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
        _safeMint(_msgSender(), quoteId);
        _quoteIds.increment();

        emit QuoteSubmitted(quoteId, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function refundUnfulfilledQuote(uint256 quoteId, address payable withdrawTo)
        external
        override
        whenNotPaused
        nonReentrant
    {
        // Must be withdrawing to a valid address.
        if (withdrawTo == address(0)) revert InvalidAddress();
        // Check if quote exists.
        if (_quoteNotExists(quoteId)) revert InvalidQuote();
        // Check if quote's owned by the sender.
        if (ownerOf(quoteId) != _msgSender()) revert QuoteNotOwned();

        QuoteStatus status = quoteStatus(quoteId);

        // Check if quote's already been settled.
        if (status == QuoteStatus.COVER_ACTIVE
            || status == QuoteStatus.COVER_EXPIRED
        ) {
            revert QuoteAlreadySettled();
        }

        // Check if quote's already been refunded.
        if (status == QuoteStatus.QUOTE_REFUNDED) revert QuoteAlreadyRefunded();
        // Check if quote's not yet expired.
        if (status != QuoteStatus.QUOTE_EXPIRED) revert QuoteNotExpired();

        (address paymentAssetAddress, uint256 totalPayment) = _totalPayment(quoteId);
        assert(pendingAmounts[paymentAssetAddress] >= totalPayment);

        pendingAmounts[paymentAssetAddress] -= totalPayment;

        _quoteSettlements[quoteId].isRefunded = true;

        if (_isNativeCoin(paymentAssetAddress)) {
            // Transfer native coin to quote owner.
            (bool success, ) = withdrawTo.call{value: totalPayment}("");
            if (!success) revert InvalidAddress();
        } else {
            // Transfer ERC20 to quote owner.
            IERC20Upgradeable(paymentAssetAddress).safeTransfer(withdrawTo, totalPayment);
        }

        emit QuoteRefunded(quoteId, withdrawTo, _msgSender());
    }

    function quoteStatus(uint256 quoteId)
        public
        view
        returns (QuoteStatus status)
    {
        if (_quoteNotExists(quoteId)) {
            status = QuoteStatus.NONE;
        } else if (_quoteSettlements[quoteId].isSettled) {
            // Quote is settled, check if it expired.
            if (_quoteSettlements[quoteId].coverExpiresAt < block.timestamp) {
                status = QuoteStatus.COVER_EXPIRED;
            } else {
                status = QuoteStatus.COVER_ACTIVE;
            }
        } else if (_quoteSettlements[quoteId].isRefunded) {
            status = QuoteStatus.QUOTE_REFUNDED;
        } else {
            // If quote exists but not settled, check if it is within the settlement period.
            uint256 settlementPeriodEnd = _quoteSettlements[quoteId].submittedAt + _providers[quotes[quoteId].providerId].settlementPeriod;
            if (settlementPeriodEnd < block.timestamp) {
                status = QuoteStatus.QUOTE_EXPIRED;
            } else {
                status = QuoteStatus.QUOTE_AWAITING_SETTLEMENT;
            }
        }
    }

    /// @inheritdoc IQuoteV1
    function settleQuote(uint256 quoteId, bytes32 txHash, uint256 coverExpiresAt)
        external
        override
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        // Check if quote exists.
        if (_quoteNotExists(quoteId)) revert InvalidQuote();
        // Check if cover expiry timestamp is valid.
        if (coverExpiresAt < block.timestamp) revert InvalidCoverExpiry();

        QuoteStatus status = quoteStatus(quoteId);

        // Check if quote's already been settled.
        if (status == QuoteStatus.COVER_ACTIVE
            || status == QuoteStatus.COVER_EXPIRED
        ) {
            revert QuoteAlreadySettled();
        }

        // Check if quote's already been refunded.
        if (status == QuoteStatus.QUOTE_REFUNDED) revert QuoteAlreadyRefunded();

        QuoteSettlement storage quoteSettlement = _quoteSettlements[quoteId];
        quoteSettlement.isSettled = true;
        quoteSettlement.settledAt = block.timestamp;
        quoteSettlement.coverExpiresAt = coverExpiresAt;
        quoteSettlement.txHash = txHash;

        (address paymentAssetAddress, uint256 totalPayment) = _totalPayment(quoteId);
        assert(pendingAmounts[paymentAssetAddress] >= totalPayment);

        pendingAmounts[paymentAssetAddress] -= totalPayment;

        emit QuoteSettled(quoteId, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function refundQuote(uint256 quoteId)
        external
        override
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        // Check if quote exists.
        if (_quoteNotExists(quoteId)) revert InvalidQuote();

        QuoteStatus status = quoteStatus(quoteId);

        // Check if quote's already been refunded.
        if (status == QuoteStatus.QUOTE_REFUNDED) revert QuoteAlreadyRefunded();

        // Check if quote's already been settled.
        if (status == QuoteStatus.COVER_ACTIVE
            || status == QuoteStatus.COVER_EXPIRED
        ) {
            revert QuoteAlreadySettled();
        }

        // There's no check for the quote expiry. This is intentional and allows the operator
        // to refund quotes that can't be fulfilled even before the settlement period expires.

        (address paymentAssetAddress, uint256 totalPayment) = _totalPayment(quoteId);
        assert(pendingAmounts[paymentAssetAddress] >= totalPayment);

        pendingAmounts[paymentAssetAddress] -= totalPayment;

        _quoteSettlements[quoteId].isRefunded = true;

        address withdrawTo = ownerOf(quoteId);
        if (_isNativeCoin(paymentAssetAddress)) {
            // Transfer native coin to quote owner.
            (bool success, ) = payable(withdrawTo).call{value: totalPayment}("");
            if (!success) revert InvalidAddress();
        } else {
            // Transfer ERC20 to quote owner.
            IERC20Upgradeable(paymentAssetAddress).safeTransfer(withdrawTo, totalPayment);
        }

        emit QuoteRefunded(quoteId, withdrawTo, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function collect(address assetAddress, uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
        onlyRole(OPERATOR_ROLE)
    {
        if (collector == address(0)) revert InvalidAddress();
        if (assetAddress == address(0)) revert InvalidPaymentAsset();
        if (amount == 0) revert InvalidPaymentAmount();

        uint256 contractBalance;
        if (_isNativeCoin(assetAddress)) {
            contractBalance = address(this).balance;
        } else {
            contractBalance = IERC20Upgradeable(assetAddress).balanceOf(address(this));
        }

        assert(contractBalance >= pendingAmounts[assetAddress]);

        uint256 maxCollectable = contractBalance - pendingAmounts[assetAddress];
        if (maxCollectable < amount) revert UnsupportedPaymentAmount();

        if (_isNativeCoin(assetAddress)) {
            (bool success, ) = collector.call{value: amount}("");
            if (!success) revert InvalidAddress();
        } else {
            IERC20Upgradeable(assetAddress).safeTransfer(collector, amount);
        }

        emit Collected(assetAddress, amount, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function setProvider(uint32 providerId, Provider calldata provider)
        external
        override
        onlyRole(ADMINISTRATOR_ROLE)
    {
        // Validate expiry boundary and settlement period.
        if (provider.maxCoverExpiry < provider.minCoverExpiry
            || provider.maxCoverExpiry == 0
            || provider.settlementPeriod == 0
        ) {
            revert InvalidProvider();
        }

        _providers[providerId] = provider;

        emit ProviderChanged(providerId, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function setAsset(uint32 providerId, uint32 assetId, Asset calldata asset)
        external
        override
        onlyRole(ADMINISTRATOR_ROLE)
    {
        if (!_providers[providerId].isEnabled) revert InvalidProvider();
        if (asset.maxCoverAmount < asset.minCoverAmount
            || asset.maxCoverAmount == 0
        )  {
            revert InvalidAsset();
        }

        _assets[providerId][assetId] = asset;

        emit AssetChanged(providerId, assetId, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function setProduct(uint32 providerId, uint32 productId, Product calldata product)
        external
        override
        onlyRole(ADMINISTRATOR_ROLE)
    {
        if (!_providers[providerId].isEnabled) revert InvalidProvider();

        _products[providerId][productId] = product;

        emit ProductChanged(providerId, productId, _msgSender());
    }

    /// @inheritdoc IQuoteV1
    function emergencyPause() external override onlyRole(ADMINISTRATOR_ROLE) {
        _pause();
    }

    /// @inheritdoc IQuoteV1
    function emergencyUnpause() external override onlyRole(ADMINISTRATOR_ROLE) {
        _unpause();
    }

    /// @inheritdoc IQuoteV1
    function setCollector(address payable collector_)
        external
        override
        onlyRole(ADMINISTRATOR_ROLE)
    {
        if (collector_ == address(0)) revert InvalidAddress();

        emit CollectorChanged(collector, collector_, _msgSender());

        collector = collector_;
    }

    /// @inheritdoc IQuoteV1
    function setQuoteMetadata(address quoteMetadata_)
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

        quoteMetadata = IQuoteMetadata(quoteMetadata_);
    }

    /// @inheritdoc IQuoteV1
    function transferOwnership(address newOwner)
        external
        override
        onlyRole(OWNER_ROLE)
    {
        if (newOwner == address(0)) revert InvalidAddress();

        // Revoke role from previous owner and grant role to new owner.
        _revokeRole(OWNER_ROLE, _msgSender());
        _grantRole(OWNER_ROLE, newOwner);

        emit OwnershipTransferred(_msgSender(), newOwner);
    }

    /// @inheritdoc IQuoteV1
    function providers(uint32 providerId)
        external
        view
        returns (Provider memory)
    {
        return _providers[providerId];
    }

    /// @inheritdoc IQuoteV1
    function products(uint32 providerId, uint32 productId)
        external
        view
        returns (Product memory)
    {
        return _products[providerId][productId];
    }

    /// @inheritdoc IQuoteV1
    function assets(uint32 providerId, uint32 assetId)
        external
        view
        returns (Asset memory)
    {
        return _assets[providerId][assetId];
    }

    /// @inheritdoc IQuoteV1
    function quoteSettlements(uint256 quoteId)
        external
        view
        returns (QuoteSettlement memory)
    {
        return _quoteSettlements[quoteId];
    }

    function _requireValidQuote(QuoteSubmission calldata quote)
        private
        view
        returns (address paymentAssetAddress, uint256 totalPayment)
    {
        // Check if the quote's within the submission period.
        if (quote.validUntil < block.timestamp) revert QuoteSubmissionExpired();

        // Check if referenced provider, product and assets are valid.
        Provider storage provider = _providers[quote.providerId];
        if (!provider.isEnabled) revert InvalidProvider();

        if (!_products[quote.providerId][quote.productId].isEnabled) revert InvalidProduct();

        Asset storage coverAsset = _assets[quote.providerId][quote.coverAssetId];
        if (!coverAsset.isCoverAsset) revert InvalidCoverAsset();

        Asset storage paymentAsset = _assets[quote.providerId][quote.paymentAssetId];
        if (!paymentAsset.isPaymentAsset) revert InvalidPaymentAsset();

        // Check if the quoted cover's expiry is valid.
        if (quote.coverExpiry < provider.minCoverExpiry
            || quote.coverExpiry > provider.maxCoverExpiry
        ) {
            revert InvalidCoverExpiry();
        }

        // Check if the quote amounts are valid.
        if (quote.coverAmount < coverAsset.minCoverAmount
            || quote.coverAmount > coverAsset.maxCoverAmount
        ) {
            revert UnsupportedCoverAmount();
        }

        totalPayment = quote.premiumAmount + quote.feeAmount;
        if (totalPayment < paymentAsset.minPaymentAmount) {
            revert UnsupportedPaymentAmount();
        }

        paymentAssetAddress = paymentAsset.assetAddress;
    }

    function _quoteNotExists(uint256 quoteId) private view returns (bool) {
        return quotes[quoteId].validUntil == 0;
    }

    function _isNativeCoin(address assetAddress) private pure returns (bool) {
        return assetAddress == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    function _totalPayment(uint256 quoteId)
        private
        view
        returns (address paymentAssetAddress, uint256 totalPayment)
    {
        if (_quoteNotExists(quoteId)) revert InvalidQuote();

        QuoteSubmission storage quote = quotes[quoteId];

        paymentAssetAddress = _assets[quote.providerId][quote.paymentAssetId].assetAddress;
        totalPayment = quote.premiumAmount + quote.feeAmount;
    }

    /// @dev Lock implementation contract by default. Can be overridden for test harnesses.
    function _lockImplementation() internal pure virtual returns (bool) {
        return true;
    }
}
