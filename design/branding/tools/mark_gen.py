"""Generate the canonical Typed mark from JetBrains Mono.

The mark is the actual `t.` from JetBrains Mono (weight 700) converted to
pure SVG paths — the brand's mono typeface IS the logo. The period is pulled
in to a fixed ink gap (JBM's monospace advance leaves a huge hole otherwise).

Outputs:
  - assets/branding/typed-mark.svg          (light colors: charcoal t, red period)
  - lib/widgets/brand_mark_paths.dart       (Dart Path builders, 64-unit space)
  - prints Android pathData + ink bbox + centering translates for drawables

Usage:  python design/branding/tools/mark_gen.py
Needs:  pip install fonttools uharfbuzz  (font cached next to this script)
"""

import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.misc.transform import Transform
import uharfbuzz as hb

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
OUT_SVG = REPO / "assets" / "branding" / "typed-mark.svg"
OUT_DART = REPO / "lib" / "widgets" / "brand_mark_paths.dart"
FONT_CACHE = HERE / "JetBrainsMono-wght700.ttf"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"

WEIGHT = 700
TEXT = "t."
T_INK_HEIGHT = 44.0   # units in the 64-unit viewbox (baseline 56 -> top 12)
BASELINE = 56.0
GAP = 6.0             # ink gap between t and period, in viewbox units
DARK = "#1A242E"
ACCENT = "#CC4D3C"


def get_font() -> TTFont:
    if FONT_CACHE.exists():
        return TTFont(FONT_CACHE)
    print(f"downloading JetBrains Mono from {FONT_URL}")
    urllib.request.urlretrieve(FONT_URL, HERE / "JetBrainsMono-var.ttf")
    var = TTFont(HERE / "JetBrainsMono-var.ttf")
    instantiateVariableFont(var, {"wght": WEIGHT}, inplace=True)
    var.save(FONT_CACHE)
    (HERE / "JetBrainsMono-var.ttf").unlink()
    return var


def shaped_paths(font: TTFont):
    """Shape TEXT, return [(glyph_name, x_offset_units, fill)] with the
    period repositioned so the t->period ink gap equals GAP viewbox units."""
    upem = font["head"].unitsPerEm
    gs = font.getGlyphSet()
    tmp = FONT_CACHE  # instance already saved
    hbfont = hb.Font(hb.Face(hb.Blob.from_file_path(str(tmp))))
    hbfont.scale = (upem, upem)
    buf = hb.Buffer()
    buf.add_str(TEXT)
    buf.guess_segment_properties()
    hb.shape(hbfont, buf, {"kern": True})

    order = font.getGlyphOrder()
    placed = []
    x = 0
    for i, (info, pos) in enumerate(zip(buf.glyph_infos, buf.glyph_positions)):
        placed.append([order[info.codepoint], x + pos.x_offset, ACCENT if i == 1 else DARK])
        x += pos.x_advance

    s = T_INK_HEIGHT / 44.0  # placeholder, fixed below
    bounds = {}
    for name, _, _ in placed:
        bp = BoundsPen(gs)
        gs[name].draw(bp)
        bounds[name] = bp.bounds

    t_h = bounds[placed[0][0]][3] - bounds[placed[0][0]][1]  # t ink height, font units
    s = T_INK_HEIGHT / t_h
    t_right = bounds[placed[0][0]][2] + placed[0][1]         # t ink right edge, font units
    p_left = bounds[placed[1][0]][0]                          # period ink left bearing
    placed[1][1] = t_right + GAP / s - p_left                 # pull period in
    return placed, bounds, s, gs


def svg_d(placed, bounds, s, gs, tx):
    """SVG path elements at scale s, shifted so ink spans [tx, tx+inkw]."""
    minx = min(bounds[n][0] + gx for n, gx, _ in placed)
    out = []
    for name, gx, fill in placed:
        pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}")
        gs[name].draw(TransformPen(pen, Transform(s, 0, 0, -s, (gx - minx) * s + tx, BASELINE)))
        out.append(f'  <path d="{pen.getCommands()}" fill="{fill}"/>')
    return out, minx


