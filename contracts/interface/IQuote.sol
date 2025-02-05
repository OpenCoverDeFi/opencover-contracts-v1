// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

/// @dev Used for tracking the status of quotes throughout their lifecycle.
enum QuoteStatus {
    /// @dev Quote doesn't exist.
    NONE,
    /// @dev Quote submitted, awaiting settlement.
    QUOTE_AWAITING_SETTLEMENT,
    /// @dev Quote submitted but not settled within the provider's `settlementPeriod`.
    QUOTE_EXPIRED,
    /// @dev Quote expired & refunded.
    QUOTE_REFUNDED,
    /// @dev Quote settled, cover not expired.
    COVER_ACTIVE,
    /// @dev Quote settled, cover expired.
    COVER_EXPIRED
}

struct Provider {
    bool isEnabled;
    /// @dev 1 for Ethereum, etc. Use 0 for off-chain.
    uint256 chainId;
    uint32 minCoverExpiry;
    uint32 maxCoverExpiry;
    /// @dev Settlement period in seconds.
    uint256 settlementPeriod;
    string name;
}

struct Product {
    bool isEnabled;
    string name;
}

struct Asset {
    bool isCoverAsset;
    bool isPaymentAsset;
    uint256 minCoverAmount;
    uint256 minPaymentAmount;
    uint256 maxCoverAmount;
    /// @dev Address of the asset on the L2 chain.
    ///      Use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    ///      for the chain's native coin (e.g. ETH).
    address assetAddress;
    uint8 decimals;
    string name;
    string symbol;
}

struct QuoteSubmission {
    /// @dev Cover provider identifier.
    uint32 providerId;
    /// @dev Cover product.
    uint32 productId;
    /// @dev Cover asset.
    uint32 coverAssetId;
    /// @dev Cover amount in cover asset.
    uint256 coverAmount;
    /// @dev Payment asset for premiums and fees.
    uint32 paymentAssetId;
    /// @dev Premium for the cover in the payment asset.
    uint256 premiumAmount;
    /// @dev OpenCover fees in the payment asset.
    uint256 feeAmount;
    /// @dev Expiry in days.
    uint16 coverExpiry;
    /// @dev Quote validity timestamp.
    uint256 validUntil;
}

struct QuoteSettlement {
    /// @dev Settlement status.
    bool isSettled;
    /// @dev Quote expired and refunded by user.
    bool isRefunded;
    /// @dec Quote submission timestamp;
    uint256 submittedAt;
    /// @dev Timestamp of the settlement transaction.
    uint256 settledAt;
    /// @dev Expiry timestamp of the cover.
    uint256 coverExpiresAt;
    /// @dev Transaction hash of the settlement on L1 / other chains.
    bytes32 txHash;
}

interface IQuoteV1 {
    // =========================================================================
    // Events
    // =========================================================================
    event QuoteSubmitted(
        uint256 indexed quoteId,
        address indexed sender
    );

    event QuoteRefunded(
        uint256 indexed quoteId,
        address indexed withdrawTo,
        address sender
    );

    event QuoteSettled(
        uint256 indexed quoteId,
        address sender
    );

    event ProviderChanged(
        uint32 indexed providerId,
        address sender
    );

    event AssetChanged(
        uint32 indexed providerId,
        uint32 indexed assetId,
        address sender
    );

    event ProductChanged(
        uint32 indexed providerId,
        uint32 indexed productId,
        address sender
    );

    event CollectorChanged(
        address payable oldCollector,
        address payable newCollector,
        address sender
    );

    event Collected(
        address indexed assetAddress,
        uint256 amount,
        address sender
    );

    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    // =========================================================================
    // Functions
    // =========================================================================
    function providers(uint32 providerId) external view returns (Provider memory);
    function products(uint32 providerId, uint32 productId) external view returns (Product memory);
    function assets(uint32 providerId, uint32 assetId) external view returns (Asset memory);
    function quoteSettlements(uint256 quoteId) external view returns (QuoteSettlement memory);

    /// @dev Removed in V1.5.
    function previewQuote(QuoteSubmission calldata quote)
        external
        view
        returns (string memory image);

    function submitQuote(QuoteSubmission calldata quote, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        returns (uint256 quoteId);

    function refundUnfulfilledQuote(uint256 quoteId, address payable withdrawTo) external;

    /// @custom:oc-access-control Operator
    function refundQuote(uint256 quoteId) external;

    /// @custom:oc-access-control Operator
    function settleQuote(uint256 quoteId, bytes32 txHash, uint256 coverExpiresAt) external;

    /// @custom:oc-access-control Operator
    function collect(address assetAddress, uint256 amount) external;

    /// @custom:oc-access-control Administrator
    function setProvider(uint32 providerId, Provider calldata provider) external;

    /// @custom:oc-access-control Administrator
    function setAsset(uint32 providerId, uint32 assetId, Asset calldata asset) external;

    /// @custom:oc-access-control Administrator
    function setProduct(uint32 providerId, uint32 productId, Product calldata product) external;

    /// @custom:oc-access-control Administrator
    function emergencyPause() external;

    /// @custom:oc-access-control Administrator
    function emergencyUnpause() external;

    /// @custom:oc-access-control Administrator
    function setCollector(address payable collector_) external;

    /// @custom:oc-access-control Administrator
    function setQuoteMetadata(address quoteMetadata_) external;

    /// @custom:oc-access-control Owner
    function transferOwnership(address newOwner) external;

    // =========================================================================
    // Errors
    // =========================================================================
    error QuoteSubmissionExpired();
    error InvalidProvider();
    error InvalidProduct();
    error InvalidAsset();
    error InvalidCoverAsset();
    error InvalidPaymentAsset();
    error InvalidPaymentAmount();
    error InvalidCoverExpiry();
    error InvalidQuote();
    error InvalidAddress();
    error InvalidSignature();
    error UnsupportedCoverAmount();
    error UnsupportedPaymentAmount();
    error QuoteNotOwned();
    error QuoteAlreadySettled();
    error QuoteAlreadyRefunded();
    error QuoteNotExpired();
    error QuoteSoulbound();
}

interface IQuoteV15 {
    // =========================================================================
    // Functions
    // =========================================================================

    function quoteIntegrators(uint256 quoteId) external view returns (uint256);
    function quoteCoveredAddresses(uint256 quoteId) external view returns (address[] memory);

    function submitQuoteV15(
        QuoteSubmission calldata quote,
        address[] memory coveredAddresses,
        uint256 integratorId,
        address mintTo,
        uint8 v, bytes32 r, bytes32 s
    )
        external
        payable
        returns (uint256 quoteId);

    /// @custom:oc-access-control Administrator
    function setIntegratorQuoteMetadata(uint256 integratorId, address quoteMetadata) external;
}

interface IQuote is IQuoteV1, IQuoteV15 {}
