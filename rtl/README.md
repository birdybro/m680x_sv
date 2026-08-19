# Synthesizable RTL

All RTL in this tree is an independent clean-room implementation under the MIT
License. Public CPU interfaces are defined for this project from documented bus
behavior and FPGA integration needs; they do not reproduce another core's API.

`common/m680x_alu_pkg.sv` contains only combinational, synthesizable arithmetic
functions. Its packed result records carry all potentially relevant family
flags; each CPU lineage selects only the bits its manufacturer table says are
affected. No function mutates unaffected condition-code state.

`make test-alu-rtl` compiles the package with warnings enabled and checks
1,969,155 finite cases in a SystemVerilog bench. This is independent of the
Python exhaustive model regression and is intended to catch translation or
bit-width errors before the package is used by a CPU state machine.

The maintained CPU and device interfaces, lineages, timing contract, and
generated Yosys views are documented in `docs/ARCHITECTURE.md`.
