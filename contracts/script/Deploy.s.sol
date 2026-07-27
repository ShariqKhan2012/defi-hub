// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {StakingPool} from "../src/StakingPool.sol";

contract Deployer is Script {
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 constant INITIAL_REWARD_RATE = 5e10; // 5e-8 per second, 18-decimal precision

    function run() external {
        vm.startBroadcast();

        // 1. Deploy GovernanceToken and mint initial supply to deployer
        GovernanceToken token = new GovernanceToken();
        token.mint(msg.sender, INITIAL_SUPPLY);
        console.log("GovernanceToken deployed at:", address(token));

        // 2. Deploy StakingPool as a UUPS proxy
        // Upgrades.deployUUPSProxy:
        //   - compiles & validates StakingPool for upgrade safety
        //   - deploys the implementation
        //   - deploys an ERC1967 proxy pointing to it
        //   - calls initialize() on the proxy
        // Owner is set to msg.sender inside initialize (the broadcast EOA at runtime).
        address proxy = Upgrades.deployUUPSProxy(
            "StakingPool.sol", abi.encodeCall(StakingPool.initialize, (address(token), INITIAL_REWARD_RATE))
        );
        console.log("StakingPool proxy deployed at:", proxy);

        vm.stopBroadcast();
    }
}
