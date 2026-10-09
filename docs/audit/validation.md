# SWARM launch report — validation record

**Complete for the stated local delivery scope.** Prepared 9 October 2026.
This is the worker's evidence record, not an independent audit or certification.
Production publication, LP-lock proof and external listing approvals are explicitly
pending facts, not claimed outcomes of this task.

## Scope and implementation

Preserved the existing HTML/CSS/TypeScript/Vite SwarmSwap application and official
assets. Added the root contract report, listing worksheet, verification inputs,
ABI exports, evidence archive and a report section with address copying and
report/JSON/PNG downloads. Corrected missing canonical/OpenGraph metadata and
misleading supply language. Added runtime-code checks before enabling trading,
recoverable connection errors and accessible pre-wallet amount validation.
Contracts, existing build configuration, dependency manifests/lockfiles and
vendored libraries were not changed. No wallets, keys or private RPCs were used.

The root report is authoritative. `web/scripts/sync-report.mjs` generates its
public copy and the listing JSON copy before Vite builds. The report's audit
facts refer to block 26,156,668 and dated live HTTP observations; the UI's live
stats can use newer blocks. Report evidence is archived under `docs/audit/`
because this worker excludes `artifacts/` from Git submission. Reproduction
scripts write fresh results under `artifacts/`.

## Commands and observed results

| Check | Actual result |
| --- | --- |
| `npm ci` in a `/tmp/swarm-validation-*` mirror using the unchanged package/lock | Exit 0; 17 installed packages; no repository node_modules or cache created |
| `node web/scripts/sync-report.mjs` | Exit 0; public report and listing copies generated |
| `npm run typecheck` in that mirror | Exit 0; TypeScript 5.9.3, `tsc --noEmit -p tsconfig.json` |
| `npm test` in that mirror | Exit 0; **9/9** unit tests passed |
| `npm run build` in that mirror | Exit 0; Vite **7.3.7**, 9 transformed modules; completed export copied to repo `dist/` |
| `forge build --offline` | Exit 0; Solidity **0.8.26**, compilation succeeded; lint warnings disclosed in report |
| `forge test --offline` | Exit 0; **78/78**, 9 suites, 0 skipped; default 256 fuzz runs |
| `forge test --offline --fuzz-seed 0x1091 --fuzz-runs 1024` | Exit 0; **78/78**, 9 suites, 0 skipped |
| `forge fmt --check` | Exit 0; no formatting differences; contracts unchanged |
| `python3 docs/audit/verify-build.py` | Exit 0; both pinned ABI and creation hashes match; runtime templates and getter-derived immutables match; token source files match Sourcify |
| `python3 .../verify-launch.py --block 26156668` for PublicNode and dRPC | Successful read-only snapshots; identical successful results including block hash, state, receipt and code |
| `node docs/audit/inspect-live.mjs` | Exit 0; live header and buy/sell token logos, manifest/list and asset bytes inspected |
| `node docs/audit/validate-browser.mjs` | Exit 0; final production export, live reads and mocked-wallet flows checked |

Tools used: Node 22.23.3, npm 10.9.9, Foundry 1.8.3, Python 3.12; system-provided
Playwright and Chromium headless shell build 1246. Package dependencies were
installed in the temporary mirror, not copied into this repository. Build output
contains local JS/CSS/assets with no build-time network fetches. Logs are in
`evidence/typecheck.log`, `frontend-tests.log`, `production-build.log`,
`forge-test.log`, `forge-test-second-seed.log` and `browser-run.log`.

The supplied browser connector failed with **Transport closed**. A direct launch
of regular Chromium also failed on crashpad initialization. The installed
headless shell worked. The browser script owns a local HTTP server and closes it
and the browser in its foreground command; no persistent shell server was left.
This fallback produced real browser screenshots and interaction results.

## Production-export browser checks

The actual `dist/` was served under a generated `http://127.0.0.1:<port>/preview/`
subpath. The script and recorded evidence use that local URL only for testing;
it is not a deployed project endpoint.

