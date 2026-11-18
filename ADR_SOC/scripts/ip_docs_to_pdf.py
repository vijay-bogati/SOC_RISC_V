#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : ip_docs_to_pdf.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Builds docs/pdf/ip/ PDFs from the IP documents, one per block
#***************************************************************

"""Build docs/pdf/ip/**.pdf from the IP documents in docs/ip/, one PDF per block.

Our own documents (protocols/, adr_soc/, adr_ip/, README.md) become one PDF each.
Each third-party folder becomes one PDF: the ADR note, then the upstream project's own documents
(Markdown, reStructuredText, spreadsheets, text), then its license files, all unchanged in content.

Needs what scripts/docs_to_pdf.py needs, plus docutils and openpyxl:
  ~/.cache/adr_docs_env/bin/pip install weasyprint markdown-it-py docutils openpyxl
  ~/.cache/adr_docs_env/bin/python scripts/ip_docs_to_pdf.py
"""
import html
import re
import sys
from pathlib import Path

from docutils.core import publish_parts
from markdown_it import MarkdownIt
from openpyxl import load_workbook
from weasyprint import HTML

sys.path.insert(0, str(Path(__file__).resolve().parent))
from docs_to_pdf import CSS, render  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "ip"
OUT = ROOT / "docs" / "pdf" / "ip"

EXTRA_CSS = """
section.part { break-before: page; }
section.part > h1.part { font-size: 18pt; border-bottom: 2px solid #1e3a5f; padding-bottom: 4pt; }
section.upstream { break-before: page; }
section.upstream > p.source { font-size: 8pt; color: #64748b; margin: 0 0 6pt; }
section.upstream h1 { font-size: 15pt; }
section.upstream h2 { font-size: 12.5pt; }
section.upstream h3, section.upstream h4 { font-size: 10.5pt; }
pre.text { white-space: pre-wrap; font: 7.5pt "DejaVu Sans Mono", monospace; }
img { max-width: 100%; }
"""

SKIP = re.compile(r"(CHANGELOG|CONTRIBUTING|CODEOWNERS|Makefile|\.gitignore|conf\.py|requirements\.txt)", re.I)
LICENSE = re.compile(r"^(LICENSE|COPYING)", re.I)


def absolute_images(body, base):
    """Make relative image paths absolute, so pieces from different folders can share one page."""
    def fix(m):
        src = m.group(2)
        if re.match(r"^(https?:|data:|file:|/)", src):
            return m.group(0)
        return f'{m.group(1)}"{(base / src).resolve().as_uri()}"'
    return re.sub(r'(<img[^>]*?\bsrc=)"([^"]+)"', fix, body)


def md_html(path):
    body = render(path.read_text(encoding="utf-8", errors="replace"), False)
    return absolute_images(body, path.parent)


def rst_html(path):
    parts = publish_parts(
        source=path.read_text(encoding="utf-8", errors="replace"),
        source_path=str(path),
        writer_name="html5",
        settings_overrides={"report_level": 5, "halt_level": 5, "file_insertion_enabled": False,
                            "raw_enabled": True, "embed_stylesheet": False, "doctitle_xform": False},
    )
    return absolute_images(parts["body"], path.parent)


def xlsx_html(path):
    wb = load_workbook(path, read_only=True, data_only=True)
    out = []
    for ws in wb.worksheets:
        rows = [[("" if v is None else str(v)) for v in r] for r in ws.iter_rows(values_only=True)]
        rows = [r for r in rows if any(c.strip() for c in r)]
        if not rows:
            continue
        width = max(i + 1 for r in rows for i, c in enumerate(r) if c.strip())
        out.append(f"<h3>Sheet: {html.escape(ws.title)}</h3><table>")
        for r in rows:
            cells = "".join(f"<td>{html.escape(c)}</td>" for c in (r + [""] * width)[:width])
            out.append(f"<tr>{cells}</tr>")
        out.append("</table>")
    return "".join(out)


def text_html(path):
    return f'<pre class="text">{html.escape(path.read_text(encoding="utf-8", errors="replace"))}</pre>'


