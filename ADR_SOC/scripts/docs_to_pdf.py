#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : docs_to_pdf.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Builds docs/pdf/*.pdf from the project's Markdown documents
#***************************************************************

"""Build docs/pdf/*.pdf from the project's Markdown documents.

Needs weasyprint and markdown-it-py:
  python3 -m venv ~/.cache/adr_docs_env
  ~/.cache/adr_docs_env/bin/pip install weasyprint markdown-it-py
  ~/.cache/adr_docs_env/bin/python scripts/docs_to_pdf.py
"""
import html
import re
from pathlib import Path

from markdown_it import MarkdownIt
from weasyprint import HTML

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "pdf"

# source file, title, wide pages for tables with many columns, contents list
DOCS = [
    ("docs/MICROARCHITECTURE.md", "ADR SoC Microarchitecture Specification", False, True),
    ("docs/FEATURES.md", "ADR SoC Feature List", False, False),
    ("docs/LIMITATIONS.md", "ADR SoC Limitations", True, False),
    ("docs/THIRD_PARTY.md", "ADR SoC Third-Party IP", False, False),
    ("docs/COVERAGE.md", "ADR SoC Code Coverage", False, False),
    ("README.md", "ADR SoC README", False, False),
]

CSS = """
@page { size: A4 %(orient)s; margin: 20mm 16mm 18mm 16mm;
  @bottom-left { content: "%(title)s"; font: 8pt "Liberation Sans"; color: #64748b; }
  @bottom-right { content: "Page " counter(page) " of " counter(pages); font: 8pt "Liberation Sans"; color: #64748b; } }
body { font: 10pt/1.4 "Liberation Sans", Arial, sans-serif; color: #1f2937; }
h1 { font-size: 21pt; color: #1e3a5f; margin: 0 0 10pt; }
h2 { font-size: 14pt; color: #1e3a5f; border-bottom: 1px solid #cbd5e1; padding-bottom: 3pt; margin: 18pt 0 7pt; }
h3 { font-size: 11pt; color: #1e3a5f; margin: 12pt 0 5pt; }
h1, h2, h3 { break-after: avoid; }
p, li { orphans: 2; widows: 2; }
code { font: 8.5pt "DejaVu Sans Mono", monospace; overflow-wrap: anywhere; }
pre { background: #f1f5f9; padding: 6pt; border-radius: 3pt; break-inside: avoid; }
pre code { font-size: 7.5pt; }
table { border-collapse: collapse; width: 100%%; margin: 6pt 0 10pt; font-size: 8.5pt; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th { background: #1e3a5f; color: #fff; text-align: left; }
th, td { border: 1px solid #cbd5e1; padding: 3pt 4pt; vertical-align: top; overflow-wrap: break-word; }
td code { font-size: 7.5pt; }
tbody tr:nth-child(even) td { background: #f8fafc; }
figure { margin: 8pt 0 12pt; text-align: center; break-inside: avoid; }
figure img { max-width: 100%%; max-height: 205mm; }
figcaption { font-size: 8.5pt; color: #475569; margin-top: 3pt; }
nav.toc { break-after: page; }
nav.toc h2 { border: 0; }
nav.toc a { display: block; color: #1f2937; text-decoration: none; padding: 2pt 0; }
nav.toc a::after { content: target-counter(attr(href), page); float: right; }
"""


def render(markdown, with_toc):
    body = MarkdownIt("commonmark").enable("table").render(markdown)
    # A table with a blank header row, used as a title block, gets no header at all.
    body = re.sub(r"<thead>\s*<tr>(\s*<th>\s*</th>)+\s*</tr>\s*</thead>", "", body)
    # Links to other Markdown files do not work inside a PDF, so keep only their text.
    body = re.sub(r'<a href="(?!https?:)[^"]*">(.*?)</a>', r"\1", body)
    body = re.sub(
        r'<p><img src="([^"]+)" alt="([^"]*)"\s*/?></p>',
        r'<figure><img src="\1" alt="\2"><figcaption>\2</figcaption></figure>',
        body,
    )
    toc = []

    def anchor(match):
        name = f"s{len(toc)}"
        toc.append((name, re.sub(r"<[^>]+>", "", match.group(1))))
        return f'<h2 id="{name}">{match.group(1)}</h2>'

    if not with_toc:
        return body
    body = re.sub(r"<h2>(.*?)</h2>", anchor, body)
    links = "".join(f'<a href="#{n}">{t}</a>' for n, t in toc)
    nav = f'<nav class="toc"><h2>Contents</h2>{links}</nav>'
    return re.sub(r"(<h2 )", nav + r"\1", body, count=1)


def main():
    OUT.mkdir(exist_ok=True)
    for source, title, wide, with_toc in DOCS:
        path = ROOT / source
        if not path.exists():
            print("skipped, not written yet:", source)
            continue
        css = CSS % {"orient": "landscape" if wide else "portrait", "title": title}
        page = (f"<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><title>{html.escape(title)}</title>"
                f"<style>{css}</style></head><body>{render(path.read_text(encoding='utf-8'), with_toc)}</body></html>")
        target = OUT / ("ADR_" + path.stem + ".pdf")  # every PDF name starts with ADR or adr
        HTML(string=page, base_url=str(path.parent) + "/").write_pdf(target)
        print("wrote", target.relative_to(ROOT))


if __name__ == "__main__":
    main()
