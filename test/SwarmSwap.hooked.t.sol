// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {Swarm} from "src/Swarm.sol";
import {SwarmSwap} from "src/SwarmSwap.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

/// @dev Stands in for the platform's pool initialization guard: a hook mined for BEFORE_INITIALIZE
/// only, which lets a single operator open the pool and refuses everyone else. Every other hook
/// entry point is unreachable because its flag bit is clear in the address.
contract InitializationGuardStub {
    address public immutable operator;
    uint256 public initializations;

    error NotTheOperator(address sender);

    constructor(address operator_) {
        operator = operator_;
    }

    function beforeInitialize(address sender, PoolKey calldata, uint160) external returns (bytes4) {
        if (sender != operator) revert NotTheOperator(sender);
        initializations += 1;
        return IHooks.beforeInitialize.selector;
    }
}

/// @dev Opens and seeds a pool under an arbitrary key the way the factory does: single-sided SWARM
/// below the opening price. It is not the token's factory, so its transfers into the manager are
/// exempt only because the recipient is the PoolManager.
contract GuardedSeeder is IUnlockCallback {
    IPoolManager public immutable manager;
    Swarm public immutable token;

    constructor(IPoolManager manager_, Swarm token_) {
        manager = manager_;
        token = token_;
    }

    function open(PoolKey calldata key, uint160 price) external {
        manager.initialize(key, price);
    }

    function seed(PoolKey calldata key, uint160 price) external returns (uint256 spent) {
        int24 upper = (TickMath.getTickAtSqrtPrice(price) / key.tickSpacing) * key.tickSpacing;
        int24 lower = TickMath.minUsableTick(key.tickSpacing);
        uint256 amount = token.balanceOf(address(this));
        uint128 liquidity = uint128(
            FullMath.mulDiv(
                amount, uint256(1) << 96, TickMath.getSqrtPriceAtTick(upper) - TickMath.getSqrtPriceAtTick(lower)
            )
        );
        manager.unlock(abi.encode(key, lower, upper, liquidity));
        return amount - token.balanceOf(address(this));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (PoolKey memory key, int24 lower, int24 upper, uint128 liquidity) =
            abi.decode(data, (PoolKey, int24, int24, uint128));
        (BalanceDelta delta,) = manager.modifyLiquidity(
            key, ModifyLiquidityParams(lower, upper, int256(uint256(liquidity)), bytes32(0)), ""
        );
        require(delta.amount0() == 0 && delta.amount1() < 0, "single sided token seed");
        uint256 owed = uint256(-int256(delta.amount1()));
        manager.sync(key.currency1);
        token.transfer(address(manager), owed);
        require(manager.settle() == owed, "exact settlement");
        return "";
    }
}