**Rendered widths:** 1440, 820, 576, 375 and 320 CSS px, all with height 1000.
Every checked width had `documentElement.scrollWidth === innerWidth`, no
out-of-viewport content detected and no broken images. Root font size 200% at
820px also produced scrollWidth 820, with no out-of-viewport elements. This is
text enlargement, not browser-native zoom. Screenshots were opened and inspected.

**Live production-preview interactions:** initial chain/metadata/runtime checks;
report-anchor navigation; full CA copying with exact clipboard comparison;
Markdown, listing JSON and PNG downloads checked byte-for-byte against source;
native Buy/Sell selector and visible SWARM SVG in either direction; invalid
amount alert/focus before wallet request; missing-wallet recovery; skip-link
activation, Tab traversal, keyboard disclosure; reduced-motion transition check.
The script recorded no unexpected console errors or failed resource requests.

**Explicit wallet/RPC fixtures:** 1,000 SWARM quoted output and 995 minimum at
0.5%; 990 minimum after changing to 1%; no swap request before confirmation;
account change invalidates quote; expiry after 31 seconds of virtual time;
buy confirmation sends the correct adapter/value to the mock provider; sell
review requests an exact 100 SWARM approval; wallet rejection clears the stale
quote; RPC failure, wrong chain and incorrect runtime code disable trading;
Retry connection recovers each; denied clipboard shows manual-copy instructions.
All wallet sends in these checks terminate inside the mock provider. No real
wallet was connected, no transaction was signed, and no mainnet swap was executed.

Evidence:

- [Browser results](evidence/browser-review.json), including exact RGB/contrast pairs.
- [Desktop export](evidence/site-1440.webp), [375px overview](evidence/site-375.webp),
  [320px overview](evidence/site-320.webp).
- [Desktop report](evidence/report-desktop.webp), [mobile report](evidence/report-mobile.webp).
- [Skip-link focus](evidence/keyboard-focus.webp), [keyboard disclosure focus](evidence/disclosure-focus.webp).
- [200% text enlargement](evidence/text-enlargement.webp).
- [Live-domain browser record](evidence/live-browser.json) and [live screenshot](evidence/live-desktop.webp),
  distinct from this unpublished export.

## Package integrity

Final package check resolved all local report/document links, 13 relative HTML
asset/download references and 7 internal anchors. Root, public and dist report
and listing copies match byte-for-byte, as do both brand assets and manifests.
All 93 protected dependency/build files checked against the initial inventory
are unchanged; no Git metadata or ignore files were edited. No node_modules,
cache, vendored npm archive or submodule is included. The candidate tree was
approximately **3.55 MB uncompressed**, with a **1.68 MB compressed tree proxy**,
well below the 8,388,608-byte limit. `git diff --check` passed. See
[evidence/package-check.json](evidence/package-check.json). A real Git bundle was
not created because this task forbids modifying `.git/`; final Git submission
is handled by the worker. The proxy is not mislabeled as a Git bundle.

## Better Interface consolidated review

Applied the pinned workflow and core principles of all six domains during the
changes, then reviewed the final source/export and corrected observed issues.
Scope is the changed report, metadata and affected shared/swap controls. The
existing visual identity and stack were retained.

