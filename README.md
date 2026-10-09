# swarm (SWARM) · SwarmSwap

<img src="assets/logo.svg" alt="SWARM logo" width="96" align="right">

Ethereum mainnet token and native ETH swap application. The token is deployed at
**`0xd2aef07b4a807062c1c9f01713def52172548eca`**. This repository contains the
contract source, the existing TypeScript/Vite application, its static export and
the post-deployment evidence package. No contract is deployed by this assignment.

Start with **[SWARM_DRAFT_CONTRACT_REPORT.md](SWARM_DRAFT_CONTRACT_REPORT.md)** for
contract specifications, verified-source parameters, security boundaries, the
live branding/CID audit and external listing requirements. The report distinguishes
observed facts from pending confirmations; it is not an independent audit.

- [Listing worksheet](docs/audit/swarm.listing-draft.json): Etherscan, CoinGecko,
  DexScreener and Trust Wallet preparation; no applications submitted.
- [Validation record](docs/audit/validation.md): actual build, test, browser and
  six-domain Better Interface results, with limitations.
- [Design system](DESIGN.md): implemented tokens, typography, components and reflow.
- [ABI exports](docs/abi/): local ABIs checked against the pinned deployment hashes.

## Install, develop, rebuild and preview

Use Node **22.23.3 or later in the Node 22 line**, or a supported newer Node
release with native TypeScript stripping. npm 10.9.9 was used. The existing
`web/package.json`, lockfile and Vite/TypeScript configuration are unchanged.
The lock resolves Vite 7.3.7 and TypeScript 5.9.3.

```sh
cd web
npm ci
node scripts/sync-report.mjs
npm run dev
```

Production validation and preview:

```sh
cd web
node scripts/sync-report.mjs
npm run typecheck
npm test
npm run build
npm run preview -- --host 127.0.0.1
```

`sync-report.mjs` copies the authoritative root Markdown report and
`docs/audit/swarm.listing-draft.json` into `web/public/`; run it whenever either
changes. Vite copies those downloads and manifests into `dist/`, and bundles the
source and brand assets. The production build uses installed, lockfile-pinned
dependencies and does not fetch remote assets. Installation may need the npm
registry; a vendored registry is neither required nor included.

For this worker run, dependencies were installed with `npm ci` in a temporary
mirror under `/tmp`, then the same package scripts ran against byte-identical
source/configuration. The resulting `dist/` was copied back. This preserved the
repository's protected package files and kept all `node_modules` and package
caches outside the submission.

The application is plain HTML/CSS/TypeScript; it retains the existing stack and
uses an injected EIP-1193 wallet. No framework, wallet SDK, font service, analytics
or backend was added. The official SVG and 512×512 PNG remain in `assets/`.

## Publish the static export

Publish **the contents of `dist/`**, including all assets, manifests and downloads,
to `https://swarm.sites.imd.fun/`, or to a static gateway subpath. The publisher
serves this export without rebuilding. Include `dist/`, source, manifests and
`web/package-lock.json` in the submission; exclude dependencies/caches. Vite's
existing `base: "./"` keeps runtime resources relative. Navigation uses same-page
anchors and requires no server route rewriting. Use HTTPS for wallet/clipboard
support.

The canonical and OpenGraph URLs intentionally name the official domain;
`og:image` is `https://swarm.sites.imd.fun/assets/logo.png`. Runtime images,
JavaScript, CSS, manifests and downloads remain relative. If the canonical domain
changes, review those metadata fields and the listing worksheet together.

Publishing is an operator step and was **not performed** here. The previously
hosted CID is `bafybeid3t2wvhqu6xb55dtbgmtdk2enyniinucfbd2juqltwaaohg5dceq`;
the live `x-ipfs-cid` header matched it during this audit. The new export has no
claimed CID. After upload, record the actual new CID, verify domain/ENS resolution,
compare served asset bytes and refresh social previews. Never reuse the old CID
as proof of publication of these changes.

## Reproduce contract evidence

The deployed compiler is **Solidity 0.8.26**, optimizer enabled with **200 runs**,
EVM **cancun**, metadata bytecode hash **none**. Use the existing configuration;
do not migrate compiler settings for verification. Dependencies are local files
under `lib/` with their original licenses. No keys or private endpoints are needed.

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x1091 --fuzz-runs 1024
forge fmt --check
python3 docs/audit/verify-launch.py --block 26156668
python3 docs/audit/verify-build.py
```

The last two commands require Python 3, curl and `cast`; only `verify-launch.py`
needs network access. It issues read-only requests to the public Ethereum RPCs,
records exact calldata and block tags, and writes evidence only under `artifacts/`.
The independent endpoint check uses:

```sh
python3 docs/audit/verify-launch.py --block 26156668 \
  --rpc https://eth.drpc.org \
  --output artifacts/evidence/chain-snapshot-drpc.json
