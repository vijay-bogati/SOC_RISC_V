# secworks AES (S-boxes) in the ADR SoC

Joachim Strömbergson's AES core. ADR uses only its forward and inverse S-box tables, inside our own `adr_aes`. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/secworks/aes |
| Vendored in | `rtl/third_party_ip/aes_sbox` |
| Modules used | `aes_sbox`, `aes_inv_sbox` |
| Where in ADR | Inside `i_periph.i_aes` |
| Changes | None: the vendored files are unmodified. |
| Integration owner | Vijay Bogati |
| Document revision | 2.0 |
| Date | 2026-11-14 |

### Revision history

| Revision | Date | Change |
|---|---|---|
| 1.0 | 2026-11-08 | First issue: version, license, configuration, upstream documents |
| 2.0 | 2026-11-14 | Integration section generated from the RTL (instances, parameters, tied and open ports, reset style); standard cover table |

## 1. Version and license

From `docs/THIRD_PARTY.md`, the record of every vendored file:

| Block | Path | Upstream | Version / commit | License |
|---|---|---|---|---|
| AES S-boxes | `aes_sbox/rtl` | github.com/secworks/aes | `80dc4718` | BSD-2-Clause |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `aes_sbox`, `aes_inv_sbox` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 3 |
| Reset style of the vendored code | No reset found in 2 files (combinational or initial values) |

#### `aes_sbox` as `i_sbox` (`rtl/adr_ip/aes/rtl/adr_aes.sv:121`)

All parameters at their defaults.

Ports: 2 connected by name; none tied to constants; none left open.

#### `aes_sbox` as `i_key_sbox` (`rtl/adr_ip/aes/rtl/adr_aes.sv:131`)

All parameters at their defaults.

Ports: 2 connected by name; none tied to constants; none left open.

#### `aes_inv_sbox` as `i_inv_sbox` (`rtl/adr_ip/aes/rtl/adr_aes.sv:125`)

All parameters at their defaults.

Ports: 2 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `aes` | AES, with FIPS-197 vectors | 17 |

## 5. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 45: AES handles single blocks only.
- Item 46: AES has no side-channel protection and keeps key material.
- Item 47: AES area.
- Item 48: AES tested with 4 published vectors only.

## 6. Related documents

- [`../../adr_ip/adr_aes.md`](../../adr_ip/adr_aes.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