| Domain | Coverage and evidence | Limits / not applicable |
| --- | --- | --- |
| Accessibility — Checked | Native landmarks/headings, button/link distinction, labels, aria-invalid/alert, 44px control targets, skip and Tab traversal, visible cyan focus in screenshots, native keyboard disclosure and reduced motion | No screen-reader session, physical touch device, full automated accessibility audit or complete forced-colors rendering check; no modal/focus trap needed |
| Layout — Checked | Shared edges, three-card report to stacked layout, full address wrapping, normal-flow actions, 5 viewport widths, container rules and 200% enlarged text | Native 200% zoom and intermediate widths beyond those listed untested; RTL/localized layouts not implemented |
| Writing — Checked | Precise fixed-supply/sink wording; explicit source/live/draft distinction; verb-led actions; recoverable errors; full contract identity; no unearned “verified LP” or listing approval claims | Third-party approval and post-publication social-crawler text remain outside local control |
| Typography — Checked | Source type hierarchy, readable measure/line-height, tabular numbers, visible mobile input text, address wrapping and screenshot inspection | Platform font identity/synthesis and every locale were not tested; no bundled/external font to validate |
| Colors — Checked | Reused existing semantic palette; actual record-card and action pairs measured: 15.71:1 main text/card, 8.22:1 secondary/card, 11.53:1 link/card, 11.26:1 action text/gold, 9.01:1 draft/page; textual status cues | Not a complete contrast audit of every inherited gradient, logo, disabled or hover state; no light theme exists |
| UI — Checked | Native disclosure, card/field/action states, download and clipboard feedback, disabled trading, retry and cancellation states; restrained 150ms transitions and reduced-motion override | No 10%-speed DevTools animation replay; no entrance/exit animation or icon transition was added |

### Findings, fixes and rechecks

Locations below identify the final source. Severity reflects the observed task
impact, not an independent security classification.

| Finding | Severity / source | Evidence, fix and recheck |
| --- | --- | --- |
| Missing canonical and social image metadata | Medium — `web/index.html:12` | Captured live HTML and live browser both lacked canonical/og:url/og:image. Added official-domain fields, image type/dimensions/alt and Twitter image metadata. Final HTML contains them; deployment/crawler refresh remains pending |
| Hero incorrectly implied falling ERC-20 supply | Medium — `web/index.html:46` | Original “Less supply” conflicted with fixed totalSupply. Replaced with “Fixed supply. Clear rules.” and explicit sink mechanics; source and rendered copy checked |
| PNG download escaped the gateway subpath | High — `web/index.html:136`, `web/src/app.ts:265` | Initial browser download was canceled because `../assets/logo.png` resolved outside `/preview/`. Bound download to Vite's imported asset URL, with relative production fallback; final download succeeded and bytes equal the 512×512 original |
| Enlarged text overflowed fixed column layouts | High — `web/src/style.css:235` | At 820px and 200% root text, initial scrollWidth was 959px. Added container-dependent stacking/wrapping and flexible download row. Rechecked: scrollWidth 820px; no overflow elements; screenshots inspected |
| Invalid amount prompted wallet before explaining input error | Medium — `web/src/app.ts:183`, `web/index.html:80` | Source parsed amount after wallet connection. Moved parsing first, added an inline alert, aria-invalid and field focus. Browser invalid-input check shows the message and focuses amount without a wallet request |
| Read failure left an unhelpful pending trade state | Medium — `web/src/app.ts:295`, `web/index.html:64` | Added explicit unavailable message and Retry connection. Offline/wrong-chain/wrong-code fixtures disable review and recover after retry |
| Contract identity was not checked against runtime bytes | High — `web/src/app.ts:127`, `web/src/deployed-code.ts:1` | Previous flow checked getters only. Added exact reviewed runtime comparison before enabling trading; live bytes pass, mismatched fixture bytes disable trading. Source and protected contracts unchanged |
| Review evidence would be omitted from Git | Medium — `docs/audit/README.md:1` | Worker excludes artifacts/ via existing Git exclusions. Archived evidence, scripts and listing worksheet under docs/audit and updated root report links; no ignore file or Git metadata changed |

No reproduced local-delivery blocker remains. Remaining confirmations are
explicit in the report: Etherscan's HTTP-403-protected status; LP custody/locking;
indexer eligibility/approval; Trust Wallet's current 100kB limit versus the
121,177-byte original; new export CID and production publication. A platform
security audit, live-wallet trade, screen reader, native zoom, physical device,
ENS resolver and independent IPFS block validation were not performed.

Attribution: [../INTERFACE-NOTICE.md](../INTERFACE-NOTICE.md), with both pinned
licenses preserved. This review does not replace the required build/test evidence.
