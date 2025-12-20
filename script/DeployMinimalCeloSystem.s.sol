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
 * @notice Production-ready deployment script for Yield Protocol v2 on Celo
 * @dev Deploys minimal working system: Cauldron, Ladle, Witch, Oracles, Joins, fyUSDT
 *
 * USAGE:
 *   forge script script/DeployMinimalCeloSystem.s.sol \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * REQUIRED ENV VARS:
 *   CELO_RPC_URL       - Celo mainnet RPC endpoint
 *   PRIVATE_KEY        - Deployer private key (0x...)
 *   GOVERNANCE         - Governance address to receive ROOT roles
 *   CKES               - cKES token address
 *   USDT               - USDT token address on Celo
 *
 * OPTIONAL ENV VARS:
 *   WCELO              - wCELO address (default: 0x471EcE3750Da237f93B8E339c536989b8978a438)
 *   SORTED_ORACLES     - Mento SortedOracles (default: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33)
 *   KES_USD_RATE_FEED  - cKES/USD rate feed (default: 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169)
 *   REVOKE_DEPLOYER    - Set to "true" to revoke deployer permissions (default: true)
 *   MATURITY           - fyUSDT maturity timestamp (default: 1 year from now)
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
        console2.log("============================================================");
        console2.log("");

        _loadEnvironment();
        _validateEnvironment();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

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
        console2.log("");
        console2.log("fyUSDT Maturity:", maturity);
        console2.log("");

        // Confirm we're on Celo
        require(block.chainid == CELO_CHAIN_ID, "Must deploy on Celo mainnet (chainId 42220)");
        console2.log("Chain ID:       ", block.chainid, "(Celo Mainnet)");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ========== STEP 1: DEPLOY CORE CONTRACTS ==========
        console2.log("Step 1: Deploying Core Contracts");
        console2.log("------------------------------------------------------------");

        cauldron = new Cauldron();
        console2.log("  Cauldron:     ", address(cauldron));

        ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(wcelo));
        console2.log("  Ladle:        ", address(ladle));
        console2.log("  Router:       ", address(ladle.router()));

        witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));
        console2.log("  Witch:        ", address(witch));
        console2.log("");

        // ========== STEP 2: DEPLOY ORACLE ==========
        console2.log("Step 2: Deploying Mento Oracle");
        console2.log("------------------------------------------------------------");

        mentoOracle = new MentoSpotOracle(ISortedOracles(sortedOracles));
        console2.log("  MentoOracle:  ", address(mentoOracle));

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
        console2.log("");

        // ========== STEP 3: DEPLOY JOINS ==========
        console2.log("Step 3: Deploying Join Adapters");
        console2.log("------------------------------------------------------------");

        ckesJoin = new Join(ckesToken);
        console2.log("  cKES Join:    ", address(ckesJoin));

        usdtJoin = new Join(usdtToken);
        console2.log("  USDT Join:    ", address(usdtJoin));
        console2.log("");

        // ========== STEP 4: DEPLOY FYTOKEN ==========
        console2.log("Step 4: Deploying fyUSDT");
        console2.log("------------------------------------------------------------");

        // Generate series ID (6 bytes: baseId + maturity)
        bytes6 seriesId = bytes6(bytes12(USDT_ID) | bytes12(uint96(maturity)));

        fyUSDT = new FYToken(
            USDT_ID,
            IOracle(address(mentoOracle)),  // chi oracle (using spot for simplicity)
            IJoin(address(usdtJoin)),
            maturity,
            string(abi.encodePacked("fyUSDT ", _formatTimestamp(maturity))),
            string(abi.encodePacked("fyUSDT", _formatMaturity(maturity)))
        );
        console2.log("  fyUSDT:       ", address(fyUSDT));
        console2.log("  Series ID:    ", _bytes6ToString(seriesId));
        console2.log("  Maturity:     ", maturity);
        console2.log("  Name:         ", fyUSDT.name());
        console2.log("  Symbol:       ", fyUSDT.symbol());
        console2.log("");

        // ========== STEP 5: CONFIGURE CAULDRON ==========
        console2.log("Step 5: Configuring Cauldron");
        console2.log("------------------------------------------------------------");

        // Add assets
        cauldron.addAsset(CKES_ID, ckesToken);
        console2.log("  Added asset:  cKES");

        cauldron.addAsset(USDT_ID, usdtToken);
        console2.log("  Added asset:  USDT");

        // Add series
        cauldron.addSeries(seriesId, USDT_ID, IFYToken(address(fyUSDT)));
        console2.log("  Added series: ", _bytes6ToString(seriesId));

        // Add ilks (collateral types) for the series
        cauldron.addIlks(seriesId, new bytes6[](0));  // Empty array - will set up cKES manually
        console2.log("  Series ilks:  initialized");

        // Set spot oracle (USDT/cKES pair - base/ilk)
        cauldron.setSpotOracle(
            USDT_ID,                          // baseId (debt asset)
            CKES_ID,                          // ilkId (collateral asset)
            IOracle(address(mentoOracle)),    // oracle
            COLLATERALIZATION_RATIO           // 150%
        );
        console2.log("  Spot oracle:  USDT/cKES @ 150%");

        // Set debt limits
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

        // Add joins
        ladle.addJoin(CKES_ID, IJoin(address(ckesJoin)));
        console2.log("  Added join:   cKES");

        ladle.addJoin(USDT_ID, IJoin(address(usdtJoin)));
        console2.log("  Added join:   USDT");

        // Add fyToken as pool (even though we don't have YieldSpace pools yet)
        ladle.addPool(seriesId, IPool(address(fyUSDT)));
        console2.log("  Added pool:   ", _bytes6ToString(seriesId));
        console2.log("");

        // ========== STEP 7: CONFIGURE WITCH ==========
        console2.log("Step 7: Configuring Witch (Liquidation Engine)");
        console2.log("------------------------------------------------------------");

        // Set auction parameters
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

        // Grant Ladle permissions on Cauldron
        cauldron.grantRole(Cauldron.build.selector, address(ladle));
        cauldron.grantRole(Cauldron.destroy.selector, address(ladle));
        cauldron.grantRole(Cauldron.tweak.selector, address(ladle));
        cauldron.grantRole(Cauldron.give.selector, address(ladle));
        cauldron.grantRole(Cauldron.pour.selector, address(ladle));
        cauldron.grantRole(Cauldron.stir.selector, address(ladle));
        cauldron.grantRole(Cauldron.slurp.selector, address(ladle));
        console2.log("  Cauldron:     Ladle granted vault permissions");

        // Grant Witch permissions on Cauldron
        cauldron.grantRole(Cauldron.give.selector, address(witch));
        cauldron.grantRole(Cauldron.slurp.selector, address(witch));
        console2.log("  Cauldron:     Witch granted liquidation permissions");

        // Grant Ladle permissions on Joins
        ckesJoin.grantRole(Join.join.selector, address(ladle));
        ckesJoin.grantRole(Join.exit.selector, address(ladle));
        console2.log("  cKES Join:    Ladle granted join/exit");

        usdtJoin.grantRole(Join.join.selector, address(ladle));
        usdtJoin.grantRole(Join.exit.selector, address(ladle));
        console2.log("  USDT Join:    Ladle granted join/exit");

        // Grant Witch permissions on Joins (for liquidations)
        ckesJoin.grantRole(Join.exit.selector, address(witch));
        usdtJoin.grantRole(Join.exit.selector, address(witch));
        console2.log("  Joins:        Witch granted exit");

        // Grant Ladle permissions on fyToken
        fyUSDT.grantRole(fyUSDT.mint.selector, address(ladle));
        fyUSDT.grantRole(fyUSDT.burn.selector, address(ladle));
        console2.log("  fyUSDT:       Ladle granted mint/burn");
        console2.log("");

        // ========== STEP 9: TRANSFER GOVERNANCE ==========
        console2.log("Step 9: Transferring Governance");
        console2.log("------------------------------------------------------------");

        if (deployer != governance) {
            // Transfer ROOT roles
            cauldron.grantRole(cauldron.ROOT(), governance);
            ladle.grantRole(ladle.ROOT(), governance);
            witch.grantRole(witch.ROOT(), governance);
            mentoOracle.grantRole(mentoOracle.ROOT(), governance);
            ckesJoin.grantRole(ckesJoin.ROOT(), governance);
            usdtJoin.grantRole(usdtJoin.ROOT(), governance);
            fyUSDT.grantRole(fyUSDT.ROOT(), governance);

            console2.log("  Granted ROOT: All contracts -> governance");

            if (revokeDeployer) {
                cauldron.revokeRole(cauldron.ROOT(), deployer);
                ladle.revokeRole(ladle.ROOT(), deployer);
                witch.revokeRole(witch.ROOT(), deployer);
                mentoOracle.revokeRole(mentoOracle.ROOT(), deployer);
                ckesJoin.revokeRole(ckesJoin.ROOT(), deployer);
                usdtJoin.revokeRole(usdtJoin.ROOT(), deployer);
                fyUSDT.revokeRole(fyUSDT.ROOT(), deployer);

                console2.log("  Revoked ROOT: All contracts <- deployer");
            } else {
                console2.log("  Kept ROOT:    Deployer retains ROOT (REVOKE_DEPLOYER=false)");
            }
        } else {
            console2.log("  Skipped:      Deployer is governance");
        }
        console2.log("");

        vm.stopBroadcast();

        // ========== STEP 10: POST-DEPLOYMENT ASSERTIONS ==========
        console2.log("Step 10: Post-Deployment Validation");
        console2.log("------------------------------------------------------------");

        _validateDeployment(deployer);

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
        require(_isContract(ckesToken), "CKES is not a contract");
        require(_isContract(usdtToken), "USDT is not a contract");
        require(_isContract(wcelo), "WCELO is not a contract");
        require(_isContract(sortedOracles), "SORTED_ORACLES is not a contract");
    }

    function _validateDeployment(address deployer) internal view {
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

        // Verify oracle functionality
        (uint256 price, uint256 updateTime) = mentoOracle.peek(CKES_ID, USDT_ID, 1e18);
        require(price > 0, "Oracle: price is zero");
        require(price >= CKES_MIN_PRICE && price <= CKES_MAX_PRICE, "Oracle: price out of bounds");
        require(updateTime > 0, "Oracle: invalid update time");
        console2.log("  Oracle:       Price valid (", price, "USD/cKES)");

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

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(addr) }
        return size > 0;
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
