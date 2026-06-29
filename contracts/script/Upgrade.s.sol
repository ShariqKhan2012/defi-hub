// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StakingPoolV2} from "../src/StakingPoolV2.sol";

contract Upgrade is Script {
    // The proxy address from your original deployment
    // TODO: Replace address(0) with the address of the Proxy once it has been deployed
    address constant PROXY = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    function run() external {
        string memory broadcastJson = vm.readFile(
            "broadcast/Deploy.s.sol/31337/run-latest.json"
        );
        // The proxy is the second transaction (index 1) — GovernanceToken is index 0
        address proxy = vm.parseJsonAddress(
            broadcastJson,
            ".transactions[1].contractAddress"
        );

        vm.startBroadcast();

        // Upgrades.upgradeProxy will:
        // 1. Validate StakingPoolV2 against StakingPool (via the annotation)
        // 2. Check storage layout compatibility
        // 3. Deploy the new implementation
        // 4. Call upgradeToAndCall() on the proxy
        Upgrades.upgradeProxy(
            PROXY,
            "StakingPoolV2.sol",
            abi.encodeCall(
                StakingPoolV2.initialize,
                (500 ether)   // or whatever limit you choose
            )
        );

        console.log("StakingPool upgraded to V2 at proxy:", PROXY);

        vm.stopBroadcast();
    }
}