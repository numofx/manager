// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Cauldron.sol";
import "../src/Ladle.sol";
import "../src/Join.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title DeployAll
 * @notice End-to-end deployment script for Yield Protocol on Celo
 * @dev Deploys and configures all core contracts in a single transaction
 *
 * Usage:
 *   forge script script/DeployAll.s.sol \
 *     --rpc-url $CELO \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Required env vars:
 * - PRIVATE_KEY: Deployer private key
 * - GOVERNANCE: Governance address (receives ROOT roles)
 *
 * Optional env vars:
 * - WETH: Custom wCELO address (default: 0x471EcE3750Da237f93B8E339c536989b8978a438)
 */
contract DeployAll is Script {
    // ========== Celo Mainnet Constants ==========
    address constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address constant SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;

    // cKES configuration
    address constant CKES_TOKEN = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant CUSD_TOKEN = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address constant KES_USD_RATE_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    bytes6 constant CKES = 0x634B45530000; // "cKES"
    bytes6 constant USD = 0x555344000000;  // "USD"

    // Oracle safety parameters
    uint256 constant MAX_AGE = 600;        // 10 minutes
    uint256 constant MIN_PRICE = 0.003e18; // 0.003 USD
    uint256 constant MAX_PRICE = 0.015e18; // 0.015 USD

    // Collateralization ratio (150%)
    uint32 constant COLLATERALIZATION_RATIO = 1500000;

    // Debt limits
    uint96 constant MAX_DEBT = 1_000_000;  // 1M (in debt units, scaled by decimals)
    uint24 constant MIN_DEBT = 0;
    uint8 constant DEC = 18;

    // ========== Deployed Contracts ==========
    Cauldron public cauldron;
    Ladle public ladle;
    MentoSpotOracle public mentoOracle;
    Join public ckesJoin;

    function run() external {
        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address governance = vm.envAddress("GOVERNANCE");
        address wethAddr = vm.envOr("WETH", WCELO);

        console2.log("============================================================");
        console2.log("Yield Protocol - Full Celo Deployment");
        console2.log("============================================================");
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance / 1e18, "CELO");
        console2.log("Governance:", governance);
        console2.log("wCELO:", wethAddr);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ========== Step 1: Deploy Cauldron ==========
        console2.log("Step 1: Deploying Cauldron...");
        cauldron = new Cauldron();
        console2.log("  Cauldron:", address(cauldron));

        // ========== Step 2: Deploy Ladle ==========
        console2.log("\nStep 2: Deploying Ladle...");
        ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(wethAddr));
        console2.log("  Ladle:", address(ladle));
        console2.log("  Router:", address(ladle.router()));

        // ========== Step 3: Deploy MentoSpotOracle ==========
        console2.log("\nStep 3: Deploying MentoSpotOracle...");
        mentoOracle = new MentoSpotOracle(ISortedOracles(SORTED_ORACLES));
        console2.log("  MentoSpotOracle:", address(mentoOracle));

        // ========== Step 4: Deploy cKES Join ==========
        console2.log("\nStep 4: Deploying cKES Join...");
        ckesJoin = new Join(CKES_TOKEN);
        console2.log("  cKES Join:", address(ckesJoin));

        // ========== Step 5: Configure MentoOracle ==========
        console2.log("\nStep 5: Configuring MentoOracle...");

        // Grant roles to deployer temporarily
        mentoOracle.grantRole(mentoOracle.setSource.selector, deployer);
        mentoOracle.grantRole(mentoOracle.setMaxAge.selector, deployer);
        mentoOracle.grantRole(mentoOracle.setBounds.selector, deployer);

        // Set source
        IERC20Metadata cKES = IERC20Metadata(CKES_TOKEN);
        IERC20Metadata cUSD = IERC20Metadata(CUSD_TOKEN);

        mentoOracle.setSource(
            CKES,
            cKES,
            USD,
            cUSD,
            KES_USD_RATE_FEED,
            false  // not inverse
        );
        console2.log("  Configured cKES/USD source");

        // Set safety parameters
        mentoOracle.setMaxAge(CKES, USD, MAX_AGE);
        mentoOracle.setBounds(CKES, USD, MIN_PRICE, MAX_PRICE);
        console2.log("  Set safety parameters (maxAge, bounds)");

        // ========== Step 6: Configure Cauldron ==========
        console2.log("\nStep 6: Configuring Cauldron...");

        // Add cKES asset
        cauldron.addAsset(CKES, CKES_TOKEN);
        console2.log("  Added cKES asset");

        // Set spot oracle for USD/cKES pair
        cauldron.setSpotOracle(
            USD,                              // baseId (debt asset)
            CKES,                             // ilkId (collateral asset)
            IOracle(address(mentoOracle)),    // oracle
            COLLATERALIZATION_RATIO           // ratio
        );
        console2.log("  Set spot oracle (USD/cKES, 150% ratio)");

        // Set debt limits
        cauldron.setDebtLimits(
            USD,      // baseId
            CKES,     // ilkId
            MAX_DEBT, // max
            MIN_DEBT, // min
            DEC       // decimals
        );
        console2.log("  Set debt limits (max: 1M USD)");

        // ========== Step 7: Grant Ladle Permissions on Cauldron ==========
        console2.log("\nStep 7: Granting Ladle permissions on Cauldron...");

        cauldron.grantRole(Cauldron.build.selector, address(ladle));
        cauldron.grantRole(Cauldron.destroy.selector, address(ladle));
        cauldron.grantRole(Cauldron.tweak.selector, address(ladle));
        cauldron.grantRole(Cauldron.give.selector, address(ladle));
        cauldron.grantRole(Cauldron.pour.selector, address(ladle));
        cauldron.grantRole(Cauldron.stir.selector, address(ladle));
        cauldron.grantRole(Cauldron.slurp.selector, address(ladle));
        console2.log("  Granted vault management permissions");

        // ========== Step 8: Grant Ladle Permissions on Join ==========
        console2.log("\nStep 8: Granting Ladle permissions on cKES Join...");

        ckesJoin.grantRole(Join.join.selector, address(ladle));
        ckesJoin.grantRole(Join.exit.selector, address(ladle));
        console2.log("  Granted join/exit permissions");

        // ========== Step 9: Add Join to Ladle ==========
        console2.log("\nStep 9: Adding cKES Join to Ladle...");

        ladle.addJoin(CKES, IJoin(address(ckesJoin)));
        console2.log("  Added cKES join");

        // ========== Step 10: Transfer Governance ==========
        console2.log("\nStep 10: Transferring governance...");

        if (deployer != governance) {
            // Transfer Cauldron ROOT
            cauldron.grantRole(cauldron.ROOT(), governance);
            cauldron.revokeRole(cauldron.ROOT(), deployer);
            console2.log("  Transferred Cauldron ROOT to governance");

            // Transfer Ladle ROOT
            ladle.grantRole(ladle.ROOT(), governance);
            ladle.revokeRole(ladle.ROOT(), deployer);
            console2.log("  Transferred Ladle ROOT to governance");

            // Transfer MentoOracle roles
            mentoOracle.grantRole(mentoOracle.ROOT(), governance);
            mentoOracle.revokeRole(mentoOracle.ROOT(), deployer);
            console2.log("  Transferred MentoOracle ROOT to governance");

            // Transfer Join ROOT
            ckesJoin.grantRole(ckesJoin.ROOT(), governance);
            ckesJoin.revokeRole(ckesJoin.ROOT(), deployer);
            console2.log("  Transferred cKES Join ROOT to governance");
        } else {
            console2.log("  Deployer is governance, skipping transfer");
        }

        vm.stopBroadcast();

        // ========== Step 11: Verification ==========
        console2.log("\nStep 11: Verifying deployment...");

        // Verify Cauldron
        require(cauldron.hasRole(cauldron.ROOT(), governance), "Cauldron: governance missing ROOT");
        console2.log("  Cauldron: governance has ROOT");

        // Verify Ladle
        require(ladle.hasRole(ladle.ROOT(), governance), "Ladle: governance missing ROOT");
        require(address(ladle.cauldron()) == address(cauldron), "Ladle: wrong cauldron");
        console2.log("  Ladle: governance has ROOT, cauldron set");

        // Verify MentoOracle
        require(mentoOracle.hasRole(mentoOracle.ROOT(), governance), "Oracle: governance missing ROOT");
        (uint256 price,) = mentoOracle.peek(CKES, USD, 1e18);
        require(price >= MIN_PRICE && price <= MAX_PRICE, "Oracle: price out of bounds");
        console2.log("  MentoOracle: governance has ROOT, price valid");

        // Verify Join
        require(ckesJoin.hasRole(ckesJoin.ROOT(), governance), "Join: governance missing ROOT");
        require(address(ckesJoin.asset()) == CKES_TOKEN, "Join: wrong asset");
        console2.log("  cKES Join: governance has ROOT, asset set");

        // Print Summary
        console2.log("\n============================================================");
        console2.log("DEPLOYMENT COMPLETE");
        console2.log("============================================================");
        console2.log("\nCore Contracts:");
        console2.log("  Cauldron:        ", address(cauldron));
        console2.log("  Ladle:           ", address(ladle));
        console2.log("  MentoSpotOracle: ", address(mentoOracle));
        console2.log("  cKES Join:       ", address(ckesJoin));
        console2.log("\nConfiguration:");
        console2.log("  Governance:      ", governance);
        console2.log("  wCELO:           ", wethAddr);
        console2.log("  Collateral Ratio:", COLLATERALIZATION_RATIO / 10000, "%");
        console2.log("  Max Debt:        ", MAX_DEBT, "USD (scaled)");
        console2.log("\nOracle:");
        console2.log("  SortedOracles:   ", SORTED_ORACLES);
        console2.log("  Rate Feed:       ", KES_USD_RATE_FEED);
        console2.log("  Current Price:   ", price, "USD per cKES (1e18)");
        console2.log("\nNext Steps:");
        console2.log("1. Verify contracts on Celoscan");
        console2.log("2. Test with small amounts");
        console2.log("3. Monitor oracle health");
        console2.log("4. Add additional assets as needed");
        console2.log("============================================================");
    }
}
