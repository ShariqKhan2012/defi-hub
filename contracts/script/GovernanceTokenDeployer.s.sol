//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract GovernanceTokenDeployer is Script {
    GovernanceToken public gtk;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1 million GTK with 18 decimals

     /**
     * @notice Deploys the GovernanceToken contract and mints the initial supply to the deployer.
     * @return The deployed GovernanceToken contract instance.
     */
    function run() public returns (GovernanceToken) {
        vm.startBroadcast();
        gtk = new GovernanceToken();
        gtk.mint(msg.sender, INITIAL_SUPPLY);
        vm.stopBroadcast();
        return gtk;
    }
}