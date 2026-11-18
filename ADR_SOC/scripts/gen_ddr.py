#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : gen_ddr.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Regenerates the LiteDRAM DDR4 core for simulation
#***************************************************************

"""Regenerate rtl/third_party_ip/ddr/rtl/litedram_core.v, for simulation only.

Needs LiteX and LiteDRAM at the commits in docs/THIRD_PARTY.md, and is run with the Python that
has them installed:
  python gen_ddr.py rtl/third_party_ip/ddr/ddr4_sim.yml <output folder>
Then copy <output folder>/gateware/litedram_core.v and <output folder>/csr.csv into that folder.
The tool ends with an error about a missing tapcfg package. That comes after the files are written,
from a simulator helper this project doesn't use.
"""
import sys

from litedram import gen, modules


class SimDDR4Small(modules.EDY4016A):
    """A smaller part, 32 MiB in total, so the model stays small."""
    nrows = 4096


modules.SimDDR4Small = SimDDR4Small
sys.argv = ["litedram_gen", sys.argv[1], "--sim", "--no-compile-software", "--output-dir", sys.argv[2]]
gen.main()
