// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StakingPoolV2} from "../src/StakingPoolV2.sol";

contract Upgrade is Script {
    function run() external {
        string memory broadcastJson = vm.readFile(
            "broadcast/Deploy.s.sol/31337/run-latest.json"
        );
        // GovernanceToken is [0], StakingPool impl is [1], proxy is [2]
        address proxy = vm.parseJsonAddress(
            broadcastJson,
            ".transactions[2].contractAddress"
        );

        vm.startBroadcast();

        // Upgrades.upgradeProxy will:
        // 1. Validate StakingPoolV2 against StakingPool (via the annotation)
        // 2. Check storage layout compatibility
        // 3. Deploy the new implementation
        // 4. Call upgradeToAndCall() on the proxy
        Upgrades.upgradeProxy(
            proxy,
            "StakingPoolV2.sol",
            abi.encodeCall(
                StakingPoolV2.initialize,
                (500 ether)
            )
        );

        console.log("StakingPool upgraded to V2 at proxy:", proxy);

        vm.stopBroadcast();
    }
}