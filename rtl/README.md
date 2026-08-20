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

`m6800/mc6800_phased_bus_wrapper.sv` projects each normalized MC6800 cycle as
phi1 high, non-overlap, phi2 high, and non-overlap. It samples processor
controls at trailing phi1 and advances the underlying wrapper only after phi2,
without using either projected phase as a generated clock. Its outputs are a
digital FPGA integration aid; historical input-pad and nanosecond timing remain
outside the implementation.

`m6801/mc6801_bus_wrapper.sv` is the Motorola device-oriented integration top.
It derives four digital subphases per E cycle without generating an internal
clock, presents multiplexed address/data and AS or Mode-5 IOS, and keeps the
historical device reset separate from the FPGA subphase reset. It deliberately
does not model oscillator, pad, or nanosecond electrical characteristics.

`hd6301/hd6303r_bus_wrapper.sv` is the separate Hitachi ROMless device-pin
top. It implements Mode-1 dedicated address/data pins, Mode-2/4 AS-controlled
Port-3 multiplexing, E-qualified writes, third-reset-cycle address-bus release,
and standby bus/E behavior. Its structured interface spec keeps only
nanosecond/oscillator/pad timing outside that active-cycle claim.
