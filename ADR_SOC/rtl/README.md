# rtl/ - the design

| Folder | Contents |
|---|---|
| [`adr_soc/`](adr_soc/) | The SoC: package, connection-only top level, and one folder per subsystem |
| [`adr_ip/`](adr_ip/) | Blocks designed for ADR, each with `rtl/` and, where it has one, `tb/` (models and UVM agents) |
| [`third_party_ip/`](third_party_ip/) | Open-source IP, kept as upstream released it; versions, licences and the few documented changes are in [`docs/THIRD_PARTY.md`](../docs/THIRD_PARTY.md) |
| [`placeholders/`](placeholders/) | PCIe, MIPI and graphics stubs, outside the build |

The file lists that compile all of it are in [`sim/`](../sim/). Every block has a datasheet in
[`docs/ip/`](../docs/ip/) (PDF in `docs/pdf/ip/`), and the SoC is described in
[`docs/MICROARCHITECTURE.md`](../docs/MICROARCHITECTURE.md).
