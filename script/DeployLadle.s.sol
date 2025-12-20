// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Ladle.sol";
import "../src/Cauldron.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";

/**
 * @title DeployLadle
 * @notice Foundry script to deploy Ladle on Celo Mainnet
 * @dev Usage:
 *   forge script script/DeployLadle.s.sol \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast -vvvv
 *
 * Required env vars:
 * - PRIVATE_KEY: Deployer private key
 * - CAULDRON: Deployed Cauldron address
 * - WETH: Wrapped CELO address (0x471EcE3750Da237f93B8E339c536989b8978a438)
 */
contract DeployLadle is Script {
    // Wrapped CELO (wCELO) on Celo Mainnet
    // This is the canonical wrapped CELO contract
    address constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;

    Ladle public ladle;

    function run() external {
        // Load from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load Cauldron address from environment (or use default if provided)
        address cauldronAddr = vm.envOr("CAULDRON", address(0));
        require(cauldronAddr != address(0), "CAULDRON address not set");

        // Allow overriding WETH if needed, default to wCELO
        address wethAddr = vm.envOr("WETH", WCELO);

        console2.log("=== Ladle Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);
        console2.log("Cauldron:", cauldronAddr);
        console2.log("WETH (wCELO):", wethAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Ladle
        console2.log("\n=== Deploying Ladle ===");
        ladle = new Ladle(ICauldron(cauldronAddr), IWETH9(wethAddr));
        console2.log("Ladle deployed at:", address(ladle));

        // Verify deployer has ROOT role
        bytes4 ROOT = 0x00000000;
        require(ladle.hasRole(ROOT, deployer), "Deployer should have ROOT role");
        console2.log("Deployer has ROOT role: OK");

        // Verify Ladle references
        require(address(ladle.cauldron()) == cauldronAddr, "Cauldron mismatch");
        require(address(ladle.weth()) == wethAddr, "WETH mismatch");
        console2.log("Ladle configuration verified: OK");

        vm.stopBroadcast();

        // Print deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Ladle:", address(ladle));
        console2.log("Cauldron:", address(ladle.cauldron()));
        console2.log("Router:", address(ladle.router()));
        console2.log("WETH:", address(ladle.weth()));
        console2.log("\nNext steps:");
        console2.log("1. Verify contract on block explorer");
        console2.log("2. Grant Ladle permissions on Cauldron (pour, stir, etc.)");
        console2.log("3. Grant Ladle permissions on Join contracts");
        console2.log("4. Add joins to Ladle via addJoin()");
        console2.log("5. Add pools to Ladle via addPool()");
        console2.log("6. Configure integrations and modules");
    }
}
