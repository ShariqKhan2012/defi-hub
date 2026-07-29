// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimpleDAO} from "../src/SimpleDAO.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract SimpleDAODeployer is Script {
    function run() external {
        string memory broadcastJson = vm.readFile("broadcast/Deploy.s.sol/31337/run-latest.json");
        // GovernanceToken is [0], mint CALL is [1], StakingPool impl is [2], proxy is [3]
        address tokenAddress = vm.parseJsonAddress(broadcastJson, ".transactions[0].contractAddress");

        vm.startBroadcast();
        SimpleDAO dao = new SimpleDAO(tokenAddress);
        console.log("SimpleDAO deployed at:", address(dao));
        vm.stopBroadcast();
    }
}
