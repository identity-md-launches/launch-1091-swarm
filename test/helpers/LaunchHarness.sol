// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Swarm} from "../../src/Swarm.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/// @dev Local-only stand-in for the network factory. Never deployed as application code.
contract LaunchHarness is IUnlockCallback {
    uint64 public constant NUMBER = 7;
    uint160 public constant OPENING_PRICE = uint160((uint256(1) << 96) * 10_000);
    IPoolManager public immutable manager;
    Swarm public token;
    address private distributor;
    uint256 private registryMode;
    /// @dev Gas the "heavy registry" mode spends before answering: above the 30,000 the token once
    /// forwarded, well inside the 100,000 it forwards now, and independent of storage warmth.
    uint256 public constant HEAVY_LOOKUP_GAS = 45_000;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function deploy() external returns (Swarm) {
        token = new Swarm(address(this), address(manager), NUMBER);
        return token;
    }

    function distributorOf(uint64 number) external view returns (address) {
        require(registryMode != 1, "registry unavailable");
        if (registryMode == 2) {
            assembly ("memory-safe") {
                mstore(0, not(0))
                return(0, 32)
            }
        }
        if (registryMode == 3) {
            assembly ("memory-safe") {
                return(0, 8192)
            }
        }
        if (registryMode == 4) {
            // Exhaust only the gas forwarded to this lookup.
            while (true) {}
        }
        if (registryMode == 5) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (registryMode == 6) {
            // A registry behind a proxy or with extra bookkeeping: correct answer, expensive lookup.
            uint256 target = gasleft() - HEAVY_LOOKUP_GAS;
            while (gasleft() > target) {}
        }
        return number == NUMBER ? distributor : address(0);
    }

    /// @dev Gas one external `distributorOf` call costs in the current registry mode.
    function lookupGas() external view returns (uint256 used) {
        uint256 before = gasleft();
        this.distributorOf(NUMBER);
        used = before - gasleft();
    }

    function setRegistryMode(uint256 mode) external {
        registryMode = mode;
    }

    function setDistributor(address distributor_) external {
        distributor = distributor_;
    }

    function move(address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    function key() public view returns (PoolKey memory) {
        return PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3000, 60, IHooks(address(0)));
    }

    function seed() external returns (uint256 spent) {
        PoolKey memory pool = key();
        manager.initialize(pool, OPENING_PRICE);
        int24 upper = (TickMath.getTickAtSqrtPrice(OPENING_PRICE) / 60) * 60;
        int24 lower = TickMath.minUsableTick(60);
        uint256 amount = token.totalSupply() * 8000 / 10_000;
        uint128 liquidity = uint128(
            FullMath.mulDiv(
                amount, uint256(1) << 96, TickMath.getSqrtPriceAtTick(upper) - TickMath.getSqrtPriceAtTick(lower)
            )
        );
        uint256 beforeBalance = token.balanceOf(address(this));
        manager.unlock(abi.encode(pool, lower, upper, liquidity));
        return beforeBalance - token.balanceOf(address(this));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (PoolKey memory pool, int24 lower, int24 upper, uint128 liquidity) =
            abi.decode(data, (PoolKey, int24, int24, uint128));
        (BalanceDelta delta,) = manager.modifyLiquidity(
            pool, ModifyLiquidityParams(lower, upper, int256(uint256(liquidity)), bytes32(0)), ""
        );
        require(delta.amount0() == 0 && delta.amount1() < 0, "single sided token seed");
        uint256 owed = uint256(-int256(delta.amount1()));
        manager.sync(pool.currency1);
        token.transfer(address(manager), owed);
        require(manager.settle() == owed, "exact settlement");
        return "";
    }
}
