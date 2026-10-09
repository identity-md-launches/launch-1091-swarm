# Vendored dependencies

All contract dependencies are ordinary source files under `lib/`; no install,
submodule, package manager, network access, or FFI is needed to build or test.
Only relevant source files and their original licenses are included. The website
uses native browser APIs and has no runtime dependencies or external assets; its build
uses Vite and TypeScript as dev dependencies pinned in `web/package-lock.json`.

| Package | Revision | Scope | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.2.0, `acd4ff74de833399287ed6b31b4debf6b2b35527` | ERC20, metadata/error interfaces, Context, ReentrancyGuard | MIT, `lib/openzeppelin-contracts/LICENSE` |
| Uniswap v4-core | `46c6834698c48bc4a463a86d8420f4eb1d7f3b75` | Core sources excluding upstream tests | Per-file SPDX; MIT and BUSL-1.1 texts in `lib/v4-core/licenses/` |
| Solmate | `89365b880c4f3c786bdd453d4b8e8fe410344a69` | Owned, used by the local PoolManager | MIT per Owned.sol's SPDX; upstream `lib/solmate/LICENSE` refers to per-file SPDX |
| forge-std | v1.9.7, `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Solidity test utilities | MIT/Apache-2.0, texts in `lib/forge-std/` |

Sources came from the corresponding GitHub repositories at the pinned revisions.
The PoolManager implementation is used in tests, not deployed by this project.
The application imports MIT-licensed v4 interfaces, types, and state/math helpers.
