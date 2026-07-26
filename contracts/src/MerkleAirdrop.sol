//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {GovernanceToken} from "./GovernanceToken.sol";

/**
 * @title MerkleAirdrop
 * @author Shariq Hasan Khan
 * @notice This is the implementation of the MerkleAirdrop contract.
 */
contract MerkleAirdrop {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ IMMUTABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    bytes32 private immutable _merkleRoot;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    mapping(address => bool) private _claimed;
    GovernanceToken private _token;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EVENTS
    // ╚═══════════════════════════════════════════════════════════════════════
    event MERKLE__Claimed(address indexed user, uint256 amountInWei);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ ERRORS
    // ╚═══════════════════════════════════════════════════════════════════════
    error MERKLE__AlreadyClaimed(address user);
    error MERKLE__InvalidProof(address user, bytes32[] proof, bytes32 root, bytes32 leaf);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTRUCTOR
    // ╚═══════════════════════════════════════════════════════════════════════
    constructor(address tokenAddress, bytes32 root) {
        _token = GovernanceToken(tokenAddress);
        _merkleRoot = root;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function claim(bytes32[] calldata proof, uint256 amountInWei) external {
        if (_claimed[msg.sender]) {
            revert MERKLE__AlreadyClaimed(msg.sender);
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amountInWei))));
        if (!MerkleProof.verify(proof, _merkleRoot, leaf)) {
            revert MERKLE__InvalidProof(msg.sender, proof, _merkleRoot, leaf);
        }
        _claimed[msg.sender] = true;
        emit MERKLE__Claimed(msg.sender, amountInWei);

        /**
         * Claim verified. Now transfer the tokens.
         * Note: The contract must have enough tokens to transfer to the user.
         * That we ensure by transferring the tokens to the contract before the airdrop
         * starts ie. at the time of deployment of the contract.
         */
        _token.transfer(msg.sender, amountInWei);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function getMerkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    function hasClaimed(address user) external view returns (bool) {
        return _claimed[user];
    }
}
