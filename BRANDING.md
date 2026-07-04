# Typed — Brand Guide

> Type-driven, minimal, warm. A monospace letter, a single deliberate accent.

---

## 1. The mark

A lowercase `t` with a period beside it — `t.` — in JetBrains Mono Bold. The crossbar and the period are accent red; the stem and foot are charcoal.

| Element | Spec |
|---|---|
| Stem | Charcoal `#1A242E`, height 10×42 in a 64-unit viewbox |
| Crossbar | Accent `#CC4D3C`, width 40×7 — overshoots the stem on both sides |
| Foot | Charcoal `#1A242E`, width 26×7 — grounds the mark |
| Period | Accent `#CC4D3C`, 8×8 square — baseline-aligned with the foot, 5 units to its right |
| Proportions | Stem 0.156w wide, sits at x 0.422 of the mark; period at x 0.781 |

Two red elements, both deliberate. The crossbar extends past the stem — a typographic overshoot. The period is a period: a small square that sits on the baseline, completing the word.

**Why it works:** A `t` reads as "type," "text," "tap." The crossbar extending past the stem is a typographic overshoot — a deliberate detail that says the people who made this understand type. The period turns the letter into a finished word: "Typed." It also functions as a visual breath — a sentence end, a pause, a complete thought. The accent is restrained: a hint of warmth, not a brand shout.

## 2. The wordmark

"Typed" in Outfit 600. The `y` is rendered in the accent color — the only colored letter, echoing the monogram's red crossbar.

- Font: Outfit (loaded via google_fonts)
- Weight: 600
- Letter spacing: -0.01em
- Color treatment: `T` `p` `[y]` `p` `e` `d` — all `#1A242E` except `y` `#CC4D3C`

## 3. Color palette

| Token | Hex | Role |
|---|---|---|
| `accent` | `#CC4D3C` | OKLCH `oklch(52% 0.18 25)` — the single warm red |
| `fg` | `#1A242E` | Primary text — near-black with a hint of blue |
| `bg` | `#F8F9FA` | Page background — cream, not pure white |
| `surface` | `#FFFFFF` | Cards, editor background |
| `muted` | `#6E7A85` | Secondary text, placeholders |
| `border` | `#E5E8EB` | Separators |

**Accent discipline:** Max 2 visible uses of accent per screen. The `y` in the wordmark, the crossbar in the mark, selected note card border, one CTA at a time. That's it.

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
├── monogram.svg          ← vector source for the t mark
├── wordmark.svg          ← vector source for the wordmark
└── icon_foreground.svg   ← source for Android adaptive icon

lib/widgets/
└── brand_mark.dart       ← CustomPainter that renders the mark in Flutter

android/app/src/main/res/
├── drawable/
│   ├── ic_launcher_foreground.xml  ← adaptive icon foreground (vector)
│   ├── ic_typed.xml                ← monogram for widget headers (vector)
│   ├── launch_background.xml       ← branded splash background
│   └── ...
├── mipmap-anydpi-v26/
│   ├── ic_launcher.xml             ← adaptive icon (Android 8+)
│   └── ic_launcher_round.xml       ← round variant
└── values/
    └── ic_launcher_background.xml ← adaptive icon bg color
```

## 7. Implementation notes

**The Flutter `BrandMark` widget** (`lib/widgets/brand_mark.dart`) uses `CustomPainter` to draw the mark at any size. The proportions are derived from a 64×64 viewbox:

- Stem: `0.422w, 0.219h, 0.156w, 0.656h`
- Crossbar: `0.188w, 0.344h, 0.625w, 0.109h`
- Foot: `0.297w, 0.766h, 0.406w, 0.109h`

Two presets: `BrandMark()` (charcoal, light bg) and `BrandMark.light()` (sidebar variant).

**Android adaptive icon** uses vector drawables — no PNGs needed, scales perfectly across all densities. The background is a solid cream color (`#F8F9FA`). The foreground is centered in the 108×108dp adaptive icon, with the mark sitting in the 72×72dp safe zone.

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
