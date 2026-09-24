# Logo discoveries — round 1

Exploration set to hone the final Typed mark. All directions stay inside the
brand system: the `t.` idea, one accent (`#CC4D3C`), charcoal (`#1A242E`),
cream (`#F8F9FA`), Outfit + JetBrains Mono. Nothing here is bundled with the
app — `assets/branding/typed-mark.svg` remains canonical until a direction is
chosen and rolled out.

Open **board.html** in a browser (or view **board.png**) — every direction is
shown large, plus 28px chips on light and dark to test small-size legibility.

| # | Direction | Idea | Status |
|---|---|---|---|
| A0 | baseline | current mark — left-only foot | incumbent; foot reads "wrong way" |
| B1 | right tail | t's tail turns right, like real type | shortlist |
| B2 | serif foot | symmetric foot, typewriter slab | viable, busier |
| B3 | no foot | pure stem + crossbar + period | shortlist |
| B4 | round period | B3 with a round full stop | shortlist (period-shape test) |
| C1 | outfit t. | the wordmark's own letterforms as paths | coherent, lighter at small sizes |
| C2 | mono t. | JetBrains Mono t., weights 600/700 | **CHOSEN (round 1)** — 700 is canonical; gap tightened to 6 units, dark t cream |
| D1 | i-beam | text cursor + period; drops the t story | clean system alternative |
| E1 | stamp | accent tile, period punched as counter | icon treatment, orthogonal to mark |
| E2 | ruled line | crossbar becomes a notebook rule | conceptual icon treatment |

Orthogonal decisions to make separately:
1. **Mark geometry** — foot: none / right tail / serif (A0's left foot is the weak point).
2. **Period shape** — square (block-cursor vibe) vs round (typographic).
3. **Personality source** — geometric build-up vs font-honest (Outfit / JetBrains Mono).
4. **Container treatment** — bare mark, stamp (E1), or ruled line (E2).

Regenerate font-derived marks with `../tools/wordmark_gen.py`'s pipeline; the
geometric ones are hand-set rects in a 64-unit viewbox.
