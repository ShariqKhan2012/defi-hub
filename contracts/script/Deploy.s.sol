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

        /*
         * Either extract the deployer, and use that or explicitly specify
         * the deployer in `vm.startBroadcast()` by using:
         * `vm.startBroadcast(<DEPLOYER_ACCOUNT>)`
         * Or use --sender flag while running the deployer script
         *
         * This is because unless explicitly specified, vm.startBroadcast() uses
         * the DEFAULT_SENDER account hard-coded in foundry, which has a strange
         * effect that Foundry signs with the private key of deployer (--account flag),
         * but the script itself sees msg.sender as DEFAULT_SENDER
         */
        (, address deployer,) = vm.readCallers();

        // 1. Deploy GovernanceToken and mint initial supply to deployer
        GovernanceToken token = new GovernanceToken();

        /**
         * Here msg.sender != deployer.
         * Interesting inside `run` msg.sender = DEFAULT_SENDER, but inside the
         * GovernanceToken constructor, msg.sender = the --account address
         * Since, we want our --account to be minted the INITIAL_SUPPLY,
         * we should use <deployer> variable instead of msg.sende (which, as stated
         * above, is DEFAULT_SENDER, inside the `run` function, unless we explicityly use
         * `vm.startBroadcast(<DEPPLOYER>)` or --sender flag while running the deployer script
         * )
         */
        //token.mint(msg.sender, INITIAL_SUPPLY);
        token.mint(deployer, INITIAL_SUPPLY);
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
