// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {StakingPool} from "../src/StakingPool.sol";

contract StakingPoolTest is Test {
    uint256 constant INITIAL_REWARD_RATE = 5e10;
    uint256 constant FUND_AMOUNT = 1000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;

    GovernanceToken internal token;
    StakingPool internal pool;
    address internal proxy;

    address internal owner = address(this); // initialize() sets owner to msg.sender (the test contract)
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new GovernanceToken();

        proxy = Upgrades.deployUUPSProxy(
            "StakingPool.sol",
            abi.encodeCall(StakingPool.initialize, (address(token), INITIAL_REWARD_RATE))
        );
        pool = StakingPool(proxy);

        deal(address(token), alice, FUND_AMOUNT);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        // Fund rewards pool as owner (address(this))
        deal(address(token), address(this), FUND_AMOUNT);
        token.approve(address(pool), type(uint256).max);
        pool.fundRewardsPool(FUND_AMOUNT);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ HELPER
    // ╚═══════════════════════════════════════════════════════════════════════

    function _expectedReward(uint256 principal, uint256 rate, uint256 time) internal pure returns (uint256) {
        return principal * rate * time / 1e18;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INITIalizATION
    // ╚═══════════════════════════════════════════════════════════════════════

    function test_Initialize_SetsOwner() public view {
        assertEq(pool.owner(), owner);
    }

    function test_Initialize_SetsRewardRate() public view {
        assertEq(pool.getProtocolRewardRate(), INITIAL_REWARD_RATE);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STAKING
    // ╚═══════════════════════════════════════════════════════════════════════
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

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ REWARDS
    // ╚═══════════════════════════════════════════════════════════════════════
    function test_SetRewardRate_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.setRewardRate(1e10);
    }

    function test_SetRewardRate_RevertsIfRateIncreases() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingPool.STKPOOL__RewardRateCanOnlyDecrease.selector,
                INITIAL_REWARD_RATE,
                INITIAL_REWARD_RATE + 1
            )
        );
        pool.setRewardRate(INITIAL_REWARD_RATE + 1);
    }
    
    function test_Rewards_AccrueOverTime() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);

        assertGt(pool.getPendingReward(alice), 0);
    }

    function test_Rewards_AccrueCorrectlyAcrossMultipleCycles() public {
        uint256 rate = INITIAL_REWARD_RATE;

        // Cycle 1: initial stake
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);
        uint256 rewardCycle1 = _expectedReward(STAKE_AMOUNT, rate, 1 days);
        assertEq(pool.getPendingReward(alice), rewardCycle1);

        // Cycle 2: add more stake — snapshots cycle 1 rewards, principal doubles
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);
        uint256 rewardCycle2 = _expectedReward(STAKE_AMOUNT * 2, rate, 1 days);
        assertEq(pool.getPendingReward(alice), rewardCycle1 + rewardCycle2);

        // Partial unstake — snapshots + pays out cycle 1+2 rewards
        uint256 balanceBeforeUnstake = token.balanceOf(alice);
        vm.prank(alice);
        pool.unstake(STAKE_AMOUNT);

        assertEq(token.balanceOf(alice), balanceBeforeUnstake + STAKE_AMOUNT + rewardCycle1 + rewardCycle2);
        assertEq(pool.getPendingReward(alice), 0);

        // Cycle 3: remaining stake (1x principal)
        skip(1 days);
        uint256 rewardCycle3 = _expectedReward(STAKE_AMOUNT, rate, 1 days);
        assertEq(pool.getPendingReward(alice), rewardCycle3);

        uint256 balanceBeforeClaim = token.balanceOf(alice);
        vm.prank(alice);
        pool.claimRewards();
        assertEq(token.balanceOf(alice) - balanceBeforeClaim, rewardCycle3);
    }

    function test_Rewards_LockedAtStakeRate() public {
        uint256 rateR1 = INITIAL_REWARD_RATE;

        // Stake locks user's rate at R1
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        // Protocol rate decreases — user's locked rate must be unaffected
        uint256 rateR2 = rateR1 / 2;
        pool.setRewardRate(rateR2);

        skip(1 days);

        // Rewards should have accrued at R1, not R2
        uint256 expectedAtR1 = _expectedReward(STAKE_AMOUNT, rateR1, 1 days);
        assertEq(pool.getPendingReward(alice), expectedAtR1);

        // Claiming snapshots rewards at R1 and updates user's rate to R2
        vm.prank(alice);
        pool.claimRewards();

        // Subsequent rewards accrue at R2
        skip(1 days);
        uint256 expectedAtR2 = _expectedReward(STAKE_AMOUNT, rateR2, 1 days);
        assertEq(pool.getPendingReward(alice), expectedAtR2);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CLAIMING REWARDS
    // ╚═══════════════════════════════════════════════════════════════════════
    function test_ClaimRewards_TransfersExactAmount() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);

        uint256 expected = _expectedReward(STAKE_AMOUNT, INITIAL_REWARD_RATE, 1 days);
        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        pool.claimRewards();

        assertEq(token.balanceOf(alice) - balanceBefore, expected);
    }

    function test_ClaimRewards_RevertsIfNoReward() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        // No time elapsed — reward = 0
        vm.prank(alice);
        vm.expectRevert(StakingPool.STKPOOL__NoRewardToClaim.selector);
        pool.claimRewards();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ UNSTAKING
    // ╚═══════════════════════════════════════════════════════════════════════
    function test_Unstake_ReturnsPrincipalPlusRewards() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        skip(1 days);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        pool.unstake(STAKE_AMOUNT);

        // Must return strictly more than principal because rewards are included
        assertGt(token.balanceOf(alice), balanceBefore + STAKE_AMOUNT);
    }

    function test_Unstake_PartialRewardPayout_PreservesRemainder() public {
        vm.prank(alice);
        pool.stake(STAKE_AMOUNT);

        // Warp until accrued reward greatly exceeds the rewards pool (1000 ether)
        skip(10 * 365 days);

        (, uint256 rewardsPoolBefore,) = pool.getPoolInfo();
        uint256 pendingBefore = pool.getPendingReward(alice);
        assertGt(pendingBefore, rewardsPoolBefore); // confirms partial-payout scenario

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        pool.unstake(STAKE_AMOUNT);

        // Received principal + reward capped at pool balance
        assertEq(token.balanceOf(alice), balanceBefore + STAKE_AMOUNT + rewardsPoolBefore);

        // Pool is fully drained
        (, uint256 rewardsPoolAfter,) = pool.getPoolInfo();
        assertEq(rewardsPoolAfter, 0);

        // Remainder preserved — not zeroed out
        uint256 remainder = pendingBefore - rewardsPoolBefore;
        assertEq(pool.getPendingReward(alice), remainder);

        // Pool empty → claim reverts
        vm.prank(alice);
        vm.expectRevert(StakingPool.STKPOOL__RewardPoolEmpty.selector);
        pool.claimRewards();

        // Refund pool, then claim remainder
        deal(address(token), address(this), remainder);
        pool.fundRewardsPool(remainder);

        vm.prank(alice);
        pool.claimRewards();
        assertEq(pool.getPendingReward(alice), 0);
    }

    function test_Unstake_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(StakingPool.STKPOOL__ZeroNotAllowed.selector);
        pool.unstake(0);
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
}
