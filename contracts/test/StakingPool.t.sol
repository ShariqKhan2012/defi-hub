// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {StakingPool} from "../src/StakingPool.sol";

contract StakingPoolTest is Test {
    uint256 constant INITIAL_REWARD_RATE = 5e10;
    uint256 constant FUND_AMOUNT = 1000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;

    GovernanceToken internal token;
    StakingPool internal pool;   // typed handle on the proxy
    address internal proxy;

    // owner = address(this): initialize() sets owner to msg.sender (the test contract)
    address internal owner = address(this);
    address internal alice = makeAddr("alice");

    function setUp() public {
        // 1. Deploy GovernanceToken
        token = new GovernanceToken();

        // 2. Deploy StakingPool implementation, then wrap in a proxy
        //    UnsafeUpgrades requires us to deploy the implementation first
        //    initialize() sets owner = msg.sender = address(this) (this test contract)
        StakingPool impl = new StakingPool();
        proxy = UnsafeUpgrades.deployUUPSProxy(
            address(impl),
            abi.encodeCall(
                StakingPool.initialize,
                (address(token), INITIAL_REWARD_RATE)
            )
        );
        pool = StakingPool(proxy);

        // 3. Give alice some tokens and approval
        deal(address(token), alice, FUND_AMOUNT);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        // 4. Fund the rewards pool (as owner = address(this), no prank needed)
        deal(address(token), address(this), FUND_AMOUNT);
        token.approve(address(pool), type(uint256).max);
        pool.fundRewardsPool(FUND_AMOUNT);
    }

    // ── Initialization ───────────────────────────────────────────────────

    function test_Initialize_SetsOwner() public view {
        assertEq(pool.owner(), owner);
    }

    function test_Initialize_SetsRewardRate() public view {
        assertEq(pool.getProtocolRewardRate(), INITIAL_REWARD_RATE);
    }

    // ── Staking ──────────────────────────────────────────────────────────

    function test_Stake_UpdatesUserInfo() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        (uint256 staked,,,) = pool.getUserInfo(alice);
        assertEq(staked, STAKE_AMOUNT);
    }

    function test_Stake_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(StakingPool.STKPOOL__ZeroNotAllowed.selector);
        pool.stake(0);
    }

    // ── Rewards ──────────────────────────────────────────────────────────

    function test_Rewards_AccrueOverTime() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        // Advance 1 day
        skip(1 days);

        uint256 pending = pool.getPendingReward(alice);
        assertGt(pending, 0);
    }

    function test_ClaimRewards_TransfersTokens() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        pool.claimRewards();
        uint256 balanceAfter = token.balanceOf(alice);

        assertGt(balanceAfter, balanceBefore);
    }

    // ── Unstaking ────────────────────────────────────────────────────────

    function test_Unstake_ReturnsTokens() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        pool.unstake(STAKE_AMOUNT);

        assertGe(token.balanceOf(alice), balanceBefore + STAKE_AMOUNT);
    }

    function test_Unstake_RevertsIfExceedsStaked() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingPool.STKPOOL__CantUnstakeMoreThanTheStakedAmount.selector,
                STAKE_AMOUNT + 1,
                STAKE_AMOUNT
            )
        );
        pool.unstake(STAKE_AMOUNT + 1);
    }

    // ── Access Control ───────────────────────────────────────────────────

    function test_SetRewardRate_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.setRewardRate(1e10);
    }

    function test_SetRewardRate_RevertsIfRateIncreases() public {
        // owner = address(this), so call directly — no prank needed
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingPool.STKPOOL__RewardRateCanOnlyDecrease.selector,
                INITIAL_REWARD_RATE,
                INITIAL_REWARD_RATE + 1
            )
        );
        pool.setRewardRate(INITIAL_REWARD_RATE + 1);
    }
}