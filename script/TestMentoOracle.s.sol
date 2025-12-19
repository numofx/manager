// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/Test.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "../src/mocks/oracles/mento/SortedOraclesMock.sol";
import "../src/mocks/CKESMock.sol";

/**
 * @title TestMentoOracle
 * @notice Standalone test runner for MentoSpotOracle (bypasses Mocks library issues)
 * @dev Run with: forge script script/TestMentoOracle.s.sol -vvv
 */
contract TestMentoOracle is Script, Test {
    MentoSpotOracle public mentoOracle;
    SortedOraclesMock public sortedOraclesMock;
    CKESMock public cKES;
    CKESMock public usd;

    bytes6 public constant CKES = 0x634B45530000;
    bytes6 public constant USD = 0x555344000000;
    address public constant KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    uint256 public constant MENTO_UNIT = 1e24;
    uint256 public constant CKES_USD_PRICE_MENTO = 0.01e24; // 0.01 USD per KES
    uint256 public constant WAD = 1e18;

    function run() external {
        console.log("\n=== MentoSpotOracle Test Runner ===\n");

        setUp();

        console.log("Running tests...\n");

        testPeekConversion();
        testDecimalConversion();
        testInversePricing();
        testStaleness();
        testBounds();
        testAccessControl();

        console.log("\n=== All Tests Passed! ===\n");
    }

    function setUp() public {
        sortedOraclesMock = new SortedOraclesMock();
        cKES = new CKESMock();
        usd = new CKESMock();

        mentoOracle = new MentoSpotOracle(ISortedOracles(address(sortedOraclesMock)));

        // Grant this contract permission to configure the oracle
        address self = address(this);
        mentoOracle.grantRole(MentoSpotOracle.setSource.selector, self);
        mentoOracle.grantRole(MentoSpotOracle.setMaxAge.selector, self);
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, self);

        mentoOracle.setSource(CKES, cKES, USD, usd, KES_USD_FEED, false);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, CKES_USD_PRICE_MENTO);

        console.log("Setup complete:");
        console.log("  Oracle:", address(mentoOracle));
        console.log("  SortedOracles Mock:", address(sortedOraclesMock));
        console.log("  Rate Feed ID:", KES_USD_FEED);
        console.log("");
    }

    function testPeekConversion() public {
        console.log("[TEST] Basic peek conversion");

        uint256 amount = 100e18; // 100 cKES
        (uint256 value, uint256 updateTime) = mentoOracle.peek(CKES, USD, amount);

        assertEq(value, 1e18, "100 cKES should equal 1 USD");
        assertEq(updateTime, block.timestamp, "Timestamp should be current");

        console.log("  PASS: 100 cKES = 1 USD");
    }

    function testDecimalConversion() public {
        console.log("[TEST] Decimal conversion (1e24 -> 1e18)");

        sortedOraclesMock.setMedianRate(KES_USD_FEED, 1e24); // 1.0 USD/KES

        uint256 amount = 1e18; // 1 cKES
        (uint256 value,) = mentoOracle.peek(CKES, USD, amount);

        assertEq(value, 1e18, "1e24 should convert to 1e18");

        console.log("  PASS: 1e24 precision -> 1e18 precision");
    }

    function testInversePricing() public {
        console.log("[TEST] Inverse pricing");

        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.01e24);

        uint256 amount = 1e18; // 1 USD
        (uint256 value,) = mentoOracle.peek(USD, CKES, amount);

        assertEq(value, 100e18, "1 USD should equal 100 cKES (inverse)");

        console.log("  PASS: USD/cKES inverse works correctly");
    }

    function testStaleness() public {
        console.log("[TEST] Staleness checks");

        mentoOracle.setMaxAge(CKES, USD, 600); // 10 min

        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.01e24, block.timestamp);
        (uint256 value,) = mentoOracle.peek(CKES, USD, 1e18);
        assertGt(value, 0, "Fresh price should work");

        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.01e24, block.timestamp - 700);
        vm.expectRevert("Stale price");
        mentoOracle.peek(CKES, USD, 1e18);

        console.log("  PASS: Staleness check working");
    }

    function testBounds() public {
        console.log("[TEST] Price bounds");

        mentoOracle.setBounds(CKES, USD, 0.005e18, 0.05e18);

        // Within bounds
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.01e24);
        (uint256 value,) = mentoOracle.peek(CKES, USD, 1e18);
        assertGt(value, 0, "Price within bounds should work");

        // Below minimum
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.001e24);
        vm.expectRevert("Price below minimum");
        mentoOracle.peek(CKES, USD, 1e18);

        // Above maximum
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0.1e24);
        vm.expectRevert("Price above maximum");
        mentoOracle.peek(CKES, USD, 1e18);

        console.log("  PASS: Bounds enforcement working");
    }

    function testAccessControl() public {
        console.log("[TEST] Access control");

        address unauthorized = address(0xbad);

        vm.prank(unauthorized);
        vm.expectRevert("Access denied");
        mentoOracle.setSource(CKES, cKES, USD, usd, KES_USD_FEED, false);

        console.log("  PASS: Access control working");
    }
}
