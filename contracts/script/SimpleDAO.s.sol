// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {SimpleDAO} from "../src/SimpleDAO.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract SimpleDAODeployer is Script {
    function run() external {
        address tokenAddress = DevOpsTools.get_most_recent_deployment("GovernanceToken", block.chainid);

        vm.startBroadcast();
        SimpleDAO dao = new SimpleDAO(tokenAddress);
        console.log("SimpleDAO deployed at:", address(dao));
        vm.stopBroadcast();
    }
}