```

The scanner uses batches of three to respect dRPC's observed free-endpoint limit.
The build verifier hashes ABIs using recursively sorted object keys, preserved
Foundry array order and whitespace-free UTF-8, then Ethereum keccak256. It also
compares creation-code hashes and runtime bytes, excluding only the compiler's
immutable references. The saved source-verification input is
`docs/audit/verification/Swarm.standard-input.json`. The contracts are already
live; there is no deployment or minting command in this handoff.

## Application behavior and boundaries

The site reads metadata, supply, automatic sink charges and pool state at a single
block. It checks Ethereum chain ID, both contracts' exact reviewed runtime bytes,
metadata and contract relationships before enabling trading. Public RPC failure,
wrong chain or code mismatch disables trading and offers **Retry connection**.
`web/src/deployed-code.ts` contains the runtime bytes from the audited snapshot;
regenerate it only after repeating the verification against reviewed evidence.

The pinned pool uses native ETH/SWARM, fee **12500 (1.25%)**, spacing **60**, and the
platform initialization guard `0x784ff9a3ac5d88a30bfff6f7f2a270161fbe6000`.
The application adapter is `0x4bc05bda38e6e4a6158b5eeb825208c1f2380360`.
The accepted manifest's opening capitalization is **1 ETH**, not the 10 ETH in the
historical template `deployment/parameters.json`; that file is retained only as
historical provenance. Use the report's observed state, not template assumptions.

Amounts use integer arithmetic. Quotes simulate the adapter via wallet `eth_call`,
expire after 30 seconds, and include a 0.5%, 1% or 2% minimum-output tolerance.
Transactions expire after two minutes. Sells first request an exact-amount
approval when needed. Only a separate **Confirm swap** sends the swap request.
Account, chain, direction, amount and slippage changes invalidate the quote.
A spot price is not an oracle or a guaranteed quote. Failed or pending receipts
and wallet cancellations are surfaced. Real transactions spend gas and require
the visitor's wallet; none were sent during this work.

The token mints one billion units once. Ordinary transfers send floor(amount/100)
to DEAD without reducing `totalSupply`. The immutable factory, registered
distributor and PoolManager settlement paths are exempt. Permissionless
PoolManager pass-throughs can therefore bypass the 1% charge. There is no token
owner or later mint, but the external factory registry is a trust boundary.
Ownerlessness does not establish LP locking. Details and audit specifications
are in the report and `SECURITY.md`.

## Actual checks and limitations

On 9 October 2026, production build and typecheck passed; all **9 frontend unit
tests** passed. All **78 contract tests** passed both normally and with the second
fuzz seed at 1,024 runs. Formatting check passed. Both supplied RPCs agreed at
block 26,156,668. Pinned ABI and creation hashes matched, and runtime comparisons
passed. Sourcify reports a match for Swarm; Etherscan returned HTTP 403, and
SwarmSwap's Sourcify match was null.

`docs/audit/validate-browser.mjs` serves the production export under `/preview/`
in a bounded foreground process and closes its server/browser. It exercises live
reads, responsive widths, downloads, copying, keyboard disclosure and errors,
then uses an explicitly mocked wallet/RPC to exercise quotes, approval, expiry,
confirmation and rejection without broadcasting. It needs an external Playwright
installation and Chromium; no browser package is included in runtime dependencies.
On this box run:

```sh
node docs/audit/validate-browser.mjs
```

Elsewhere set `SWARM_PLAYWRIGHT_MODULE` to the installed Playwright `index.mjs` and
`SWARM_CHROMIUM` to a compatible Chromium executable. This script replaces the
local browser evidence files and needs public RPC access for its live-read case.
The supplied browser connector returned `Transport closed`; local headless
Chromium provided the rendered checks instead.

Confirmed widths: 1440, 820, 576, 375 and 320 CSS px, plus 200% root text enlargement
at 820 px. The final checked export had no horizontal overflow, broken images,
unexpected browser-console errors or failed resource requests. Full screen-reader
sessions, physical devices, native browser zoom, RTL/localization, third-party
social previews and live signed swap execution were not tested. Pending LP lock,
external approvals and the oversized Trust Wallet submission PNG are disclosed in
the report. These are worker observations, not independent certification.

Design guidance attribution and licenses: [docs/INTERFACE-NOTICE.md](docs/INTERFACE-NOTICE.md).
