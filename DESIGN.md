# SwarmSwap design system

Documents the implemented design of the SWARM website as it exists in `web/` after the
branding job. Values are taken from the source files named below, not from a mock-up.
Rendered observations come from the scripted Chromium checks recorded in
`artifacts/validation.md`; anything not listed there is unverified.

## Overview

One static page, built with Vite from `web/index.html`, `web/src/style.css` and
`web/src/app.ts`, exported to `dist/` with relative URLs. The brand is a dark ground with
two neon accents taken from the logo: gold for the one filled action and headline
emphasis, cyan for focus, links and live signals. The official mark lives in
`assets/logo.svg` (source of truth) and `assets/logo.png` (512×512 raster made from the
SVG); both are bundled into `dist/assets/` under those exact names.

## Colors

All tokens are declared once on `:root` in `web/src/style.css`. Components reference
semantic tokens only; primitives are named by hue and step.

| Semantic token | Primitive | Value | Role |
| --- | --- | --- | --- |
| `--color-bg` | `--ink-950` | `#0b0f14` | Page background (plus a cyan radial glow on `body`) |
| `--color-surface` | `--ink-900` | `#121a23` | Swap card, token chips |
| `--color-surface-raised` | `--ink-800` | `#182330` | Amount box, selects |
| `--color-line` | `--ink-700` | `#27354a` | Structural dividers and section borders (decorative) |
| `--color-line-control` | `--ink-600` | `#5b6f90` | Borders of controls: selects, chips, outlined button |
| `--color-text` | `--gray-100` | `#eef3f8` | Primary text |
| `--color-text-secondary` | `--gray-300` | `#a6b3c2` | Labels, captions, body copy |
| `--color-text-placeholder` | `--ink-400` | `#8392a6` | Input placeholder |
| `--color-accent` | `--gold-500` | `#f5c518` | Filled primary action, brand name, headline emphasis, pool share bar |
| `--color-accent-hover` | `--gold-400` | `#ffd84d` | Primary action hover |
| `--color-on-accent` | `--gold-950` | `#1a1400` | Text on gold or cyan fills |
| `--color-signal` | `--cyan-400` | `#19e6ff` | Eyebrows, links, live dot, pill, confirm button fill |
| `--color-focus` | `--cyan-400` | `#19e6ff` | 3px focus ring, 4px offset, on every focusable element |
| `--color-error` | `--red-300` | `#ff9b8f` | Error text in status regions (always paired with the message text) |

Measured WCAG 2 contrast for the declared pairs (`test/scratch` script, recorded in
`artifacts/validation.md`): primary text on background 17.2:1, secondary text on
background 9.0:1 and on the card 8.2:1, gold on background 11.8:1, dark text on gold
11.3:1 and on cyan 12.1:1, cyan on background 12.6:1 and on the card 11.5:1, error on
card 8.6:1, placeholder on the amount box 5.0:1, control borders 3.1–3.8:1 against
every surface they sit on. Structural `--color-line` dividers are 1.55:1 and are
intentionally decorative. There is no light theme; `color-scheme: dark` is declared.

Rules: one filled gold action per view (`Review swap`; `Confirm swap` replaces it and is
cyan-filled so the second step reads as a different, final action). Cyan on static text
is limited to eyebrows and the brand caption. Selection uses gold with dark text.

## Typography

- Family: `Inter, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`.
  No font files ship; Inter is used only if installed, so the rendered face is the
  platform's system sans. Root sets antialiased smoothing.
- Scale (`:root`): `--text-xs` 12px, `--text-sm` 13px, `--text-base` 16px, `--text-md` 17px,
  `--text-lg` 24px, `--text-xl` clamp(36px, 5vw, 56px), `--text-display` clamp(48px, 6.5vw, 88px).
- Roles: `h1` display size, weight 600, line-height 1.03, letter-spacing −0.04em;
  `h2` `--text-xl`, weight 600, line-height 1.05; `h3` `--text-lg`, weight 600; body and
  lede 16–17px at line-height 1.65–1.8; labels and captions 12–13px; eyebrows 12px
  uppercase with 0.18em tracking. Measured heading sizes descend at every width checked
  (88/56/24px desktop, 48/36/24px at 375px and 320px).
- Numbers: stats, the amount input, quotes and the block status use
  `font-variant-numeric: tabular-nums`. Long values use `overflow-wrap: anywhere` as a
  last resort; below 36rem the stats become one column so values never break mid-digit.
- Wrapping: headings `text-wrap: balance`, paragraphs `text-wrap: pretty`, badges and chips
  `white-space: nowrap`. Long-form paragraphs in `.details` are capped at `65ch`.
- Inputs: the amount field is 32px (24px under 36rem) and selects are 16px, so iOS never
  zooms on focus.

