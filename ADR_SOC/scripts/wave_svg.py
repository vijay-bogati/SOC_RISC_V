#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : wave_svg.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Draws timing diagrams for the documents as SVG from a small JSON description
#***************************************************************
"""python3 scripts/wave_svg.py <wave.json> [<out.svg>]

The JSON file holds one diagram:
  {"title": "...", "cycles": 10,
   "signals": [ {"name": "clk_i", "wave": "p........."},
                {"name": "psel_i", "wave": "01.0......"},
                {"name": "paddr_i", "wave": "x=.x......", "data": ["0x0C"]},
                {},                                   # an empty entry is a gap
                ...],
   "marks": [ {"at": 3, "text": "count = 0"} ]}       # optional dashed lines at a cycle
One character per clock cycle:
  p  clock (rising edge at the start of the cycle)
  0  low     1  high     .  same as before
  x  unknown or don't care
  =  a value; the next label from "data" is written inside it
  z  released (middle line)
"""
import html
import json
import sys
from pathlib import Path

FONT = "Liberation Sans, Arial, sans-serif"
NAME_W, CYCLE_W, ROW_H, HIGH, TOP = 170, 40, 30, 18, 50
LINE, FILL, X_FILL, MARK = "#1f2937", "#dbeafe", "#e5e7eb", "#b45309"


def draw(spec):
    sigs, cycles = spec["signals"], spec["cycles"]
    width = NAME_W + cycles * CYCLE_W + 200  # room for mark labels
    height = TOP + len(sigs) * ROW_H + 26
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">',
           f'<rect width="{width}" height="{height}" fill="#ffffff"/>']
    if spec.get("title"):
        out.append(f'<text x="8" y="16" font-family="{FONT}" font-size="12" font-weight="bold" fill="{LINE}">'
                   f'{html.escape(spec["title"])}</text>')
    # cycle grid and numbers
    for c in range(cycles + 1):
        x = NAME_W + c * CYCLE_W
        out.append(f'<line x1="{x}" y1="{TOP - 6}" x2="{x}" y2="{TOP + len(sigs) * ROW_H}" stroke="#f3f4f6"/>')
        if c < cycles:
            out.append(f'<text x="{x + CYCLE_W / 2}" y="{TOP - 9}" font-family="{FONT}" font-size="9" '
                       f'text-anchor="middle" fill="#6b7280">{c}</text>')
    for row, sig in enumerate(sigs):
        if not sig:
            continue
        y0 = TOP + row * ROW_H + (ROW_H - HIGH) / 2
        y1, ymid = y0 + HIGH, y0 + HIGH / 2
        out.append(f'<text x="8" y="{ymid + 4}" font-family="{FONT}" font-size="11" fill="{LINE}">'
                   f'{html.escape(sig["name"])}</text>')
        wave, data = sig["wave"], list(sig.get("data", []))
        level = None  # last drawn kind: "0", "1", "x", "=", "z"
        c = 0
        while c < len(wave):
            ch = wave[c]
            x = NAME_W + c * CYCLE_W
            if ch == "p":
                xm = x + CYCLE_W / 2
                out.append(f'<polyline points="{x},{y1} {x},{y0} {xm},{y0} {xm},{y1} {x + CYCLE_W},{y1}" '
                           f'fill="none" stroke="{LINE}" stroke-width="1.3"/>')
                c += 1
                continue
            n = 1
            while c + n < len(wave) and wave[c + n] == ".":
                n += 1
            xe = x + n * CYCLE_W
            if ch in "01":
                y = y1 if ch == "0" else y0
                if level in ("0", "1") and level != ch:
                    out.append(f'<line x1="{x}" y1="{y0}" x2="{x}" y2="{y1}" stroke="{LINE}" stroke-width="1.3"/>')
                elif level in ("x", "=", "z"):
                    out.append(f'<line x1="{x}" y1="{ymid}" x2="{x + 3}" y2="{y}" stroke="{LINE}" stroke-width="1.3"/>')
                    x += 3
                out.append(f'<line x1="{x}" y1="{y}" x2="{xe}" y2="{y}" stroke="{LINE}" stroke-width="1.3"/>')
            elif ch == "z":
                out.append(f'<line x1="{x}" y1="{ymid}" x2="{xe}" y2="{ymid}" stroke="#2563eb" stroke-width="1.3"/>')
            else:  # "x" or "="
                fill = X_FILL if ch == "x" else FILL
                pts = f"{x},{ymid} {x + 4},{y0} {xe - 4},{y0} {xe},{ymid} {xe - 4},{y1} {x + 4},{y1}"
                out.append(f'<polygon points="{pts}" fill="{fill}" stroke="{LINE}" stroke-width="1.1"/>')
                if ch == "=" and data:
                    out.append(f'<text x="{(x + xe) / 2}" y="{ymid + 4}" font-family="{FONT}" font-size="10" '
                               f'text-anchor="middle" fill="{LINE}">{html.escape(str(data.pop(0)))}</text>')
            level = ch
            c += n
    for m in spec.get("marks", []):
        x = NAME_W + m["at"] * CYCLE_W
        out.append(f'<line x1="{x}" y1="{TOP - 4}" x2="{x}" y2="{TOP + len(sigs) * ROW_H + 4}" stroke="{MARK}" '
                   f'stroke-dasharray="4,3" stroke-width="1.2"/>')
        out.append(f'<text x="{x + 3}" y="{TOP + len(sigs) * ROW_H + 18}" font-family="{FONT}" font-size="10" '
                   f'fill="{MARK}">{html.escape(m["text"])}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".svg")
    dst.write_text(draw(json.loads(src.read_text(encoding="utf-8"))), encoding="utf-8")
    print("wrote", dst)


if __name__ == "__main__":
    main()
