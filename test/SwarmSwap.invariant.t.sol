// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Swarm} from "src/Swarm.sol";
import {SwarmSwap} from "src/SwarmSwap.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

/// @dev Trades use real v4 accounting, no mocked reserves, forks or mid-sequence funding.
contract SwarmMarketHandler is Test {
    Swarm public immutable token;
    SwarmSwap public immutable router;
    address public immutable manager;
    address[3] public actors;
    mapping(address => uint256) public expectedTokens;
    mapping(address => uint256) public expectedETH;
    mapping(address => uint256) public expectedAllowance;
    uint256 public boughtTokens;
    uint256 public soldTokens;
    uint256 public paidETH;
    uint256 public receivedETH;
    uint256 public expectedBurned;

    constructor(Swarm token_, SwarmSwap router_) {
        token = token_;
        router = router_;
        manager = address(router_.manager());
        for (uint256 i; i < 3; ++i) {
            actors[i] = makeAddr(string.concat("market trader ", vm.toString(i)));
            expectedETH[actors[i]] = 20 ether;
        }
    }

    function buy(uint256 actorSeed, uint256 amountSeed) public {
        address actor = actors[actorSeed % 3];
        // At depth 96 even 96 maximum buys from one account cost less than its initial ETH.
        uint256 amount = bound(amountSeed, 0.000001 ether, 0.05 ether);
        _buy(actor, amount);
    }

    function sell(uint256 actorSeed, uint256 amountSeed, bool infiniteApproval) public {
        address actor = actors[actorSeed % 3];
        uint256 balance = expectedTokens[actor];
        // Below this size output may round to zero; the unit suite covers dust rejection.
        if (balance < 1e12) return;
        uint256 amount = bound(amountSeed, 1e12, balance);
        _sell(actor, amount, infiniteApproval);
    }

    function walletTransfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        uint256 amount = bound(amountSeed, 0, expectedTokens[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedTokens[from] -= amount;
        expectedTokens[to] += amount - amount / 100;
        expectedBurned += amount / 100;
    }

    function roundTrip(uint256 actorSeed, uint256 amountSeed) public {
        address actor = actors[actorSeed % 3];
        uint256 amount = bound(amountSeed, 0.000001 ether, 0.05 ether);
        uint256 tokensBefore = token.balanceOf(actor);
        uint256 ethBefore = actor.balance;
        uint256 bought = _buy(actor, amount);
        uint256 returnedETH = _sell(actor, bought, false);
        assertLe(returnedETH, amount, "immediate round trip created ETH");
        assertLe(actor.balance, ethBefore);
        assertEq(token.balanceOf(actor), tokensBefore);
    }

    function rejectSlippage(uint256 actorSeed, uint256 amountSeed) public {
        address actor = actors[actorSeed % 3];
        uint256 amount = bound(amountSeed, 0.000001 ether, 0.05 ether);
        bytes32 beforeState = _marketState(actor);
        vm.prank(actor);
        vm.expectRevert(SwarmSwap.InsufficientOutput.selector);
        router.swap{value: amount}(3000, 60, address(0), true, amount, 1_000_000_000 ether, block.timestamp);
        assertEq(_marketState(actor), beforeState, "failed buy changed market state");
    }

    function revokeAndRejectSale(uint256 actorSeed) public {
        address actor = actors[actorSeed % 3];
        if (expectedTokens[actor] < 1e12) return;
        vm.prank(actor);
        token.approve(address(router), 0);
        expectedAllowance[actor] = 0;
        bytes32 beforeState = _marketState(actor);
        vm.prank(actor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(router), 0, expectedTokens[actor]
            )
        );
        router.swap(3000, 60, address(0), false, expectedTokens[actor], 1, block.timestamp);
        assertEq(_marketState(actor), beforeState, "failed sale changed market state");
    }

    function _buy(address actor, uint256 amount) private returns (uint256 out) {
        vm.prank(actor);
        out = router.swap{value: amount}(3000, 60, address(0), true, amount, 1, block.timestamp);
        assertGt(out, 0);
        expectedETH[actor] -= amount;
        expectedTokens[actor] += out;
        paidETH += amount;
        boughtTokens += out;
        // Verify the returned quote against actual receipts, not just cumulative totals.
        assertEq(token.balanceOf(actor), expectedTokens[actor]);
        assertEq(actor.balance, expectedETH[actor]);
    }

    function _sell(address actor, uint256 amount, bool infiniteApproval) private returns (uint256 out) {
        uint256 approval = infiniteApproval ? type(uint256).max : amount;
        vm.startPrank(actor);
        token.approve(address(router), approval);
        out = router.swap(3000, 60, address(0), false, amount, 1, block.timestamp);
        vm.stopPrank();
        assertGt(out, 0);
        expectedTokens[actor] -= amount;
        expectedETH[actor] += out;
        expectedAllowance[actor] = infiniteApproval ? approval : 0;
        soldTokens += amount;
        receivedETH += out;
        assertEq(token.balanceOf(actor), expectedTokens[actor]);
        assertEq(actor.balance, expectedETH[actor]);
        assertEq(token.allowance(actor, address(router)), expectedAllowance[actor]);
    }

    function _marketState(address actor) private view returns (bytes32) {
        (uint160 price, int24 tick, uint24 protocolFee, uint24 lpFee) = router.poolState(3000, 60, address(0));
        bytes32 poolState = keccak256(abi.encode(price, tick, protocolFee, lpFee));
        bytes32 balances = keccak256(
            abi.encode(
                actor.balance, manager.balance, token.balanceOf(actor), token.balanceOf(manager), token.totalBurned()
            )
        );
        return keccak256(
            abi.encode(
                poolState,
                balances,
                token.allowance(actor, address(router)),
                address(router).balance,
                token.balanceOf(address(router))
            )
        );
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmMarketInvariantTest is StdInvariant, Test {
    Swarm token;
    SwarmSwap router;
    PoolManager manager;
    LaunchHarness factory;
    SwarmMarketHandler handler;
    address distributor = makeAddr("market distributor");
    address remainder = makeAddr("market remainder");
    uint256 seedAmount;

    function setUp() public {
        vm.chainId(1);
        manager = new PoolManager(address(this));
        factory = new LaunchHarness(manager);
        token = factory.deploy();
        router = new SwarmSwap(token);
        factory.setDistributor(distributor);
        factory.move(distributor, 100_000_000 ether);
        seedAmount = factory.seed();
        factory.move(remainder, 900_000_000 ether - seedAmount);
        handler = new SwarmMarketHandler(token, router);
        for (uint256 i; i < 3; ++i) {
            vm.deal(handler.actors(i), 20 ether);
            // Ensure sells, wallet burns and revoked-approval paths are reachable immediately.
            handler.buy(i, 0.01 ether);
        }
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.buy.selector;
        selectors[1] = handler.sell.selector;
        selectors[2] = handler.walletTransfer.selector;
        selectors[3] = handler.roundTrip.selector;
        selectors[4] = handler.rejectSlippage.selector;
        selectors[5] = handler.revokeAndRejectSale.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariantMarketConservesETHAndTokensWithoutRouterCustody() public view {
        uint256 totalETH = address(manager).balance;
        uint256 totalTokens = token.balanceOf(address(manager)) + token.balanceOf(distributor)
            + token.balanceOf(remainder) + token.balanceOf(token.DEAD());
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(actor.balance, handler.expectedETH(actor), "trader ETH mismatch");
            assertEq(token.balanceOf(actor), handler.expectedTokens(actor), "trader tokens mismatch");
            assertEq(token.allowance(actor, address(router)), handler.expectedAllowance(actor));
            totalETH += actor.balance;
            totalTokens += token.balanceOf(actor);
        }
        assertEq(totalETH, 60 ether);
        assertEq(totalTokens, 1_000_000_000 ether);
        assertEq(token.totalSupply(), totalTokens);
        assertEq(address(router).balance, 0);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertFalse(TransientStateLibrary.isUnlocked(IPoolManager(address(manager))));
        assertEq(
            TransientStateLibrary.currencyDelta(
                IPoolManager(address(manager)), address(router), Currency.wrap(address(0))
            ),
            0
        );
        assertEq(
            TransientStateLibrary.currencyDelta(
                IPoolManager(address(manager)), address(router), Currency.wrap(address(token))
            ),
            0
        );
    }

    function invariantPoolSettlesExactInputsAndOutputsAndOnlyWalletTransfersBurn() public view {
        assertEq(address(manager).balance, handler.paidETH() - handler.receivedETH());
        assertEq(token.balanceOf(address(manager)), seedAmount + handler.soldTokens() - handler.boughtTokens());
        assertEq(token.totalBurned(), handler.expectedBurned());
        assertEq(token.balanceOf(token.DEAD()), handler.expectedBurned());
        assertEq(token.balanceOf(distributor), 100_000_000 ether);
        assertEq(token.balanceOf(remainder), 900_000_000 ether - seedAmount);
    }

    function testHandlerExercisesInterleavedTradesFailuresAndBurns() public {
        handler.buy(0, 0.02 ether);
        handler.walletTransfer(0, 1, 100 ether);
        handler.rejectSlippage(2, 0.01 ether);
        handler.revokeAndRejectSale(1);
        handler.sell(1, 100 ether, true);
        handler.roundTrip(0, 0.001 ether);
        handler.sell(2, type(uint256).max, false);
        invariantMarketConservesETHAndTokensWithoutRouterCustody();
        invariantPoolSettlesExactInputsAndOutputsAndOnlyWalletTransfersBurn();
        assertGt(handler.soldTokens(), 0);
        assertGt(handler.expectedBurned(), 0);
    }
}
