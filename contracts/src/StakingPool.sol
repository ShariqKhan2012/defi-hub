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
 *
 * @notice This is the implementation of the StakingPool contract.
 * @notice Main features:
 * 1. A protocol that allows users to stake their GTK toens
 * 2. Users can unstake, partially or fully, anytime they want to.
 * 3. Users earn rewards proportional to the amount of the the tokens they have staked, and the
 *    time they have staked the tokens for. The users can claim their rewards anytime they want.
 * 4. Interest rate
 *      - Individually set up an interest rate for each user based on some global interest rate of
 *      the protocol at the time the user stakes into the pool.
 *      - This global interest rate can only decrease over time to incentivise/reward early adopters.
 *      - Increases token adoption.
 *      - The individual interest rate is unaffected by the change in the global reward rate, unless
 *      the user performs any of these actions: a. Stake b. Unstake c. Claim rewards
 * 5. Upgradeable
 *
 * @dev Uses UUPS Upgradeable Proxy Pattern via OpenZeppelin's relevant contracts.
 */
contract StakingPool is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardTransient {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTANTS
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 internal constant DECIMAL_PRECISION = 18;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    GovernanceToken internal _token;

    // Total amountstaked by all users
    uint256 internal _totalStakedAmount;
    // Total rewards pool
    uint256 internal _rewardsPool;

    /**
     * @dev Consider, as an example, a Protocol-level reward
     * rate of 0.000005% per second
     * 0.000005% per second = 0.00000005 per second = 5e-8 per second
     * 5e-8 per second standardized to 18  decimals = 5e10
     */
    uint256 internal _protocolRewardRatePerSecond;

    /**
     * @dev Stores the individual reward rate of users
     * A user's reward rate is initilly set to the current
     * protocol reward rate.
     * It is unchanged even when the protocol reward rate is updated,
     * UNLESS the user performs any of these actions:
     * 1. Staking 2. Unstaking 3. Claiming reward
     * In these cases, it is updated via _updatePendingRewards.
     */
    mapping(address user => uint256 rewardRate) internal _usersRewardRatePerSecond;

    /**
     * @dev Mapping storing the amount by each user
     * 18 Decimal places
     */
    mapping(address owner => uint256 amount) internal _stakedAmount;

    /**
     * @dev Mapping storing, for each user, the timestamp when their
     * claim time was updated.
     * Updated everytime (via _updatePendingRewards) on:
     * 1. Staking 2. Unstaking 3. Claiming reward
     */
    mapping(address owner => uint256 timestamp) internal _lastClaimTime;

    /**
     * @dev Mapping storing, for each user, the reward they had earned
     * when their claim time was updated.
     * Updated everytime (via _updatePendingRewards) on:
     * 1. Staking 2. Unstaking 3. Claiming reward
     */
    mapping(address owner => uint256 amount) internal _pendingRewards;

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
    error STKPOOL__RewardTransferFailed(address user, uint256 amountInWei);
    error STKPOOL__StakeTransferFailed(address user, uint256 amountInWei);
    error STKPOOL__UnstakeTransferFailed(address user, uint256 amountInWei);
    error STKPOOL__FundRewardTransferFailed(address funder, uint256 amountInWei);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTRUCTOR
    // ╚═══════════════════════════════════════════════════════════════════════
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the owner, token address, and the reward rate
     * @dev Replacement for the constructor
     * @dev Provided by the "Initializable" contract from OpenZeppelin
     * @dev Uses the `initializer` modifier
     * @dev Owner is set to msg.sender (the proxy deployer) so that broadcast scripts
     *      and tests both get the correct owner without needing to pass it as calldata.
     *      Passing the owner as a parameter would bake the script-simulation address
     *      (Foundry's DEFAULT_SENDER) into the calldata, setting the wrong owner on-chain.
     *
     * @param tokenAddress Address of the GovernanceToken contract
     * @param initialRewardRatePerSecond The initial protolcol level reward rate. Consider,
     * as an example, a Protocol-level reward rate of 0.000005% per second
     * 0.000005% per second = 0.00000005 per second = 5e-8 per second
     * 5e-8 per second standardized to 18  decimals = 5e10
     */
    function initialize(address tokenAddress, uint256 initialRewardRatePerSecond) external initializer {
        __Ownable_init(msg.sender);
        _protocolRewardRatePerSecond = initialRewardRatePerSecond;
        _token = GovernanceToken(tokenAddress);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the rewards user has earned since last claim/stake/unstake
     * @dev Wrapper around the internal (and virtual) `_getPendingReward` function
     *
     * @param user The user-address for which the query is being made
     * @return The rewards earned
     */
    function getPendingReward(address user) external view returns (uint256) {
        return _getPendingReward(user);
    }

    /**
     * @notice Get the total amount available in the rewards pool
     * @return The total amount available in the rewards pool
     */
    function getRewardsPoolAmount() external view virtual returns (uint256) {
        return _rewardsPool;
    }

    /**
     * @notice Gets the global reward rate
     * @return global reward rate. In 18 decimals
     */
    function getProtocolRewardRate() external view virtual returns (uint256) {
        return _protocolRewardRatePerSecond;
    }

    /**
     * @notice Gets the time a user's reward rate was last updated
     * @param user The user whose reward rate updation time is sought
     * @return Last updation time
     */
    function getUserRewardRateLastUpdationTime(address user) external view virtual returns (uint256) {
        return _lastClaimTime[user];
    }

    /**
     * @notice Gets the user info (staked amount, rewards, last claim time, and the reward rate)
     * @param user The user in question
     * @return A tuple containing the required values
     */
    function getUserInfo(address user) external view virtual returns (uint256, uint256, uint256, uint256) {
        return (_stakedAmount[user], _getPendingReward(user), _lastClaimTime[user], _usersRewardRatePerSecond[user]);
    }

    /**
     * @notice Gets the pool info (stotal taked amount, rewards pool, and the protocol reward rate)
     * @return A tuple containing the required values
     */
    function getPoolInfo() external view virtual returns (uint256, uint256, uint256) {
        return (_totalStakedAmount, _rewardsPool, _protocolRewardRatePerSecond);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
        /**
     * @notice Stake GovernanceToken tokens in the pool
     * @param amountInWei Amount to stake in 18 decimals
     */
    function stake(uint256 amountInWei) public virtual {
        if (amountInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }

        address user = msg.sender;
        /**
         * Snapshot the rewards accumulated till now, first.
         * And then, update the staked amount.
         */
        _updatePendingRewards(user);
        _stakedAmount[user] += amountInWei;
        _totalStakedAmount += amountInWei;

        emit STKPOOL__Staked(user, amountInWei);

        bool success = _token.transferFrom(user, address(this), amountInWei);
        if (!success) {
            revert STKPOOL__StakeTransferFailed(user, amountInWei);
        }
    }

    /**
     * @notice Unstake GovernanceToken tokens from the pool
     * @param amountInWei Amount to unstake in 18 decimals
     */
    function unstake(uint256 amountInWei) public virtual {
        if (amountInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }

        address user = msg.sender;
        // Ensure the user is not trying to unstake more than they have
        if (amountInWei > _stakedAmount[user]) {
            revert STKPOOL__CantUnstakeMoreThanTheStakedAmount(amountInWei, _stakedAmount[user]);
        }

        /**
         * stakedAmount[user] <= totalStaked by invariant.
         * So, if the above test does not fail, then this test too
         * should NOT fail.
         * Still, lets put this as a DEFENSIVE guard
         */
        if (amountInWei > _totalStakedAmount) {
            revert STKPOOL__NotEnoughFundsInStakedPool(amountInWei, _totalStakedAmount);
        }

        /**
         * Snapshot the rewards accumulated till now, first.
         * Payout the rewards
         * And THEN, update the staked amount.
         */
        _updatePendingRewards(user);
        uint256 reward = _pendingRewards[user];
        uint256 rewardsPoolAmount = _rewardsPool;
        uint256 actualRewardPayout = 0;

        if (reward > 0 && rewardsPoolAmount > 0) {
            actualRewardPayout = Math.min(reward, rewardsPoolAmount);
            _pendingRewards[user] -= actualRewardPayout;
            _rewardsPool -= actualRewardPayout;
            emit STKPOOL__RewardPaid(user, actualRewardPayout, reward);
        }

        _stakedAmount[user] -= amountInWei;
        _totalStakedAmount -= amountInWei;

        // Principal + any reward paid out in a single transfer
        bool success = _token.transfer(user, amountInWei + actualRewardPayout);
        if (!success) {
            revert STKPOOL__UnstakeTransferFailed(user, amountInWei + actualRewardPayout);
        }

        emit STKPOOL__Unstaked(user, amountInWei);
    }

    /**
     * @notice Claim your earned rewards
     */
    function claimRewards() public virtual {
        address user = msg.sender;

        uint256 rewardsPoolAmount = _rewardsPool;

        /**
         * @dev Intentionally check pool balance BEFORE calling _updatePendingRewards.
         * An empty pool is a protocol failure, not a user action. The user's individual
         * reward rate must not be updated — and thereby reduced — due to the protocol's
         * own insolvency.
         */
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
        _rewardsPool -= actualRewardPayout;
        emit STKPOOL__RewardPaid(user, actualRewardPayout, reward);

        bool success =_token.transfer(user, actualRewardPayout);
        if (!success) {
            revert STKPOOL__RewardTransferFailed(user, actualRewardPayout);
        }
    }

    /**
     * @notice Fund the rewards pool
     * @param amountInWei Amount to stake in 18 decimals
     */
    function fundRewardsPool(uint256 amountInWei) public virtual {
        if (amountInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }
        _rewardsPool += amountInWei;
        emit STKPOOL__RewardPoolFunded(msg.sender, amountInWei);

        bool success = _token.transferFrom(msg.sender, address(this), amountInWei);
        if (!success) {
            revert STKPOOL__FundRewardTransferFailed(msg.sender, amountInWei);
        }
    }

    /**
     * @notice Updates the global reward rate
     * @dev Reverts if the new rate is higher than the current rate
     * @dev Uses the `onlyOwner` modifier
     *
     * @param newRewardRate New reward rate
     */
    function setRewardRate(uint256 newRewardRate) public virtual onlyOwner {
        if (newRewardRate >= _protocolRewardRatePerSecond) {
            revert STKPOOL__RewardRateCanOnlyDecrease(_protocolRewardRatePerSecond, newRewardRate);
        }
        uint256 oldRewardRate = _protocolRewardRatePerSecond;
        _protocolRewardRatePerSecond = newRewardRate;

        // Log the updation
        emit STKPOOL__RewardRateUpdated(oldRewardRate, newRewardRate);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if the user is allowed to upgrade to a newer contract
     * @dev UUPSUpgradeable declares this as a pure virtual function with
     * NO default implementation. Since forgetting access control here is a
     * critical, contract-bricking vulnerability, OZ refuses to guess a
     * "safe default" on our behalf.
     * So, we are forced to write it ourself
     *
     * @dev Uses the `onlyOwner` modifier
     *
     * @param newImplementation Address of the new impleentation to upgrade to
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Updates the pending rewards user has earned since last update
     * @param user The user in question
     */
    function _updatePendingRewards(address user) internal {
        _pendingRewards[user] += _calculateUserAccruedRewardSinceLastUpdate(user);
        _lastClaimTime[user] = block.timestamp;

        // Update the user's reward rate to that of the protocol
        _usersRewardRatePerSecond[user] = _protocolRewardRatePerSecond;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates reward accured by a user since the last time his
     * reward rate was updated
     * @dev Simple reward formula: Reward = Principal * Rate * Time
     *
     * @param user The user in question
     * @return The reward amount accured
     */
    function _calculateUserAccruedRewardSinceLastUpdate(address user) internal view virtual returns (uint256) {
        uint256 lastUpdationTime = _lastClaimTime[user];
        if (lastUpdationTime == 0) {
            return 0;
        }

        // Since our reward rate is per second, timeElapsed should be in seconds
        uint256 timeElapsed = block.timestamp - lastUpdationTime;
        // Adjusting for DECIMAL_PRECISION decimals
        return (_stakedAmount[user] * _usersRewardRatePerSecond[user] * timeElapsed) / 10 ** DECIMAL_PRECISION;
    }

    /**
     * @notice Gets the total rewards user has earned since last claim
     * @dev Total rewards = settled rewards + unsettled rewards
     * Settled rewards = Marked in _pendingRewards
     * Unsettled rewards = Rewards earned since _pendingRewards was last updated
     *
     * @param user The user in question
     * @return The reward amount accured
     */
    function _getPendingReward(address user) internal view virtual returns (uint256) {
        // _pendingRewards[user] holds already-settled amount
        // rewardNotYetCalculated is the unsettled real-time portion
        uint256 rewardAlreadyCalculated = _pendingRewards[user];
        uint256 rewardNotYetCalculated = _calculateUserAccruedRewardSinceLastUpdate(user);
        return rewardAlreadyCalculated + rewardNotYetCalculated;
    }
}
