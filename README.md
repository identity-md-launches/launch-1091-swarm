# swarm (SWARM)

A fixed-supply Ethereum mainnet ERC-20, a native ETH swap adapter, and a static
website. Solidity 0.8.26 is pinned in `foundry.toml`; contract dependencies are
vendored as ordinary files. There are no keys, environment-variable requirements,
installation steps, or network calls in the test suite.

## Run locally

```sh
forge build
forge test
forge fmt --check
node --test web/test/*.test.mjs
python3 -m http.server 8080 --directory web
```

Open `http://localhost:8080`. The site shows a launch-pending state until its
deployment configuration is filled. Serve `web/` over HTTPS in production; it has
no build step, CDN imports, analytics, fonts, or third-party JavaScript.

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
PoolManager exemption necessarily covers its other pools and settlement paths
as well; routing through it can avoid the ordinary wallet-transfer burn. The
website discloses exempt pool trades. No application hook or ERC-8004 check exists.

The factory registry is the platform trust boundary. Its selected distributor
can transfer without the fee, but cannot seize unapproved balances. Ordinary
transfers use a 30,000-gas static lookup with a bounded one-word return buffer;
a reverted, missing, or malformed response falls back to the ordinary burn and
does not deliberately freeze users. The platform must keep the launch's mapping
correct and its claim path working. There are no token admin keys to repair it.

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

The protected platform harness uses its own initialization-only guard. This
project deploys no hook. If the platform attaches its mandatory guard, publish
that actual address as `web/config.mjs`'s `pool.hooks`; the pool key must match
exactly. A genuinely hookless pool uses the protocol-defined zero hook value.

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
4. Set `web/config.mjs`'s `token` and `swap` to the verified deployment addresses,
   and `pool` to the exact final key. These are static website settings, not
   owner-settable contract state. Keep the chain at 1; choose a reliable mainnet
   read RPC (the public endpoint is the supplied website default).
5. Confirm live mint/allocation/claim balances, pool price, a small buy and sell,
   ordinary transfer burn, and the website's quotes. Host the website over HTTPS
   and monitor RPC availability. No contract setter or initialization is needed.

## Validation and review limits

The delivered tests cover metadata, single constructor mint, mainnet restriction,
burn events/rounding/self-transfers, allowances/revocation/failure rollback,
missing or malformed registry, exact launch allocations and claims, administrative
call rejection, local real-v4 seeding and bidirectional swaps, pool price math,
slippage, deadlines, wrong value, unauthorized callbacks, partial fills, ETH
receiver failure, and reentrancy. Fuzz tests cover arbitrary transfer sizes and
trade sizes; a stateful invariant checks conservation over mixed transfer and
transferFrom sequences. The frontend's integer/ABI/configuration tests use Node's
built-in test runner and need no packages.

The protected file was read as the launch compatibility specification; it depends
on network-supplied manifest/environment and platform contracts absent from this
assignment, so it is not claimed as locally executed. Its allocation/trading/no
admin requirements are exercised independently by the delivered local tests.
The local PoolManager is real v4 code, not a mainnet fork. Mainnet deployment
addresses and real liquidity have not been verified here. Slither and Mythril
were not run. An independent adversarial review of the final deployment, platform
integration, and UI is still an operational responsibility before release.