/// @notice The launch pool key is not hookless: the platform attaches an initialization guard. The
/// adapter and the website must therefore address the pool by that guard, and a hookless key names a
/// different pool that anyone can open at any price.
/// forge-config: default.fuzz.runs = 500
contract SwarmSwapHookedPoolTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;
    Swarm token;
    SwarmSwap router;
    PoolManager manager;
    LaunchHarness factory;
    GuardedSeeder seeder;
    InitializationGuardStub guard;
    PoolKey guardedKey;
    uint256 seedAmount;
    address alice = makeAddr("hooked alice");
    address stranger = makeAddr("hooked stranger");
    address distributor = makeAddr("hooked distributor");
    address remainder = makeAddr("hooked remainder");

    function setUp() public {
        vm.chainId(1);
        manager = new PoolManager(address(this));
        factory = new LaunchHarness(manager);
        token = factory.deploy();
        router = new SwarmSwap(token);
        factory.setDistributor(distributor);
        seeder = new GuardedSeeder(manager, token);
        guard = _mineGuard(address(seeder));
        guardedKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3000, 60, IHooks(address(guard)));

        // The factory's order: distributor, pool seed, then the paying wallet's remainder.
        factory.move(distributor, SUPPLY / 10);
        factory.move(address(seeder), SUPPLY * 8 / 10);
        seeder.open(guardedKey, factory.OPENING_PRICE());
        seedAmount = seeder.seed(guardedKey, factory.OPENING_PRICE());
        factory.move(remainder, token.balanceOf(address(factory)));
        vm.deal(alice, 20 ether);
        vm.deal(stranger, 20 ether);
    }

    function testGuardAddressCarriesOnlyTheBeforeInitializeFlag() public view {
        assertEq(uint160(address(guard)) & Hooks.ALL_HOOK_MASK, Hooks.BEFORE_INITIALIZE_FLAG);
        assertEq(guard.initializations(), 1, "the guard did not see the opening");
        assertEq(seedAmount, SUPPLY * 8 / 10 - token.balanceOf(address(seeder)));
        assertLt(SUPPLY * 8 / 10 - seedAmount, 10_000, "seed rounding dust exceeds the documented bound");
        assertEq(token.balanceOf(address(manager)), seedAmount, "the seed was taxed on its way into the manager");
        assertEq(token.totalBurned(), 0);
    }

    function testGuardRefusesAStrangerOpeningTheLaunchKey() public {
        PoolKey memory other = guardedKey;
        other.fee = 500;
        other.tickSpacing = 10;
        uint160 opening = factory.OPENING_PRICE();
        vm.prank(stranger);
        vm.expectPartialRevert(CustomRevert.WrappedError.selector);
        manager.initialize(other, opening);
        (uint160 price,,,) = router.poolState(500, 10, address(guard));
        assertEq(price, 0, "a refused initialization left pool state behind");
    }

    function testAdapterReadsAndTradesTheGuardedPool() public {
        (uint160 price,,, uint24 lpFee) = router.poolState(3000, 60, address(guard));
        assertEq(price, factory.OPENING_PRICE());
        assertEq(lpFee, 3000);
        vm.prank(alice);
        uint256 bought = router.swap{value: 0.01 ether}(3000, 60, address(guard), true, 0.01 ether, 1, block.timestamp);
        assertGt(bought, 0);
        assertEq(token.balanceOf(alice), bought, "the buy arrived short");
        assertEq(alice.balance, 20 ether - 0.01 ether);
        vm.startPrank(alice);
        token.approve(address(router), bought);
        uint256 received = router.swap(3000, 60, address(guard), false, bought, 1, block.timestamp);
        vm.stopPrank();
        assertGt(received, 0);
        assertLt(received, 0.01 ether, "a round trip through the pool created ETH");
        assertEq(token.balanceOf(alice), 0, "the sell left tokens behind");
        assertEq(token.balanceOf(address(manager)), seedAmount);
        assertEq(alice.balance + address(manager).balance, 20 ether);
        assertEq(address(router).balance, 0);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.totalBurned(), 0, "pool settlement was burned");
        assertEq(guard.initializations(), 1, "trading re-entered the guard");
    }

    function testFuzzGuardedRoundTripNeverCreatesValue(uint96 inputSeed) public {
        uint256 amount = bound(uint256(inputSeed), 0.000001 ether, 1 ether);
        vm.prank(alice);
        uint256 bought = router.swap{value: amount}(3000, 60, address(guard), true, amount, 1, block.timestamp);
        vm.startPrank(alice);
        token.approve(address(router), bought);
        uint256 received = router.swap(3000, 60, address(guard), false, bought, 1, block.timestamp);
        vm.stopPrank();
        assertLe(received, amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(manager)), seedAmount);
        assertEq(alice.balance + address(manager).balance, 20 ether);
        assertEq(token.totalBurned(), 0);
    }

    /// @dev What the website would read and trade if it shipped the zero hook address: nothing, until
    /// anyone at all opens that pool at a price of their choosing.
    function testHooklessKeyIsADifferentPoolThatAStrangerCanOpenAtAnyPrice() public {
        (uint160 price,,,) = router.poolState(3000, 60, address(0));
        assertEq(price, 0, "the hookless key must not resolve to the guarded pool");
        vm.prank(alice);
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        router.swap{value: 1 ether}(3000, 60, address(0), true, 1 ether, 1, block.timestamp);
        assertEq(alice.balance, 20 ether, "a swap against an unopened pool kept ETH");

        PoolKey memory hookless = guardedKey;
        hookless.hooks = IHooks(address(0));
        uint160 absurd = factory.OPENING_PRICE() / 1000;
        vm.prank(stranger);
        manager.initialize(hookless, absurd);
        (price,,,) = router.poolState(3000, 60, address(0));
        assertEq(price, absurd, "the stranger's pool is what a zero-hook site would display");
        (uint160 guarded,,,) = router.poolState(3000, 60, address(guard));
        assertEq(guarded, factory.OPENING_PRICE(), "the stranger's pool touched the guarded one");

        // The stranger's pool has no liquidity: an exact-input buy there cannot consume the input.
        vm.prank(alice);
        vm.expectRevert(SwarmSwap.PartialFill.selector);
        router.swap{value: 1 ether}(3000, 60, address(0), true, 1 ether, 1, block.timestamp);
        assertEq(alice.balance, 20 ether);
        assertEq(address(router).balance, 0);
    }

    function testWrongFeeTierUnderTheGuardIsNotTheLaunchPool() public {
        vm.prank(alice);
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        router.swap{value: 1 ether}(500, 10, address(guard), true, 1 ether, 1, block.timestamp);
        (uint160 price,,,) = router.poolState(3000, 10, address(guard));
        assertEq(price, 0);
        assertEq(alice.balance, 20 ether);
    }

    function testNeitherContractAcceptsPlainETH() public {
        vm.startPrank(alice);
        (bool routerTook,) = address(router).call{value: 1 wei}("");
        (bool tokenTook,) = address(token).call{value: 1 wei}("");
        vm.stopPrank();
        assertFalse(routerTook, "the adapter accepted ETH it can never return");
        assertFalse(tokenTook, "the token accepted ETH it can never return");
        assertEq(alice.balance, 20 ether);
        assertEq(address(router).balance, 0);
        assertEq(address(token).balance, 0);
    }

    function testGuardedPoolSeedCannotBeRepeatedByTheAdapterCaller() public {
        // A second initialization of the launch key fails inside the manager before the guard runs.
        uint160 price = factory.OPENING_PRICE();
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        seeder.open(guardedKey, price);
        assertEq(guard.initializations(), 1);
    }

    /// @dev CREATE2 salt search for an address whose low 14 bits are exactly BEFORE_INITIALIZE.
    function _mineGuard(address operator) private returns (InitializationGuardStub deployed) {
        bytes memory code = abi.encodePacked(type(InitializationGuardStub).creationCode, abi.encode(operator));
        bytes32 codeHash = keccak256(code);
        for (uint256 i; i < 1_000_000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == Hooks.BEFORE_INITIALIZE_FLAG) {
                address at;
                assembly ("memory-safe") {
                    at := create2(0, add(code, 32), mload(code), salt)
                }
                require(at == predicted && at.code.length > 0, "guard deployment failed");
                return InitializationGuardStub(at);
            }
        }
        revert("guard salt search exhausted");
    }
}
