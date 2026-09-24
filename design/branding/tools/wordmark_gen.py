"""Generate design/branding/wordmark.svg from the Outfit font.

"Typed" is set in Outfit SemiBold (600) with -0.01em tracking, converted to
pure SVG paths so the wordmark renders identically everywhere with no font
dependency (same principle as the t. mark). The y is the only accent-colored
letter.

Usage:  python design/branding/tools/wordmark_gen.py
Needs:  pip install fonttools uharfbuzz  (and brotli if the font arrives as woff2)
"""

import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.misc.transform import Transform
import uharfbuzz as hb

HERE = Path(__file__).resolve().parent
OUT_SVG = HERE.parent / "wordmark.svg"
FONT_CACHE = HERE / "Outfit-wght600.ttf"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf"

TEXT = "Typed"
FONT_SIZE = 52.0
MARGIN = 2.0
TRACK_EM = -0.01  # brand spec: letter-spacing -0.01em
DARK = "#1A242E"
ACCENT = "#CC4D3C"


def get_font() -> TTFont:
    if FONT_CACHE.exists():
        return TTFont(FONT_CACHE)
    print(f"downloading Outfit from {FONT_URL}")
    urllib.request.urlretrieve(FONT_URL, HERE / "Outfit-var.ttf")
    var = TTFont(HERE / "Outfit-var.ttf")
    instantiateVariableFont(var, {"wght": 600}, inplace=True)
    var.save(FONT_CACHE)
    (HERE / "Outfit-var.ttf").unlink()
    return var


def main() -> None:
    font = get_font()
    upem = font["head"].unitsPerEm
    glyph_set = font.getGlyphSet()

    blob = hb.Blob.from_file_path(str(FONT_CACHE))
    hbfont = hb.Font(hb.Face(blob))
    hbfont.scale = (upem, upem)

    buf = hb.Buffer()
    buf.add_str(TEXT)
    buf.guess_segment_properties()
    hb.shape(hbfont, buf, {"kern": True, "liga": True})

    order = font.getGlyphOrder()
    track = TRACK_EM * upem
    pen_x = 0
    placed = []  # (glyph_name, pen_x_units, fill)
    for i, (info, pos) in enumerate(zip(buf.glyph_infos, buf.glyph_positions)):
        name = order[info.codepoint]
        placed.append((name, pen_x + pos.x_offset, ACCENT if TEXT[i] == "y" else DARK))
        pen_x += pos.x_advance + (track if i < len(buf.glyph_infos) - 1 else 0)

    s = FONT_SIZE / upem
    minx = miny = 1e9
    maxx = maxy = -1e9
    for name, gx, _ in placed:
        bp = BoundsPen(glyph_set)
        glyph_set[name].draw(bp)
        if bp.bounds is None:
            continue
        x0, y0, x1, y1 = bp.bounds
        minx, maxx = min(minx, x0 + gx), max(maxx, x1 + gx)
        miny, maxy = min(miny, y0), max(maxy, y1)

    # Bake the translation into the coordinates so the viewBox starts at 0 0.
    paths = []
    for name, gx, fill in placed:
        pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
        tp = TransformPen(pen, Transform(s, 0, 0, -s, (gx - minx) * s + MARGIN, maxy * s + MARGIN))
        glyph_set[name].draw(tp)
        if (d := pen.getCommands()):
            paths.append(f'  <path d="{d}" fill="{fill}"/>')

    w = (maxx - minx) * s + 2 * MARGIN
    h = (maxy - miny) * s + 2 * MARGIN
    svg = (
        f'<svg viewBox="0 0 {w:.1f} {h:.1f}" width="{w:.0f}" height="{h:.0f}" '
        f'xmlns="http://www.w3.org/2000/svg">\n'
        f'  <!-- Typed wordmark: "{TEXT}" in Outfit SemiBold (600), letter-spacing\n'
        f'       -0.01em, converted to pure paths from the Outfit variable font (OFL)\n'
        f'       — no font dependency. The y is the only accent-colored letter.\n'
        f'       Regenerate with design/branding/tools/wordmark_gen.py. -->\n'
        f'  <title>Typed wordmark</title>\n'
        + "\n".join(paths) + "\n</svg>\n"
    )
    OUT_SVG.write_text(svg, encoding="utf-8")
    print(f"wrote {OUT_SVG}  viewBox 0 0 {w:.1f} {h:.1f}")


if __name__ == "__main__":
    main()
