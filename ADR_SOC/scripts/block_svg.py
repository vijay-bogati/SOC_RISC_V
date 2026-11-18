#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : block_svg.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Draws block diagrams for the documents as SVG from a small JSON description
#***************************************************************
"""python3 scripts/block_svg.py <block.json> [<out.svg>]

The JSON file holds one diagram:
  {"size": [820, 320],
   "frame": {"box": [150, 14, 520, 290], "title": "adr_wdt"},      # optional dashed IP outline
   "boxes": [ {"box": [x, y, w, h], "title": "Counter", "lines": ["reload = LOAD"],
               "color": "blue"} ],                                  # blue green amber red grey violet
   "arrows": [ {"points": [[x1, y1], [x2, y2], ...], "label": "irq_o", "at": [x, y],
                "dashed": false, "both": false} ],
   "texts": [ {"at": [x, y], "text": "clk_i", "size": 11, "anchor": "start", "color": "grey"} ]}
"""
import html
import json
import sys
from pathlib import Path

FONT = "Liberation Sans, Arial, sans-serif"
INK = "#1f2937"
COLORS = {"blue": ("#dbeafe", "#2563eb"), "green": ("#dcfce7", "#15803d"), "amber": ("#fef3c7", "#b45309"),
          "red": ("#fee2e2", "#b91c1c"), "grey": ("#f3f4f6", "#6b7280"), "violet": ("#ede9fe", "#6d28d9")}
TEXT_COLORS = {"grey": "#6b7280", "red": "#b91c1c", "blue": "#2563eb", "ink": INK}


def text(x, y, s, size=11, anchor="start", bold=False, color=INK):
    weight = ' font-weight="bold"' if bold else ""
    return (f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" text-anchor="{anchor}" '
            f'fill="{color}"{weight}>{html.escape(s)}</text>')


def draw(spec):
    w, h = spec["size"]
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">',
           f'<rect width="{w}" height="{h}" fill="#ffffff"/>',
           '<defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
           f'<path d="M0,0 L8,4 L0,8 z" fill="{INK}"/></marker>'
           '<marker id="b" markerWidth="8" markerHeight="8" refX="1" refY="4" orient="auto">'
           f'<path d="M8,0 L0,4 L8,8 z" fill="{INK}"/></marker></defs>']
    if "frame" in spec:
        x, y, fw, fh = spec["frame"]["box"]
        out.append(f'<rect x="{x}" y="{y}" width="{fw}" height="{fh}" rx="6" fill="#f9fafb" stroke="#6b7280" '
                   f'stroke-dasharray="5,3"/>')
        out.append(text(x + 10, y + 18, spec["frame"].get("title", ""), 12, bold=True))
    for b in spec.get("boxes", []):
        x, y, bw, bh = b["box"]
        fill, stroke = COLORS[b.get("color", "blue")]
        out.append(f'<rect x="{x}" y="{y}" width="{bw}" height="{bh}" rx="5" fill="{fill}" stroke="{stroke}" '
                   f'stroke-width="1.4"/>')
        lines = b.get("lines", [])
        total = 15 + 14 * len(lines)
        ty = y + (bh - total) / 2 + 12
        out.append(text(x + bw / 2, ty, b.get("title", ""), 12, "middle", True))
        for i, line in enumerate(lines):
            out.append(text(x + bw / 2, ty + 15 + 14 * i, line, 10, "middle"))
    for a in spec.get("arrows", []):
        pts = " ".join(f"{px},{py}" for px, py in a["points"])
        dash = ' stroke-dasharray="4,3"' if a.get("dashed") else ""
        start = ' marker-start="url(#b)"' if a.get("both") else ""
        out.append(f'<polyline points="{pts}" fill="none" stroke="{INK}" stroke-width="1.3"{dash}{start} '
                   f'marker-end="url(#a)"/>')
        if a.get("label"):
            lx, ly = a.get("at", a["points"][0])
            out.append(text(lx, ly, a["label"], 10))
    for t in spec.get("texts", []):
        out.append(text(t["at"][0], t["at"][1], t["text"], t.get("size", 11), t.get("anchor", "start"),
                        t.get("bold", False), TEXT_COLORS[t.get("color", "ink")]))
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".svg")
    dst.write_text(draw(json.loads(src.read_text(encoding="utf-8"))), encoding="utf-8")
    print("wrote", dst)


if __name__ == "__main__":
    main()
