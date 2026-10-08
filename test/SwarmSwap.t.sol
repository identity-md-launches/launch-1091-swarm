// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Swarm} from "../src/Swarm.sol";
import {SwarmSwap} from "../src/SwarmSwap.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

contract ReenteringTrader {
    SwarmSwap public router;
    Swarm public token;
    bool public reentrySucceeded;
    bool public rejectETH;

    constructor(SwarmSwap router_, Swarm token_) {
        router = router_;
        token = token_;
    }

    function sell(uint256 amount, bool reject) external {
        rejectETH = reject;
        token.approve(address(router), amount);
        router.swap(3000, 60, address(0), false, amount, 1, block.timestamp);
    }

    receive() external payable {
        require(!rejectETH, "reject ETH");
        (reentrySucceeded,) =
            address(router).call(abi.encodeCall(SwarmSwap.swap, (3000, 60, address(0), false, 1, 1, block.timestamp)));
    }
}

/// @dev Moves SWARM between two wallets through the PoolManager's ledger without touching any pool:
/// settle in, then take out or mint an ERC-6909 claim. Models a router's SETTLE + TAKE actions.
contract PassThroughCourier is IUnlockCallback {
    IPoolManager private immutable manager;
    Swarm private immutable token;
    address private sender;

    constructor(IPoolManager manager_, Swarm token_) {
        manager = manager_;
        token = token_;
    }

    function send(address to, uint256 amount, bool asClaim) external {
        sender = msg.sender;
        manager.unlock(abi.encode(to, amount, asClaim));
        sender = address(0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (address to, uint256 amount, bool asClaim) = abi.decode(data, (address, uint256, bool));
        Currency currency = Currency.wrap(address(token));
        manager.sync(currency);
        token.transferFrom(sender, address(manager), amount);
        require(manager.settle() == amount, "exact settlement");
        if (asClaim) manager.mint(to, currency.toId(), amount);
        else manager.take(currency, to, amount);
        return "";
    }
}

contract SwarmSwapTest is Test {
    Swarm token;
    SwarmSwap router;
    PoolManager manager;
    LaunchHarness factory;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address distributor = makeAddr("distributor");
    uint256 seedAmount;

    function setUp() public {
        vm.chainId(1);
        manager = new PoolManager(address(this));
        factory = new LaunchHarness(manager);
        token = factory.deploy();
        router = new SwarmSwap(token);
        factory.setDistributor(distributor);
        factory.move(distributor, token.totalSupply() / 10);
        seedAmount = factory.seed();
        factory.move(bob, token.balanceOf(address(factory)));
        vm.deal(alice, 20 ether);
    }

    function testLaunchEconomicsAndOpeningPrice() public view {
        uint256 poolBudget = token.totalSupply() * 8 / 10;
        assertLe(seedAmount, poolBudget);
        assertLt(poolBudget - seedAmount, 10_000);
        assertEq(token.balanceOf(distributor), 100_000_000 ether);
        assertEq(token.balanceOf(bob), token.totalSupply() - seedAmount - token.balanceOf(distributor));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(address(manager)), seedAmount);
        assertEq(address(manager).balance, 0);
        assertEq(token.totalBurned(), 0);
        (uint160 sqrtPrice,,,) = router.poolState(3000, 60, address(0));
        assertEq(sqrtPrice, factory.OPENING_PRICE());
        assertEq((uint256(1) << 192) * 1 ether / (uint256(sqrtPrice) * sqrtPrice), 10_000_000_000);
    }

    function _buy(uint256 amount) private returns (uint256) {
        vm.prank(alice);
        return router.swap{value: amount}(3000, 60, address(0), true, amount, 1, block.timestamp);
    }

    function testBuyThenSellRoundTrip() public {
        uint256 bought = _buy(0.01 ether);
        assertGt(bought, 0);
        assertEq(token.balanceOf(alice), bought);
        assertEq(alice.balance, 20 ether - 0.01 ether);
        vm.startPrank(alice);
        token.approve(address(router), bought);
        uint256 received = router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        vm.stopPrank();
        assertGt(received, 0);
        assertLt(received, 0.01 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, address(router)), 0);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
        assertEq(token.totalBurned(), 0);
        assertEq(alice.balance + address(manager).balance, 20 ether);
    }

    function testFuzzRoundTripAndConservation(uint96 input) public {
        uint256 amount = bound(uint256(input), 0.000001 ether, 1 ether);
        uint256 bought = _buy(amount);
        vm.startPrank(alice);
        token.approve(address(router), bought);
        uint256 received = router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        vm.stopPrank();
        assertLe(received, amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(manager)), seedAmount);
        assertEq(token.totalBurned(), 0);
        assertEq(alice.balance + address(manager).balance, 20 ether);
        assertEq(address(router).balance, 0);
    }

    function testWalletTransferAfterPurchaseBurns() public {
        uint256 bought = _buy(0.01 ether);
        uint256 beforeBob = token.balanceOf(bob);
        vm.prank(alice);
        token.transfer(bob, bought);
        assertEq(token.balanceOf(bob) - beforeBob, bought - bought / 100);
        assertEq(token.totalBurned(), bought / 100);
    }

    /// @dev Pins the documented limit of the burn: SWARM routed through the PoolManager's ledger
    /// (settle in, take out, or an ERC-6909 claim) is exempt in both directions, pool or no pool.
    /// This is the same exemption that lets a sell settle exactly; the README, SECURITY.md and the
    /// website state it. A change that makes this test fail changes the launch's settlement flows.
    function testPoolManagerPassThroughIsExemptAndDisclosed() public {
        uint256 bought = _buy(0.01 ether);
        PassThroughCourier courier = new PassThroughCourier(manager, token);
        address carol = makeAddr("carol");
        uint256 beforeBob = token.balanceOf(bob);
        uint256 beforeManager = token.balanceOf(address(manager));
        vm.startPrank(alice);
        token.approve(address(courier), bought);
        courier.send(bob, bought / 2, false);
        courier.send(carol, bought - bought / 2, true);
        vm.stopPrank();
        assertEq(token.balanceOf(bob) - beforeBob, bought / 2, "take delivered the gross amount");
        assertEq(manager.balanceOf(carol, Currency.wrap(address(token)).toId()), bought - bought / 2);
        assertEq(token.balanceOf(address(manager)) - beforeManager, bought - bought / 2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalBurned(), 0, "no burn applies to PoolManager settlement in either direction");
        // Leaving the manager's ledger for a wallet-to-wallet transfer pays the ordinary charge again.
        vm.prank(bob);
        token.transfer(carol, bought / 2);
        assertEq(token.totalBurned(), (bought / 2) / 100);
    }

    function testMinimumOutputFailureRollsBackPoolAndBalances() public {
        (uint160 beforePrice,,,) = router.poolState(3000, 60, address(0));
        uint256 minimum = token.totalSupply();
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.InsufficientOutput.selector);
        router.swap{value: 0.01 ether}(3000, 60, address(0), true, 0.01 ether, minimum, block.timestamp);
        (uint160 afterPrice,,,) = router.poolState(3000, 60, address(0));
        assertEq(afterPrice, beforePrice);
        assertEq(alice.balance, 20 ether);
        assertEq(address(router).balance, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testExpiredSwap() public {
        vm.warp(100);
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.Expired.selector);
        router.swap{value: 1 ether}(3000, 60, address(0), true, 1 ether, 1, 99);
    }

    function testRejectsIncorrectValueZeroAndOversizedInput() public {
        vm.startPrank(alice);
        vm.expectRevert(SwarmSwap.IncorrectValue.selector);
        router.swap(3000, 60, address(0), true, 1 ether, 1, block.timestamp);
        vm.expectRevert(SwarmSwap.IncorrectValue.selector);
        router.swap{value: 1}(3000, 60, address(0), false, 1 ether, 1, block.timestamp);
        vm.expectRevert(SwarmSwap.InvalidAmount.selector);
        router.swap(3000, 60, address(0), false, 0, 1, block.timestamp);
        vm.expectRevert(SwarmSwap.InvalidAmount.selector);
        router.swap(3000, 60, address(0), false, 1, 0, block.timestamp);
        vm.expectRevert(SwarmSwap.InvalidAmount.selector);
        router.swap(3000, 60, address(0), false, type(uint256).max, 1, block.timestamp);
        vm.stopPrank();
    }

    function testCallbackCannotBeForged() public {
        vm.expectRevert(SwarmSwap.UnauthorizedCallback.selector);
        router.unlockCallback("");
        vm.prank(address(manager));
        vm.expectRevert(SwarmSwap.UnauthorizedCallback.selector);
        router.unlockCallback("");
    }

    function testCannotSellWithoutApprovalOrUseAnotherTradersApproval() public {
        uint256 bought = _buy(0.01 ether);
        vm.prank(alice);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        vm.prank(alice);
        token.approve(address(router), bought);
        vm.prank(bob);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        assertEq(token.balanceOf(alice), bought);
        assertEq(token.allowance(alice, address(router)), bought);
    }

    function testPartialFillRevertsInsteadOfKeepingInput() public {
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.PartialFill.selector);
        router.swap(3000, 60, address(0), false, 1 ether, 1, block.timestamp);
        assertEq(address(router).balance, 0);
    }

    function testInvalidAndUninitializedPoolsRevert() public {
        vm.expectRevert(SwarmSwap.InvalidPool.selector);
        router.poolState(3000, 0, address(0));
        vm.expectRevert(SwarmSwap.InvalidPool.selector);
        router.poolState(1_000_001, 60, address(0));
        vm.prank(alice);
        vm.expectRevert();
        router.swap{value: 1 ether}(500, 10, address(0), true, 1 ether, 1, block.timestamp);
    }

    function testRejectingReceiverRollsBackSale() public {
        uint256 bought = _buy(0.01 ether);
        ReenteringTrader trader = new ReenteringTrader(router, token);
        vm.prank(alice);
        token.transfer(address(trader), bought);
        uint256 held = token.balanceOf(address(trader));
        vm.expectRevert();
        trader.sell(held, true);
        assertEq(token.balanceOf(address(trader)), held);
        assertEq(address(router).balance, 0);
    }

    function testETHRecipientCannotReenterSwap() public {
        uint256 bought = _buy(0.01 ether);
        ReenteringTrader trader = new ReenteringTrader(router, token);
        vm.prank(alice);
        token.transfer(address(trader), bought);
        trader.sell(token.balanceOf(address(trader)), false);
        assertFalse(trader.reentrySucceeded());
        assertGt(address(trader).balance, 0);
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(address(router).balance, 0);
    }
}
