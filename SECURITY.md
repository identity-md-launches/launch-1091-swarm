# Security review notes

The token has no owner or administrative entry points. OpenZeppelin ERC20 handles
balances, zero-address checks, allowance spending, and standard errors. Its sole
mint is in the mainnet-only constructor. The factory and pool manager are
immutable. The distributor is resolved from the network factory because its
address depends on the deployed token; this external registry remains a platform
trust assumption, not a token admin interface.

The burn override uses checked arithmetic and the inherited balance update.
Reverting after either movement rolls back balances, the allowance, the burn
counter, and events. Both self-transfers and transferFrom require the gross
amount. The registry lookup is static, has a gas bound, copies at most one word,
and rejects malformed address data. Tests cover a reverting registry, empty and
oversized return data, invalid address data, and gas exhaustion.

Swap authorization is tied to the public caller. `payer` is set to `msg.sender`
inside the nonReentrant swap entry point, and an unlock callback is accepted only
from the immutable PoolManager during that active swap. There is no arbitrary
`from` or recipient input. The caller supplies a pool key, so the application is
not a verifier of every possible pool or hook. The website must publish the
reviewed launch's exact key.

The pool receives each sell directly via transferFrom. Each settlement checks the
actual settled amount. Native output goes directly to the caller, with all
effects inside one manager unlock; recipient reentrancy is blocked and a failed
ETH receipt reverts everything. Exact input, positive minimum output, int128-safe
input bounds, and a deadline are enforced. A partial fill reverts. There is no
treasury, fee receiver, withdrawal path, or contract upgrade path.

## Foundry lint review

`forge build` succeeds with advisory lint warnings. Each relevant pattern was
reviewed against the implementation and tests:

* **missing-zero-check:** constructor addresses must have deployed code; zero
  cannot pass. The factory must also equal the constructor caller.
* **reentrancy-no-eth / reentrancy-events:** the public entry point holds
  OpenZeppelin's ReentrancyGuard across manager unlock, callback, ETH receipt,
  payer reset, and the emitted swap event. Reentrant recipient tests pass.
* **arbitrary-send-erc20:** the callback's stored payer originates exclusively
  from the guarded entry point's caller. Another account cannot consume the
  victim's allowance; that failure is tested.
* **unsafe-typecast:** input is bounded to int128's positive range before its
  int256 conversion. Output must be positive int128 before conversion to uint128
  and widening to uint256. No user amount is truncated.
* **block-timestamp:** timestamps are used only for user-selected expiry, not
  randomness, authorization, rewards, or price calculation.

## Evidence and operational limits

Local checks: `forge build`, `forge test` (33 tests, including two fuzz tests and
an invariant with 128 runs / 8,192 operations), `forge fmt --check`, eight Node
frontend tests, and a Chromium browser smoke check of desktop/mobile layout,
launch-pending state, simulated live reads, buy confirmation, exact sell approval,
sell confirmation, and wallet-chain invalidation. Browser wallet/RPC responses
were mocked; Solidity integration tests used the real vendored PoolManager.

The provided protected harness was inspected but requires the network's final
manifest, addresses, environment, and platform contracts to execute. Its exact
allocation and trading constraints are covered by local integration tests. No
mainnet fork, transaction, source verification, Slither, Mythril, or independent
audit was performed. The network operator must verify final addresses, LP custody,
allocation receipts, and the final pool configuration before release. An
independent adversarial review remains necessary for a production launch.
