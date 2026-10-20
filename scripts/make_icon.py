"""Builds the mdpeek icon: SVGs (text outlined to paths), PNGs at every size, and AppIcon.icns."""
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image
from playwright.sync_api import sync_playwright

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)

INK, LIME, PAPER = "#23262B", "#C6F05A", "#FAFAF7"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def text_path(text, cx, baseline, size):
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(c)] for c in text]
    width = sum(glyphs[n].width for n in names) * scale
    x = cx - width / 2
    pen = SVGPathPen(glyphs)
    for name in names:
        # Font units are y-up; flip into SVG's y-down space.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        x += glyphs[name].width * scale
    return pen.getCommands()


PAGE = "M100 600H924V739A185 185 0 0 1 739 924H285A185 185 0 0 1 100 739Z"
TILE = '<rect x="100" y="100" width="824" height="824" rx="185" fill="{ink}"/>'

FULL = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
{TILE.format(ink=INK)}
<path d="M196 456C330 240 694 240 828 456C694 672 330 672 196 456Z" fill="{PAPER}"/>
<circle cx="512" cy="456" r="132" fill="{LIME}"/>
<circle cx="512" cy="456" r="54" fill="{INK}"/>
<circle cx="550" cy="418" r="18" fill="{PAPER}"/>
<path d="{PAGE}" fill="{PAPER}"/>
<path d="M100 600H924" stroke="{INK}" stroke-width="28"/>
<path d="{text_path("md", 512, 826, 230)}" fill="{INK}"/>
<g fill="{INK}" fill-opacity="0.24">
<rect x="196" y="716" width="150" height="26" rx="13"/>
<rect x="196" y="770" width="110" height="26" rx="13"/>
<rect x="678" y="716" width="150" height="26" rx="13"/>
<rect x="718" y="770" width="110" height="26" rx="13"/>
</g>
</svg>
"""

SMALL = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
{TILE.format(ink=INK)}
<path d="M180 440C320 200 704 200 844 440C704 680 320 680 180 440Z" fill="{PAPER}"/>
<circle cx="512" cy="440" r="150" fill="{LIME}"/>
<circle cx="512" cy="440" r="64" fill="{INK}"/>
<path d="{PAGE}" fill="{PAPER}"/>
<path d="M100 600H924" stroke="{INK}" stroke-width="40"/>
<rect x="196" y="716" width="170" height="60" rx="30" fill="{INK}" fill-opacity="0.3"/>
<rect x="398" y="676" width="228" height="140" rx="36" fill="{INK}"/>
<rect x="658" y="716" width="170" height="60" rx="30" fill="{INK}" fill-opacity="0.3"/>
</svg>
"""

(OUT / "icon.svg").write_text(FULL)
(OUT / "icon-small.svg").write_text(SMALL)

pngs = {}
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        svg = SMALL if size <= 32 else FULL
        page.set_viewport_size({"width": size, "height": size})
        page.set_content(
            f'<style>html,body{{margin:0;background:transparent}}svg{{display:block;width:{size}px;height:{size}px}}</style>{svg}')
        path = OUT / f"icon_{size}.png"
        page.screenshot(path=str(path), omit_background=True)
        pngs[size] = Image.open(path).convert("RGBA")
    browser.close()

# ICNS: Pillow uses each appended image at its own size.
pngs[1024].save(OUT / "AppIcon.icns", append_images=[pngs[s] for s in [16, 32, 64, 128, 256, 512]])
print("ok", sorted(pngs))
