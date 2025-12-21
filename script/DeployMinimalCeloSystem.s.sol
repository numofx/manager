// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Cauldron.sol";
import "../src/Ladle.sol";
import "../src/Witch.sol";
import "../src/Join.sol";
import "../src/FYToken.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title DeployMinimalCeloSystem
 * @notice Production-ready IDEMPOTENT deployment script for Yield Protocol v2 on Celo
 * @dev Deploys minimal working system: Cauldron, Ladle, Witch, Oracles, Joins, fyUSDT
 *
 * IDEMPOTENCY:
 *   This script can be safely rerun multiple times. It will reuse existing contracts
 *   if they are already deployed (detected via bytecode check) or if override env vars
 *   are provided. Only missing contracts will be deployed.
 *
 * PREFLIGHT (always run first):
 *   source .env
 *   # Simulation (no transactions):
 *   forge script script/DeployMinimalCeloSystem.s.sol --rpc-url "$CELO_RPC_URL" -vvvv
 *
 * DEPLOY:
 *   source .env
 *   forge script script/DeployMinimalCeloSystem.s.sol \
 *     --rpc-url "$CELO_RPC_URL" \
 *     --broadcast \
 *     --slow \
 *     -vvvv
 *
 * REQUIRED ENV VARS:
 *   CELO_RPC_URL       - Celo mainnet RPC endpoint
 *   PRIVATE_KEY        - Deployer private key (0x...)
 *   GOVERNANCE         - Governance address to receive ROOT roles
 *   CKES               - cKES token address
 *   USDT               - USDT token address on Celo
 *
 * OPTIONAL ENV VARS (infrastructure):
 *   WCELO              - wCELO address (default: 0x471EcE3750Da237f93B8E339c536989b8978a438)
 *   SORTED_ORACLES     - Mento SortedOracles (default: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33)
 *   KES_USD_RATE_FEED  - cKES/USD rate feed (default: 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169)
 *   REVOKE_DEPLOYER    - Set to "true" to revoke deployer permissions (default: true)
 *   MATURITY           - fyUSDT maturity timestamp (default: 1 year from now)
 *
 * OPTIONAL ENV VARS (contract overrides for idempotency):
 *   CAULDRON           - Reuse existing Cauldron at this address
 *   LADLE              - Reuse existing Ladle at this address
 *   WITCH              - Reuse existing Witch at this address
 *   MENTO_ORACLE       - Reuse existing MentoSpotOracle at this address
 *   JOIN_CKES          - Reuse existing cKES Join at this address
 *   JOIN_USDT          - Reuse existing USDT Join at this address
 *   FYUSDT             - Reuse existing fyUSDT at this address
 */
