# SwarmSwap — implemented design

## Overview

A static Ethereum token application with a launch-record section for holders,
reviewers and listing operators. The existing dark, gold and cyan bee branding
is retained. `web/index.html` provides the document, `web/src/style.css` the
shared tokens/components, and `web/src/app.ts` the interactions. Vite exports
`dist/` with relative runtime resources. There is no component framework or
external font service.

The page moves from overview to live token statistics and swap, transfer rules,
and the evidence record. Same-page navigation makes the report directly
reachable. The report marks source evidence, live observations and pending
confirmations explicitly; a neutral Draft badge does not imply certification.
The official unchanged artwork is `assets/logo.svg` and `assets/logo.png`.

## Colors

Canonical token definitions are at `web/src/style.css:2`. The existing hex
primitives and role aliases are retained; isolated inherited glow/image-outline
values are not a separate theme. Only a dark theme is implemented.

| Semantic token | Exact value | Use |
| --- | --- | --- |
| `--color-bg` | `#0b0f14` | Page; body also has a cyan radial glow near the top |
| `--color-surface` | `#121a23` | Swap/record cards, address strip, token chips |
| `--color-surface-raised` | `#182330` | Input and select surfaces |
| `--color-line` | `#27354a` | Decorative dividers and structural card borders |
| `--color-line-control` | `#5b6f90` | Outlined button/select boundaries |
| `--color-text` | `#eef3f8` | Main text, headings and values |
| `--color-text-secondary` | `#a6b3c2` | Descriptions, labels, captions |
| `--color-text-placeholder` | `#8392a6` | Amount placeholder |
| `--color-accent` | `#f5c518` | Gold primary action, brand wordmark and headline |
| `--color-accent-hover` | `#ffd84d` | Gold action hover |
| `--color-on-accent` | `#1a1400` | Text on gold/cyan actions |
| `--color-signal` / `--color-focus` | `#19e6ff` | Links, focus rings, live signal; confirm action |
| `--color-error` | `#ff9b8f` | Explicit error messages |

The report's rendered WCAG 2 pairs were measured in Chromium: primary text/card
**15.71:1**, secondary text/card **8.22:1**, cyan link/card **11.53:1**, dark text/gold
button **11.26:1**, and draft-label text/page **9.01:1**. These apply to those
identified solid backgrounds, not all states or gradient/image regions.
The evidence JSON retains the measured RGB pairs. Color never carries status
alone: “Draft”, “Not verified”, errors and pending checks also appear in text.

## Typography

The font stack is `Inter, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica,
Arial, sans-serif`. No Inter font is bundled; the system fallback is expected.
Exact platform font identity and all synthesized weights were not separately
audited. Root smoothing is enabled.

The source scale is: `--text-xs` .75rem, `--text-sm` .8125rem, `--text-base` 1rem,
`--text-md` 1.0625rem, `--text-lg` 1.5rem, `--text-xl`
`clamp(2.25rem, 5vw, 3.5rem)`, and `--text-display`
`clamp(3rem, 6.5vw, 5.5rem)`. At the default 16px root these are 12, 13, 16, 17,
24, 36–56 and 48–88px.

- Hero h1: 600, line-height 1.03, −.04em tracking. In a content container up to
  25rem it uses `clamp(2.5rem, 12cqi, 3rem)` to retain readable short lines.
- Trade/report h2: 600, the XL scale, about 1.05/1.1 line-height, −.03em tracking.
  The transfer-rules h2 is a quieter 1.5rem.
- Card h3: 1.25rem/1.3, weight 600; download heading: 1.5rem/1.3.
- Report prose: 1rem, line-height 1.6–1.65, capped at 60–70ch where appropriate.
  Existing compact transfer details use .8125rem/1.8.
- Eyebrows: .75rem, 700, uppercase, .18em tracking. Card index tracking is .12em.
- Stats, quote amounts, block numbers and report values use tabular numerals.
- Full addresses use monospace and `overflow-wrap: anywhere`, without truncation.
  Heading balance and paragraph pretty wrapping are used throughout.
- Amount input: 2rem, falling to 1.5rem at the small viewport breakpoint.
  Selects stay at 1rem; fields have persistent labels.

## Layout

Main/header/footer have a 77.5rem maximum width. Side margins are 2.5rem below
82.5rem viewport width, 1.375rem below 50rem and 1rem below 36rem. Spacing tokens
are .25, .5, .75, 1, 1.5, 2, 3 and 4rem. Logical margin/padding properties retain
consistent leading/trailing edges. Header and navigation wrap in normal flow.

The existing hero begins at 1.35fr/1fr, statistics at four columns, swap and
transfer details at two. Viewport rules reduce stats to two columns at 50rem and
one at 36rem; the small viewport also stacks hero/trade/details. The network
label is hidden below 50rem, footer tagline below 36rem, and the small header
wordmark is visually hidden below 22.5rem while remaining accessible.

