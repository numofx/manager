// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../../interfaces/IOracle.sol";
import "./ISortedOracles.sol";

/**
 * @title MentoSpotOracle
 * @notice Oracle adapter for Mento protocol's SortedOracles
 * @dev Reads spot prices from Mento's SortedOracles contract and adapts them to the Yield protocol IOracle interface.
 *
 * Mento Specifics:
 * - Mento rates are expressed in 1e24 fixed-point precision (24 decimals)
 * - This oracle converts to the standard 1e18 precision used by most DeFi protocols
 * - RateFeedIDs in Mento are addresses (derived identifiers, not Chainlink-style aggregators)
 *   Example: KES/USD feed is 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169
 *
 * Price Direction:
 * - Mento's KES/USD feed returns USD per 1 KES (quote per base)
 * - This oracle supports both direct and inverse pricing via the `inverse` flag
 * - When inverse=false: uses Mento rate directly (e.g., USD per 1 KES → use for cKES collateral pricing)
 * - When inverse=true: inverts the rate (e.g., 1/rate = KES per USD)
 *
 * Example: Pricing cKES collateral
 * - Mento KES/USD returns: 0.0073 USD per 1 KES (in 1e24: 7.3e21)
 * - Oracle converts to 1e18: 0.0073e18 = 7.3e15
 * - For 1000 cKES: 1000e18 * 7.3e15 / 1e18 = 7.3e18 (7.3 USD)
 *
 * Security Features:
 * - Staleness checks: Rejects prices older than configurable maxAge
 * - Sanity bounds: Rejects prices outside [minPrice, maxPrice] range
 * - Access control: Only authorized addresses can configure sources
 */
