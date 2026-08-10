// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract MerkleAirdropDeployer is Script {
    function run() external {
        address tokenAddress = DevOpsTools.get_most_recent_deployment("GovernanceToken", block.chainid);

        string memory merkleJson = vm.readFile("../frontend/script/merkle/merkleOutput.json");
        bytes32 merkleRoot = vm.parseJsonBytes32(merkleJson, ".root");
        uint256 totalAmount = vm.parseJsonUint(merkleJson, ".totalAmount");

        vm.startBroadcast();

        MerkleAirdrop airdrop = new MerkleAirdrop(tokenAddress, merkleRoot);
        console.log("MerkleAirdrop deployed at:", address(airdrop));

        GovernanceToken(tokenAddress).mint(address(airdrop), totalAmount);
        console.log("Funded airdrop with", totalAmount, "GTK (wei)");

        vm.stopBroadcast();
    }
}
