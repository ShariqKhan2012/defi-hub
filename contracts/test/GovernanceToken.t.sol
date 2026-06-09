//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {GovernanceTokenDeployer} from "../script/GovernanceTokenDeployer.s.sol";

contract GovernanceTokenTest is Test {
    address DEFAULT_ADDRESS;
    GovernanceToken private _gtk;
    address ALICE = makeAddr("ALICE");
    address BOB = makeAddr("BOB");

    function setUp() public {
        DEFAULT_ADDRESS = vm.envAddress("ANVIL_DEPLOYER_ACCOUNT");
        GovernanceTokenDeployer deployer = new GovernanceTokenDeployer();
        _gtk = deployer.run();
    }

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
        assertEq(owner, DEFAULT_ADDRESS);
    }

    function testInitialSupply() public view {
        uint256 initialSupply = _gtk.totalSupply();
        assertEq(initialSupply, 1_000_000 * 10 ** 18);
    }

    function testNonOwnerCanNotMintTokens() public {
        uint256 initialBalanceOfAlice = _gtk.balanceOf(ALICE);
        assertEq(initialBalanceOfAlice, 0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _gtk.mint(ALICE, 1000);
        uint256 finalBalanceOfAlice = _gtk.balanceOf(ALICE);
        assertEq(finalBalanceOfAlice, initialBalanceOfAlice);
    }

    function testOwnerCanMintTokens() public {
        uint256 initialBalanceOfAlice = _gtk.balanceOf(ALICE);
        assertEq(initialBalanceOfAlice, 0);
        /**
         * Since the mint function can only be called y the owner, and
         * the owner is the wallet, we have to prank the `mint` call
         */
        vm.prank(DEFAULT_ADDRESS);
        _gtk.mint(ALICE, 1000);
        uint256 finalBalanceOfAlice = _gtk.balanceOf(ALICE);
        assertEq(finalBalanceOfAlice, 1000);
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
        emit IERC20.Transfer(address(0), ALICE, 1000);

        /**
         * Since the mint function can only be called y the owner, and
         * the owner is the wallet, we have to prank the `mint` call
         */
        vm.prank(DEFAULT_ADDRESS);

        _gtk.mint(ALICE, 1000);
    }
}