contract MentoSpotOracle is IOracle, AccessControl {
    using Cast for bytes32;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed rateFeedID,
        uint8 baseDecimals,
        uint8 quoteDecimals,
        bool inverse
    );
    event MaxAgeSet(bytes6 indexed baseId, bytes6 indexed quoteId, uint256 maxAge);
    event BoundsSet(bytes6 indexed baseId, bytes6 indexed quoteId, uint256 minPrice, uint256 maxPrice);

    /// @dev Mento uses 24 decimal places for rate precision
    uint256 private constant MENTO_DECIMALS = 24;

    /// @dev Standard DeFi precision (18 decimals)
    uint256 private constant TARGET_DECIMALS = 18;

    /// @dev Mento SortedOracles contract instance
    ISortedOracles public immutable sortedOracles;

    struct Source {
        address rateFeedID;      // Mento rate feed identifier (address format)
        uint8 baseDecimals;      // Decimals of the base asset
        uint8 quoteDecimals;     // Decimals of the quote asset
        bool inverse;            // If true, invert the Mento rate
        uint256 maxAge;          // Maximum age in seconds for a valid price (0 = no check)
        uint256 minPrice;        // Minimum acceptable price (0 = no check)
        uint256 maxPrice;        // Maximum acceptable price (0 = no check)
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Construct the MentoSpotOracle
     * @param sortedOracles_ Address of Mento's SortedOracles contract
     */
    constructor(ISortedOracles sortedOracles_) {
        require(address(sortedOracles_) != address(0), "Invalid SortedOracles address");
        sortedOracles = sortedOracles_;
    }

    /**
     * @notice Set or update a price source
     * @param baseId Yield protocol identifier for base asset (e.g., "cKES")
     * @param base Base asset ERC20 metadata (for decimals)
     * @param quoteId Yield protocol identifier for quote asset (e.g., "USD")
     * @param quote Quote asset ERC20 metadata (for decimals)
     * @param rateFeedID Mento rate feed identifier (address format, e.g., 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169)
     * @param inverse If true, invert the Mento rate (base/quote becomes quote/base)
     *
     * @dev Inverse Pair Behavior (Policy A):
     * This function automatically creates the inverse pair (quoteId/baseId) with flipped parameters.
     * However, safety parameters (maxAge, minPrice, maxPrice) are NOT propagated to the inverse pair.
     * The inverse pair starts with maxAge=0, minPrice=0, maxPrice=0 (all checks disabled).
     *
     * To enable safety checks on the inverse pair, you must explicitly call:
     * - setMaxAge(quoteId, baseId, maxAge)
     * - setBounds(quoteId, baseId, minPrice, maxPrice)
     *
     * This design ensures explicit configuration of safety parameters for each direction.
     *
     * @dev Only callable by authorized addresses (via AccessControl)
     */
    function setSource(
        bytes6 baseId,
        IERC20Metadata base,
        bytes6 quoteId,
        IERC20Metadata quote,
        address rateFeedID,
        bool inverse
    ) external auth {
        require(rateFeedID != address(0), "Invalid rateFeedID");

        sources[baseId][quoteId] = Source({
            rateFeedID: rateFeedID,
            baseDecimals: base.decimals(),
            quoteDecimals: quote.decimals(),
            inverse: inverse,
            maxAge: 0,      // No staleness check by default
            minPrice: 0,    // No minimum bound by default
            maxPrice: 0     // No maximum bound by default
        });
        emit SourceSet(baseId, quoteId, rateFeedID, base.decimals(), quote.decimals(), inverse);

        // Set up the inverse pair automatically with disabled safety checks (Policy A)
        if (baseId != quoteId) {
            sources[quoteId][baseId] = Source({
                rateFeedID: rateFeedID,
                baseDecimals: quote.decimals(), // Swap base and quote
                quoteDecimals: base.decimals(),
                inverse: !inverse,               // Flip the inverse flag
                maxAge: 0,
                minPrice: 0,
                maxPrice: 0
            });
            emit SourceSet(quoteId, baseId, rateFeedID, quote.decimals(), base.decimals(), !inverse);
        }
    }

    /**
     * @notice Set maximum age for a price source
     * @param baseId Base asset identifier
     * @param quoteId Quote asset identifier
     * @param maxAge Maximum age in seconds (0 to disable staleness check)
     * @dev Prices older than maxAge will cause the oracle to revert
     */
    function setMaxAge(bytes6 baseId, bytes6 quoteId, uint256 maxAge) external auth {
        require(sources[baseId][quoteId].rateFeedID != address(0), "Source not found");
        sources[baseId][quoteId].maxAge = maxAge;
        emit MaxAgeSet(baseId, quoteId, maxAge);
    }

    /**
     * @notice Set sanity bounds for a price source
     * @param baseId Base asset identifier
     * @param quoteId Quote asset identifier
     * @param minPrice Minimum acceptable price in 1e18 precision (0 to disable)
     * @param maxPrice Maximum acceptable price in 1e18 precision (0 to disable)
     * @dev Prices outside [minPrice, maxPrice] will cause the oracle to revert
     */
    function setBounds(bytes6 baseId, bytes6 quoteId, uint256 minPrice, uint256 maxPrice) external auth {
        require(sources[baseId][quoteId].rateFeedID != address(0), "Source not found");
        if (minPrice > 0 && maxPrice > 0) {
            require(minPrice < maxPrice, "Invalid bounds");
        }
        sources[baseId][quoteId].minPrice = minPrice;
        sources[baseId][quoteId].maxPrice = maxPrice;
        emit BoundsSet(baseId, quoteId, minPrice, maxPrice);
    }

    /**
     * @notice Check the configuration status of a price source
     * @param baseId Base asset identifier
     * @param quoteId Quote asset identifier
     * @return configured Whether the source has been configured (rateFeedID set)
     * @return hasStalenessCheck Whether staleness checking is enabled (maxAge > 0)
     * @return hasBounds Whether sanity bounds are configured (minPrice and maxPrice both > 0)
     * @dev Use this to verify inverse pairs have appropriate safety parameters set
     */
    function configStatus(bytes6 baseId, bytes6 quoteId) external view returns (
        bool configured,
        bool hasStalenessCheck,
        bool hasBounds
    ) {
        Source memory s = sources[baseId][quoteId];
        configured = s.rateFeedID != address(0);
        hasStalenessCheck = s.maxAge != 0;
        hasBounds = (s.minPrice != 0) && (s.maxPrice != 0);
    }

    /**
     * @notice Peek at the latest oracle price without state changes
     * @param base Base asset identifier
     * @param quote Quote asset identifier
     * @param amount Amount of base asset to convert
     * @return value Equivalent amount in quote asset
     * @return updateTime Timestamp when the price was last updated
     * @dev This is a view function and doesn't update state
     * @dev CRITICAL: `amount` MUST be normalized to 18 decimals regardless of the token's native decimals.
     *      This oracle returns values in 18-decimal precision.
     *      Token-decimal normalization is the caller's responsibility (e.g., Join/adapters).
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Get the latest oracle price (same as peek for this oracle)
     * @param base Base asset identifier
     * @param quote Quote asset identifier
     * @param amount Amount of base asset to convert
     * @return value Equivalent amount in quote asset
     * @return updateTime Timestamp when the price was last updated
     * @dev For Mento oracles, get() is identical to peek() since SortedOracles is always view-only
     * @dev CRITICAL: `amount` MUST be normalized to 18 decimals regardless of the token's native decimals.
     *      This oracle returns values in 18-decimal precision.
     *      Token-decimal normalization is the caller's responsibility (e.g., Join/adapters).
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Internal function to fetch and convert prices from Mento
     * @param baseId Base asset identifier (bytes6)
     * @param quoteId Quote asset identifier (bytes6)
     * @param amount Amount to convert
     * @return value Converted amount
     * @return updateTime Price timestamp
     * @dev Handles decimal conversion from Mento's 1e24 to standard 1e18
     * @dev Applies staleness checks and sanity bounds
     * @dev CRITICAL: `amount` MUST be normalized to 18 decimals regardless of the token's native decimals.
     *      This oracle returns values in 18-decimal precision.
     *      Token-decimal normalization is the caller's responsibility (e.g., Join/adapters).
     */
    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amount
    ) private view returns (uint256 value, uint256 updateTime) {
        // Handle same-asset conversion
        if (baseId == quoteId) {
            return (amount, block.timestamp);
        }

        Source memory source = sources[baseId][quoteId];
        require(source.rateFeedID != address(0), "Source not found");

        // Fetch median rate from Mento SortedOracles
        uint256 mentoRate;
        (mentoRate, updateTime) = sortedOracles.medianRate(source.rateFeedID);

        require(mentoRate > 0, "Invalid Mento rate");

        // Check staleness if maxAge is configured
        if (source.maxAge > 0) {
            require(block.timestamp - updateTime <= source.maxAge, "Stale price");
        }

        // ========== DECIMAL CONVERSION: 1e24 → 1e18 ==========
        // Mento returns rates in 1e24 fixed-point precision
        // We convert to 1e18 (standard DeFi precision)
        //
        // Example: Mento KES/USD returns 0.0073 USD per 1 KES
        // mentoRate = 0.0073 * 1e24 = 7.3e21
        // rate18 = 7.3e21 / 1e6 = 7.3e15 (which is 0.0073 * 1e18)
        uint256 rate18 = mentoRate / 1e6;  // 1e24 / 1e6 = 1e18

        // ========== INVERSION (if needed) ==========
        // Mento's KES/USD feed returns: USD per 1 KES
        // If inverse=false: use as-is (for cKES collateral → USD value)
        // If inverse=true: flip to KES per USD (rarely needed)
        uint256 finalRate;
        if (source.inverse) {
            // Invert: finalRate = 1 / rate18 (in 1e18 precision)
            // Example: if rate18 = 0.0073e18, then finalRate = 1e18 / 0.0073e18 ≈ 137e18
            require(rate18 > 0, "Cannot invert zero rate");
            finalRate = (1e18 * 1e18) / rate18;
        } else {
            // Direct use: most common case for collateral pricing
            // rate18 already represents USD per 1 KES/cKES
            finalRate = rate18;
        }

        // ========== SANITY BOUNDS ==========
        // Reject prices outside configured [minPrice, maxPrice] range
        // Prices are in 1e18 precision
        if (source.minPrice > 0) {
            require(finalRate >= source.minPrice, "Price below minimum");
        }
        if (source.maxPrice > 0) {
            require(finalRate <= source.maxPrice, "Price above maximum");
        }

        // ========== AMOUNT CONVERSION ==========
        // Convert `amount` of base asset to equivalent quote asset value
        // Formula: value = (amount * rate) / 1e18
        //
        // Example: Pricing 1000 cKES in USD at 0.0073 USD/KES
        // - amount = 1000e18 (1000 cKES in 18 decimals)
        // - finalRate = 7.3e15 (0.0073 USD/KES in 1e18)
        // - value = (1000e18 * 7.3e15) / 1e18 = 7.3e18 (7.3 USD)
        //
        // Note: The oracle operates in abstract "wei" units. Actual token decimals
        // (baseDecimals, quoteDecimals) are stored but not used in the math because
        // Yield Protocol expects all amounts to be normalized to 18 decimals at the
        // integration layer (Joins, Cauldron, etc.).
        value = (amount * finalRate) / 1e18;
    }
}
