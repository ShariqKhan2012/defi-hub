// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.24;

import { Test } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { StakingPool } from "../src/StakingPool.sol";

contract StakingPoolValidatedTest is Test {
    uint256 constant INITIAL_REWARD_RATE = 5e10;
    uint256 constant FUND_AMOUNT = 1000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;

    GovernanceToken internal token;
    StakingPool internal pool;
    address internal proxy;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

  function setUp() public {
    token = new GovernanceToken();

    // Upgrades.deployUUPSProxy validates upgrade safety before deploying
    proxy = Upgrades.deployUUPSProxy(
      "StakingPool.sol",
      abi.encodeCall(
        StakingPool.initialize,
        (owner, address(token), INITIAL_REWARD_RATE)
      )
    );
    pool = StakingPool(proxy);

    deal(address(token), alice, FUND_AMOUNT);
    vm.prank(alice);
    token.approve(address(pool), type(uint256).max);

    deal(address(token), owner, FUND_AMOUNT);
    vm.startPrank(owner);
    token.approve(address(pool), type(uint256).max);
    pool.fundRewardsPool(FUND_AMOUNT);
    vm.stopPrank();
  }

  // The validated test suite mirrors the fast suite.
  // Its unique value is that setUp() itself will REVERT
  // if StakingPool is not upgrade-safe — catching issues
  // like state variable assignments, immutables, or
  // constructors that would corrupt upgradeable storage.

  function test_Initialize_SetsOwner() public view {
    assertEq(pool.owner(), owner);
  }

  function test_Stake_UpdatesUserInfo() public {
    vm.prank(alice);
    pool.stake(STAKE_AMOUNT);
    (uint256 staked,,,) = pool.getUserInfo(alice);
    assertEq(staked, STAKE_AMOUNT);
  }

  function test_Rewards_AccrueOverTime() public {
    vm.prank(alice);
    pool.stake(STAKE_AMOUNT);
    skip(1 days);
    assertGt(pool.getPendingReward(alice), 0);
  }
}