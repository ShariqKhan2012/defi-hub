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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title GovernanceToken
 * @author Shariq Hasan Khan
 * @notice GovernanceToken (GTK) is the foundation of the DeFi-Hub.
 * It is an ERC20 token with voting power built in (ERC20Votes). It is the single currency of the entire hub.
 *
 * Used to stake in the Staking feature
 * Distributed via the Airdrop feature
 * Used to vote in the DAO feature
 * Prize in the Lottery feature
 * All paymasters hold GTK or ETH to sponsor gas
 *
 * @dev This contract inherits from ERC20, ERC20Votes, ERC20Permit and Ownable.
 * It implements the necessary overrides for the ERC20Votes and ERC20Permit contracts.
 */
contract GovernanceToken is ERC20, ERC20Votes, ERC20Permit, Ownable {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTANTS
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 public constant DECIMAL_PRECISION = 18;
    uint256 public constant FAUCET_CLAIM_AMOUNT_IN_WEI = 3000 * (10 ** DECIMAL_PRECISION); // 3000 GTK

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    mapping(address claimant => uint256 timestamp) private _lastFaucetClaim;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EVENTS
    // ╚═══════════════════════════════════════════════════════════════════════
    event GTK__FaucetUsed(address indexed claimant);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ ERRORS
    // ╚═══════════════════════════════════════════════════════════════════════
    error GTK__FaucetUsedBefore24Hours();

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTRUCTOR
    // ╚═══════════════════════════════════════════════════════════════════════
    constructor() ERC20("Governance Token", "GTK") ERC20Permit("Governance Token") Ownable(msg.sender) {}

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function mint(address to, uint256 amountInWei) public onlyOwner {
        _mint(to, amountInWei);
        // Delegate the voting power to the recipient
        _delegate(to, to);
    }

    function faucet() public {
        // Proceed only if 24 hours have elapsed since the last usage of the faucet
        if (_lastFaucetClaim[msg.sender] != 0 && (block.timestamp < _lastFaucetClaim[msg.sender] + 24 hours)) {
            revert GTK__FaucetUsedBefore24Hours();
        }
        _lastFaucetClaim[msg.sender] = block.timestamp;
        emit GTK__FaucetUsed(msg.sender);
        _mint(msg.sender, FAUCET_CLAIM_AMOUNT_IN_WEI);
        // Delegate the voting power to the claimant themselves
        _delegate(msg.sender, msg.sender);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PUBLIC VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    /**
     * @inheritdoc ERC20Permit
     * @return Returns the next unused nonce for an address.
     */
    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ INTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Updates the voting power of the sender and receiver
     * @dev Required override for ERC20Votes and ERC20Permit. Resolves ERC20 + ERC20Votes conflict
     * @dev It is called internally by the ERC20Votes and ERC20Permit contracts on every transfer/mint/burn.
     * @dev Calls the parent contracts' _update function to update the voting power of the sender and receiver
     *
     * @param from Address of the sender
     * @param to Address of the receiver
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
