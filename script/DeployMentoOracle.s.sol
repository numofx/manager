// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "../src/Cauldron.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title DeployMentoOracle
 * @notice Foundry script to deploy and configure MentoSpotOracle for Yield Protocol
 * @dev Usage:
 *   forge script script/DeployMentoOracle.s.sol:DeployMentoOracle \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployMentoOracle is Script {
    // ========== Configuration ==========
    // Update these addresses for your deployment

    // Mento SortedOracles contract on Celo Mainnet
    address constant SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;

    // Mento KES/USD rate feed ID (returns USD per 1 KES in 1e24 precision)
    // This is a derived identifier (address type), not a Chainlink aggregator
    address constant KES_USD_RATE_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    // Token addresses (Celo Mainnet)
    address constant CKES_TOKEN = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0; // cKES (tokenized KES)
    address constant CUSD_TOKEN = 0x765DE816845861e75A25fCA122bb6898B8B1282a; // cUSD

    // Your Cauldron deployment (update this!)
    address constant CAULDRON = address(0); // SET THIS

    // Asset identifiers (bytes6)
    bytes6 constant CKES = 0x634B45530000; // "cKES"
    bytes6 constant USD = 0x555344000000;  // "USD"

    // Safety parameters for cKES/USD (forward pair only)
    // Based on historical KES/USD range of ~0.007-0.008 USD per KES
    // Setting conservative bounds to allow reasonable price movement while guarding against oracle failure
    uint256 constant MAX_AGE = 600;           // 10 minutes staleness threshold
    uint256 constant MIN_PRICE = 0.003e18;    // 0.003 USD minimum (in 1e18) - guards against oracle failure
    uint256 constant MAX_PRICE = 0.015e18;    // 0.015 USD maximum (in 1e18) - allows ~2x from typical rate
    //
    // NOTE: Inverse pair (USD/cKES) is auto-created with maxAge=0, minPrice=0, maxPrice=0 (checks disabled)
    // Configure inverse bounds separately if needed via setMaxAge() and setBounds()

    // Collateralization ratio for Cauldron (150% = 1.5M in 6 decimals)
    uint32 constant COLLATERALIZATION_RATIO = 1500000;

    // Deployed contracts (populated during deployment)
    MentoSpotOracle public mentoOracle;

    function run() external {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // ========== Step 1: Deploy MentoSpotOracle ==========
        console.log("\n=== Deploying MentoSpotOracle ===");
        mentoOracle = new MentoSpotOracle(ISortedOracles(SORTED_ORACLES));
        console.log("MentoSpotOracle deployed at:", address(mentoOracle));

        // ========== Step 2: Grant Permissions ==========
        console.log("\n=== Granting Permissions ===");

        // Grant setSource role
        bytes4 setSourceRole = mentoOracle.setSource.selector;
        mentoOracle.grantRole(setSourceRole, deployer);
        console.log("Granted setSource role to deployer");

        // Grant setMaxAge role
        bytes4 setMaxAgeRole = mentoOracle.setMaxAge.selector;
        mentoOracle.grantRole(setMaxAgeRole, deployer);
        console.log("Granted setMaxAge role to deployer");

        // Grant setBounds role
        bytes4 setBoundsRole = mentoOracle.setBounds.selector;
        mentoOracle.grantRole(setBoundsRole, deployer);
        console.log("Granted setBounds role to deployer");

        // ========== Step 3: Configure Oracle Source ==========
        console.log("\n=== Configuring Oracle Source ===");

        IERC20Metadata cKES = IERC20Metadata(CKES_TOKEN);
        IERC20Metadata cUSD = IERC20Metadata(CUSD_TOKEN);

        console.log("cKES decimals:", cKES.decimals());
        console.log("cUSD decimals:", cUSD.decimals());

        mentoOracle.setSource(
            CKES,               // baseId (cKES - the collateral asset)
            cKES,               // base token
            USD,                // quoteId (USD - the quote/accounting unit)
            cUSD,               // quote token
            KES_USD_RATE_FEED,  // Mento's KES/USD rateFeedID (USD per 1 KES, 1e24)
            false               // inverse=false: use rate as-is (USD per KES)
        );
        console.log("Configured cKES/USD source using Mento KES/USD feed");
        console.log("Rate Feed ID:", KES_USD_RATE_FEED);
        console.log("Feed returns: USD per 1 KES in 1e24 precision");

        // ========== Step 4: Configure Safety Parameters (Forward Pair Only) ==========
        console.log("\n=== Configuring Safety Parameters (cKES/USD) ===");
        console.log("NOTE: Inverse pair (USD/cKES) is auto-created with disabled safety checks");
        console.log("      Configure inverse bounds separately if needed");

        // Set staleness check for forward pair (cKES/USD)
        mentoOracle.setMaxAge(CKES, USD, MAX_AGE);
        console.log("Set maxAge:", MAX_AGE, "seconds");

        // Set price bounds for forward pair (cKES/USD)
        // These bounds are based on expected USD per KES range (~0.007-0.008)
        // MIN_PRICE: Prevents oracle failure, guards against zero/near-zero prices
        // MAX_PRICE: Allows reasonable upside (~2x typical rate) while preventing manipulation
        // Bounds apply ONLY to cKES/USD direction, not to inverse (USD/cKES)
        mentoOracle.setBounds(CKES, USD, MIN_PRICE, MAX_PRICE);
        console.log("Set price bounds:");
        console.log("  minPrice:", MIN_PRICE);
        console.log("  maxPrice:", MAX_PRICE);

        // ========== Step 5: Test Oracle ==========
        console.log("\n=== Testing Oracle ===");

        try mentoOracle.peek(CKES, USD, 1e18) returns (uint256 value, uint256 updateTime) {
            console.log("Test conversion: 1 cKES =", value, "USD (in 1e18)");
            console.log("Price age:", block.timestamp - updateTime, "seconds");

            // Verify price is within bounds
            require(value >= MIN_PRICE && value <= MAX_PRICE, "Price out of bounds");
            console.log("Price within bounds: OK");

            // Verify price is fresh
            require(block.timestamp - updateTime <= MAX_AGE, "Price stale");
            console.log("Price freshness: OK");

            console.log("Oracle test: PASSED");
        } catch Error(string memory reason) {
            console.log("Oracle test FAILED:", reason);
            revert("Oracle test failed");
        }

        // ========== Step 6: Register with Cauldron (Optional) ==========
        if (CAULDRON != address(0)) {
            console.log("\n=== Registering Oracle with Cauldron ===");

            Cauldron cauldron = Cauldron(CAULDRON);

            // Note: You need the appropriate role on Cauldron to call setSpotOracle
            // This may fail if deployer doesn't have permissions
            try cauldron.setSpotOracle(
                USD,                            // baseId (debt asset)
                CKES,                           // ilkId (collateral asset)
                IOracle(address(mentoOracle)),  // oracle
                COLLATERALIZATION_RATIO         // ratio (150%)
            ) {
                console.log("Registered oracle with Cauldron");
                console.log("Collateralization ratio:", COLLATERALIZATION_RATIO);
            } catch {
                console.log("WARNING: Could not register with Cauldron");
                console.log("You may need to call setSpotOracle separately with appropriate permissions");
            }
        } else {
            console.log("\n=== Skipping Cauldron Registration ===");
            console.log("Set CAULDRON address to register oracle");
        }

        vm.stopBroadcast();

        // ========== Step 7: Print Summary ==========
        console.log("\n=== Deployment Summary ===");
        console.log("MentoSpotOracle:", address(mentoOracle));
        console.log("SortedOracles:", SORTED_ORACLES);
        console.log("Rate Feed ID:", KES_USD_RATE_FEED);
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Transfer admin roles to governance multisig");
        console.log("3. Register oracle with Cauldron (if not done above)");
        console.log("4. Monitor oracle health and price feeds");
    }

    /**
     * @notice Helper function to verify oracle configuration after deployment
     * @dev Can be called separately to test oracle without deploying
     */
    function verify() external view {
        require(address(mentoOracle) != address(0), "Oracle not deployed");

        console.log("\n=== Oracle Verification ===");

        // Check source configuration
        (
            address rateFeedID,
            uint8 baseDecimals,
            uint8 quoteDecimals,
            bool inverse,
            uint256 maxAge,
            uint256 minPrice,
            uint256 maxPrice
        ) = mentoOracle.sources(CKES, USD);

        console.log("Source Configuration:");
        console.log("  rateFeedID:", rateFeedID);
        console.log("  baseDecimals:", baseDecimals);
        console.log("  quoteDecimals:", quoteDecimals);
        console.log("  inverse:", inverse);
        console.log("  maxAge:", maxAge);
        console.log("  minPrice:", minPrice);
        console.log("  maxPrice:", maxPrice);

        // Test conversion
        (uint256 value, uint256 updateTime) = mentoOracle.peek(CKES, USD, 1e18);
        console.log("\nCurrent Price:");
        console.log("  1 cKES =", value, "USD");
        console.log("  Update time:", updateTime);
        console.log("  Age:", block.timestamp - updateTime, "seconds");

        // Test inverse
        (uint256 inverseValue,) = mentoOracle.peek(USD, CKES, 1e18);
        console.log("\nInverse Price:");
        console.log("  1 USD =", inverseValue, "cKES");
    }
}
