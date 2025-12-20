// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Join.sol";

/**
 * @title GrantCkesJoinPermissions
 * @notice Foundry script to grant join/exit/retrieve permissions on the cKES Join contract
 * @dev Usage:
 *   forge script script/GrantCkesJoinPermissions.s.sol \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast -vvvv
 *
 * IMPORTANT: Update the LADLE and GOVERNANCE addresses before running!
 */
contract GrantCkesJoinPermissions is Script {
    // Deployed Join contract address
    address constant CKES_JOIN = 0x952e385c18cfc6A426488b48ab48345275B3Cf3D;

    function run() external {
        // Load from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load addresses from environment (use envOr to make them optional)
        address LADLE = vm.envOr("LADLE", address(0));
        address GOVERNANCE = vm.envOr("GOVERNANCE", address(0));

        console2.log("=== Grant cKES Join Permissions ===");
        console2.log("Deployer:", deployer);
        console2.log("cKES Join:", CKES_JOIN);
        console2.log("Ladle:", LADLE);
        console2.log("Governance:", GOVERNANCE);

        // Get the Join contract
        Join join = Join(CKES_JOIN);

        // Verify deployer has ROOT role
        bytes4 ROOT = 0x00000000;
        require(join.hasRole(ROOT, deployer), "Deployer must have ROOT role");
        console2.log("\nDeployer has ROOT role: OK");

        vm.startBroadcast(deployerPrivateKey);

        // Get function selectors
        bytes4 joinSelector = join.join.selector;
        bytes4 exitSelector = join.exit.selector;
        bytes4 retrieveSelector = join.retrieve.selector;

        console2.log("\nFunction Selectors:");
        console2.log("join():", vm.toString(joinSelector));
        console2.log("exit():", vm.toString(exitSelector));
        console2.log("retrieve():", vm.toString(retrieveSelector));

        // Grant join and exit permissions to Ladle
        if (LADLE != address(0)) {
            console2.log("\n=== Granting Permissions to Ladle ===");

            console2.log("Granting join() permission to Ladle...");
            join.grantRole(joinSelector, LADLE);
            require(join.hasRole(joinSelector, LADLE), "Failed to grant join role");
            console2.log("join() permission granted: OK");

            console2.log("Granting exit() permission to Ladle...");
            join.grantRole(exitSelector, LADLE);
            require(join.hasRole(exitSelector, LADLE), "Failed to grant exit role");
            console2.log("exit() permission granted: OK");
        } else {
            console2.log("\n=== Skipping Ladle Permissions ===");
            console2.log("LADLE address not set");
        }

        // Grant retrieve permission to Governance
        if (GOVERNANCE != address(0)) {
            console2.log("\n=== Granting Permissions to Governance ===");

            console2.log("Granting retrieve() permission to Governance...");
            join.grantRole(retrieveSelector, GOVERNANCE);
            require(join.hasRole(retrieveSelector, GOVERNANCE), "Failed to grant retrieve role");
            console2.log("retrieve() permission granted: OK");
        } else {
            console2.log("\n=== Skipping Governance Permissions ===");
            console2.log("GOVERNANCE address not set");
        }

        vm.stopBroadcast();

        // Print summary
        console2.log("\n=== Permission Grant Summary ===");
        if (LADLE != address(0)) {
            console2.log("Ladle has join():", join.hasRole(joinSelector, LADLE));
            console2.log("Ladle has exit():", join.hasRole(exitSelector, LADLE));
        }
        if (GOVERNANCE != address(0)) {
            console2.log("Governance has retrieve():", join.hasRole(retrieveSelector, GOVERNANCE));
        }
        console2.log("\nPermissions successfully configured!");
    }

    /**
     * @notice Helper function to verify current permissions
     * @dev Can be called to check permission state without broadcasting
     */
    function verify() external {
        Join join = Join(CKES_JOIN);

        // Load addresses from environment
        address LADLE = vm.envOr("LADLE", address(0));
        address GOVERNANCE = vm.envOr("GOVERNANCE", address(0));

        bytes4 joinSelector = join.join.selector;
        bytes4 exitSelector = join.exit.selector;
        bytes4 retrieveSelector = join.retrieve.selector;

        console2.log("=== Current Permissions ===");
        console2.log("cKES Join:", CKES_JOIN);
        console2.log("");

        if (LADLE != address(0)) {
            console2.log("Ladle Permissions:");
            console2.log("  join():", join.hasRole(joinSelector, LADLE));
            console2.log("  exit():", join.hasRole(exitSelector, LADLE));
            console2.log("");
        }

        if (GOVERNANCE != address(0)) {
            console2.log("Governance Permissions:");
            console2.log("  retrieve():", join.hasRole(retrieveSelector, GOVERNANCE));
        }
    }
}