`main` is additionally an inline-size container. At a **48rem content width**,
hero/trade/details stack and the stats and record facts use auto-fit columns with
13rem minimums bounded by 100%. These container thresholds track enlarged text,
which fixed viewport breakpoints alone did not. Below **25rem content width**,
form rows, allocation labels and the amount box wrap, and the download action
can fill the available width.

The report has three equal `minmax(0, 1fr)` cards with 1.5rem gaps. At 62rem
viewport width they become one column, with fact lists initially in three
columns. The container rules collapse facts as text grows. The address strip
wraps its copy action without hiding the address. The download row wraps and
stacks under 50rem; prose and actions have no fixed text heights.

Rendered checks covered 1440, 820, 576, 375 and 320 CSS px, plus 200% root text
enlargement at 820px. All final checks showed no horizontal overflow. Native
browser zoom, RTL and physical devices were not tested.

## Elevation & depth

Record cards are flat `--color-surface` planes with structural borders. The
existing swap card retains `0 1.5rem 3rem #00000055` shadow and a faint cyan border
shadow. Hero artwork has its existing cyan glow/drop shadow; logo images have a
1px inset white-at-10%-opacity outline. The live dot has a cyan halo. No modal,
sticky navigation, overlay or entrance animation was introduced. The skip link
uses z-index 10 and is otherwise out of view.

## Shapes

`--radius-sm` .5rem: small badges, select and header logo.
`--radius-md` .75rem: amount box, address strip and download/primary action.
`--radius-lg` 1.375rem: swap card, record cards and hero artwork.
`--radius-pill` 999px: outlined buttons, status badge and token chips.
Token thumbnails are circular, allocation bars use 2px corners. The full artwork
remains square and is not replaced by a cropped submission asset.

## Components

All components are document/CSS patterns, not library exports.

| Pattern | Source/reuse point | Behavior |
| --- | --- | --- |
| Brand lockup | `.brand`, `.brand-logo`, `installBranding()` | Header/footer SVG; Vite-resolved URLs; decorative image alongside visible brand name |
| Page navigation | `.section-nav` | Native same-page anchors, wrapping row, 44px minimum target height |
| Quiet action | `.quiet` | Outlined pill; wallet connect, retry, copy; hover, disabled and visible focus states |
| Swap form | `.swap-card`, `review()`, `execute()` | Native direction/slippage selects, integer amounts, explicit quote/confirm stages; wallet-required controls |
| Field feedback | `#amount-error`, `.field-error` | Inline alert, aria-invalid and input focus before any wallet request |
| Token rows | `.token-chip`, `syncSelector()` | SVG follows SWARM on either pay/receive side; data-contract holds the exact CA; native dropdown option rows remain text |
| Connection feedback | `.connection-row`, `update()` | Verified state or explicit error; Retry connection appears after failure; mismatch disables trading |
| Contract strip | `.contract-strip`, `#copy-address` | Full selectable CA; Clipboard API with visible success or manual-copy fallback |
| Record card | `.record-card`, `.record-index` | Numbered label, heading, prose, native definition list and underlined evidence/download link |
| Download action | `.download-button` | Gold anchor with download attribute; wrapping label, format caption; JS is not required for Markdown/JSON downloads |
| Audit disclosure | `.audit-disclosure` | Native details/summary, Enter/Space toggling, browser semantics, visible focus |
| Status regions | `#swap-status`, `#copy-status`, `#data-status` | Swap/copy feedback uses polite announcements; passive block updates are not a live region. Connection failures are also announced through swap-status |

Focus is a 3px cyan outline with 4px offset on buttons, links, fields, main and
summary. Forced-colors uses the system Highlight outline. No overlay focus trap
is needed. Transitions name only affected properties and use 150ms
`cubic-bezier(0.2, 0, 0, 1)`. Existing pointer press scale is .96; reduced motion
disables transitions and restores press scale to 1. Download hover changes fill
only. No loading spinner is necessary: disabled controls and explanatory text
communicate unavailable/busy states.

## Do's and don'ts

- Reuse role tokens, spacing steps and card/link patterns. Keep secondary actions
  outlined or underlined; reserve a filled primary action for the current task.
- Keep source assets unchanged and use their Vite-resolved URLs for downloads.
  Do not write `../assets` links into the final static export.
- Distinguish a recorded snapshot from live data and an unverified claim from a
  completed check. Do not label a draft worksheet an approved listing or audit.
- Let addresses, long labels and fact rows wrap. Test enlarged text as well as
  narrow viewports; do not solve overflow by hiding useful information.
- Add related content as a semantic section inside main, using an h2, the shared
  surfaces and a navigation anchor. There is no multi-page router to configure.
- Preserve the gold/cyan/dark identity. No light theme, custom select, animation
  library or external font is needed for another record section.

Review evidence and remaining limits: [validation record](docs/audit/validation.md).
Guidance attribution: [docs/INTERFACE-NOTICE.md](docs/INTERFACE-NOTICE.md).
