//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {SimpleDAO} from "../src/SimpleDAO.sol";

contract SimpleDAOTest is Test {
    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CONSTANTS
    // ╚═══════════════════════════════════════════════════════════════════════
    uint256 private constant DEFAULT_VOTING_PERIOD = 10; // 10 blocks
    string private constant DEFAULT_DESCRIPTION = "Test Proposal";
    uint256 private constant DEFAULT_VOTING_POWER = 1000 ether; // 1000 GTK
    uint256 private constant HIGHER_VOTING_POWER = 2000 ether; // 2000 GTK

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ STATE VARIABLES
    // ╚═══════════════════════════════════════════════════════════════════════
    GovernanceToken private _gtk;
    SimpleDAO private _dao;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private charlie = makeAddr("charlie");

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ MODIFIERS
    // ╚═══════════════════════════════════════════════════════════════════════
    modifier withProposal() {
        vm.prank(alice);
        _dao.createProposal(DEFAULT_DESCRIPTION, DEFAULT_VOTING_PERIOD);
        _;
    }

    modifier withVoting(address voter, bool inSupport) {
        vm.prank(voter);
        _dao.vote(0, inSupport);
        _;
    }

    modifier withVotingCompleted() {
        vm.roll(block.number + DEFAULT_VOTING_PERIOD + 1); // Move to block after deadline
        _;
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ FETCHING PROPOSAL
    // ╚═══════════════════════════════════════════════════════════════════════
    function setUp() public {
        _gtk = new GovernanceToken();
        _dao = new SimpleDAO(address(_gtk));

        // Pre-fund the owner (this contract) and alice with voting power
        _gtk.mint(address(this), HIGHER_VOTING_POWER);
        _gtk.mint(alice, DEFAULT_VOTING_POWER);
        _gtk.mint(charlie, DEFAULT_VOTING_POWER);

        vm.roll(block.number + 1); // Move to next block to ensure snapshotBlock is set correctly
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ DEPLOYMENT
    // ╚═══════════════════════════════════════════════════════════════════════
    function testDeployment() public view {
        address daoOwner = _dao.owner();
        address gtkOwner = _gtk.owner();
        assertEq(daoOwner, address(this));
        assertEq(gtkOwner, address(this));
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CREATING PROPOSAl
    // ╚═══════════════════════════════════════════════════════════════════════
    function testCanNotCreateProposalWithoutVotingPower() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__NoVotingPower.selector, bob));
        vm.prank(bob);
        _dao.createProposal(DEFAULT_DESCRIPTION, DEFAULT_VOTING_PERIOD);
    }

    function testCanNotCreateProposalWithZeroVotingPeriod() public {
        uint256 votingPeriod = 0; // Invalid voting period

        vm.expectRevert(SimpleDAO.SDAO__VotingPeriodMustBeGreaterThanZero.selector);
        vm.prank(alice);
        _dao.createProposal(DEFAULT_DESCRIPTION, votingPeriod);
    }

    function testAnyoneCanCreateProposal() public {
        vm.prank(alice);
        _dao.createProposal(DEFAULT_DESCRIPTION, DEFAULT_VOTING_PERIOD);
        assertEq(_dao.getProposalCount(), 1);
    }

    function testCreatedProposalHasCorrectProperties() public withProposal {
        (SimpleDAO.Proposal memory newProposal,) = _dao.getProposal(0);
        assertEq(newProposal.description, DEFAULT_DESCRIPTION);
        assertEq(newProposal.snapshotBlock, block.number - 1);
        assertEq(newProposal.deadline, block.number + DEFAULT_VOTING_PERIOD);
        assertEq(newProposal.forVotes, 0);
        assertEq(newProposal.againstVotes, 0);
        assertEq(newProposal.executed, false);
        SimpleDAO.ProposalState state = _dao.getProposalState(0);
        assertEq(uint256(state), uint256(SimpleDAO.ProposalState.Active));
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ FETCHING PROPOSAL
    // ╚═══════════════════════════════════════════════════════════════════════
    function testCanNotFetchNonExistentProposal() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__ProposalDoesNotExist.selector, 0));
        _dao.getProposal(0);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ VOTING
    // ╚═══════════════════════════════════════════════════════════════════════
    function testCanNotVoteOnNonExistentProposal() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__ProposalDoesNotExist.selector, 0));
        _dao.vote(0, true);
    }

    function testCanNotVoteWithoutVotingPower() public withProposal {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__NoVotingPower.selector, bob));
        vm.prank(bob);
        _dao.vote(0, true);
    }

    function testCanNotVoteAfterVotingPeriod() public withProposal {
        uint256 currentBlock = block.number;

        vm.roll(currentBlock + DEFAULT_VOTING_PERIOD + 1); // Move to block after deadline

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleDAO.SDAO__VotingPeriodEnded.selector, 0, block.number, currentBlock + DEFAULT_VOTING_PERIOD
            )
        );
        vm.prank(alice);
        _dao.vote(0, true);
    }

    function testAnyValidUserCanVoteOnProposal() public withProposal {
        vm.prank(alice);
        _dao.vote(0, true);

        (SimpleDAO.Proposal memory proposal,) = _dao.getProposal(0);
        assertEq(proposal.forVotes, DEFAULT_VOTING_POWER);
        assertEq(proposal.againstVotes, 0);
    }

    function testCanNotVoteTwiceOnSameProposal() public withProposal {
        vm.prank(alice);
        _dao.vote(0, true);

        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__AlreadyVoted.selector, 0, alice));
        vm.prank(alice);
        _dao.vote(0, false);
    }

    function testTiedVotingResultsInFailedProposal()
        public
        withProposal
        withVoting(alice, true) // Alice votes FOR
        withVoting(charlie, false) // Charlie votes AGAINST
        withVotingCompleted
    {
        SimpleDAO.ProposalState state = _dao.getProposalState(0);
        assertEq(uint256(state), uint256(SimpleDAO.ProposalState.Failed));
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ EXECUTION
    // ╚═══════════════════════════════════════════════════════════════════════
    function testCanNotExecuteNonExistentProposal() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__ProposalDoesNotExist.selector, 0));
        _dao.executeProposal(0);
    }

    function testNonOwnerCanNotExecuteProposal()
        public
        withProposal
        withVoting(alice, true)
        withVoting(address(this), false)
        withVotingCompleted
    {
        vm.prank(alice);
        vm.expectRevert();
        _dao.executeProposal(0);
    }

    function testOnlyOwnerCanExecuteProposal()
        public
        withProposal
        withVoting(alice, false)
        withVoting(address(this), true)
        withVotingCompleted
    {
        _dao.executeProposal(0);
    }

    function testCanNotExecuteAnActiveProposal() public withProposal {
        (SimpleDAO.Proposal memory proposal,) = _dao.getProposal(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleDAO.SDAO__CanNotExecuteAnActiveProposal.selector, 0, block.number, proposal.deadline
            )
        );
        _dao.executeProposal(0);
    }

    function testCanExecuteProposalAfterVotingPeriod()
        public
        withProposal
        withVoting(alice, false)
        withVoting(address(this), true)
        withVotingCompleted
    {
        _dao.executeProposal(0);

        (SimpleDAO.Proposal memory proposal,) = _dao.getProposal(0);
        assertEq(proposal.executed, true);
    }

    /**
     * @notice The owner (this contract) votes AGAINST, while alice votes FOR.
     * Since the former has higher voting power than alice, the proposal will fail,
     * and the owner can NOT execute it after the voting period.
     */
    function testCanNotExecuteFailedProposal()
        public
        withProposal
        withVoting(alice, true) // Alice votes FOR
        withVoting(address(this), false) // This contract votes AGAINST
        withVotingCompleted
    {
        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__ProposalDidNotPass.selector, 0));
        _dao.executeProposal(0);
    }

    function testCanNotExecuteProposalTwice()
        public
        withProposal
        withVoting(alice, false)
        withVoting(address(this), true)
        withVotingCompleted
    {
        _dao.executeProposal(0);

        (SimpleDAO.Proposal memory proposal,) = _dao.getProposal(0);
        assertEq(proposal.executed, true);

        vm.expectRevert(abi.encodeWithSelector(SimpleDAO.SDAO__ProposalAlreadyExecuted.selector, 0));
        _dao.executeProposal(0);
    }
}

