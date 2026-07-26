//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {Test} from "forge-std/Test.sol";

contract MerkleAirdropTest is Test {
    GovernanceToken private _token;
    MerkleAirdrop private _airdrop;
    bytes32 private _merkleRootOfAirdrop = 0x7727901f7c04ce45a6360bc797972f65671a366ea22a306a388698492203681f;

    address alice = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    uint256 claimAmountOfAlice = 1000 ether;
    bytes32[] proofOfAlice = new bytes32[](3);

    address bob = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    uint256 claimAmountOfBob = 5000 ether;
    bytes32[] proofOfBob = new bytes32[](3);

    function setUp() public {
        _token = new GovernanceToken();
        _airdrop = new MerkleAirdrop(address(_token), _merkleRootOfAirdrop);
        // Prefund the airdrop contract with enough tokens to transfer to the users
        _token.mint(address(_airdrop), 20000 ether);

        proofOfAlice[0] = 0x08bb1fee0cafdaa850b7c234ddd1fb8c1accb1321057f55d9ba449882fc7d69e;
        proofOfAlice[1] = 0x5512bda1c8314026724e65dd853a633cbe1b97f8583150170480da50150f1137;
        proofOfAlice[2] = 0xea40f20a596e7ead42cbd66e579fb2265203dd8e17744c0905b73a8afbfca120;

        proofOfBob[0] = 0x0d19554039b714b1f4c023957229f9e9d2774c17b74920e4f66c2cbddb537905;
        proofOfBob[1] = 0x5512bda1c8314026724e65dd853a633cbe1b97f8583150170480da50150f1137;
        proofOfBob[2] = 0xea40f20a596e7ead42cbd66e579fb2265203dd8e17744c0905b73a8afbfca120;
    }

    function testValidClaimIsProved() public {
        vm.prank(alice);
        /*bytes32[] memory proofOfAlice = new bytes32[](3);
        proofOfAlice[0] = 0x08bb1fee0cafdaa850b7c234ddd1fb8c1accb1321057f55d9ba449882fc7d69e;
        proofOfAlice[1] = 0x5512bda1c8314026724e65dd853a633cbe1b97f8583150170480da50150f1137;
        proofOfAlice[2] = 0xea40f20a596e7ead42cbd66e579fb2265203dd8e17744c0905b73a8afbfca120;*/

        _airdrop.claim(proofOfAlice, claimAmountOfAlice);

        assertTrue(_airdrop.hasClaimed(alice), "Claim should be marked as fulfilled");
    }

    function testValidClaimUpdatesBalance() public {
        uint256 startingBalanceOfAlice = _token.balanceOf(alice);
        uint256 startingBalanceOfAirdrop = _token.balanceOf(address(_airdrop));
        vm.prank(alice);
        _airdrop.claim(proofOfAlice, claimAmountOfAlice);
        uint256 endingBalanceOfAlice = _token.balanceOf(alice);
        uint256 endingBalanceOfAirdrop = _token.balanceOf(address(_airdrop));

        assertTrue(_airdrop.hasClaimed(alice));
        assertEq(endingBalanceOfAlice, startingBalanceOfAlice + claimAmountOfAlice);
        assertEq(endingBalanceOfAirdrop, startingBalanceOfAirdrop - claimAmountOfAlice);
    }

    function testValidClaimCantBeProcessTwice() public {
        uint256 startingBalanceOfAlice = _token.balanceOf(alice);
        vm.prank(alice);
        _airdrop.claim(proofOfAlice, claimAmountOfAlice);

        assertTrue(_airdrop.hasClaimed(alice), "Claim should be marked as fulfilled");

        // Cant claimthe same proof again
        vm.prank(alice);
        vm.expectPartialRevert(MerkleAirdrop.MERKLE__AlreadyClaimed.selector);
        _airdrop.claim(proofOfAlice, 1000 ether);
        uint256 endingBalanceOfAlice = _token.balanceOf(alice);
        assertEq(endingBalanceOfAlice, startingBalanceOfAlice + claimAmountOfAlice);
    }

    function testClaimWithInvalidProofIsRejected() public {
        vm.prank(alice);
        vm.expectPartialRevert(MerkleAirdrop.MERKLE__InvalidProof.selector);
        _airdrop.claim(proofOfBob, claimAmountOfAlice);
    }

    function testClaimWithInvalidAmountIsRejected() public {
        vm.prank(alice);
        vm.expectPartialRevert(MerkleAirdrop.MERKLE__InvalidProof.selector);
        _airdrop.claim(proofOfAlice, claimAmountOfBob);
    }
}
