# Typed — Brand Guide

> Type-driven, minimal, warm. A monospace letter, a single deliberate accent.

---

## 1. The mark

The actual `t.` from **JetBrains Mono 700** — the brand's mono typeface IS the logo — converted to pure paths (no font dependency) in a 64-unit viewbox. The t is charcoal, with the monospace letterform's bottom hook swinging right; the period is the accent red, pulled in to a 6-unit ink gap so it reads as punctuation, not a floating dot.

| Element | Spec (64-unit viewbox) |
|---|---|
| t | JetBrains Mono 700 glyph as paths — ink 44 tall (top y 12, baseline y 56), stem ~7.8 wide, crossbar y 21.7–28.7, bottom hook swings right to x ~29.7 |
| Period | JBM 700 period, Ø ~11.7, center (50.1, 50.8) — dips 0.6 below the baseline, the type-true overshoot |
| Gap | 6 units of ink between t and period |
| Ink | 48 wide total, horizontally centered in the viewbox |
| Colors | t `#1A242E` · period `#CC4D3C` — dark surfaces: t `#F8F9FA`, period `#E0634F` |

One red element, and it's the one that does the talking: the period turns the letter into a finished word — `t.` — a sentence end, a pause, a complete thought.

**Why it works:** Making the logo out of the mono font's own letterform means the mark and the type system are the same decision. "Typed" is literally what it looks like when Typed types. The real letterform (hook swinging right, type-true period) reads as typography rather than a grid-assembled glyph, and the single red period keeps the one-accent discipline.

## 2. The wordmark

"Typed" in Outfit 600. The `y` is rendered in the accent color — the only colored letter, echoing the mark's red period.

- Font: Outfit (loaded via google_fonts)
- Weight: 600
- Letter spacing: -0.01em
- Color treatment: `T` `[y]` `p` `e` `d` — all `#1A242E` except `y` `#CC4D3C`

## 3. Color palette

| Token | Hex | Role |
|---|---|---|
| `accent` | `#CC4D3C` | OKLCH `oklch(52% 0.18 25)` — the single warm red |
| `fg` | `#1A242E` | Primary text — near-black with a hint of blue |
| `bg` | `#F8F9FA` | Page background — cream, not pure white |
| `surface` | `#FFFFFF` | Cards, editor background |
| `muted` | `#6E7A85` | Secondary text, placeholders |
| `border` | `#E5E8EB` | Separators |

**Accent discipline:** Max 2 visible uses of accent per screen. The `y` in the wordmark, the period in the mark, selected note card border, one CTA at a time. That's it.

## 4. Typography

| Role | Font | Weight | Size |
|---|---|---|---|
| Display (H1) | Outfit | 700 | 24px |
| Display (H2) | Outfit | 600 | 20px |
| Body | Outfit | 400 | 15px |
| Nav items | Outfit | 400 | 13.5px |
| Mono / code / counts | JetBrains Mono | 400 | 11-13px |

**Outfit** for everything UI. **JetBrains Mono** for code, timestamps, word counts, the monogram. The contrast between the geometric sans and the technical mono is the type system's whole personality.

## 5. Spacing

8px grid. 6px half-step for dense rows. Always.

- Sidebar nav items: `6px 12px` padding
- Note cards: `14px 16px` padding, `10px` radius
- Editor body: `16px 24px` padding
- Touch targets: minimum `44×44dp` desktop, `48×48dp` Android

## 6. Asset inventory

```
assets/branding/
└── typed-mark.svg           ← primary logo source, bundled with the app

design/branding/              ← design sources (not shipped in the app bundle)
├── typed-logo-hero.svg       ← marketing hero: paper grid + mark (B5)
├── logo-tile-cream.svg       ← app icon tile, cream field (B1, flagship)
├── logo-tile-accent.svg      ← app icon tile, accent field (B2)
├── logo-tile-night.svg       ← app icon tile, near-black + keyline (B7)
├── monogram.svg              ← compact standalone source for the t mark
├── wordmark.svg              ← wordmark as pure paths from Outfit 600
├── icon_foreground.svg       ← source for Android adaptive icon
├── tools/
│   ├── wordmark_gen.py       ← regenerates wordmark.svg from the Outfit font
│   └── mark_gen.py           ← regenerates typed-mark.svg + painter paths from JetBrains Mono
└── discoveries/              ← logo exploration rounds (not brand — see README.md)

lib/widgets/
└── brand_mark.dart           ← CustomPainter that renders the mark in Flutter

android/app/src/main/res/
├── drawable/
│   ├── ic_launcher_foreground.xml  ← adaptive icon foreground (vector)
│   ├── ic_typed.xml                ← monogram for widget headers (vector)
│   ├── launch_background.xml       ← branded splash background
│   └── ...
├── drawable-night/
│   └── ic_launcher_foreground.xml  ← night variant: cream mark, warm accent
├── mipmap-anydpi-v26/
│   ├── ic_launcher.xml             ← adaptive icon (Android 8+)
│   └── ic_launcher_round.xml       ← round variant
└── values/
    ├── ic_launcher_background.xml  ← cream tile bg (#F8F9FA)
    └── ...
    values-night/ic_launcher_background.xml ← night tile bg (#141A20)
```

## 7. Implementation notes

**The Flutter `BrandMark` widget** (`lib/widgets/brand_mark.dart`) uses the bundled path-based SVG on default surfaces and a tintable `CustomPainter` on compact/dark surfaces. Both draw the same 64-unit geometry — the painter's paths are generated into `lib/widgets/brand_mark_paths.dart` by `mark_gen.py` (`brandMarkTPath()` takes the fg color, `brandMarkPeriodPath()` the accent). Tinted call sites pass theme colors, so dark mode automatically renders the t in cream with the warm-accent period.

**Android adaptive icon** uses vector drawables — no PNGs needed, scales perfectly across all densities. Light mode is a solid cream background (`#F8F9FA`) with the charcoal/red mark; night mode swaps to a near-black tile (`#141A20`) with the cream mark and warm accent (`#E0634F`). The foreground is centered in the 108×108dp adaptive icon, with the mark sitting in the 72×72dp safe zone.

**Monochrome variant** is provided for Android 13+ themed icons — system can re-tint based on wallpaper.

## 8. What's deliberately not here

- **No gradient.** A single red, used sparingly. Gradients are for apps that need to shout.
- **No secondary accent.** One red. Adding another color dilutes the mark.
- **No logotype variants.** "Typed" is set in Outfit, not a custom letterform. The mark is the brand.
- **No mascot, no illustration, no photography.** A note-taking app is a tool. Tools don't need faces.

## 9. Future work

- Custom typeface for "Typed" wordmark (custom `y` glyph)
- Splash screen with full mark + "Typed" wordmark, fade to editor
- Themed icon variants (Android 13+) for light/dark wallpaper
- iOS app icon (once iOS build is set up)
- In-app illustrations for empty states (one-time, hand-drawn feel)
