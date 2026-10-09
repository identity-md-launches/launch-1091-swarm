# SWARM ($SWARM) — post-deployment report and audit specifications

**Status: evidence-backed draft for project review.** Prepared 9 October 2026 for
`launch-1091-swarm`. This document records observed deployment facts and the
remaining publication/listing checks; it is not an independent security audit or
an assertion that third-party listings have been approved. No transaction,
redeployment, mint, listing submission or production-site publication was performed.

## 1. Identity and evidence boundary

| Field | Value |
| --- | --- |
| Network | Ethereum mainnet, chain ID **1** |
| Token contract | `0xd2aef07b4a807062c1c9f01713def52172548eca` |
| EIP-55 token address | `0xd2aEF07B4A807062C1C9f01713def52172548ECA` |
| On-chain name / symbol | **swarm / SWARM** (`$SWARM` is display notation) |
| Decimals | **18** |
| Initial and current total supply | **1,000,000,000 SWARM** = `1000000000000000000000000000` base units |
| Deployment block | **26,150,507** |
| Deployment transaction | [`0xcdbb09627e10374f92eb9ce9c82dd6805692e7edc5d949d5d816585f25008ebc`](https://etherscan.io/tx/0xcdbb09627e10374f92eb9ce9c82dd6805692e7edc5d949d5d816585f25008ebc) |
| Contract source commit | [`a90f7546492326d5f6a43b04cf685124063ac858`](https://github.com/identity-md-launches/launch-1091-swarm/tree/a90f7546492326d5f6a43b04cf685124063ac858) |
| Previous website commit | `858227bf5e97578b0bbf6d1b024efde4525bf7f5` |
| Project repository | [identity-md-launches/launch-1091-swarm](https://github.com/identity-md-launches/launch-1091-swarm) |
| Official dApp | [swarm.sites.imd.fun](https://swarm.sites.imd.fun/) |
| Hosted name | `swarm.site.identitymd.eth` (pinned project record; ENS resolution not independently queried) |

**On-chain snapshot:** block **26,156,668** (`0x18f1e7c`), timestamp
**2026-10-09 18:32:47 UTC**, hash
`0xd0ae562e9af5638f767a52d8bf56a3c94bc5a50b58624c24b1afa034934b43e9`.
Read-only calls used `https://ethereum-rpc.publicnode.com`, with every `eth_call`
and `eth_getCode` pinned to that block. The deployment receipt reports success at
the pinned deployment block. Values here are a snapshot, not real-time market data.
Raw requests and responses: [chain-snapshot.json](docs/audit/evidence/chain-snapshot.json).
Both supplied public endpoints returned chain ID 1 and the same initial head;
dRPC initially rejected batches larger than three requests. Retrying in batches
of three succeeded, with the same block hash, state and runtime code as PublicNode.
See [chain-snapshot-drpc.json](docs/audit/evidence/chain-snapshot-drpc.json) and
[the initial limit response](docs/audit/evidence/drpc-batch-limit.json).

## 2. Token mechanics and ownership

The constructor in [`src/Swarm.sol`](src/Swarm.sol) mints the entire initial supply
once to `msg.sender`, the launch factory. There is **no callable subsequent mint,
public burn function, owner, pause, blacklist, upgrade entry point, fee setter or
exemption setter**. No ownership was “renounced”: this contract has no ownership
role to begin with. `owner()` reverted at the snapshot; this observation supports,
but does not replace, the source and bytecode review.

Ordinary transfers send **floor(gross amount / 100)** base units to
`0x000000000000000000000000000000000000dEaD` and the rest to the recipient.
For example, 100 SWARM sends 99 SWARM to the recipient and 1 SWARM to the sink.
Amounts below 100 base units have a zero automatic charge. This is a **1% transfer
charge to a sink address**, not an ERC-20 supply reduction. `totalSupply()` stays
at one billion. Do not describe the token as having “no transfer fee” without this
qualification. No treasury or owner collects the charge.

At the snapshot, `totalBurned()` and `balanceOf(DEAD)` were both **10,000 SWARM**
(`10000000000000000000000` base units). `totalBurned` accumulates automatic
charges only; voluntary transfers to DEAD can make its balance larger. Subtracting
DEAD's balance yields **999,990,000 SWARM outside the sink**, not a verified
circulating-supply figure. A sink address is not proof of inaccessible keys.

**Exemptions are material:** calls by the immutable factory, calls by the current
`factory.distributorOf(launchNumber)`, and transfers with the immutable PoolManager
as sender or recipient carry no automatic charge. Exempt callers still need
allowances to transfer another holder's tokens. The factory registry is an external
trust boundary: it selects the distributor. The lookup is a bounded 100,000-gas
static call; a bad response falls back to charging the ordinary 1%.

The PoolManager exemption can be used to move tokens through permissionless
`sync/settle/take` or ERC-6909 claims without paying the 1%. Consequently the burn
is not guaranteed on every economic transfer. This accepted design limitation is
covered by existing local tests and remains disclosed on the website.

## 3. Verification parameters and reproducibility

| Parameter | Token verification input |
| --- | --- |
| Contract | `src/Swarm.sol:Swarm` |
| Compiler | `v0.8.26+commit.8a97fa7a` |
| Language / license | Solidity / MIT for project source (dependency licenses retained) |
| Optimization | Enabled, **200** runs |
| EVM target | **cancun** |
| Metadata bytecode hash | **none** |
| viaIR | Not enabled (compiler default false) |
| Linked libraries | None |
| Constructor signature | `(address factory_, address poolManager_, uint64 launchNumber_)` |
| Factory | `0xff03410d0fe5fa8f7f59f743de35e333d9857120` |
| PoolManager | `0x000000000004444c5dc75cb358380d2e3de08a90` |
| Launch number | `1091` |

The constructor values above were read on chain and independently appear in the
Sourcify creation transformation; they are not guessed deployment arguments.
The factory is distinct from the outer transaction deployer.
ABI-encoded constructor arguments, **without** a `0x` prefix for explorer forms:

```text
000000000000000000000000ff03410d0fe5fa8f7f59f743de35e333d9857120000000000000000000000000000000000004444c5dc75cb358380d2e3de08a900000000000000000000000000000000000000000000000000000000000000443
```

The [Sourcify token record](https://sourcify.dev/server/v2/contract/1/0xd2aef07b4a807062c1c9f01713def52172548eca?fields=all)
reports `creationMatch: "match"` and `runtimeMatch: "match"`, verified at
**2026-10-09 12:19:36 UTC**. Preserve those exact status names; this report does not
upgrade them to a full/exact metadata match. All six returned Solidity source
files equal the local files byte for byte. The local ABI and Sourcify ABI contain
the same entries in different array order.

The [Etherscan source tab](https://etherscan.io/address/0xd2aef07b4a807062c1c9f01713def52172548eca#code)
returned HTTP **403** to this check. Etherscan source-verification and token-logo
approval statuses therefore remain **unconfirmed**, despite the positive Sourcify
and local checks. The complete submission input is
[Swarm.standard-input.json](docs/audit/verification/Swarm.standard-input.json);
it contains the verified sources, optimizer, metadata, EVM and remapping settings.
Use Solidity Standard JSON Input, the exact compiler above and the constructor
arguments above. This task did not submit a verification request.

`forge build --offline` reproduced both pinned creation-code hashes and both
pinned ABI hashes. Local runtime templates match the on-chain runtime bytes after
excluding the compiler-declared immutable locations; immutable values are recorded
and agree with the state getters. The token runtime also matches Sourcify's
on-chain runtime. This supports equivalence to the pinned deployment without
claiming an independent audit.

| Hash (Ethereum keccak256) | Swarm | SwarmSwap |
| --- | --- | --- |
| Canonical ABI | `256e5c5caeb272a253f1a3b0a1aef5dd46f75db9194f26b92d52605ee3ef00fc` | `0a01dd50e61ea61d9e164bb4056b7299b152fa0d6e4cd2816581dc8a4eb109f9` |
| Creation code | `9f34b3913bdf902fcc6c9face93d70b711813af2354fcdad42575c98bbcf94a2` | `3ecac95e2705bed7bb7318c5aade6bd99509ecd8fbc2b72223dccd3a5289a5b8` |
| Runtime code at snapshot | `8b30bc2136422339f303bd416bca9dc70645f4d6dbd20b792ab6e55a08a1a5bf` | `3d67deae8741be9eae28eb06c4a82fe2f9c8d3fce4450aa0b3f2f5e62e091776` |

ABI exports: [Swarm](docs/abi/Swarm.json), [SwarmSwap](docs/abi/SwarmSwap.json).
Canonical ABI hashing recursively sorts object keys, preserves Foundry ABI array
order and removes whitespace before UTF-8 keccak256. Hashing the differently
ordered Sourcify ABI directly does not produce the pinned hash.
Full comparison: [verification.json](docs/audit/evidence/verification.json).

Reproduce from the repository root with Python 3, curl and Foundry:

```sh
forge build --offline
python3 docs/audit/verify-launch.py --block 26156668
python3 docs/audit/verify-build.py
forge test --offline
forge test --offline --fuzz-seed 0x1091 --fuzz-runs 1024
forge fmt --check
```

The scanner's JSON includes exact methods, calldata, addresses and block tags,
including the unsuccessful `owner()` probe. It uses no keys and sends no
transaction. Historical RPC availability is an external dependency of rechecking
chain evidence; compilation and contract tests are offline.

## 4. SwarmSwap, pool and security checks

| Item | Observed status or audit specification |
| --- | --- |
| SwarmSwap | `0x4bc05bda38e6e4a6158b5eeb825208c1f2380360`; 4,343 runtime bytes; `token()` and `manager()` match the token and supplied PoolManager |
| SwarmSwap constructor | `(Swarm token_)`; argument is the SWARM contract above; same compiler/settings as the token |
| Swap source verification | Local build/runtime comparison passes; Sourcify returned null match fields for this address; explorer verification not established |
| Token runtime | 2,579 bytes; direct token implementation, no proxy dispatch in reviewed source |
| Pool key | Native ETH as currency0, SWARM as currency1, fee **12500**, tickSpacing **60**, hooks `0x784ff9a3ac5d88a30bfff6f7f2a270161fbe6000` |
| Pool spot state | `sqrtPriceX96 = 2505414483750479311864138015696064`, tick `207243`, protocolFee `0`, lpFee `12500`, all at the snapshot block |
| Pool fee | **1.25%** LP fee at the snapshot, distinct from the token's ordinary 1% sink charge |
| Distributor | `0x32c3afc39b0d5f30a94a13272bef548259b509c2` in pinned project record; deployed code present at snapshot; registry relationship requires separate confirmation |
| Initialization guard | Code present (488 bytes); platform initialization hook, not a token burn hook or evidence of a liquidity lock |
| LP lock | **Not verified.** No position ID, custodian proof, lock transaction, beneficiary, unlock time or locker withdrawal rules were supplied or established |

The current pool key in the pinned deployment record takes precedence over the
old template's fee 3000. The accepted manifest specifies a **1 ETH** opening
market cap and an **80% pool allocation budget**. Earlier prose and
`deployment/parameters.json` describe 10 ETH; these are historical intent, not
current deployed parameters. Opening capitalization is a price-derived value,
not the ETH deposited, present market cap, or a guarantee of liquidity. This
report does not certify the actual allocation balances or locked percentage.

The token being ownerless does not prove that liquidity cannot be withdrawn.
Before making any “liquidity locked” claim, independently identify the v4 pool
position(s) or direct PoolManager liquidity owner, reconcile `ModifyLiquidity`
events and position accounting, prove the owner/custodian, inspect the locker
code and any privileged withdrawal/upgrade paths, and record lock percentage,
beneficiary and unlock timestamp with block-hashed calls and transactions.
A PoolManager balance alone is shared across pools and cannot establish this.

Security review scope and dispositions:

- **Mint/admin surface:** source and ABI contain constructor-only minting and no
  owner or administrative token controls. No external burn reduces supply.
- **Transfer economics:** rounding, allowances, sink accounting and exemptions
  are explicit; PoolManager burn bypass is a disclosed design limit.
- **Swap settlement:** exact input, positive minimum output, deadline,
  caller-bound payer, callback authentication and a reentrancy guard are present.
  Partial fills revert. Pool parameters remain caller-supplied; the UI must use
  the pinned guard-bearing pool key.
- **External trust:** factory registry, PoolManager, initialization guard,
  distributor and LP custodian deserve a separate platform audit. This report
  has not certified their administration or liquidity policy.
- **Tool warnings:** the build emitted Foundry lints for zero checks, casts,
  timestamps, external calls and transferFrom payer handling. Source guards
  include code-length checks, bounded signed input, positive output and a
  guarded caller-derived payer; this is a manual disposition, not a clean
  static-analysis certificate. Slither/Mythril were not run.
- **Audit tests:** existing offline tests cover mint/metadata, transfer rounding,
  supply conservation, registry failure/budget, allowance rollback, direct and
  exempt paths, real local v4 buy/sell settlement, deadlines, minimum output,
  unauthorized callbacks and reentrancy. Current commands/results and browser
  scope are recorded in [validation.md](docs/audit/validation.md).

## 5. Live dApp branding, metadata and IPFS audit

HTTP observations were collected on **2026-10-09 at 18:32–18:33 UTC**.
[requests.json](docs/audit/evidence/requests.json) records times, statuses, paths
and SHA-256 digests. The saved live HTML, manifests and logos are pre-change
observations, separate from this assignment's new `dist/` export.

| Surface | Live observation | Delivered source/export |
| --- | --- | --- |
| Domain | HTTPS 200 from `https://swarm.sites.imd.fun/` | Same intended canonical domain |
| Header mark | `./assets/logo.svg` | Preserved |
| Token selection | Native Buy/Sell dropdown selects direction; adjacent pay/receive SWARM chips resolve to the official SVG | Preserved; logo shown for SWARM in either direction. Native option rows themselves are text, not image-bearing options |
| Web manifest | HTTP 200; related_contracts binds chain 1 and CA to both SVG and 512×512 PNG icons | Preserved with canonical project URL and direct per-contract logo references |
| Token list | HTTP 200; single SWARM entry binds CA, name, symbol, decimals and relative PNG/SVG URLs | Preserved for gateway-relative use |
| Logo identity | Live SVG and PNG equal repository assets byte for byte | Original brand assets retained |
| Title/description | Present; name and mainnet context correct | Preserved with precise supply/burn wording |
| Canonical / `og:url` / `og:image` | **Missing** in captured live HTML | Added canonical URL, OG URL and absolute `https://swarm.sites.imd.fun/assets/logo.png`, PNG dimensions/type/alt, and Twitter card metadata |
| Local assets | Live compiled JS/CSS and logos are relative | New `dist/` retains relative runtime URLs for gateway subpaths |

Absolute social image and canonical URLs identify the official domain; they are
metadata, not required runtime asset fetches. Script, stylesheet, manifest, logo
and report download paths remain relative. Social crawler preview refreshes are
not verified until the host publishes this export and caches are refreshed.

The live response header **`x-ipfs-cid`** equals the pinned project's current CID:

```text
bafybeid3t2wvhqu6xb55dtbgmtdk2enyniinucfbd2juqltwaaohg5dceq
```

This establishes agreement between the hosting response and the project record.
It does **not** independently cryptographically verify all IPFS blocks. The
`ipfs.io` request returned HTTP **429**, and the DNS query for
`_dnslink.swarm.sites.imd.fun` returned a CNAME without a DNSLink TXT value. ENS
contenthash resolution was not performed. No new CID can be stated before the
publisher uploads the final export. Never label the old CID as the CID of this
updated build. Recheck the new `x-ipfs-cid`, IPFS content and ENS contenthash after
publication, then amend this draft with the actual publication evidence.

## 6. External indexer submission package

Machine-readable handoff: [swarm.listing-draft.json](docs/audit/swarm.listing-draft.json).
This is a project submission worksheet, **not** a universal indexer API schema.
No submission, payment, account login or repository PR was made. Unknown contacts,
social accounts, CoinGecko ID, market URLs and approval states remain null or
explicitly unverified; no unrelated SWARM project is used as a substitute.

Shared project bindings:

| Field | Submission value |
| --- | --- |
| Chain / contract | Ethereum / `0xd2aEF07B4A807062C1C9f01713def52172548ECA` |
| Name / symbol / decimals | `swarm` / `SWARM` / `18` |
| Website / dApp | `https://swarm.sites.imd.fun/` |
| Repository | `https://github.com/identity-md-launches/launch-1091-swarm` |
| Explorer | `https://etherscan.io/token/0xd2aef07b4a807062c1c9f01713def52172548eca` |
| SVG | `assets/logo.svg`; `https://swarm.sites.imd.fun/assets/logo.svg` |
| PNG | `assets/logo.png`; `https://swarm.sites.imd.fun/assets/logo.png`; **512×512** |
| Description | Fixed-supply Ethereum token with one constructor mint and a 1% sink charge on ordinary transfers; factory, distributor and PoolManager paths are exempt. SwarmSwap supports native ETH/SWARM swaps. |

**Etherscan:** use the token page's Update Token Info workflow with official URL,
logo and accurate token facts. Etherscan requires address-ownership verification
and source publication. Its account-level ownership verification is distinct
from an on-chain `owner()` role; a factory-deployed ownerless token may require
the authorized project/operator to establish the accepted proof. Source and
branding approval are unconfirmed here. See the [official update instructions](https://info.etherscan.com/how-to-update-token-information-on-token-page/)
and [submission guidelines](https://kb.etherscan.com/token-update-guide).

**CoinGecko:** prepare an Ethereum token application through the
[official request workflow](https://support.coingecko.com/hc/en-us/articles/7291312302617-How-to-List-a-New-Cryptocurrency-on-CoinGecko).
Its guide requires active trading on a supported exchange. Establish an indexed
market, applicant contact and circulation methodology before submission. The
one-billion ERC-20 total supply and sink balance are not a circulation attestation.
An existing CoinGecko listing/ID was not verified.

**DexScreener:** the [official listing documentation](https://docs.dexscreener.com/token-listing)
describes automatic discovery after liquidity and at least one transaction;
metadata can propagate from external token lists or its token-info service.
The [token API](https://api.dexscreener.com/latest/dex/tokens/0xd2aef07b4a807062c1c9f01713def52172548eca)
returned `{"schemaVersion":"1.0.0","pairs":null}` at this check. This establishes
no indexed pair in that response, not proof of absent on-chain liquidity. The v4
pool ID is not a v2/v3 pair contract. Do not fabricate a pair address or approved
market URL; confirm v4 discovery/support before any metadata application.

**Trust Wallet Assets:** prepare the checksum-address directory
`blockchains/ethereum/assets/0xd2aEF07B4A807062C1C9f01713def52172548ECA/`
with `info.json` and `logo.png`. The manifest includes proposed identity fields,
with eligibility/status left for operator confirmation. The original PNG is
**121,177 bytes**, exceeding the current documented **100 kB** limit even though
its 512×512 dimensions are within the maximum (256×256 is recommended). Keep the
required official 512×512 original; prepare an approved optimized asset before a
real submission. Token eligibility, circular-mask appearance and approval must
also be checked. See [repository/image requirements](https://developer.trustwallet.com/developer/new-asset/repository_details)
and the [asset submission process](https://developer.trustwallet.com/developer/new-asset).

## 7. Release handoff and remaining confirmations

The report, source, unchanged dependency lockfile, static export, ABI exports,
listing worksheet and evidence form a review package. The HTML includes a launch
record with report/manifest/logo downloads and exposes the full token address.
The existing wallet flow remains subject to mainnet reads and user confirmation.
See [README.md](README.md) for installation/build/publication and
[DESIGN.md](DESIGN.md) for the implemented interface.

Before turning this draft into an official final announcement, the project
operator should establish Etherscan verification/branding status, prove LP
custody and any lock, confirm exact allocation and circulating supply, publish
the export and record its new CID, and complete provider-specific applications
with authorized contact details and an eligible Trust Wallet asset. This task
can report those unknowns accurately without inventing them.
