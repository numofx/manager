// forge script script/FinalizeCkesJoin.s.sol \
//   --rpc-url $CELO_RPC_URL \
//   --broadcast -vvvv

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Join.sol";

contract FinalizeCkesJoin is Script {
    address constant CKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant CKES_JOIN = 0x952e385c18cfc6A426488b48ab48345275B3Cf3D;
    bytes4 constant ROOT = 0x00000000;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ladle = vm.envAddress("LADLE");
        address governance = vm.envAddress("GOVERNANCE");

        Join join = Join(CKES_JOIN);

        console2.log("=== Finalize cKES Join ===");
        console2.log("Join:", CKES_JOIN);
        console2.log("Asset (expected cKES):", CKES);
        console2.log("Ladle:", ladle);
        console2.log("Governance:", governance);
        console2.log("Deployer:", deployer);

        require(join.asset() == CKES, "Join asset mismatch");

        bytes4 joinRole = join.join.selector;
        bytes4 exitRole = join.exit.selector;
        bytes4 retrieveRole = join.retrieve.selector;

        vm.startBroadcast(deployerKey);

        if (!join.hasRole(joinRole, ladle)) {
            join.grantRole(joinRole, ladle);
        }
        if (!join.hasRole(exitRole, ladle)) {
            join.grantRole(exitRole, ladle);
        }

        if (!join.hasRole(retrieveRole, governance)) {
            join.grantRole(retrieveRole, governance);
        }

        // Give governance admin control before revoking deployer.
        if (!join.hasRole(ROOT, governance)) {
            join.grantRole(ROOT, governance);
        }

        // Clean up deployer permissions.
        if (join.hasRole(joinRole, deployer)) {
            join.revokeRole(joinRole, deployer);
        }
        if (join.hasRole(exitRole, deployer)) {
            join.revokeRole(exitRole, deployer);
        }
        if (join.hasRole(retrieveRole, deployer)) {
            join.revokeRole(retrieveRole, deployer);
        }
        if (deployer != governance && join.hasRole(ROOT, deployer)) {
            join.revokeRole(ROOT, deployer);
        }

        vm.stopBroadcast();

        console2.log("\n=== Finalization Summary ===");
        console2.log("Join address:", CKES_JOIN);
        console2.log("Join.asset() == cKES:", join.asset() == CKES);
        console2.log("Ladle authorized for join():", join.hasRole(joinRole, ladle));
        console2.log("Ladle authorized for exit():", join.hasRole(exitRole, ladle));
        console2.log("Governance authorized for retrieve():", join.hasRole(retrieveRole, governance));
        console2.log("Governance has ROOT:", join.hasRole(ROOT, governance));
        console2.log("Deployer has ROOT:", join.hasRole(ROOT, deployer));
    }
}
