#!/usr/bin/env python3
"""Draws the README pictures (docs/*.svg) from the same art/ grids the island uses. All original."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART, OUT = ROOT / "art", ROOT / "docs"
OUT.mkdir(exist_ok=True)
palette = json.loads((ART / "palette.json").read_text())


def grid(name):
    return [r for r in (ART / "pixels" / f"{name}.txt").read_text().split("\n") if r]


def rects(rows, px, ox=0, oy=0):
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in palette:
                out.append(f'<rect x="{ox + x * px}" y="{oy + y * px}" width="{px}" height="{px}" fill="{palette[ch]}"/>')
    return "\n".join(out)


def sprite_svg(name, px=6):
    rows = grid(name)
    w, h = len(rows[0]) * px, len(rows) * px
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'shape-rendering="crispEdges">\n{rects(rows, px)}\n</svg>\n')


for state in ("calm", "happy", "upset"):
    (OUT / f"sprite-{state}.svg").write_text(sprite_svg(f"{state}-compact"))

# Cover: a soft cream card, the wide happy sprite big in the middle, a pill-shaped "island" above it.
rows = grid("happy-wide")
px = 7
sw, sh = len(rows[0]) * px, len(rows) * px
W, H = 960, 360
ox, oy = (W - sw) // 2, 150
compact = grid("happy-compact")
cpx = 2
cw, ch = len(compact[0]) * cpx, len(compact) * cpx
pill_w, pill_h = 150, 46
pill_x, pill_y = (W - pill_w) // 2, 40
cover = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fbf7ee"/><stop offset="1" stop-color="#f1f6ec"/>
  </linearGradient>
</defs>
<rect width="{W}" height="{H}" rx="28" fill="url(#bg)"/>
<rect x="{pill_x}" y="{pill_y}" width="{pill_w}" height="{pill_h}" rx="23" fill="#1c1c1e"/>
<g shape-rendering="crispEdges">{rects(compact, cpx, pill_x + 14, pill_y + (pill_h - ch) // 2)}</g>
<circle cx="{pill_x + pill_w - 22}" cy="{pill_y + pill_h // 2}" r="4" fill="{palette['g']}"/>
<text x="{W // 2}" y="{pill_y + pill_h + 48}" text-anchor="middle" font-family="-apple-system, 'PingFang SC', 'Noto Sans CJK SC', sans-serif" font-size="30" font-weight="600" fill="#4a5a44">没有推送，也能有一座小岛</text>
<g shape-rendering="crispEdges">{rects(rows, px, ox, oy)}</g>
<text x="{W // 2}" y="{H - 22}" text-anchor="middle" font-family="-apple-system, 'PingFang SC', 'Noto Sans CJK SC', sans-serif" font-size="15" fill="#8a957f">免费 Apple ID · 灵动岛 · 锁屏实时活动 · 本地通知</text>
</svg>
'''
(OUT / "cover.svg").write_text(cover)


def badge(name, label, value, color, bg):
    lw, vw = 14 + 11 * len(label.encode("utf-16-le")) // 2, 14 + 11 * len(value.encode("utf-16-le")) // 2
    w, h = lw + vw, 26
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<rect width="{w}" height="{h}" rx="13" fill="{bg}"/>
<rect x="{lw}" width="{vw}" height="{h}" rx="13" fill="{color}"/>
<rect x="{lw}" width="13" height="{h}" fill="{color}"/>
<text x="{lw / 2}" y="17" text-anchor="middle" font-family="-apple-system, 'PingFang SC', 'Noto Sans CJK SC', sans-serif" font-size="12" fill="#5c6655">{label}</text>
<text x="{lw + vw / 2}" y="17" text-anchor="middle" font-family="-apple-system, 'PingFang SC', 'Noto Sans CJK SC', sans-serif" font-size="12" font-weight="600" fill="#ffffff">{value}</text>
</svg>
'''
    (OUT / f"badge-{name}.svg").write_text(svg)


badge("ios", "iOS", "16.2 以上", "#8fbcd4", "#f4f9fc")
badge("account", "Apple ID", "免费的就行", "#a8d8b9", "#f2faf5")
badge("push", "推送", "一个都不用", "#f4a7c1", "#fff1f5")
badge("license", "协议", "MIT", "#c9b7e2", "#f7f3fb")

# A thin divider: a row of grass from the wide grid's ground line.
ground = grid("calm-wide")[-3:]
gpx = 4
gw = len(ground[0]) * gpx
(OUT / "divider.svg").write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{gw}" height="{3 * gpx}" viewBox="0 0 {gw} {3 * gpx}" '
    f'shape-rendering="crispEdges">\n{rects(ground, gpx)}\n</svg>\n')
print("wrote", sorted(p.name for p in OUT.glob("*.svg")))
