# syn/ - synthesis

Full-chip synthesis with Yosys (oss-cad-suite with yosys-slang) to generic gates, with no PDK. It
gives the gate counts and the zero-delay netlist used for gate-level simulation (`NETLIST=1`).

| Command | What it does |
|---|---|
| `make syn` | Both steps, about 2 hours: read and elaborate the RTL, coarse synthesis and checkpoint, then the generic gate netlist |
| `make syn_gate` | Only the gate step, from the checkpoint (about 15 minutes) |

| Folder | Contents |
|---|---|
| `scripts/` | `adr_soc_coarse.ys` (read, elaborate, coarse synthesis, checkpoint) and `adr_soc_gate.ys` (checkpoint to gates) |
| `fixes/` | `tc_sram_wrapper_syn.sv`, a synthesis-only drop-in for CVA6's SRAM wrapper with plain vector ports |
| `out/` | Generated: netlist `adr_soc_top_syn.v`, gate counts, checks and logs (not kept in the repository) |

The boot ROM and SRAM storage stay as memory macros (black boxes), so the same program images load in
gate-level simulation as in RTL.
