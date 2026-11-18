#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : bin2hex64.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Converts a raw binary to 64-bit hex words for $readmemh
#***************************************************************

"""Convert a raw binary to 64-bit little-endian hex words for $readmemh."""
import sys


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        data = f.read()
    data += b"\x00" * (-len(data) % 8)
    with open(dst, "w") as f:
        for i in range(0, len(data), 8):
            f.write(f"{int.from_bytes(data[i:i + 8], 'little'):016x}\n")


if __name__ == "__main__":
    main()
