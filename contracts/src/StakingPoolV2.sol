//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StakingPool} from "./StakingPool.sol";

/**
 * @title StakingPoolV2
 * @author Shariq Hasan Khan
 * @dev Innherits the `StakingPool` contract
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
/// @custom:oz-upgrades-from StakingPool
contract StakingPoolV2 is StakingPool {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTANTS
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 internal constant DEFAUL_STAKE_LIMIT = 10000 * 10**DECIMAL_PRECISION; //10K GTK tokens limit

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 internal _maxStakeLimit;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EVENTS
    // ╚═══════════════════════════════════════════════════════════════════════
    event STKPOOL__StakeLimitChanged(uint256 oldLimit, uint256 newLimit);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ ERRORS
    // ╚═══════════════════════════════════════════════════════════════════════
    error STKPOOL__CanNotStakeMoreThanTheLimit(uint256 amountToStake, uint256 stakeLimit);

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
     * @notice Initializes the max stake limit
     * @dev Replacement for the constructor
     * @dev Provided by the "Initializable" contract from OpenZeppelin
     * @dev Uses the `initializer` modifier
     * @dev Ony initialize NEW V2 state.
     * V1 state (owner, token, rewardRate) already exists on the proxy.
     *
     * @param initialMaxStakeLimitInWei The max state limit allowed.
     */
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function initialize(uint256 initialMaxStakeLimitInWei) external reinitializer(2) {
        // Use the default limit, if zero passed
        if(initialMaxStakeLimitInWei == 0) {
            initialMaxStakeLimitInWei = DEFAUL_STAKE_LIMIT;
        }
        _maxStakeLimit = initialMaxStakeLimitInWei;
    }

    /**
     * @notice Stake GovernanceToken tokens in the pool
     * @param amountInWei Amount to stake in 18 decimals
     */
    function stake(uint256 amountInWei) public override virtual {
        if(amountInWei > _maxStakeLimit) {
            revert STKPOOL__CanNotStakeMoreThanTheLimit(amountInWei, _maxStakeLimit);
        }
        super.stake(amountInWei);
    }

    /**
     * @notice Returns the current per-user stake limit
     * @return The max stake limit in 18-decimal precision
     */
    function getMaxStakeLimit() external view virtual returns (uint256) {
        return _maxStakeLimit;
    }

    /**
     * @notice Changes the stake limit
     * @param newLimitInWei New Stke Limit, in 18-decimal precision
     */
    function setStakeLimit(uint256 newLimitInWei) public virtual onlyOwner{
        if(newLimitInWei == 0) {
            revert STKPOOL__ZeroNotAllowed();
        }
        uint256 oldLimit = _maxStakeLimit;
        _maxStakeLimit = newLimitInWei;

        emit STKPOOL__StakeLimitChanged(oldLimit, newLimitInWei);
    }
}
