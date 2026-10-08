// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Swarm} from "./Swarm.sol";

/// @notice Exact-input native ETH/SWARM swaps with a deadline and a caller-selected minimum output.
/// @dev No custody, fee, owner, or arbitrary payer. Pool parameters identify the operator-published pool.
contract SwarmSwap is IUnlockCallback, ReentrancyGuard {
    using StateLibrary for IPoolManager;

    Swarm public immutable token;
    IPoolManager public immutable manager;
    address private payer;

    error InvalidAmount();
    error Expired();
    error IncorrectValue();
    error UnauthorizedCallback();
    error PartialFill();
    error InsufficientOutput();
    error SettlementFailed();
    error InvalidPool();

    event Swapped(address indexed trader, bool buy, uint256 amountIn, uint256 amountOut);

    constructor(Swarm token_) {
        if (block.chainid != 1) revert Swarm.MainnetOnly();
        token = token_;
        manager = IPoolManager(token_.poolManager());
    }

    function swap(
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        bool buy,
        uint256 amountIn,
        uint256 minimumOut,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert Expired();
        if (amountIn == 0 || amountIn > uint256(uint128(type(int128).max)) || minimumOut == 0) {
            revert InvalidAmount();
        }
        if (msg.value != (buy ? amountIn : 0)) revert IncorrectValue();
        PoolKey memory key = _key(fee, tickSpacing, hooks);
        payer = msg.sender;
        amountOut = abi.decode(manager.unlock(abi.encode(key, buy, amountIn, minimumOut)), (uint256));
        payer = address(0);
        emit Swapped(msg.sender, buy, amountIn, amountOut);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager) || payer == address(0)) revert UnauthorizedCallback();
        (PoolKey memory key, bool buy, uint256 amountIn, uint256 minimumOut) =
            abi.decode(data, (PoolKey, bool, uint256, uint256));
        BalanceDelta delta = manager.swap(
            key, SwapParams(buy, -int256(amountIn), buy ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1), ""
        );
        int128 inputDelta = buy ? delta.amount0() : delta.amount1();
        int128 outputDelta = buy ? delta.amount1() : delta.amount0();
        if (int256(inputDelta) != -int256(amountIn)) revert PartialFill();
        if (outputDelta <= 0 || uint256(uint128(outputDelta)) < minimumOut) revert InsufficientOutput();
        uint256 amountOut = uint256(uint128(outputDelta));
        if (buy) {
            // Native settlement has no preceding ERC-20 sync.
            manager.sync(key.currency0);
            if (manager.settle{value: amountIn}() != amountIn) revert SettlementFailed();
            manager.take(key.currency1, payer, amountOut);
        } else {
            manager.sync(key.currency1);
            if (!token.transferFrom(payer, address(manager), amountIn)) revert SettlementFailed();
            if (manager.settle() != amountIn) revert SettlementFailed();
            manager.take(key.currency0, payer, amountOut);
        }
        return abi.encode(amountOut);
    }

    /// @notice Live spot state for display; this is not an oracle or a guaranteed execution price.
    function poolState(uint24 fee, int24 tickSpacing, address hooks)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        return manager.getSlot0(_key(fee, tickSpacing, hooks).toId());
    }

    function _key(uint24 fee, int24 tickSpacing, address hooks) private view returns (PoolKey memory) {
        if (fee > 1_000_000 || tickSpacing <= 0 || tickSpacing > 32_767) revert InvalidPool();
        // Native ETH is always currency0. No hook is deployed by this project. The launch pool key
        // carries the platform's initialization guard, so callers pass that address, not zero: a
        // hookless key names a different pool that anyone may initialize at any price.
        return PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), fee, tickSpacing, IHooks(hooks));
    }
}