## Layout

- Content width `77.5rem` (1240px) centered; side margins step down at the breakpoints
  `82.5rem` (2.5rem), `50rem` (1.375rem) and `36rem` (1rem). Logical properties
  (`margin-inline`, `padding-inline-start`, `border-inline-end`) are used throughout.
- Spacing steps `--space-1` … `--space-10` (4px to 64px). Groups are separated by space
  first; dividers appear only on the stats band, section tops and the footer.
- Sections: `.hero` is a 1.35fr/1fr grid (text, logo figure) that stacks at 36rem;
  `.stats` is four columns, two under 50rem, one under 36rem; `.trade-section` is two
  equal columns (copy, swap card) that stack at 36rem; `.details` is two text columns
  that stack at 36rem. Hidden at small widths: the network label under 50rem, the
  footer tagline under 36rem; at 22.5rem the header wordmark is visually hidden but
  stays in the accessible name.
- Observed in Chromium: no horizontal overflow at 1366, 820, 375 and 320px widths.
  Widths between those points, native 200% zoom and RTL were not checked.

## Elevation & depth

Flat surfaces with one lifted card. The swap card has a 1px structural border plus
`0 1.5rem 3rem #00000055` and a faint cyan 1px glow. The hero logo carries a cyan glow
and a drop shadow. Logo images use a 1px `oklch(1 0 0 / 0.1)` outline inset by 1px.
The live dot has a cyan box-shadow halo. No overlays or stacking contexts beyond the
skip link (`z-index: 10`).

## Shapes

`--radius-sm` 8px (badges, selects, header logo, skip link), `--radius-md` 12px (amount
box, primary buttons), `--radius-lg` 22px (swap card, hero logo), `--radius-pill` for
the outlined header button, the pill and token chips. Token logos are circular.
Allocation bar segments use 2px.

## Components

All components are plain HTML and CSS classes in `web/index.html` and `web/src/style.css`;
behaviour lives in `web/src/app.ts`.

- **Brand lockup** (`.brand`, `.brand-logo`, `.brand-text`): logo plus `SWARM` wordmark
  and `SwarmSwap` app name, used in the header and footer. `img[data-logo]` elements get
  their `src` from the bundled asset URL at start-up.
- **Outlined button** (`.quiet`): the wallet connect control, pill-shaped, 44px tall.
  Shows the shortened address once connected and an `aria-label` with the full address.
- **Primary button** (`.primary`, `.primary.confirm`): full-width, 48px minimum, gold or
  cyan fill. Enabled only when the chain read succeeded; disabled state at 50% opacity
  with `not-allowed` cursor. Press feedback scales to 0.96 on pointer devices only.
- **Swap card** (`.swap-card`, `.card-heading`, `.form-row`, `.amount-box`,
  `.quote-row`): the primary task. Native `select` for direction and slippage, a single
  amount input labelled "You pay", quote rows, the status region
  (`#swap-status`, `role="status"`, `aria-live="polite"`) and the transaction link.
- **Token selector** (`.token-chip`, `.token-logo`, `.token-glyph`, `.token-text`): the
  pay and receive chips follow the direction select. SWARM shows `assets/logo.svg`
  with alt text; ETH shows a Ξ glyph marked decorative. Rendered by `renderToken` in
  `web/src/app.ts`.
- **Stats band** (`.stats article`): label, value, caption. Values are tabular numerals.
- **Status line** (`.data-status`): block number and update time, refreshed every 20s;
  deliberately not a live region so it does not re-announce.
- **Badges** (`.token-tag li`, `.pill`): uppercase 12px facts and the ETH ↔ SWARM pill.
- **Skip link** (`.skip-link`): first tab stop, visible on focus, targets `main`.

Keyboard order observed: skip link, brand, connect, direction, amount, slippage, review,
footer brand, two Etherscan links. Every stop shows the 3px cyan ring.

## Do's and don'ts

- Start a new surface from `.swap-card` and the `--space-*` steps; use `--color-line`
  for structure and `--color-line-control` for anything interactive.
- Keep exactly one gold-filled action per view. Secondary actions use `.quiet`.
- Put brand files only in `assets/`; import them from TypeScript or reference
  `../assets/…` from `web/index.html` so Vite emits `dist/assets/logo.svg` and
  `dist/assets/logo.png` under those stable names (see `web/vite.config.ts`).
- Do not add a live region for passive data; reserve `role="status"` for the swap flow.
- Do not introduce a light theme or a second notation; all colors are hex primitives.
- Adding a page: copy `web/index.html`'s `head` and `header`, keep the stylesheet and
  the `#main` landmark, and import `./src/style.css`; Vite's `base: "./"` keeps it
  relative.