def convert(path):
    ext = path.suffix.lower()
    if ext == ".md":
        return md_html(path)
    if ext == ".rst":
        return rst_html(path)
    if ext == ".xlsx":
        return xlsx_html(path)
    if ext in (".hjson", ".txt", ".json") or LICENSE.match(path.name):
        return text_html(path)
    return None


def toctree_order(folder):
    """Files named in an index.rst toctree, in that order."""
    index = folder / "index.rst"
    if not index.exists():
        return []
    names, inside = [], False
    for line in index.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip().startswith(".. toctree::"):
            inside = True
            continue
        if inside:
            if line.strip() and not line.startswith(" "):
                inside = False
                continue
            entry = line.strip()
            if not entry or entry.startswith(":"):
                continue
            m = re.search(r"<([^>]+)>", entry)
            names.append(m.group(1) if m else entry)
    files = []
    for n in names:
        for ext in (".rst", ".md"):
            p = folder / (n + ext)
            if p.exists():
                files.append(p)
    return files


def upstream_files(up):
    """Documents first (README at the top, then each folder in toctree or name order), licenses last."""
    docs, licenses = [], []
    for p in sorted(up.rglob("*")):
        if not p.is_file() or SKIP.search(p.name) or p.suffix.lower() in (".png", ".svg", ".jpg", ".dia"):
            continue
        (licenses if LICENSE.match(p.name) else docs).append(p)
    ordered = []
    for p in sorted(docs, key=lambda q: (len(q.relative_to(up).parts), not q.name.lower().startswith("readme"), str(q))):
        if p in ordered:
            continue
        if p.name == "index.rst":
            ordered.append(p)
            for q in toctree_order(p.parent):
                if q not in ordered:
                    ordered.append(q)
            continue
        ordered.append(p)
    return ordered, licenses


def adr_name(target):
    """Every PDF name starts with ADR or adr: ADR_ before upper-case names, adr_ before lower-case ones."""
    name = target.name
    if name.lower().startswith("adr"):
        return target
    return target.with_name(("ADR_" if name[0].isupper() else "adr_") + name)


def write(target, title, body):
    target = adr_name(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    css = CSS % {"orient": "portrait", "title": html.escape(title)} + EXTRA_CSS
    page = (f"<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><title>{html.escape(title)}</title>"
            f"<style>{css}</style></head><body>{body}</body></html>")
    HTML(string=page, base_url=str(SRC) + "/").write_pdf(target)
    print("wrote", target.relative_to(ROOT))


def own_docs():
    for path in [SRC / "README.md"] + sorted((SRC / "protocols").glob("*.md")) + \
            sorted((SRC / "adr_soc").glob("*.md")) + sorted((SRC / "adr_ip").glob("*.md")):
        rel = path.relative_to(SRC)
        name = "IP documents index" if rel.name == "README.md" else path.stem
        write(OUT / rel.with_suffix(".pdf"), f"ADR SoC IP: {name}", md_html(path))


def third_party_docs():
    for folder in sorted((SRC / "third_party_ip").iterdir()):
        note = folder / "ADR.md"
        if not note.exists():
            continue
        parts = [md_html(note)]
        up = folder / "upstream"
        if up.is_dir():
            docs, licenses = upstream_files(up)
            if docs:
                parts.append('<section class="part"><h1 class="part">Upstream documents</h1>'
                             "<p>Copied unchanged from the upstream repository at the commit ADR vendors. "
                             "Links inside them point to the upstream project.</p></section>")
                for p in docs:
                    body = convert(p)
                    if body is None:
                        continue
                    rel = p.relative_to(up)
                    parts.append(f'<section class="upstream"><p class="source">Upstream file: <code>{html.escape(str(rel))}</code></p>{body}</section>')
            if licenses:
                parts.append('<section class="part"><h1 class="part">Upstream licenses</h1></section>')
                for p in licenses:
                    parts.append(f'<section class="upstream"><p class="source">Upstream file: <code>{html.escape(str(p.relative_to(up)))}</code></p>{text_html(p)}</section>')
        write(OUT / "third_party_ip" / f"{folder.name}.pdf", f"ADR SoC IP: {folder.name}", "".join(parts))


def main():
    only = sys.argv[1:]
    if not only or "own" in only:
        own_docs()
    if not only or "third_party" in only:
        third_party_docs()


if __name__ == "__main__":
    main()
