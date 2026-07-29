//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernanceToken} from "./GovernanceToken.sol";

/**
 * @title SimpleDAO
 * @author Shariq Hasan Khan
 * @notice This is the implementation of a simple DAO contract.
 * @notice This contract allows the users vote on pre-created governance proposals using their
 * token balance as voting power
 * CORE LOGIC:
 * 1. Voting power = how many GovernanceToken the user holds (uses OpenZeppelin's ERC20Votes extension)
 * 2. Anyone with voting power can create a proposal, which has a description and a voting period (in blocks)
 * 3. Users vote FOR or AGAINST
 * 4. Proposal is Active until and including the deadline block. Voting closes at block.number > deadline.
 * 5. After period ends, the proposal is marked Passed or Failed
 * 6. The owner of the contract can execute the proposal if it has passed (forVotes > againstVotes)
 * Note that execution is just symbolic here. No actual code runs when a contract is marked as executed
 *
 *
 * KEY RESTRICTION:
 * 1. Users must delegate their voting power before voting (quirk of ERC20Votes — tokens don't automatically count as votes until delegated, even to * * yourself).
 *
 * @dev Inherits from OpenZeppelin's Ownable extension, to restrict certain functions to the contract owner.
 */
contract SimpleDAO is Ownable {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ TYPE DECLARATIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    struct Proposal {
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 snapshotBlock;
        uint256 deadline;
        bool executed;
    }

    enum ProposalState {
        Active,
        Passed,
        Failed,
        Executed
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    mapping(uint256 proposalId => Proposal proposal) private _proposals;
    mapping(uint256 proposalId => mapping(address voter => bool hasVoted)) private _hasVoted;
    uint256 private _proposalCount;
    GovernanceToken private _token;

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EVENTS
    // ╚═══════════════════════════════════════════════════════════════════════
    event SDAO__ProposalCreated(uint256 indexed proposalId, string description, uint256 deadline);
    event SDAO__Voted(uint256 indexed proposalId, address indexed voter, bool inSupport, uint256 weight);
    event SDAO__ProposalExecuted(uint256 indexed proposalId);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ ERRORS
    // ╚═══════════════════════════════════════════════════════════════════════
    error SDAO__VotingPeriodMustBeGreaterThanZero();
    error SDAO__VotingPeriodEnded(uint256 proposalId, uint256 currentBlock, uint256 deadline);
    error SDAO__AlreadyVoted(uint256 proposalId, address voter);
    error SDAO__NoVotingPower(address voterId);
    error SDAO__ProposalDoesNotExist(uint256 proposalId);
    error SDAO__ProposalAlreadyExecuted(uint256 proposalId);
    error SDAO__ProposalDidNotPass(uint256 proposalId);
    error SDAO__CanNotExecuteAnActiveProposal(uint256 proposalId, uint256 currentBlock, uint256 deadline);

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTRUCTOR
    // ╚═══════════════════════════════════════════════════════════════════════
    constructor(address tokenAddress) Ownable(msg.sender) {
        _token = GovernanceToken(tokenAddress);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL STATE-CHANGING FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function createProposal(string memory description, uint256 votingPeriod) external returns (Proposal memory) {
        if (votingPeriod == 0) {
            revert SDAO__VotingPeriodMustBeGreaterThanZero();
        }

        uint256 votingPower = _token.getPastVotes(msg.sender, block.number - 1);
        if (votingPower == 0) {
            revert SDAO__NoVotingPower(msg.sender);
        }

        Proposal storage newProposal = _proposals[_proposalCount];
        newProposal.description = description;
        newProposal.snapshotBlock = block.number - 1;
        newProposal.deadline = block.number + votingPeriod;
        _proposalCount++;

        emit SDAO__ProposalCreated(_proposalCount - 1, description, newProposal.deadline);
        return newProposal;
    }

    function vote(uint256 proposalId, bool inSupport) external {
        // Revert, if invalid proposal id
        if (proposalId >= _proposalCount) {
            revert SDAO__ProposalDoesNotExist(proposalId);
        }

        Proposal storage proposal = _proposals[proposalId];
        ProposalState state = _getProposalState(proposalId);

        if (state != ProposalState.Active) {
            revert SDAO__VotingPeriodEnded(proposalId, block.number, proposal.deadline);
        }

        if (_hasVoted[proposalId][msg.sender]) {
            revert SDAO__AlreadyVoted(proposalId, msg.sender);
        }

        uint256 weight = _token.getPastVotes(msg.sender, proposal.snapshotBlock);
        if (weight == 0) {
            revert SDAO__NoVotingPower(msg.sender);
        }

        if (inSupport) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }
        _hasVoted[proposalId][msg.sender] = true;

        emit SDAO__Voted(proposalId, msg.sender, inSupport, weight);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        // Revert, if invalid proposal id
        if (proposalId >= _proposalCount) {
            revert SDAO__ProposalDoesNotExist(proposalId);
        }

        Proposal storage proposal = _proposals[proposalId];
        ProposalState state = _getProposalState(proposalId);

        // Revert, if proposal is still active (voting period not ended)
        if (state == ProposalState.Active) {
            revert SDAO__CanNotExecuteAnActiveProposal(proposalId, block.number, proposal.deadline);
        }

        // Revert, if proposal as already been executed
        if (state == ProposalState.Executed) {
            revert SDAO__ProposalAlreadyExecuted(proposalId);
        }

        // Revert, if proposal did not pass (forVotes <= againstVotes)
        if (state == ProposalState.Failed) {
            revert SDAO__ProposalDidNotPass(proposalId);
        }

        proposal.executed = true;

        emit SDAO__ProposalExecuted(proposalId);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXTERNAL VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function getProposalState(uint256 proposalId) external view returns (ProposalState) {
        return _getProposalState(proposalId);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        if (proposalId >= _proposalCount) {
            revert SDAO__ProposalDoesNotExist(proposalId);
        }
        return _proposals[proposalId];
    }

    function getProposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return _hasVoted[proposalId][voter];
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ PRIVATE VIEW FUNCTIONS
    // ╚═══════════════════════════════════════════════════════════════════════
    function _getProposalState(uint256 proposalId) private view returns (ProposalState) {
        // Revert, if invalid proposal id
        if (proposalId >= _proposalCount) {
            revert SDAO__ProposalDoesNotExist(proposalId);
        }

        Proposal storage proposal = _proposals[proposalId];
        if (block.number <= proposal.deadline) {
            return ProposalState.Active;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (proposal.forVotes > proposal.againstVotes) {
            return ProposalState.Passed;
        } else {
            return ProposalState.Failed;
        }
    }
}
