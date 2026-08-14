# Landing page — web → native reconstruction

Screen 1 of the priority order. Nothing else was touched.

## 1. Web route inspected

`index.html` at the repo root — 306 lines, served at `https://chopedit.com/`.
(`landing.html` is a 4-line redirect to `/`, not a page. The app lives
separately at `app/index.html` and is *not* the source for this screen.)

Section order, taken from the document, not from memory:

| # | Element | Anchor |
|---|---|---|
| 1 | `<nav>` | — |
| 2 | `<section class="hero">` + `.stage` phone | — |
| 3 | `.marq` marquee | — |
| 4 | `<section class="sect">` the transform | — |
| 5 | `<section class="sect" id="feat">` | `#feat` |
| 6 | `<section class="sect" id="price">` | `#price` |
| 7 | `<section class="sect" id="faq">` | `#faq` |
| 8 | `.offer` launch offer | — |
| 9 | `<footer>` | — |

My previous native landing had **only section 2**, and a trimmed version of it.
Sections 1 and 3–9 were absent. That is what "not the landing page" meant.

## 2. Components found

- `.btn` in three variants: `.w` (white), `.gh` (ghost, `--ln2` border), `.bl`
  (blue→violet gradient, blue glow); `.big` bumps to 15/30 at 16px, r12
- `.card` — top-lit white wash, `--ln` border, r20. `.card.out` swaps the border
  to `rgba(59,130,246,.5)` and brightens the body text
- `.feat` — `--srf` panel, r20, with a `.viz` demo well inside (`#0b0d12`, r14,
  min-height 132)
- `.price` / `.price.mid` — `.mid` carries the `MOST POPULAR` ribbon via `::before`
- `<details>` / `summary` with a `+` → `−` marker
- `.eyeb`, `h1`, `h2`, `.lead`, `.sub`, `.note`, `.badge`, `.claims`
- `em` — Georgia italic 500 under a 92deg `#60a5fa → #a78bfa` gradient. This is
  the single most recognisable thing on the page and it appears in five headings.

Landing tokens are **not** the app's tokens. Landing `--srf` is `#0f1117`;
the app's card is `#161922`. I kept them in a separate `LandColor` enum so the
two cannot bleed into each other. The landing is dark-only.

## 3. Assets found

| Asset | Handling |
|---|---|
| Inline `<svg>` Chop mark | Redrawn in `Canvas` from the same geometry — 64×64 r16 tile, r14.25 circle stroked 9.13 with dasharray 67.1/22.4 rotated 52°, and the 3.8-tall band rotated −30° masked out. **No asset catalog entry needed**, which is what was causing the purple square. |
| `hero-still.jpg` | Copied to `native-poc/HeroStill.jpg`. **You need to drag this into Assets and name it `HeroStill`.** |
| `apple-touch-icon.png`, `favicon-32.png` | Not used on-page; already covered by AppIcon. |

No SF Symbols anywhere on this screen.

## 4. Native views created

`ChopMarkView`, `LandBackdrop`, `LandColor`, `LandEyebrow`, `LandH2`, `LandLead`,
`LandCard`, `LandButton`, `LandFlexRow`, `LandFlow`, `LandNav`, `LandHero`,
`LandPhone`, `LandMarquee`, `LandTransform`, `LandArrow`, `LandMini`,
`LandFeatures`, `LandFeat`, `VizBox`, `VizTimeline`, `VizRetakes`,
`VizQuickEdit`, `LandPricing`, `LandPrice`, `LandFAQ`, `LandOffer`,
`LandOfferState`, `LandFooter`.

Animations reproduced: `cutaway` (7s, plain → struck → faded, with the five
0.6s-stepped delays), `collapse`, `glow`, `trim`, `pulse`, `blink`, and the 28s
marquee scroll.

The launch offer reads `chop_offer` from the same public REST endpoint the web
page uses, and swaps heading, body and CTA when the cap is hit — same as the
inline script.

## 5. What could not be translated directly

- **Body grid + fixed radial washes.** `background-attachment`-style fixed
  overlays don't exist in a `ScrollView`. Drawn once behind the scroll instead,
  so the glow doesn't travel with the content. Visually equivalent at rest.
- **`backdrop-filter: blur(14px)` on the nav.** Used `.ultraThinMaterial` over
  `--bg` at 0.72. iOS material, not a literal 14px blur.
- **Nav links (`Features` / `Pricing` / `FAQ`).** These are `display:none` below
  640px on the web, so the phone nav is correctly just mark + wordmark +
  `Start chopping`. Not a divergence — that *is* the mobile design.
- **Hover states.** `.btn.w:hover`, `.feat:hover`, `.price:hover` translate to
  press states; there is no hover on a phone.
- **`::before` ribbon positioning** is an overlay with a −10 offset rather than
  a pseudo-element.

## 6. Remaining differences

- The three-column grids (`.feats`, `.prices`) and the `.demo` are stacked, which
  is what the web does at ≤900px. Faithful to the responsive design.
- `.mini` and the phone filmstrip use proportional widths via `LandFlexRow`.
  CSS `flex` has no SwiftUI equivalent and `layoutPriority` is not one — this was
  a real bug in my first pass and is now fixed.
- Georgia renders slightly narrower on iOS than in Safari, so the `em` lines are
  a hair shorter than the web at the same point size.

## 7. One thing you should decide, not me

The pricing section is reproduced exactly, including `£1 / 85p / 75p per video`
and three `Get credits` buttons. On the web those go to `/app/?signup=1`, and
natively they open the create-account tab — so nothing links out to an external
purchase, which is the thing that gets apps rejected.

But App Store Guideline 3.1.1 also covers *displaying* prices for digital content
that isn't purchasable via IAP. A reviewer seeing a price table on the first
screen may flag it even though no purchase happens there.

I have not changed it, because you told me not to invent or remove. Flagging it
so it's your call, not a surprise in review.
