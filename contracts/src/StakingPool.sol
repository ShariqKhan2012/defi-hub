/**
 * Code layout of this file as recommendad by Solidity Style Guide
 * https://docs.soliditylang.org/en/latest/style-guide.html
 *
 * Pragma statements
 * Import statements
 * Events
 * Errors
 * Interfaces
 * Libraries
 * Contracts
 *
 * ===============================================================
 *
 * Within a Contract, the order is:
 * Type declarations
 * State variables
 * Events
 * Errors
 * Modifiers
 * Functions
 *
 * ===============================================================
 *
 * Functions are ordered as follows:
 * constructor
 * receive function (if exists)
 * fallback function (if exists)
 * external
 * public
 * internal
 * private
 * Within a grouping, the view and pure functions are placed last.
 */

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {GovernanceToken} from "./GovernanceToken.sol";

/**
 * @title StakingPool
 * @author Shariq Hasan Khan
 * @notice This is the implementation of the Decentralized Stable Coin (DSC) contract.
 */
contract StakingPool is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardTransient {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ TYPE DECLARATIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    GovernanceToken private _token;

    uint256 private _totalStakedAmount;
    uint256 private _rewardsPool;

    /**
     * @dev We start with a default Protocol-level reward
     * rate of 0.000005% per second
     * 0.000005% per second = 0.00000005 per second = 5e-8 per second
     * 5e-8 per second standardized to 18  decimals = 5e10
     */
    uint256 private _protocolRewardRatePerSecond = 5e10;

    /**
     * @dev Stores the individual reward rate of users
     * A user's reward rate is updated everytime on:
     * 1. Staking 2. Unstaking 3. Claiming reward
     */
    mapping(address user => uint256 rewardRate) private _usersRewardRatePerSecond;

    mapping(address owner => uint256 amount) private _stakedAmount;
    mapping(address owner => uint256 timestamp) private _lastClaimTime;
    mapping(address owner => uint256 amount) private _pendingRewards;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTANTS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ IMMUTABLES
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 private _someVariable;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EVENTS
    // ╚═══════════════════════════════════════════════════════════════════════
    event STKPOOL__Staked(address indexed user, uint256 amountInWei);
    event STKPOOL__Unstaked(address indexed user, uint256 amountInWei);
    event STKPOOL__RewardPaid(address indexed user, uint256 amountPaidInWei, uint256 amountUserOwnsInWei);
    event STKPOOL__RewardPoolFunded(address indexed funder, uint256 amountInWei);
    event STKPOOL__RewardRateUpdated(uint256 currentRewardRate, uint256 newRewardRate);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ ERRORS
    // ╚═══════════════════════════════════════════════════════════════════════
    error STKPOOL__ZeroNotAllowed();
    error STKPOOL__CantUnstakeMoreThanTheStakedAmount(uint256 amountInWei, uint256 stakedAmount);
    error STKPOOL__NoRewardToClaim();
    error STKPOOL__RewardPoolEmpty();
    error STKPOOL__NotEnoughFundsInStakedPool(uint256 reward, uint256 stakedPool);
    error STKPOOL__RewardRateCanOnlyDecrease(uint256 currentRewardRate, uint256 newRewardRate);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ MODIFIERS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTRUCTOR
    // ╚═══════════════════════════════════════════════════════════════════════
    constructor() {
        _disableInitializers();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ RECEIVER FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ FALLBACK FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL PURE FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    // --------------------------------------------------------
    // Stand-in for: our hand-rolled `initialize()` + the
    // `initializer` modifier from our own Initializable.
    //
    // OZ requires explicitly chaining each parent's init function
    // (Ownable_init, UUPSUpgradeable_init) — this replaces the
    // manual "owner = owner_;" we wrote by hand, and additionally
    // wires up Ownable's storage/events correctly.
    // --------------------------------------------------------
    function initialize(address owner, address tokenAddress, uint256 initialRewardRatePerSecond) public initializer {
        __Ownable_init(owner);
        _protocolRewardRatePerSecond = initialRewardRatePerSecond;
        _token = GovernanceToken(tokenAddress);
    }

    function stake(uint256 amountInWei) public {
        address user = msg.sender;
        /**
         * Snapshot the rewards accumulated till now, first.
         * And then, update the staked amount.
         */
        _updatePendingRewards(user);
        _stakedAmount[user] += amountInWei;
        _totalStakedAmount += amountInWei;

        emit STKPOOL__Staked(user, amountInWei);

        _token.transferFrom(user, address(this), amountInWei);
    }

    function unstake(uint256 amountInWei) public {
        if (amountInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }

        if (amountInWei > _totalStakedAmount) {
            revert STKPOOL__NotEnoughFundsInStakedPool(amountInWei, _totalStakedAmount);
        }

        address user = msg.sender;
        // Ensure the user is not trying to unstake more than they have
        if (amountInWei > _stakedAmount[user]) {
            revert STKPOOL__CantUnstakeMoreThanTheStakedAmount(amountInWei, _stakedAmount[user]);
        }

        /**
         * Snapshot the rewards accumulated till now, first.
         * Payout the rewards
         * And THEN, update the staked amount.
         */
        _updatePendingRewards(user);
        uint256 reward = _pendingRewards[user];
        uint256 rewardsPoolAmount = _getRewardsPoolAmount();
        uint256 actualRewardPayout = Math.min(reward, rewardsPoolAmount);

        if (reward > 0 && rewardsPoolAmount > 0) {
            _pendingRewards[user] -= actualRewardPayout;
            _lastClaimTime[user] = block.timestamp;
            _rewardsPool -= actualRewardPayout;
            emit STKPOOL__RewardPaid(user, actualRewardPayout, reward);
        }

        _stakedAmount[user] -= amountInWei;
        _totalStakedAmount -= amountInWei;

        // Combine the transfer of reward and unstaked amounts in a single txn to save gas
        _token.transfer(user, amountInWei + actualRewardPayout);

        emit STKPOOL__Unstaked(user, amountInWei);
    }

    function claimRewards() public {
        address user = msg.sender;

        uint256 rewardsPoolAmount = _getRewardsPoolAmount();
        if (rewardsPoolAmount <= 0) {
            revert STKPOOL__RewardPoolEmpty();
        }

        _updatePendingRewards(user);
        uint256 reward = _pendingRewards[user];
        //
        if (reward <= 0) {
            revert STKPOOL__NoRewardToClaim();
        }

        // User has earned some reward, and the pool is also not empty. Let's proceed
        uint256 actualRewardPayout = Math.min(reward, rewardsPoolAmount);

        _pendingRewards[user] -= actualRewardPayout;
        _lastClaimTime[user] = block.timestamp;
        _rewardsPool -= actualRewardPayout;
        emit STKPOOL__RewardPaid(user, actualRewardPayout, reward);

        _token.transfer(user, actualRewardPayout);
    }

    function fundRewardsPool(uint256 amountInWei) public {
        if (amountInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }
        _rewardsPool += amountInWei;
        emit STKPOOL__RewardPoolFunded(msg.sender, amountInWei);

        _token.transferFrom(msg.sender, address(this), amountInWei);
    }

    /**
     * @notice Updates the global reward rate
     * @dev Reverts if the new rate is higher than the current rate
     *
     * @param newRewardRate New reward rate
     */
    function setRewardRate(uint256 newRewardRate) external {
        if (newRewardRate == _protocolRewardRatePerSecond) {
            revert STKPOOL__RewardRateCanOnlyDecrease(_protocolRewardRatePerSecond, newRewardRate);
        }
        uint256 oldRewardRate = _protocolRewardRatePerSecond;
        _protocolRewardRatePerSecond = newRewardRate;

        // Log the updation
        emit STKPOOL__RewardRateUpdated(oldRewardRate, newRewardRate);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function getPendingReward(address user) public view returns (uint256) {
        return _getPendingReward(user);
    }

    function getRewardsPoolAmount() public view returns (uint256) {
        return _getRewardsPoolAmount();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC PURE FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // UUPSUpgradeable declares this as a pure virtual function
    // with NO default implementation — OZ deliberately forces
    // you to write this override yourself, for the same reason
    // we had to write it by hand: forgetting access control here
    // is a critical, contract-bricking vulnerability, and OZ
    // refuses to guess a "safe default" on your behalf.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function _getPendingReward(address user) internal view returns (uint256) {
        // _pendingRewards[user] holds already-settled amount
        // livePending is the unsettled real-time portion
        uint256 rewardAlreadyCalculated = _pendingRewards[user];
        uint256 rewardNotYetCalculated =
            (block.timestamp - _lastClaimTime[user]) * _stakedAmount[user] * _usersRewardRatePerSecond[user];
        return rewardAlreadyCalculated + rewardNotYetCalculated;
    }

    function _getRewardsPoolAmount() internal view returns (uint256) {
        return _rewardsPool;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL PURE FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PRIVATE STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function _updatePendingRewards(address user) private {
        // TODO: Do we need to worry about _lastClaimTime[user]?
        // What if this has not been set ever? In this case, it
        // would be zero, and consequently block.timestamp - _lastClaimTime[user]
        // would be a huge number
        _pendingRewards[user] =
            (block.timestamp - _lastClaimTime[user]) * _stakedAmount[user] * _usersRewardRatePerSecond[user];
        _lastClaimTime[user] = block.timestamp;

        // Update the user's reward rate to that of the protocol
        _usersRewardRatePerSecond[user] = _protocolRewardRatePerSecond;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PRIVATE VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PRIVATE PURE FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
}
