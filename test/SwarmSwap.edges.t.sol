// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Swarm} from "src/Swarm.sol";
import {SwarmSwap} from "src/SwarmSwap.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

/// forge-config: default.fuzz.runs = 1000
contract SwarmSwapEdgesTest is Test {
    using StateLibrary for IPoolManager;

    Swarm token;
    SwarmSwap router;
    PoolManager manager;
    LaunchHarness factory;
    address alice = makeAddr("swap edge alice");
    address bob = makeAddr("swap edge bob");
    address distributor = makeAddr("swap edge distributor");

    event Swapped(address indexed trader, bool buy, uint256 amountIn, uint256 amountOut);

    function setUp() public {
        vm.chainId(1);
        manager = new PoolManager(address(this));
        factory = new LaunchHarness(manager);
        token = factory.deploy();
        router = new SwarmSwap(token);
        factory.setDistributor(distributor);
        factory.move(distributor, 100_000_000 ether);
        factory.seed();
        factory.move(bob, token.balanceOf(address(factory)));
        vm.deal(alice, 20 ether);
    }

    function testExactMinimumAndDeadlineEqualitySucceedWithAccurateEvent() public {
        uint256 deadline = vm.getBlockTimestamp();
        uint256 snapshot = vm.snapshotState();
        uint256 quoted = _buy(0.01 ether);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.expectEmit(true, false, false, true, address(router));
        emit Swapped(alice, true, 0.01 ether, quoted);
        vm.prank(alice);
        uint256 received = router.swap{value: 0.01 ether}(3000, 60, address(0), true, 0.01 ether, quoted, deadline);
        assertEq(received, quoted);
        assertEq(token.balanceOf(alice), quoted);
        vm.prank(alice);
        token.approve(address(router), received);
        snapshot = vm.snapshotState();
        vm.prank(alice);
        uint256 sellQuote = router.swap(3000, 60, address(0), false, received, 1, deadline);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.expectEmit(true, false, false, true, address(router));
        emit Swapped(alice, false, received, sellQuote);
        vm.prank(alice);
        assertEq(router.swap(3000, 60, address(0), false, received, sellQuote, deadline), sellQuote);
        _assertIdleCallbackRejected();
    }

    function testSellSlippageRollbackIncludesAllowancePriceLiquidityAndFeeGrowth() public {
        uint256 bought = _buy(0.01 ether);
        vm.prank(alice);
        token.approve(address(router), bought);
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.InsufficientOutput.selector);
        router.swap(3000, 60, address(0), false, bought, 1 ether, block.timestamp);
        assertEq(_state(), beforeState);
        _assertIdleCallbackRejected();
        vm.prank(alice);
        assertGt(router.swap(3000, 60, address(0), false, bought, 1, block.timestamp), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testBuySettlementMismatchRevertsWholeSwap() public {
        bytes32 beforeState = _state();
        vm.mockCall(address(manager), abi.encodeCall(IPoolManager.settle, ()), abi.encode(uint256(0)));
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.SettlementFailed.selector);
        router.swap{value: 0.01 ether}(3000, 60, address(0), true, 0.01 ether, 1, block.timestamp);
        vm.clearMockedCalls();
        assertEq(_state(), beforeState);
        _assertIdleCallbackRejected();
        assertGt(_buy(0.01 ether), 0);
    }

    function testSellSettlementMismatchRestoresAlreadyTransferredTokensAndAllowance() public {
        uint256 bought = _buy(0.01 ether);
        vm.prank(alice);
        token.approve(address(router), bought);
        bytes32 beforeState = _state();
        vm.mockCall(address(manager), abi.encodeCall(IPoolManager.settle, ()), abi.encode(bought - 1));
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.SettlementFailed.selector);
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        vm.clearMockedCalls();
        assertEq(_state(), beforeState);
        _assertIdleCallbackRejected();
        vm.prank(alice);
        assertGt(router.swap(3000, 60, address(0), false, bought, 1, block.timestamp), 0);
    }

    function testFalseTransferReturnRevertsWholeSale() public {
        uint256 bought = _buy(0.01 ether);
        vm.prank(alice);
        token.approve(address(router), bought);
        bytes32 beforeState = _state();
        // Fault injection covers the adapter's defensive check; SWARM normally returns true or reverts.
        vm.mockCall(
            address(token), abi.encodeCall(token.transferFrom, (alice, address(manager), bought)), abi.encode(false)
        );
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.SettlementFailed.selector);
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        vm.clearMockedCalls();
        assertEq(_state(), beforeState);
    }

    function testSellWithApprovalButNoTokensRevertsAndRestoresPool() public {
        uint256 bought = _buy(0.01 ether);
        vm.startPrank(alice);
        token.transfer(bob, bought);
        token.approve(address(router), bought);
        vm.stopPrank();
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, bought));
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        assertEq(_state(), beforeState);
    }

    function testOneWeiSaleCannotConsumeInputForZeroOutput() public {
        _buy(0.01 ether);
        vm.prank(alice);
        token.approve(address(router), 1);
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.InsufficientOutput.selector);
        router.swap(3000, 60, address(0), false, 1, 1, block.timestamp);
        assertEq(_state(), beforeState);
    }

    function testInputImmediatelyAboveInt128MaximumRejected() public {
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.InvalidAmount.selector);
        router.swap(3000, 60, address(0), false, uint256(1) << 127, 1, block.timestamp);
        assertEq(_state(), beforeState);
    }

    function testFuzzInvalidPoolBoundsAreRejectedByViewAndSwap(uint24 feeSeed, int24 spacingSeed, bool invalidFee)
        public
    {
        uint24 fee = invalidFee ? uint24(bound(feeSeed, 1_000_001, type(uint24).max)) : 3000;
        int24 spacing = invalidFee ? int24(60) : int24(bound(int256(spacingSeed), type(int24).min, 0));
        vm.expectRevert(SwarmSwap.InvalidPool.selector);
        router.poolState(fee, spacing, address(0));
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.InvalidPool.selector);
        router.swap{value: 1 ether}(fee, spacing, address(0), true, 1 ether, 1, block.timestamp);
        assertEq(alice.balance, 20 ether);
        vm.expectRevert(SwarmSwap.InvalidPool.selector);
        router.poolState(3000, 32_768, address(0));
    }

    function testUninitializedPoolHasSpecificErrorAndDoesNotTrapETH() public {
        bytes32 beforeState = _state();
        vm.prank(alice);
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        router.swap{value: 1 ether}(500, 10, address(0), true, 1 ether, 1, block.timestamp);
        assertEq(_state(), beforeState);
        _assertIdleCallbackRejected();
    }

    function testSwapCannotSpendPreexistingRouterDonations() public {
        // Model unsolicited ETH without introducing a production recovery function.
        vm.deal(address(router), 1 ether);
        vm.prank(bob);
        token.transfer(address(router), 100 ether);
        uint256 donatedTokens = token.balanceOf(address(router));
        uint256 bought = _buy(0.01 ether);
        vm.prank(alice);
        token.approve(address(router), bought);
        vm.prank(alice);
        router.swap(3000, 60, address(0), false, bought, 1, block.timestamp);
        assertEq(address(router).balance, 1 ether);
        assertEq(token.balanceOf(address(router)), donatedTokens);
        assertEq(token.balanceOf(alice), 0);
        assertLt(alice.balance, 20 ether);
    }

    function testRouterConstructorRejectsNonMainnet() public {
        vm.chainId(8453);
        vm.expectRevert(Swarm.MainnetOnly.selector);
        new SwarmSwap(token);
    }

    function _buy(uint256 amount) private returns (uint256) {
        uint256 deadline = vm.getBlockTimestamp();
        vm.prank(alice);
        return router.swap{value: amount}(3000, 60, address(0), true, amount, 1, deadline);
    }

    function _assertIdleCallbackRejected() private {
        vm.prank(address(manager));
        vm.expectRevert(SwarmSwap.UnauthorizedCallback.selector);
        router.unlockCallback("");
    }

    function _state() private view returns (bytes32) {
        PoolId id = factory.key().toId();
        IPoolManager poolManager = IPoolManager(address(manager));
        (uint160 price, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(id);
        (uint256 feeGrowth0, uint256 feeGrowth1) = poolManager.getFeeGrowthGlobals(id);
        bytes32 poolState = keccak256(
            abi.encode(price, tick, protocolFee, lpFee, poolManager.getLiquidity(id), feeGrowth0, feeGrowth1)
        );
        bytes32 balances = keccak256(
            abi.encode(
                alice.balance,
                address(manager).balance,
                address(router).balance,
                token.balanceOf(alice),
                token.balanceOf(address(manager)),
                token.balanceOf(address(router))
            )
        );
        return keccak256(abi.encode(poolState, balances, token.allowance(alice, address(router)), token.totalBurned()));
    }
}
