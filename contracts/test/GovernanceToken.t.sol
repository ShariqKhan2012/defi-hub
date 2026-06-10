//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {GovernanceTokenDeployer} from "../script/GovernanceTokenDeployer.s.sol";

contract GovernanceTokenTest is Test {
    uint256 public constant DECIMAL_PRECISION = 18;
    uint256 public constant MINT_AMOUNT_IN_WEI = 5000 * (10 ** DECIMAL_PRECISION); // 5000 GTK
    uint256 public constant FAUCET_CLAIM_AMOUNT_IN_WEI = 3000 * (10 ** DECIMAL_PRECISION); // 3000 GTK
    uint256 public constant TRANSFER_AMOUNT_IN_WEI = 1000 * (10 ** DECIMAL_PRECISION); // 1000 GTK

    address DEFAULT_SENDER_ADDRESS;
    GovernanceToken private _gtk;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        DEFAULT_SENDER_ADDRESS = vm.envAddress("ANVIL_DEPLOYER_ACCOUNT");
        GovernanceTokenDeployer deployer = new GovernanceTokenDeployer();
        _gtk = deployer.run();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ DEPLOYMENT
    // ╚═══════════════════════════════════════════════════════════════════════
    function testGTKDeployment() public view {
        assert(address(_gtk) != address(0));

        string memory symbol = _gtk.symbol();
        assertEq(symbol, "GTK");

        string memory name = _gtk.name();
        assertEq(name, "Governance Token");
    }

    /**
     * @notice Tests that the owner of the GovernanceToken contract is correctly
     * set to the deployer.
     * @dev msg.sender inside startBroadcast() is the broadcaster — the wallet whose
     * private key is passed via --private-key or PRIVATE_KEY in .env. So the owner is
     * actually the wallet, not the script contract.
     * Foundry's vm.startBroadcast() makes all subsequent calls appear to come from
     * our wallet, not from the script contract itself.
     */
    function testOwnership() public view {
        address owner = _gtk.owner();
        assertEq(owner, msg.sender);
        assertEq(owner, DEFAULT_SENDER_ADDRESS);
    }

    function testInitialSupply() public view {
        uint256 initialSupply = _gtk.totalSupply();
        assertEq(initialSupply, 1_000_000 * 10 ** 18);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ MINTING
    // ╚═══════════════════════════════════════════════════════════════════════
    function testNonOwnerCanNotMintTokens() public {
        uint256 initialBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(initialBalanceOfAlice, 0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);
        uint256 finalBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(finalBalanceOfAlice, initialBalanceOfAlice);
    }

    function testOwnerCanMintTokens() public {
        uint256 initialBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(initialBalanceOfAlice, 0);
        /**
         * Since the mint function can only be called y the owner, and
         * the owner is the wallet, we have to prank the `mint` call
         */
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);
        uint256 finalBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(finalBalanceOfAlice, MINT_AMOUNT_IN_WEI);
    }

    function testMinEmitsTransferEvent() public {
        /**
         * When using expectEmit, we can chose to match some, or all topics.
         * For that we need to pass true for the indexed topics that we need
         * to check.
         * Or, we can ignore all the topics, and only care that the event was emitted.
         * In that case, we pass false for all arguments i.e.
         * vm.expectEmit(false, false, false, false)
         */
        vm.expectEmit(true, true, true, true); // Natch all parameters. Equivalent to vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, MINT_AMOUNT_IN_WEI);

        /**
         * Since the mint function can only be called y the owner, and
         * the owner is the wallet, we have to prank the `mint` call
         */
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ FAUCET
    // ╚═══════════════════════════════════════════════════════════════════════
    function testAnyoneCanUseFaucet() public {
        uint256 initialBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(initialBalanceOfAlice, 0);
        vm.prank(alice);
        _gtk.faucet();
        uint256 finalBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(finalBalanceOfAlice, FAUCET_CLAIM_AMOUNT_IN_WEI);
    }

    function testCanNotReuseFaucetBefore24Hours() public {
        vm.prank(alice);
        _gtk.faucet();
        uint256 finalBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(finalBalanceOfAlice, FAUCET_CLAIM_AMOUNT_IN_WEI);
        //Simulate passing of 23 hours, 59 minutes, and 59 seconds
        vm.warp(block.timestamp + 23 hours + 59 minutes + 59 seconds);

        vm.expectRevert(GovernanceToken.GTK__FaucetUsedBefore24Hours.selector);
        vm.prank(alice);
        _gtk.faucet();
        uint256 updatedFinalBalanceOfAlice = _gtk.balanceOf(alice);
        // The final balance should still be the amount received in the first attempt
        assertEq(updatedFinalBalanceOfAlice, finalBalanceOfAlice);
    }

    function testCanReuseFaucetAfter24Hours() public {
        vm.prank(alice);
        _gtk.faucet();
        uint256 finalBalanceOfAlice = _gtk.balanceOf(alice);
        assertEq(finalBalanceOfAlice, FAUCET_CLAIM_AMOUNT_IN_WEI);
        //Simulate passing of
        vm.warp(block.timestamp + 23 hours + 59 minutes + 60 seconds);
        vm.prank(alice);
        _gtk.faucet();

        uint256 updatedFinalBalanceOfAlice = _gtk.balanceOf(alice);

        /**
         * The final balance should be the sum of the amounts received in the
         * first and second attempts
         */
        assertEq(updatedFinalBalanceOfAlice, 2 * finalBalanceOfAlice);
    }

    function testUsingFaucetEmitsUsageEvent() public {
        vm.prank(alice);
        vm.expectEmit();
        emit GovernanceToken.GTK__FaucetUsed(alice);
        _gtk.faucet();
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ DELEGATION & VOTING POWER
    // ╚═══════════════════════════════════════════════════════════════════════
    function testVotingPowerIsZeroBeforeDelegation() public view {
        uint256 votingPowerOfAliceBeforeDelegation = _gtk.getVotes(alice);
        assertEq(votingPowerOfAliceBeforeDelegation, 0);
    }

    function testVotingPowerChangesAfterDelegation() public {
        uint256 votingPowerOfAliceBeforeDelegation = _gtk.getVotes(alice);
        assertEq(votingPowerOfAliceBeforeDelegation, 0);

        vm.prank(alice);
        _gtk.faucet();
        uint256 votingPowerOfAliceAfterDelegation = _gtk.getVotes(alice);
        assertEq(votingPowerOfAliceAfterDelegation, FAUCET_CLAIM_AMOUNT_IN_WEI);
    }

    function testAutoDelegatesToUserOnMint() public {
        address delegateeOfAliceBeforeMint = _gtk.delegates(alice);
        assertEq(delegateeOfAliceBeforeMint, address(0));
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);
        address delegateeOfAliceAfterMint = _gtk.delegates(alice);
        assertEq(delegateeOfAliceAfterMint, alice);
    }

    function testAutoDelegatesToUserOnUsingFaucet() public {
        address delegateeOfAliceBeforeMint = _gtk.delegates(alice);
        assertEq(delegateeOfAliceBeforeMint, address(0));
        vm.prank(alice);
        _gtk.faucet();
        address delegateeOfAliceAfterMint = _gtk.delegates(alice);
        assertEq(delegateeOfAliceAfterMint, alice);
    }

    function testTransferUpdatesVotingPowerOfSenderAndRecepient() public {
        vm.startPrank(alice);
        _gtk.faucet();

        uint256 votingPowerOfAliceBeforeTransfer = _gtk.getVotes(alice);
        uint256 votingPowerOfBobBeforeTransfer = _gtk.getVotes(bob);
        assertEq(votingPowerOfAliceBeforeTransfer, FAUCET_CLAIM_AMOUNT_IN_WEI);
        assertEq(votingPowerOfBobBeforeTransfer, 0);
        (bool success) = _gtk.transfer(bob, TRANSFER_AMOUNT_IN_WEI);
        assertTrue(success); //Confirm transfer was successful
        vm.stopPrank();
        //Since transfer does not auto-delegate, we need to do it explicityly
        vm.prank(bob);
        _gtk.delegate(bob);
        uint256 votingPowerOfAliceAfterTransfer = _gtk.getVotes(alice);
        uint256 votingPowerOfBobAfterTransfer = _gtk.getVotes(bob);
        assertEq(votingPowerOfAliceAfterTransfer, (FAUCET_CLAIM_AMOUNT_IN_WEI - TRANSFER_AMOUNT_IN_WEI));
        assertEq(votingPowerOfBobAfterTransfer, TRANSFER_AMOUNT_IN_WEI);
    }

    // ╔═══════════════════════════════════════════════════════════════════════
    // ║ CHECKPOINTS
    // ╚═══════════════════════════════════════════════════════════════════════
    function testCannotQueryCurrentBlock() public {
        vm.expectRevert();
        _gtk.getPastVotes(alice, block.number); // must be strictly past
    }

    function testCheckpointIsCreatedOnMinting() public {
        uint256 mintBlock = block.number;

        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);

        /**
         * Advance one block ahead, so that mintBlock is
         * now in the past, and we can check past snapshot
         */
        vm.roll(mintBlock + 1);
        assertEq(_gtk.getPastVotes(alice, mintBlock), MINT_AMOUNT_IN_WEI);
    }

    function testCheckpointIsCreatedOnUsingFaucet() public {
        uint256 mintBlock = block.number;

        vm.prank(alice);
        _gtk.faucet();

        /**
         * Advance one block ahead, so that mintBlock is
         * now in the past, and we can check past snapshot
         */
        vm.roll(mintBlock + 1);
        assertEq(_gtk.getPastVotes(alice, mintBlock), FAUCET_CLAIM_AMOUNT_IN_WEI);
    }

    function testCheckpointUpdatesOnTransfer() public {
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);

        uint256 snapshotBlock = block.number;
        vm.roll(snapshotBlock + 1);

        vm.prank(alice);
        _gtk.transfer(bob, TRANSFER_AMOUNT_IN_WEI);
        //Since transfer does not auto-delegate, we need to do it explicityly
        vm.prank(bob);
        _gtk.delegate(bob);

        vm.roll(block.number + 1);

        // At snapshot, alice had MINT_AMOUNT_IN_WEI
        assertEq(_gtk.getPastVotes(alice, snapshotBlock), MINT_AMOUNT_IN_WEI);
        // At snapshot, bob had none
        assertEq(_gtk.getPastVotes(bob, snapshotBlock), 0);

        // Now alice has (MINT_AMOUNT_IN_WEI - TRANSFER_AMOUNT_IN_WEI),
        assertEq(_gtk.getVotes(alice), MINT_AMOUNT_IN_WEI - TRANSFER_AMOUNT_IN_WEI);
        // Now bob has TRANSFER_AMOUNT_IN_WEI
        assertEq(_gtk.getVotes(bob), TRANSFER_AMOUNT_IN_WEI);
    }

    function testPastVotesReflectSnapshotNotCurrentBalance() public {
        uint256 initialBlock = block.number;
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);

        // Move one block ahead
        uint256 nextBlock = initialBlock + 1;
        vm.roll(nextBlock);
        vm.prank(DEFAULT_SENDER_ADDRESS);
        _gtk.mint(alice, MINT_AMOUNT_IN_WEI);

        // Move one block ahead
        uint256 nextToNextBlock = nextBlock + 1;
        vm.roll(nextToNextBlock);
        vm.prank(alice);
        _gtk.transfer(bob, TRANSFER_AMOUNT_IN_WEI);

        assertEq(_gtk.getPastVotes(alice, initialBlock), MINT_AMOUNT_IN_WEI);
        assertEq(_gtk.getPastVotes(alice, nextBlock), 2 * MINT_AMOUNT_IN_WEI);

        // Roll forward because we can not query snapshot at the current block
        vm.roll(nextToNextBlock + 1);
        assertEq(_gtk.getPastVotes(alice, nextToNextBlock), (2 * MINT_AMOUNT_IN_WEI) - TRANSFER_AMOUNT_IN_WEI);
    }
}
