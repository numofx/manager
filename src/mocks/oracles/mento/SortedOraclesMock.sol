// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../../oracles/mento/ISortedOracles.sol";

/**
 * @title SortedOraclesMock
 * @notice Mock implementation of Mento's SortedOracles for testing
 * @dev Allows setting arbitrary median rates and timestamps for testing
 */
contract SortedOraclesMock is ISortedOracles {
    struct RateData {
        uint256 medianRate;
        uint256 timestamp;
        uint256 numRates;
    }

    mapping(address => RateData) public rateData;

    /**
     * @notice Set the median rate and timestamp for a rateFeedID
     * @param rateFeedID The rate feed identifier
     * @param rate The median rate (in 1e24 precision)
     * @param timestamp The timestamp of the rate
     */
    function setMedianRate(address rateFeedID, uint256 rate, uint256 timestamp) external {
        rateData[rateFeedID] = RateData({
            medianRate: rate,
            timestamp: timestamp,
            numRates: 1
        });
    }

    /**
     * @notice Set the median rate with current block timestamp
     * @param rateFeedID The rate feed identifier
     * @param rate The median rate (in 1e24 precision)
     */
    function setMedianRate(address rateFeedID, uint256 rate) external {
        rateData[rateFeedID] = RateData({
            medianRate: rate,
            timestamp: block.timestamp,
            numRates: 1
        });
    }

    /**
     * @notice Set the number of rates for a rateFeedID (for testing numRates function)
     * @param rateFeedID The rate feed identifier
     * @param num The number of rates
     */
    function setNumRates(address rateFeedID, uint256 num) external {
        rateData[rateFeedID].numRates = num;
    }

    /**
     * @notice Returns the median rate for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return rate The median rate value
     * @return time The timestamp of the rate
     */
    function medianRate(address rateFeedID)
        external
        view
        override
        returns (uint256 rate, uint256 time)
    {
        RateData memory data = rateData[rateFeedID];
        // Return 0 if not set, let the oracle handle the validation
        return (data.medianRate, data.timestamp);
    }

    /**
     * @notice Returns the number of rates in the list for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return The number of oracle reports
     */
    function numRates(address rateFeedID)
        external
        view
        override
        returns (uint256)
    {
        return rateData[rateFeedID].numRates;
    }

    /**
     * @notice Returns the median timestamp for a given rateFeedID
     * @param rateFeedID The identifier (address) of the rate feed
     * @return The timestamp of the median report
     */
    function medianTimestamp(address rateFeedID)
        external
        view
        override
        returns (uint256)
    {
        return rateData[rateFeedID].timestamp;
    }
}
