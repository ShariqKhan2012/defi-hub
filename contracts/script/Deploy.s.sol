// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {StakingPool} from "../src/StakingPool.sol";

contract Deployer is Script {
    // Tune these as needed
    uint256 constant INITIAL_REWARD_RATE = 5e10; // 5e-8 per second, 18-decimal precision

    function run() external {
        address deployer = msg.sender;
        vm.startBroadcast();

        // 1. Deploy GovernanceToken — plain, non-upgradeable
        GovernanceToken token = new GovernanceToken();
        console.log("GovernanceToken deployed at:", address(token));

        // 2. Deploy StakingPool as a UUPS proxy
        // Upgrades.deployUUPSProxy:
        //   - compiles & validates StakingPool for upgrade safety
        //   - deploys the implementation
        //   - deploys an ERC1967 proxy pointing to it
        //   - calls initialize() on the proxy
        address proxy = Upgrades.deployUUPSProxy(
            "StakingPool.sol", abi.encodeCall(StakingPool.initialize, (deployer, address(token), INITIAL_REWARD_RATE))
        );
        console.log("StakingPool proxy deployed at:", proxy);

        vm.stopBroadcast();
    }
}