contract DeployMinimalCeloSystem is Script {
    // ========== CELO MAINNET CONSTANTS ==========
    uint256 constant CELO_CHAIN_ID = 42220;

    // Default addresses (can be overridden via env vars)
    address constant DEFAULT_WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address constant DEFAULT_SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address constant DEFAULT_KES_USD_RATE_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;
    address constant DEFAULT_CUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Asset IDs (deterministic bytes6 from symbols)
    bytes6 constant CKES_ID = 0x634b45530000; // "cKES"
    bytes6 constant USDT_ID = 0x555344540000; // "USDT"

    // Oracle safety parameters
    uint256 constant ORACLE_MAX_AGE = 600;        // 10 minutes
    uint256 constant CKES_MIN_PRICE = 0.003e18;   // 0.003 USD
    uint256 constant CKES_MAX_PRICE = 0.015e18;   // 0.015 USD

    // Collateralization parameters
    uint32 constant COLLATERALIZATION_RATIO = 1500000;  // 150%
    uint96 constant MAX_DEBT = 1_000_000e18;             // 1M USDT
    uint24 constant MIN_DEBT = 0;
    uint8 constant DEC = 18;

    // Liquidation parameters
    uint128 constant AUCTION_DURATION = 3600;     // 1 hour
    uint128 constant INITIAL_COLLATERAL = 1e18;   // 1.0 (100%)

    // ========== DEPLOYED CONTRACTS ==========
    Cauldron public cauldron;
    Ladle public ladle;
    Witch public witch;
    MentoSpotOracle public mentoOracle;
    Join public ckesJoin;
    Join public usdtJoin;
    FYToken public fyUSDT;

    // ========== CONFIGURATION ==========
    address public wcelo;
    address public sortedOracles;
    address public kesUsdRateFeed;
    address public governance;
    address public ckesToken;
    address public usdtToken;
    address public cusdToken;
    uint256 public maturity;
    bool public revokeDeployer;

    function run() external {
        // ========== STEP 0: LOAD AND VALIDATE ENVIRONMENT ==========
        console2.log("============================================================");
        console2.log("Yield Protocol v2 - Minimal Celo System Deployment");
        console2.log("(IDEMPOTENT - Safe to rerun)");
        console2.log("============================================================");
        console2.log("");

        _loadEnvironment();
        _validateEnvironment();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        uint64 nonceBefore = vm.getNonce(deployer);

        console2.log("Deployer:       ", deployer);
        console2.log("Balance:        ", deployer.balance / 1e18, "CELO");
        console2.log("Governance:     ", governance);
        console2.log("Revoke Deployer:", revokeDeployer);
        console2.log("");
        console2.log("Assets:");
        console2.log("  cKES:         ", ckesToken);
        console2.log("  USDT:         ", usdtToken);
        console2.log("  wCELO:        ", wcelo);
        console2.log("");
        console2.log("Oracle:");
        console2.log("  SortedOracles:", sortedOracles);
        console2.log("  Rate Feed:    ", kesUsdRateFeed);
        console2.log("  MENTO_ORACLE: ", vm.envOr("MENTO_ORACLE", address(0)), vm.envOr("MENTO_ORACLE", address(0)) != address(0) ? "(will reuse)" : "(will deploy)");
        console2.log("");
        console2.log("fyUSDT Maturity:", maturity);
        console2.log("");

        // CRITICAL: Enforce Celo mainnet only
        require(block.chainid == CELO_CHAIN_ID, "Wrong chain: must be Celo mainnet (chainId 42220)");
        console2.log("Chain ID:       ", block.chainid, "(Celo Mainnet)");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ========== STEP 1: DEPLOY/REUSE CORE CONTRACTS ==========
        console2.log("Step 1: Deploying/Reusing Core Contracts");
        console2.log("------------------------------------------------------------");

        // Cauldron: deploy or reuse (non-payable)
        address cauldronOverride = vm.envOr("CAULDRON", address(0));
        if (cauldronOverride != address(0) && _hasCode(cauldronOverride)) {
            cauldron = Cauldron(cauldronOverride);
            console2.log("  Cauldron:     ", address(cauldron), "(REUSED)");
        } else {
            cauldron = new Cauldron();
            console2.log("  Cauldron:     ", address(cauldron), "(DEPLOYED)");
        }

        // Ladle: deploy or reuse (PAYABLE - has receive())
        address payable ladleOverride = payable(vm.envOr("LADLE", address(0)));
        if (address(ladleOverride) != address(0) && _hasCode(address(ladleOverride))) {
            ladle = Ladle(ladleOverride);
            console2.log("  Ladle:        ", address(ladle), "(REUSED)");
        } else {
            ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(wcelo));
            console2.log("  Ladle:        ", address(ladle), "(DEPLOYED)");
            console2.log("  Router:       ", address(ladle.router()));
        }

        // Witch: deploy or reuse (non-payable)
        address witchOverride = vm.envOr("WITCH", address(0));
        if (witchOverride != address(0) && _hasCode(witchOverride)) {
            witch = Witch(witchOverride);
            console2.log("  Witch:        ", address(witch), "(REUSED)");
        } else {
            witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));
            console2.log("  Witch:        ", address(witch), "(DEPLOYED)");
        }
        console2.log("");

        // ========== STEP 2: DEPLOY/REUSE ORACLE ==========
        console2.log("Step 2: Deploying/Reusing Mento Oracle");
        console2.log("------------------------------------------------------------");

        // MentoOracle: deploy or reuse (non-payable)
        address oracleOverride = vm.envOr("MENTO_ORACLE", address(0));
        bool oracleReused = false;
        if (oracleOverride != address(0) && _hasCode(oracleOverride)) {
            mentoOracle = MentoSpotOracle(oracleOverride);
            console2.log("  MentoOracle:  ", address(mentoOracle), "(REUSED)");
            oracleReused = true;
        } else {
            mentoOracle = new MentoSpotOracle(ISortedOracles(sortedOracles));
            console2.log("  MentoOracle:  ", address(mentoOracle), "(DEPLOYED)");
        }

        // Configure oracle (only if newly deployed)
        if (!oracleReused) {
            // Grant oracle configuration roles
            mentoOracle.grantRole(mentoOracle.setSource.selector, deployer);
            mentoOracle.grantRole(mentoOracle.setMaxAge.selector, deployer);
            mentoOracle.grantRole(mentoOracle.setBounds.selector, deployer);

            // Configure cKES/USD oracle source
            IERC20Metadata cKES = IERC20Metadata(ckesToken);
            IERC20Metadata cUSD = IERC20Metadata(cusdToken);

            mentoOracle.setSource(
                CKES_ID,
                cKES,
                USDT_ID,  // Use USDT as USD proxy
                cUSD,
                kesUsdRateFeed,
                false  // not inverse
            );
            console2.log("  Configured:   cKES/USD source");

            // Set safety parameters
            mentoOracle.setMaxAge(CKES_ID, USDT_ID, ORACLE_MAX_AGE);
            mentoOracle.setBounds(CKES_ID, USDT_ID, CKES_MIN_PRICE, CKES_MAX_PRICE);
            console2.log("  Safety:       maxAge=", ORACLE_MAX_AGE, "s, bounds set");

            // Verify configuration succeeded
            require(_oracleConfiguredForCKES(mentoOracle), "Oracle configuration failed verification");
        } else {
            console2.log("  Configuration: Skipped (oracle reused)");

            // CRITICAL: Validate reused oracle is configured
            require(
                _oracleConfiguredForCKES(mentoOracle),
                "Reused oracle missing cKES/USD source; unset MENTO_ORACLE to deploy fresh or configure manually"
            );
            console2.log("  Validation:   cKES/USD source verified");
        }
        console2.log("");

        // ========== STEP 3: DEPLOY/REUSE JOINS ==========
        console2.log("Step 3: Deploying/Reusing Join Adapters");
        console2.log("------------------------------------------------------------");

        // cKES Join: deploy or reuse (non-payable)
        address ckesJoinOverride = vm.envOr("JOIN_CKES", address(0));
        if (ckesJoinOverride != address(0) && _hasCode(ckesJoinOverride)) {
            ckesJoin = Join(ckesJoinOverride);
            console2.log("  cKES Join:    ", address(ckesJoin), "(REUSED)");
        } else {
            ckesJoin = new Join(ckesToken);
            console2.log("  cKES Join:    ", address(ckesJoin), "(DEPLOYED)");
        }

        // USDT Join: deploy or reuse (non-payable)
        address usdtJoinOverride = vm.envOr("JOIN_USDT", address(0));
        if (usdtJoinOverride != address(0) && _hasCode(usdtJoinOverride)) {
            usdtJoin = Join(usdtJoinOverride);
            console2.log("  USDT Join:    ", address(usdtJoin), "(REUSED)");
        } else {
            usdtJoin = new Join(usdtToken);
            console2.log("  USDT Join:    ", address(usdtJoin), "(DEPLOYED)");
        }
        console2.log("");

        // ========== STEP 4: DEPLOY/REUSE FYTOKEN ==========
        console2.log("Step 4: Deploying/Reusing fyUSDT");
        console2.log("------------------------------------------------------------");

        // Generate series ID (6 bytes: baseId + maturity)
        bytes6 seriesId = bytes6(bytes12(USDT_ID) | bytes12(uint96(maturity)));

        // fyUSDT: deploy or reuse (non-payable)
        address fyUSDTOverride = vm.envOr("FYUSDT", address(0));
        if (fyUSDTOverride != address(0) && _hasCode(fyUSDTOverride)) {
            fyUSDT = FYToken(fyUSDTOverride);
            console2.log("  fyUSDT:       ", address(fyUSDT), "(REUSED)");
        } else {
            fyUSDT = new FYToken(
                USDT_ID,
                IOracle(address(mentoOracle)),  // chi oracle (using spot for simplicity)
                IJoin(address(usdtJoin)),
                maturity,
                string(abi.encodePacked("fyUSDT ", _formatTimestamp(maturity))),
                string(abi.encodePacked("fyUSDT", _formatMaturity(maturity)))
            );
            console2.log("  fyUSDT:       ", address(fyUSDT), "(DEPLOYED)");
        }
        console2.log("  Series ID:    ", _bytes6ToString(seriesId));
        console2.log("  Maturity:     ", maturity);
        console2.log("  Name:         ", fyUSDT.name());
        console2.log("  Symbol:       ", fyUSDT.symbol());
        console2.log("");

        // ========== STEP 5: CONFIGURE CAULDRON ==========
        console2.log("Step 5: Configuring Cauldron");
        console2.log("------------------------------------------------------------");

        // Grant deployer temporary configuration permissions (safe to re-grant)
        _grantRoleIfNeeded(cauldron, Cauldron.addAsset.selector, deployer);
        _grantRoleIfNeeded(cauldron, Cauldron.setLendingOracle.selector, deployer);
        _grantRoleIfNeeded(cauldron, Cauldron.addSeries.selector, deployer);
        _grantRoleIfNeeded(cauldron, Cauldron.addIlks.selector, deployer);
        _grantRoleIfNeeded(cauldron, Cauldron.setSpotOracle.selector, deployer);
        _grantRoleIfNeeded(cauldron, Cauldron.setDebtLimits.selector, deployer);

        // Add assets (safe to call multiple times - will revert if already exists, but we'll handle)
        try cauldron.addAsset(CKES_ID, ckesToken) {
            console2.log("  Added asset:  cKES");
        } catch {
            console2.log("  Asset exists: cKES (skipped)");
        }

        try cauldron.addAsset(USDT_ID, usdtToken) {
            console2.log("  Added asset:  USDT");
        } catch {
            console2.log("  Asset exists: USDT (skipped)");
        }

        // Set rate oracle (safe to call multiple times)
        cauldron.setLendingOracle(USDT_ID, IOracle(address(mentoOracle)));
        console2.log("  Rate oracle:  set for USDT");

        // Add series (will revert if exists, handle gracefully)
        try cauldron.addSeries(seriesId, USDT_ID, IFYToken(address(fyUSDT))) {
            console2.log("  Added series: ", _bytes6ToString(seriesId));
        } catch {
            console2.log("  Series exists:", _bytes6ToString(seriesId), "(skipped)");
        }

        // Add ilks (collateral types) for the series
        try cauldron.addIlks(seriesId, new bytes6[](0)) {
            console2.log("  Series ilks:  initialized");
        } catch {
            console2.log("  Series ilks:  already initialized (skipped)");
        }

        // Set spot oracle (safe to call multiple times)
        cauldron.setSpotOracle(
            USDT_ID,                          // baseId (debt asset)
            CKES_ID,                          // ilkId (collateral asset)
            IOracle(address(mentoOracle)),    // oracle
            COLLATERALIZATION_RATIO           // 150%
        );
        console2.log("  Spot oracle:  USDT/cKES @ 150%");

        // Set debt limits (safe to call multiple times)
        cauldron.setDebtLimits(
            USDT_ID,  // baseId
            CKES_ID,  // ilkId
            MAX_DEBT, // max
            MIN_DEBT, // min
            DEC       // decimals
        );
        console2.log("  Debt limits:  max=", MAX_DEBT / 1e18, "USDT");
        console2.log("");

        // ========== STEP 6: CONFIGURE LADLE ==========
        console2.log("Step 6: Configuring Ladle");
        console2.log("------------------------------------------------------------");

        // Grant deployer temporary configuration permissions for Ladle
        _grantRoleIfNeeded(ladle, Ladle.addJoin.selector, deployer);

        // Add joins (safe to call multiple times - will revert if exists)
        try ladle.addJoin(CKES_ID, IJoin(address(ckesJoin))) {
            console2.log("  Added join:   cKES");
        } catch {
            console2.log("  Join exists:  cKES (skipped)");
        }

        try ladle.addJoin(USDT_ID, IJoin(address(usdtJoin))) {
            console2.log("  Added join:   USDT");
        } catch {
            console2.log("  Join exists:  USDT (skipped)");
        }
        console2.log("");

        // ========== STEP 7: CONFIGURE WITCH ==========
        console2.log("Step 7: Configuring Witch (Liquidation Engine)");
        console2.log("------------------------------------------------------------");

        // Grant deployer temporary configuration permissions for Witch
        _grantRoleIfNeeded(witch, witch.setLineAndLimit.selector, deployer);

        // Set auction parameters (safe to call multiple times)
        witch.setLineAndLimit(
            CKES_ID,           // ilkId
            USDT_ID,           // baseId
            uint32(AUCTION_DURATION),  // duration
            uint64(INITIAL_COLLATERAL),// vaultProportion
            uint64(INITIAL_COLLATERAL),// collateralProportion
            uint128(MAX_DEBT / 10)     // max (line: 10% of max debt)
        );
        console2.log("  Auction params:");
        console2.log("    Duration:   ", AUCTION_DURATION, "seconds");
        console2.log("    Initial:    ", INITIAL_COLLATERAL / 1e16, "%");
        console2.log("    Line:       ", MAX_DEBT / 10 / 1e18, "USDT");
        console2.log("");

        // ========== STEP 8: GRANT PERMISSIONS ==========
        console2.log("Step 8: Granting Permissions");
        console2.log("------------------------------------------------------------");

        // Grant Ladle permissions on Cauldron (safe to re-grant)
        _grantRoleIfNeeded(cauldron, Cauldron.build.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.destroy.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.tweak.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.give.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.pour.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.stir.selector, address(ladle));
        _grantRoleIfNeeded(cauldron, Cauldron.slurp.selector, address(ladle));
        console2.log("  Cauldron:     Ladle granted vault permissions");

        // Grant Witch permissions on Cauldron (safe to re-grant)
        _grantRoleIfNeeded(cauldron, Cauldron.give.selector, address(witch));
        _grantRoleIfNeeded(cauldron, Cauldron.slurp.selector, address(witch));
        console2.log("  Cauldron:     Witch granted liquidation permissions");

        // Grant Ladle permissions on Joins (safe to re-grant)
        _grantRoleIfNeeded(ckesJoin, Join.join.selector, address(ladle));
        _grantRoleIfNeeded(ckesJoin, Join.exit.selector, address(ladle));
        console2.log("  cKES Join:    Ladle granted join/exit");

        _grantRoleIfNeeded(usdtJoin, Join.join.selector, address(ladle));
        _grantRoleIfNeeded(usdtJoin, Join.exit.selector, address(ladle));
        console2.log("  USDT Join:    Ladle granted join/exit");

        // Grant Witch permissions on Joins (for liquidations)
        _grantRoleIfNeeded(ckesJoin, Join.exit.selector, address(witch));
        _grantRoleIfNeeded(usdtJoin, Join.exit.selector, address(witch));
        console2.log("  Joins:        Witch granted exit");

        // Grant Ladle permissions on fyToken
        _grantRoleIfNeeded(fyUSDT, fyUSDT.mint.selector, address(ladle));
        _grantRoleIfNeeded(fyUSDT, fyUSDT.burn.selector, address(ladle));
        console2.log("  fyUSDT:       Ladle granted mint/burn");
        console2.log("");

        // ========== STEP 9: TRANSFER GOVERNANCE ==========
        console2.log("Step 9: Transferring Governance");
        console2.log("------------------------------------------------------------");

        if (deployer != governance) {
            // Transfer ROOT roles (safe to re-grant)
            _grantRoleIfNeeded(cauldron, cauldron.ROOT(), governance);
            _grantRoleIfNeeded(ladle, ladle.ROOT(), governance);
            _grantRoleIfNeeded(witch, witch.ROOT(), governance);
            _grantRoleIfNeeded(mentoOracle, mentoOracle.ROOT(), governance);
            _grantRoleIfNeeded(ckesJoin, ckesJoin.ROOT(), governance);
            _grantRoleIfNeeded(usdtJoin, usdtJoin.ROOT(), governance);
            _grantRoleIfNeeded(fyUSDT, fyUSDT.ROOT(), governance);

            console2.log("  Granted ROOT: All contracts -> governance");

            if (revokeDeployer) {
                // Only revoke if deployer still has ROOT
                if (cauldron.hasRole(cauldron.ROOT(), deployer)) {
                    cauldron.revokeRole(cauldron.ROOT(), deployer);
                    ladle.revokeRole(ladle.ROOT(), deployer);
                    witch.revokeRole(witch.ROOT(), deployer);
                    mentoOracle.revokeRole(mentoOracle.ROOT(), deployer);
                    ckesJoin.revokeRole(ckesJoin.ROOT(), deployer);
                    usdtJoin.revokeRole(usdtJoin.ROOT(), deployer);
                    fyUSDT.revokeRole(fyUSDT.ROOT(), deployer);
                    console2.log("  Revoked ROOT: All contracts <- deployer");
                } else {
                    console2.log("  Revoke ROOT:  Already revoked (skipped)");
                }
            } else {
                console2.log("  Kept ROOT:    Deployer retains ROOT (REVOKE_DEPLOYER=false)");
            }
        } else {
            console2.log("  Skipped:      Deployer is governance");
        }
        console2.log("");

        vm.stopBroadcast();
        bool didBroadcast = vm.getNonce(deployer) > nonceBefore;

        // ========== STEP 10: POST-DEPLOYMENT ASSERTIONS ==========
        console2.log("Step 10: Post-Deployment Validation");
        console2.log("------------------------------------------------------------");

        _validateDeployment(deployer, didBroadcast);

        // ========== DEPLOYMENT SUMMARY ==========
        console2.log("");
        console2.log("============================================================");
        console2.log("DEPLOYMENT COMPLETE");
        console2.log("============================================================");
        console2.log("");
        console2.log("Core Contracts:");
        console2.log("  Cauldron:        ", address(cauldron));
        console2.log("  Ladle:           ", address(ladle));
        console2.log("  Witch:           ", address(witch));
        console2.log("  MentoOracle:     ", address(mentoOracle));
        console2.log("");
        console2.log("Joins:");
        console2.log("  cKES Join:       ", address(ckesJoin));
        console2.log("  USDT Join:       ", address(usdtJoin));
        console2.log("");
        console2.log("Series:");
        console2.log("  fyUSDT:          ", address(fyUSDT));
        console2.log("  Maturity:        ", maturity);
        console2.log("  Series ID:       ", _bytes6ToString(seriesId));
        console2.log("");
        console2.log("Configuration:");
        console2.log("  Governance:      ", governance);
        console2.log("  Collateral:      cKES");
        console2.log("  Base Asset:      USDT");
        console2.log("  Coll. Ratio:     ", COLLATERALIZATION_RATIO / 10000, "%");
        console2.log("  Max Debt:        ", MAX_DEBT / 1e18, "USDT");
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Verify contracts on Celoscan");
        console2.log("2. Test vault creation with small amounts");
        console2.log("3. Monitor oracle price feeds");
        console2.log("4. Set up liquidation monitoring");
        console2.log("5. Add additional series as needed");
        console2.log("============================================================");
    }

    // ========== INTERNAL HELPERS ==========

    /// @dev Check if address has deployed bytecode
    function _hasCode(address addr) internal view returns (bool) {
        return addr.code.length > 0;
    }

    /// @dev Check if oracle is configured with the expected cKES/USD source
    function _oracleConfiguredForCKES(MentoSpotOracle oracle) internal view returns (bool) {
        try oracle.sources(CKES_ID, USDT_ID) returns (
            address rateFeedID, uint8, uint8, bool, uint256, uint256, uint256
        ) {
            return rateFeedID != address(0);
        } catch {
            return false;
        }
    }

    /// @dev Grant role only if not already granted (idempotent)
    function _grantRoleIfNeeded(AccessControl target, bytes4 role, address account) internal {
        if (!target.hasRole(role, account)) {
            target.grantRole(role, account);
        }
    }

    function _loadEnvironment() internal {
        // Required
        governance = vm.envAddress("GOVERNANCE");
        ckesToken = vm.envAddress("CKES");
        usdtToken = vm.envAddress("USDT");

        // Optional with defaults
        wcelo = vm.envOr("WCELO", DEFAULT_WCELO);
        sortedOracles = vm.envOr("SORTED_ORACLES", DEFAULT_SORTED_ORACLES);
        kesUsdRateFeed = vm.envOr("KES_USD_RATE_FEED", DEFAULT_KES_USD_RATE_FEED);
        cusdToken = vm.envOr("CUSD", DEFAULT_CUSD);

        // Maturity: default to 1 year from now
        maturity = vm.envOr("MATURITY", block.timestamp + 365 days);

        // Revoke deployer: default to true
        string memory revokeStr = vm.envOr("REVOKE_DEPLOYER", string("true"));
        revokeDeployer = keccak256(bytes(revokeStr)) == keccak256(bytes("true"));
    }

    function _validateEnvironment() internal view {
        require(governance != address(0), "GOVERNANCE not set");
        require(ckesToken != address(0), "CKES not set");
        require(usdtToken != address(0), "USDT not set");
        require(wcelo != address(0), "WCELO not set");
        require(sortedOracles != address(0), "SORTED_ORACLES not set");
        require(kesUsdRateFeed != address(0), "KES_USD_RATE_FEED not set");
        require(maturity > block.timestamp, "MATURITY must be in the future");

        // Verify token contracts exist
        require(_hasCode(ckesToken), "CKES is not a contract");
        require(_hasCode(usdtToken), "USDT is not a contract");
        require(_hasCode(wcelo), "WCELO is not a contract");
        require(_hasCode(sortedOracles), "SORTED_ORACLES is not a contract");
    }

    function _validateDeployment(address deployer, bool isBroadcast) internal view {
        // Verify governance has ROOT
        address expectedRoot = revokeDeployer && deployer != governance ? governance : deployer;
        if (deployer != governance && revokeDeployer) {
            expectedRoot = governance;
        }

        require(cauldron.hasRole(cauldron.ROOT(), governance), "Cauldron: governance missing ROOT");
        require(ladle.hasRole(ladle.ROOT(), governance), "Ladle: governance missing ROOT");
        require(witch.hasRole(witch.ROOT(), governance), "Witch: governance missing ROOT");
        require(mentoOracle.hasRole(mentoOracle.ROOT(), governance), "Oracle: governance missing ROOT");
        console2.log("  ROOT roles:   All transferred to governance");

        // Verify Cauldron configuration
        require(address(ladle.cauldron()) == address(cauldron), "Ladle: wrong cauldron");
        console2.log("  Ladle:        Cauldron reference correct");

        // Verify oracle functionality (only when broadcasting)
        if (isBroadcast) {
            uint256 amountIn = 1e18; // 1 USDT (normalized to 18 decimals)
            try mentoOracle.peek(USDT_ID, CKES_ID, amountIn) returns (uint256 amountOut, uint256 updateTime) {
                require(amountOut > 0, "Oracle: zero output amount");
                uint256 impliedPrice = (amountIn * 1e18) / amountOut; // USD per CKES in 1e18
                require(impliedPrice >= CKES_MIN_PRICE && impliedPrice <= CKES_MAX_PRICE, "Oracle: price out of bounds");
                require(updateTime > 0, "Oracle: invalid update time");
                console2.log("  Oracle:       Price valid (", impliedPrice, "USD/cKES)");
            } catch Error(string memory reason) {
                revert(reason);
            } catch (bytes memory) {
                revert("Oracle: peek failed during broadcast validation");
            }
        } else {
            console2.log("  Oracle:       Skipping oracle validation (not broadcasting)");
        }

        // Verify Joins
        require(address(ckesJoin.asset()) == ckesToken, "cKES Join: wrong asset");
        require(address(usdtJoin.asset()) == usdtToken, "USDT Join: wrong asset");
        console2.log("  Joins:        Assets configured correctly");

        // Verify fyToken
        require(fyUSDT.maturity() == maturity, "fyUSDT: wrong maturity");
        console2.log("  fyUSDT:       Maturity correct");

        console2.log("");
        console2.log("  All assertions passed!");
    }

    function _formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        // Simple formatting: just show as Unix timestamp
        // In production, you'd want proper date formatting
        return vm.toString(timestamp);
    }

    function _formatMaturity(uint256 timestamp) internal pure returns (string memory) {
        // Format as suffix for symbol
        return string(abi.encodePacked(vm.toString(timestamp / 1000000)));
    }

    function _bytes6ToString(bytes6 b) internal pure returns (string memory) {
        bytes memory result = new bytes(12);
        for (uint256 i = 0; i < 6; i++) {
            result[i * 2] = _toHexChar(uint8(b[i]) / 16);
            result[i * 2 + 1] = _toHexChar(uint8(b[i]) % 16);
        }
        return string(abi.encodePacked("0x", result));
    }

    function _toHexChar(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(48 + value)); // '0'-'9'
        }
        return bytes1(uint8(87 + value)); // 'a'-'f'
    }
}
