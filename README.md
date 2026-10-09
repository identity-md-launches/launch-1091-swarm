# swarm (SWARM)

<img src="assets/logo.svg" alt="SWARM logo" width="96" align="right">

A fixed-supply Ethereum mainnet ERC-20, a native ETH swap adapter, and the
SwarmSwap static website. Solidity 0.8.26 is pinned in `foundry.toml`; contract
dependencies are vendored as ordinary files. The contract test suite needs no keys,
environment variables, installation steps, or network calls.

The official SWARM mark (a cybernetic gold and cyan bee in a hexagonal honeycomb
border on a dark ground) is `assets/logo.svg`, with a 512×512 raster in
`assets/logo.png`. The website embeds both in its header, token selector, web app
manifest (`manifest.webmanifest`) and token list (`swarm.tokenlist.json`) for the
token contract `0xd2aef07b4a807062c1c9f01713def52172548eca`.

## Contracts: build and test

```sh
forge build
forge test
forge fmt --check
```

## Website: install, preview, rebuild, publish

The site is a single page in `web/` (plain HTML, CSS and TypeScript, no framework)
built with Vite. The finished export is committed in `dist/` so a publisher can serve
it without rebuilding. Node 24 and npm 11 were used.

```sh
cd web
npm install          # installs vite and typescript from package-lock.json
npm run dev          # local development server with live reload
npm run typecheck    # tsc --noEmit
npm test             # node --test test/*.test.ts (integer, ABI, config and manifest tests)
npm run build        # production export to ../dist with relative URLs
npm run preview      # serves ../dist locally to check the export
```

Rebuild after any change under `web/` or `assets/`, then commit `dist/` together with
the source and `web/package-lock.json`. Never commit `web/node_modules`.

Publish by uploading the contents of `dist/` to any static host, IPFS gateway or ENS
content hash; `vite.config.ts` sets `base: "./"`, so the page works from a subpath.
Serve over HTTPS. There is no server-side routing, backend, analytics or third-party
script. `dist/assets/logo.svg` and `dist/assets/logo.png` keep stable names because the
manifest and token list point at them.

Design tokens, typography, components and responsive behaviour are documented in
`DESIGN.md`; the build, interaction and Better Interface review results are in
`artifacts/validation.md`.

## Token behavior and assumptions

`src/Swarm.sol:Swarm` uses the explicitly requested lowercase name **swarm**,
symbol **SWARM**, and 18 decimals. Its constructor mints exactly
`1000000000000000000000000000` base units (one billion SWARM) to `msg.sender`,
the network factory. Deployment reverts outside chain ID 1. There is no owner,
subsequent mint, external burn, pause, blacklist, upgrade, fee setter, or exemption
setter. ERC-20 allowances are required even for privileged launch participants.

For an ordinary `transfer` or `transferFrom` of `amount`, `floor(amount / 100)`
base units move to `0x000000000000000000000000000000000000dEaD`; the recipient
receives the remainder. A transferFrom consumes the gross allowance. The fee and
net movement each emit a standard Transfer event. Amounts below 100 base units
round to zero fee. Self-transfers still require the full amount and charge the
same burn. Zero transfers succeed; zero recipients and insufficient balances or
allowances revert atomically. No fee is paid to a treasury or administrator.

Sending to the dead address is a sink transfer, not an ERC-20 supply reduction:
`totalSupply()` remains one billion. `totalBurned()` is the cumulative automatic
1% charge, including that charge on voluntary transfers to the dead address;
it excludes the net amount of voluntary dead-address transfers. Thus the dead
address balance can exceed `totalBurned`. The sink relies on no one controlling
the dead address. Nothing in this token adds a blacklist to enforce that assumption.

**Launch compatibility exception:** the phrase “every transfer” is implemented
for ordinary transfers. The supplied protected checks explicitly require exact
allocation, claim, seed, buy, and sell amounts. Accordingly these flows are exempt:

* The caller is the immutable factory (initial distributions).
* The sender or recipient is the immutable PoolManager (seed and both trade directions).
* The caller is the current `factory.distributorOf(launchNumber)` (claims).

A transfer **to** the factory or distributor is not exempt on that basis.
Approving another spender does not let it inherit the distributor exemption.
No application hook or ERC-8004 check exists.

