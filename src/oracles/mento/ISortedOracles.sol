// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISortedOracles
 * @notice Interface for Mento's SortedOracles contract
 * @dev The SortedOracles contract maintains sorted lists of oracle reports for rate feeds
 * and provides the median value as the canonical oracle rate.
 */
interface ISortedOracles {
    /**
     * @notice Returns the median rate for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return medianRate The median rate value from all oracle reports
     * @return timestamp The timestamp of the most recent report contributing to the median
     * @dev Mento uses 1e24 (24 decimal places) fixed-point precision for rates
     * @dev The rateFeedID is typically the address of the rate feed identifier contract
     */
    function medianRate(address rateFeedID)
        external
        view
        returns (uint256 medianRate, uint256 timestamp);

    /**
     * @notice Returns the number of rates in the list for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return The number of oracle reports currently in the sorted list
     */
    function numRates(address rateFeedID)
        external
        view
        returns (uint256);

    /**
     * @notice Returns the median timestamp for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return The timestamp of the median report
     */
    function medianTimestamp(address rateFeedID)
        external
        view
        returns (uint256);
}
