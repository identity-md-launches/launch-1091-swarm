// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Swarm} from "src/Swarm.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

contract EdgeManagerCode {}

/// forge-config: default.fuzz.runs = 1000
contract SwarmEdgesTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;
    Swarm token;
    LaunchHarness factory;
    address manager;
    address alice = makeAddr("edge alice");
    address bob = makeAddr("edge bob");
    address spender = makeAddr("edge spender");
    address distributor = makeAddr("edge distributor");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.chainId(1);
        manager = address(new EdgeManagerCode());
        factory = new LaunchHarness(IPoolManager(manager));
        token = factory.deploy();
        factory.setDistributor(distributor);
    }

    function testPinnedBurnBoundariesIncludingFullSupply() public {
        uint256[8] memory amounts = [uint256(0), 1, 99, 100, 101, 199, 200, SUPPLY];
        uint256[8] memory fees = [uint256(0), 0, 0, 1, 1, 1, 2, 10_000_000 ether];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            factory.move(alice, amounts[i]);
            vm.prank(alice);
            assertTrue(token.transfer(bob, amounts[i]));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), amounts[i] - fees[i]);
            assertEq(token.balanceOf(token.DEAD()), fees[i]);
            assertEq(token.totalBurned(), fees[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function testZeroTransferFromWithoutApprovalEmitsTransferAndChangesNothing() public {
        bytes32 beforeState = _state();
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(_state(), beforeState);
    }

    function testFuzzSelfTransferFromChargesBurnAndGrossAllowance(uint256 amountSeed, bool infinite) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        factory.move(alice, amount);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), amount - amount / 100);
        assertEq(token.totalBurned(), amount / 100);
        assertEq(token.balanceOf(token.DEAD()), amount / 100);
        assertEq(token.allowance(alice, spender), infinite ? approved : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApprovalOverwriteAndPartialSpending(uint256 approvalSeed, uint256 spendSeed) public {
        uint256 approved = bound(approvalSeed, 1, SUPPLY);
        uint256 spent = bound(spendSeed, 0, approved);
        factory.move(alice, SUPPLY);
        vm.startPrank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, approved);
        assertTrue(token.approve(spender, approved));
        vm.stopPrank();
        vm.prank(spender);
        token.transferFrom(alice, bob, spent);
        assertEq(token.allowance(alice, spender), approved - spent);
        assertEq(token.balanceOf(alice), SUPPLY - spent);
        assertEq(token.balanceOf(bob), spent - spent / 100);
        vm.prank(alice);
        token.approve(spender, 0);
        bytes32 beforeState = _state();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(_state(), beforeState);
    }

    function testFuzzInsufficientGrossAllowanceIsAtomic(uint256 seed) public {
        uint256 amount = bound(seed, 100, SUPPLY);
        factory.move(alice, amount);
        // Approval of the net receipt must not authorize the larger gross debit.
        uint256 approved = amount - amount / 100;
        vm.prank(alice);
        token.approve(spender, approved);
        bytes32 beforeState = _state();
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        token.transferFrom(alice, bob, amount);
        assertEq(_state(), beforeState);
    }

    function testFuzzOverdrawRollsBackBurnAndFiniteAllowance(uint256 balanceSeed, uint256 excessSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = balance + bound(excessSeed, 1, SUPPLY);
        factory.move(alice, balance);
        vm.prank(alice);
        token.approve(spender, amount);
        bytes32 beforeState = _state();
        vm.prank(spender);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transferFrom(alice, bob, amount);
        assertEq(_state(), beforeState);
    }

    function testMaximumTransferAndTransferFromRevertWithoutOverflowOrStateChange() public {
        factory.move(alice, SUPPLY);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transfer(bob, type(uint256).max);
        assertEq(_state(), beforeState);
        vm.prank(spender);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(_state(), beforeState);
    }

    function testZeroAddressesRemainInvalidForZeroAmountsAndApprovedTransfers() public {
        factory.move(alice, 100);
        vm.prank(alice);
        token.approve(spender, 100);
        bytes32 beforeState = _state();
        vm.startPrank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 100);
        // transferFrom validates the allowance owner before reaching _transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), bob, 0);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.stopPrank();
        assertEq(_state(), beforeState);
    }

    function testAllExemptRolesStillNeedAllowanceAndGrossBalance() public {
        factory.move(alice, 100);
        address[3] memory roles = [address(factory), manager, distributor];
        for (uint256 i; i < roles.length; ++i) {
            vm.prank(roles[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, roles[i], 0, 1));
            token.transferFrom(alice, manager, 1);
            vm.prank(alice);
            token.approve(roles[i], 101);
            vm.prank(roles[i]);
            vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
            token.transferFrom(alice, manager, 101);
            assertEq(token.allowance(alice, roles[i]), 101);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(manager), 0);
            assertEq(token.totalBurned(), 0);
        }
    }

    function testRegistryUsesExactLaunchNumberAndRejectsShortOrDirtyResponses() public {
        factory.move(alice, 400);
        bytes memory lookup = abi.encodeWithSignature("distributorOf(uint64)", factory.NUMBER());
        vm.expectCall(address(factory), lookup);
        vm.prank(alice);
        token.transfer(bob, 100);
        // A truncated word and a noncanonical ABI address must not grant alice an exemption.
        vm.mockCall(address(factory), lookup, abi.encodePacked(bytes31(uint248(uint160(alice)))));
        vm.prank(alice);
        token.transfer(bob, 100);
        vm.mockCall(address(factory), lookup, abi.encode((uint256(1) << 160) | uint160(alice)));
        vm.prank(alice);
        token.transfer(bob, 100);
        vm.mockCall(address(factory), lookup, abi.encode(alice, uint256(0)));
        vm.prank(alice);
        token.transfer(bob, 100);
        vm.clearMockedCalls();
        assertEq(token.balanceOf(bob), 396);
        assertEq(token.totalBurned(), 4);
    }

    function testConstructorRejectsCodeAtDeadAndFactoryWithoutCode() public {
        address dead = token.DEAD();
        vm.etch(dead, address(manager).code);
        vm.expectRevert(Swarm.InvalidLaunchConfiguration.selector);
        new Swarm(address(this), dead, 0);
        vm.prank(alice);
        vm.expectRevert(Swarm.InvalidLaunchConfiguration.selector);
        new Swarm(alice, manager, type(uint64).max);
    }

    function testFuzzConstructorRejectsEveryNonMainnetChain(uint64 seed) public {
        uint256 chain = seed == 1 ? 0 : uint256(seed);
        vm.chainId(chain);
        vm.expectRevert(Swarm.MainnetOnly.selector);
        factory.deploy();
    }

    function _state() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                token.totalSupply(),
                token.totalBurned(),
                token.balanceOf(alice),
                token.balanceOf(bob),
                token.balanceOf(token.DEAD()),
                token.balanceOf(address(factory)),
                token.allowance(alice, spender)
            )
        );
    }
}
