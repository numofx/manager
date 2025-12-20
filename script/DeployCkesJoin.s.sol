// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Join.sol";
import "@yield-protocol/utils-v2/src/token/IERC20.sol";

/**
 * @title DeployCkesJoin
 * @notice Foundry script to deploy a Join contract for cKES on Celo Mainnet
 * @dev Usage:
 *   forge script script/DeployCkesJoin.s.sol \
 *     --rpc-url $CELO_RPC_URL \
 *     --broadcast -vvvv
 */
contract DeployCkesJoin is Script {
    // cKES token address on Celo Mainnet
    address constant CKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;

    Join public ckesJoin;

    function run() external {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== cKES Join Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);
        console2.log("cKES token:", CKES);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Join contract for cKES
        console2.log("\n=== Deploying Join for cKES ===");
        ckesJoin = new Join(CKES);
        console2.log("Join deployed at:", address(ckesJoin));

        // Sanity check: verify the Join's asset equals cKES address
        require(ckesJoin.asset() == CKES, "Join asset mismatch");
        console2.log("Sanity check passed: Join.asset() == cKES");

        // Verify initial stored balance is zero
        require(ckesJoin.storedBalance() == 0, "Initial stored balance should be zero");
        console2.log("Initial stored balance: 0");

        vm.stopBroadcast();

        // Print deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("cKES Join:", address(ckesJoin));
        console2.log("Asset:", ckesJoin.asset());
        console2.log("Stored Balance:", ckesJoin.storedBalance());
        console2.log("\nNext steps:");
        console2.log("1. Verify contract on block explorer");
        console2.log("2. Grant join/exit permissions to Ladle");
        console2.log("3. Grant retrieve permissions to governance");
    }
}
