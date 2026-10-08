// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Swarm} from "../src/Swarm.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract ManagerCode {}

contract SwarmTest is Test {
    Swarm token;
    LaunchHarness factory;
    address manager;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");
    address distributor = makeAddr("distributor");
    uint256 constant SUPPLY = 1_000_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.chainId(1);
        manager = address(new ManagerCode());
        factory = new LaunchHarness(IPoolManager(manager));
        token = factory.deploy();
        factory.setDistributor(distributor);
    }

    function testMetadataAndConstructorMint() public view {
        assertEq(token.name(), "swarm");
        assertEq(token.symbol(), "SWARM");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.totalBurned(), 0);
    }

    function testRejectsWrongChain() public {
        vm.chainId(8453);
        vm.expectRevert(Swarm.MainnetOnly.selector);
        factory.deploy();
    }

    function testRejectsWrongFactoryAndMissingManager() public {
        vm.expectRevert(Swarm.InvalidLaunchConfiguration.selector);
        new Swarm(address(factory), manager, 7);
        vm.expectRevert(Swarm.InvalidLaunchConfiguration.selector);
        new Swarm(address(this), alice, 7);
        vm.expectRevert(Swarm.InvalidLaunchConfiguration.selector);
        new Swarm(address(this), address(this), 7);
    }

    function testTransferBurnAndEvents() public {
        factory.move(alice, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, token.DEAD(), 1 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 99 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 99 ether);
        assertEq(token.balanceOf(token.DEAD()), 1 ether);
        assertEq(token.totalBurned(), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferConservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        factory.move(alice, amount);
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(bob), amount - amount / 100);
        assertEq(token.totalBurned(), amount / 100);
        assertEq(token.balanceOf(token.DEAD()), amount / 100);
        assertEq(token.balanceOf(address(factory)) + token.balanceOf(bob) + token.balanceOf(token.DEAD()), SUPPLY);
    }

    function testRoundingZeroAndSelfTransfers() public {
        factory.move(alice, 10_000);
        vm.startPrank(alice);
        token.transfer(bob, 0);
        token.transfer(bob, 99);
        assertEq(token.totalBurned(), 0);
        token.transfer(bob, 101);
        assertEq(token.totalBurned(), 1);
        token.transfer(alice, 1000);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 9790);
        assertEq(token.balanceOf(bob), 199);
        assertEq(token.totalBurned(), 11);
    }

    function testSelfTransferStillRequiresGrossBalance() public {
        factory.move(alice, 99);
        vm.prank(alice);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transfer(alice, 100);
        assertEq(token.balanceOf(alice), 99);
        assertEq(token.totalBurned(), 0);
    }

    function testTransferFromSpendsGrossAllowance() public {
        factory.move(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 99 ether);
        assertEq(token.totalBurned(), 1 ether);
    }

    function testInfiniteAllowanceAndRevocation() public {
        factory.move(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        vm.prank(alice);
        token.approve(spender, 0);
        vm.prank(spender);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.transferFrom(alice, bob, 1);
    }

    function testInsufficientBalanceRevertsAtomically() public {
        factory.move(alice, 100);
        vm.prank(alice);
        token.approve(spender, 101);
        vm.prank(spender);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transferFrom(alice, bob, 101);
        assertEq(token.allowance(alice, spender), 101);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalBurned(), 0);
    }

    function testRejectsZeroRecipientAndSpender() public {
        factory.move(alice, 100 ether);
        vm.startPrank(alice);
        vm.expectPartialRevert(IERC20Errors.ERC20InvalidReceiver.selector);
        token.transfer(address(0), 1 ether);
        vm.expectPartialRevert(IERC20Errors.ERC20InvalidSpender.selector);
        token.approve(address(0), 1 ether);
        vm.stopPrank();
        assertEq(token.totalBurned(), 0);
    }

    function testLaunchAndClaimArriveWhole() public {
        factory.move(distributor, SUPPLY / 10);
        vm.prank(distributor);
        token.transfer(alice, SUPPLY / 10);
        factory.move(bob, SUPPLY / 10);
        assertEq(token.balanceOf(alice), SUPPLY / 10);
        assertEq(token.balanceOf(bob), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalBurned(), 0);
    }

    function testPoolManagerTransfersInBothDirectionsArriveWhole() public {
        factory.move(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(alice, manager, 100 ether);
        vm.prank(manager);
        token.transfer(bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalBurned(), 0);
    }

    function testTransfersToFactoryAndDistributorAreNotExempt() public {
        factory.move(alice, 200 ether);
        vm.startPrank(alice);
        token.transfer(address(factory), 100 ether);
        token.transfer(distributor, 100 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(distributor), 99 ether);
        assertEq(token.totalBurned(), 2 ether);
    }

    function testThirdPartyCannotBorrowDistributorExemption() public {
        factory.move(distributor, 100 ether);
        vm.prank(distributor);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(distributor, bob, 100 ether);
        assertEq(token.balanceOf(bob), 99 ether);
    }

    function testRegistryFailureAndMalformedAddressDoNotFreezeTransfers() public {
        factory.move(alice, 600 ether);
        for (uint256 mode; mode < 6; ++mode) {
            factory.setRegistryMode(mode);
            if (mode == 0) factory.setDistributor(address(0));
            vm.prank(alice);
            token.transfer(bob, 100 ether);
        }
        assertEq(token.balanceOf(bob), 594 ether);
        assertEq(token.totalBurned(), 6 ether);
    }

    function testRuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
            }
        }
    }

    function testVoluntaryDeadTransferOnlyCountsAutomaticCharge() public {
        factory.move(alice, 100 ether);
        address dead = token.DEAD();
        vm.prank(alice);
        token.transfer(dead, 100 ether);
        assertEq(token.balanceOf(token.DEAD()), 100 ether);
        assertEq(token.totalBurned(), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintOrAdministrativeEntryPoints() public {
        factory.move(alice, 100 ether);
        string[9] memory signatures = [
            "mint(address,uint256)",
            "pause()",
            "blacklist(address)",
            "burnFrom(address,uint256)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "setExempt(address,bool)",
            "setMinter(address)",
            "owner()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            vm.prank(address(factory));
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], alice, 100 ether));
            assertFalse(ok);
        }
        vm.prank(address(factory));
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(alice);
        token.transfer(bob, 100 ether);
        assertEq(token.balanceOf(bob), 99 ether);
    }
}