def main() -> None:
    font = get_font()
    placed, bounds, s, gs = shaped_paths(font)
    upem = font["head"].unitsPerEm

    minx = min(bounds[n][0] + gx for n, gx, _ in placed)
    maxx = max(bounds[n][2] + gx for n, gx, _ in placed)
    miny = min(bounds[n][1] for n, _, _ in placed)
    maxy = max(bounds[n][3] for n, _, _ in placed)
    inkw = (maxx - minx) * s
    top = BASELINE - maxy * s
    bottom = BASELINE - miny * s
    cx = inkw / 2          # ink center x after left-edge alignment
    cy = (top + bottom) / 2
    print(f"scale {s:.4f}  ink w {inkw:.2f}  top {top:.2f}  bottom {bottom:.2f}  "
          f"center ({cx + 0:.2f}, {cy:.2f}) in 64 box")

    # --- canonical SVG: ink centered horizontally in the 64-unit box
    tx = (64 - inkw) / 2
    paths, _ = svg_d(placed, bounds, s, gs, tx)
    OUT_SVG.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg viewBox="0 0 64 64" width="64" height="64" xmlns="http://www.w3.org/2000/svg">\n'
        '  <title>Typed mark (t.)</title>\n'
        '  <!-- The t. from JetBrains Mono 700 as pure paths — the brand mono IS\n'
        '       the logo. Regenerate with design/branding/tools/mark_gen.py.\n'
        '       Dark surfaces: t in cream #F8F9FA, period #E0634F (see painter /\n'
        '       drawable-night variants). -->\n'
        + "\n".join(paths) + "\n</svg>\n",
        encoding="utf-8",
    )
    print("wrote", OUT_SVG)

    # --- Dart painter paths (64-unit space, expanded TrueType quadratics)
    def dart_path(name, gx):
        pen = RecordingPen()
        gs[name].draw(TransformPen(pen, Transform(1, 0, 0, 1, gx - minx, 0)))
        lines = ["    final p = Path();"]
        for op, args in pen.value:
            if op == "moveTo":
                lines.append(f"    p.moveTo({args[0][0]*s:.2f}, {BASELINE - args[0][1]*s:.2f});")
            elif op == "lineTo":
                lines.append(f"    p.lineTo({args[0][0]*s:.2f}, {BASELINE - args[0][1]*s:.2f});")
            elif op == "qCurveTo":
                offs = list(args[:-1])
                last = args[-1]
                for i, o in enumerate(offs):
                    end = last if i == len(offs) - 1 else \
                        ((offs[i][0] + offs[i + 1][0]) / 2, (offs[i][1] + offs[i + 1][1]) / 2)
                    lines.append(f"    p.quadraticBezierTo({o[0]*s:.2f}, {BASELINE - o[1]*s:.2f}, "
                                 f"{end[0]*s:.2f}, {BASELINE - end[1]*s:.2f});")
            elif op == "curveTo":
                c1, c2, pt = args
                lines.append(f"    p.cubicTo({c1[0]*s:.2f}, {BASELINE - c1[1]*s:.2f}, "
                             f"{c2[0]*s:.2f}, {BASELINE - c2[1]*s:.2f}, "
                             f"{pt[0]*s:.2f}, {BASELINE - pt[1]*s:.2f});")
            elif op == "closePath":
                lines.append("    p.close();")
        return "\n".join(lines)

    dart = (
        "// GENERATED by design/branding/tools/mark_gen.py — JetBrains Mono 700\n"
        "// `t.` as paths in the 64-unit mark space (baseline y=56). Do not edit\n"
        "// by hand; run the generator instead.\n"
        "import 'dart:ui';\n\n"
        "Path brandMarkTPath() {\n"
        + dart_path(placed[0][0], placed[0][1]) + "\n    return p;\n  }\n\n"
        "Path brandMarkPeriodPath() {\n"
        + dart_path(placed[1][0], placed[1][1]) + "\n    return p;\n  }\n"
    )
    OUT_DART.write_text(dart, encoding="utf-8")
    print("wrote", OUT_DART)

    # --- Android pathData (raw 64-space d strings for both glyphs)
    raw = []
    for name, gx, fill in placed:
        pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}")
        gs[name].draw(TransformPen(pen, Transform(s, 0, 0, -s, (gx - minx) * s, BASELINE)))
        raw.append(pen.getCommands())
    print("\nAndroid pathData (64-space, ink left edge at x=0):")
    print("  t:     ", raw[0])
    print("  period:", raw[1])
    print(f"\ncentering translates -> launcher108: tx={54 - cx:.2f} ty={54 - cy:.2f} | "
          f"splash120: tx={60 - cx:.2f} ty={60 - cy:.2f}")


if __name__ == "__main__":
    main()
