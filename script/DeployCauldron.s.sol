// SPDX-License-Identifier: BUSL-1.1
// forge script script/DeployCauldron.s.sol \
//   --rpc-url $CELO_RPC_URL \
//   --broadcast -vvvv
pragma solidity ^0.8.13;

import "forge-std/src/Script.sol";
import "forge-std/src/console2.sol";
import "../src/Cauldron.sol";

/**
 * Env vars:
 * - PRIVATE_KEY: Deployer EOA private key
 * - GOVERNANCE: Governance EOA or multisig address
 */
contract DeployCauldron is Script {
    Cauldron public cauldron;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address governance = vm.envAddress("GOVERNANCE");

        vm.startBroadcast(deployerPrivateKey);
        cauldron = new Cauldron();
        cauldron.grantRole(cauldron.ROOT(), governance);
        if (deployer != governance && cauldron.hasRole(cauldron.ROOT(), deployer)) {
            cauldron.revokeRole(cauldron.ROOT(), deployer);
        }
        vm.stopBroadcast();

        require(cauldron.hasRole(cauldron.ROOT(), governance), "governance not authed");

        console2.log("Cauldron:", address(cauldron));
        console2.log("Governance:", governance);
    }
}
