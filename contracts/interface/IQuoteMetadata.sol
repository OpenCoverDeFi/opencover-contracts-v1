// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import "./IQuote.sol";

interface IQuoteMetadataV1 {
    // =========================================================================
    // Functions
    // =========================================================================
    function generateQuoteMetadata(
        QuoteSubmission calldata quoteSubmission,
        QuoteStatus status,
        uint256 quoteId
    )
        external
        view
        returns (
            string memory name,
            string memory description,
            string memory image
        );

    // =========================================================================
    // Errors
    // =========================================================================
    error NotQuote();
}

interface IQuoteMetadata is IQuoteMetadataV1 {}