**Known limit: the burn is bypassable through the PoolManager.** The PoolManager
exemption is unconditional in both directions and does not depend on who calls
or on any pool being touched. Uniswap v4's PoolManager is a permissionless
settlement ledger: inside its `unlock`, any contract (a 40-line courier, or an
existing v4 router's SETTLE and TAKE actions) can `sync` SWARM, transfer it in
(exempt because the recipient is the PoolManager), `settle` for a credit, and
then `take` it to any wallet (exempt because the sender is the PoolManager) or
`mint` an ERC-6909 claim that changes hands indefinitely without touching this
token's ledger. The cost is gas only, so any over-the-counter or large transfer
can avoid the 1%, and `totalBurned` and the dead-address balance understate the
deflation a literal reading of "every transfer" would promise. The 1% is enforced
on direct SWARM transfers; it is not a guarantee over every path.

This is a deliberate scope decision, not an oversight, and no token-level fix
exists within the brief. The PoolManager credits a sell with exactly the balance
it receives, so a burn on transfers **to** it would leave every sell unsettled
and revert; a burn on transfers **from** it would short every buy, which the
launch floor refuses; and a courier's settle is indistinguishable at the token
level from a sell's settle. Moving the 1% onto pool trades would need an
`afterSwap` hook, which the brief rules out. The requester should treat the
options as: (a) accept the weaker guarantee, which is what this delivery
implements and states on the website, or (b) commission a hook, which changes
the brief. `test/SwarmSwap.t.sol` pins the exempt pass-through path with the real
vendored PoolManager so the limit is tested, not merely documented.

The factory registry is the platform trust boundary. Its selected distributor
can transfer without the fee, but cannot seize unapproved balances. Ordinary
transfers use a 100,000-gas static lookup with a bounded one-word return buffer;
a reverted, missing, or malformed response falls back to the ordinary burn and
does not deliberately freeze users. A plain mapping getter costs about 3,000 gas,
so the budget leaves room for a proxy hop and extra bookkeeping; a registry that
exceeded it would silently short claims by 1%, which is why the budget is wide
and a test exercises a 45,000-gas lookup. The platform must keep the launch's
mapping correct and its claim path working. There are no token admin keys to
repair it.

## Deployment parameters

`deployment/parameters.json` is a handoff template for the network's final
manifest, not a broadcast script or a finalized `launch.json`. Its symbolic
placeholders must be resolved by the network from the admitted launch:

| Input | Value or source |
| --- | --- |
| Chain | Ethereum mainnet, chain ID 1 |
| Token | `src/Swarm.sol:Swarm` |
| Constructor | `($factory, $poolManager, $launchNumber)`; the factory must be the deployer |
| Application | `src/SwarmSwap.sol:SwarmSwap($token)` |
| Paired currency | Native ETH, represented by the protocol's zero currency address |
| Token supply | `1000000000000000000000000000` |
| Pool allocation | 8000 basis points, 800,000,000 SWARM budget |
| Platform swarm allocation | 10%, 100,000,000 SWARM; factory-managed |
| Paying wallet remainder | 10%, 100,000,000 SWARM, plus unavoidable pool rounding dust |
| Remainder recipient | `$requester`: the authenticated paying wallet, never an invented address |
| Opening market cap | `10000000000000000000` wei, 10 ETH |
| Chosen static LP fee / tick spacing | 3000 (0.3%) / 60 |
| Application hook | None |

The platform divides its swarm allocation into 2% for accepted contributors and
8% for connected paired seats. There are no additional allocations. The token
constructor itself makes **no distributions**; the factory must do them in the
required order: distributor, pool seed, then remainder. No actual factory,
manager, token, distributor, launch number, or paying wallet was supplied, so none
is fabricated. The placeholders are the launch substitution mechanism permitted
by the task. Do not deploy by calling the constructor from an arbitrary wallet.

Native ETH is currency0 and SWARM is currency1. The opening price is
`10 ETH / 1,000,000,000 SWARM = 0.00000001 ETH/SWARM`, or 10,000,000,000 wei per
whole token. Therefore `sqrtPriceX96 = 10,000 * 2^96` =
`792281625142643375935439503360000`. This is a price-derived market cap, **not** a
requirement to deposit 10 ETH. The pool opens with single-sided token liquidity.

The launch operator derives and verifies the range and liquidity with the final
pool key. The tested range uses the minimum usable tick and the opening tick
rounded down to spacing 60 as its upper tick. With native ETH first, token-only
liquidity lies below the opening price. Integer liquidity rounding leaves fewer
than 10,000 token base units of the 80% budget in the factory in this setup;
that dust belongs with the paying wallet remainder. The price crosses a small
empty tick gap before the first trade becomes active.

The launch pool key is **not hookless**. This project deploys no hook, but the
platform factory attaches its own pool initialization guard (a hook mined for
the BEFORE_INITIALIZE flag) to the pool it opens, and that guard's address is
part of the pool key. `web/src/config.ts` therefore carries the guard address from
the verified launch record as `pool.hooks` (with the record's fee 12500 and tick
spacing 60), and the site refuses both `null` and the zero address. A hookless key would point the
site at a different ETH/SWARM 3000/60 pool that anyone can initialize at any
price with a few gwei of liquidity, after which the site would show the
squatter's price and route swaps there.

## Swap and website

`SwarmSwap` derives its immutable PoolManager from the token. It accepts only
native ETH/SWARM pairs, exact input, positive minimum output, and a deadline.
Pool fee, spacing, and hook are explicit per-call parameters: the router is not
an authority certifying a pool. Use the operator-published canonical pool key.
It sends output directly to the caller and, on sells, pulls only that caller's
approved input directly into the PoolManager. There is no intermediate token
transfer charged a burn. It rejects partial fills instead of keeping a surplus
or creating refunds. Failed settlement, minimum output, or ETH receipt reverts
the whole swap. Direct/idle callbacks are rejected and swaps are reentrancy-guarded.
Accidentally sent tokens or forcibly sent ETH have no recovery administrator.

The website reads token metadata, supply, automatic burned total, and the pool's
live slot0 price at one block, checks chain ID and contract relationships, and
shows the latest block. A spot price is informational, not an oracle or a firm
execution quote. Quotes simulate the complete swap with `eth_call`. Selling
requires an exact-amount approval first. Quotes expire after 30 seconds, minimum
output includes the selected 0.5%/1%/2% slippage, and the on-chain transaction
expires after two minutes. A user reviews a quote before confirming a swap.
Wallet/account/chain changes invalidate quotes. Failed reads disable trading;
pending or reverted receipts and user rejection are shown explicitly.

## After launch: operator responsibilities

1. Resolve the three constructor placeholders and paying wallet from the actual
   launch; verify Ethereum mainnet factory/manager code and registry ABI. Create
   the final network manifest from the provided template and admitted addresses.
2. Confirm the allocation math and actual range/liquidity, distributor funding,
   pool fee/key, LP ownership, and the network's custody/locking policy for the
   liquidity position. This project adds no withdrawal/admin key or LP lock.
3. Deploy through the network's reviewed launch process. Verify token and swap
   sources/bytecode with this exact compiler configuration; record receipts,
   addresses, immutable configuration, and pool ID. This assignment sends no
   transactions and handles no keys.
4. `web/src/config.ts` holds the verified token, SwarmSwap and pool key (including
   the platform's pool initialization guard hook) copied from the launch record.
   Change them only from a newer verified record, then rebuild and recommit `dist/`. Confirm it by reading
   `SwarmSwap.poolState(fee, tickSpacing, hooks)` and checking that the returned
   price is the opening price, not zero and not a stranger's. These are static
   website settings, not owner-settable contract state. Keep the chain at 1;
   choose a reliable mainnet read RPC (the public endpoint is the supplied
   website default).
5. Confirm live mint/allocation/claim balances, pool price, a small buy and sell,
   ordinary transfer burn, and the website's quotes. Host the website over HTTPS
   and monitor RPC availability. No contract setter or initialization is needed.

## Validation and review limits

The delivered tests cover metadata, single constructor mint, mainnet restriction,
burn events/rounding/self-transfers, allowances/revocation/failure rollback,
missing, malformed, or expensive registry, exact launch allocations and claims,
administrative call rejection, local real-v4 seeding and bidirectional swaps,
the exempt PoolManager pass-through path (take and ERC-6909 claim), pool price math,
slippage, deadlines, wrong value, unauthorized callbacks, partial fills, ETH
receiver failure, and reentrancy. Fuzz tests cover arbitrary transfer sizes and
trade sizes; a stateful invariant checks conservation over mixed transfer and
transferFrom sequences. The frontend's integer/ABI/configuration/manifest tests
use Node's built-in test runner on the TypeScript sources and need no packages beyond
the dev dependencies. On 2026-10-09 `npm run typecheck`, `npm test` (9 passing) and
`npm run build` all exited 0, and the export was inspected in Chromium at 1366, 820,
375 and 320 px widths with live mainnet reads, no console errors, no failed resources
and no horizontal overflow; see `artifacts/validation.md` for the full record and the
checks that were not performed (screen reader, automated audit, on-chain swap).

The protected file was read as the launch compatibility specification; it depends
on network-supplied manifest/environment and platform contracts absent from this
assignment, so it is not claimed as locally executed. Its allocation/trading/no
admin requirements are exercised independently by the delivered local tests.
The local PoolManager is real v4 code, not a mainnet fork. Mainnet deployment
addresses and real liquidity have not been verified here. Slither and Mythril
were not run. An independent adversarial review of the final deployment, platform
integration, and UI is still an operational responsibility before release.
