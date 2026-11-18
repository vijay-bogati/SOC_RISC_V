# scripts/

| Script | Purpose |
|---|---|
| `bin2hex64.py` | Converts a raw binary to 64-bit hex words for `$readmemh` (used by the Makefile for every test image) |
| `gen_ddr.py` | Regenerates the LiteDRAM DDR4 core in `rtl/third_party_ip/ddr/` |
| `docs_to_pdf.py` | Builds `docs/pdf/*.pdf` from the Markdown documents |
| `ip_docs_to_pdf.py` | Builds the per-block datasheets in `docs/pdf/ip/` |
| `ip_ports.py` | Prints the parameter and port tables of a module as Markdown, for the datasheets |
| `block_svg.py`, `wave_svg.py` | Draw the block and timing diagrams in `docs/images/` from small JSON descriptions |

The PDF builders need `weasyprint` and `markdown-it-py` (see the header of `docs_to_pdf.py`).
