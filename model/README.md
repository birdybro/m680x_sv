# Independent executable model

This directory contains the specification-derived Python model. It is written
for obvious architectural behavior and deterministic verification, not by
translation from RTL. The RTL and model will retain separate control
structures so that differential tests can expose mistakes in either one.

`alu.py` reports only the flags an operation
defines, leaving each CPU lineage to preserve unaffected condition-code bits.
The DAA function transcribes the nine manufacturer table rows and explicitly
marks every other input state undefined instead of inventing silicon behavior.

`make test-alu` currently checks 1,839,105 finite ALU cases:

- 131,072 ADD/ADC operand and carry states;
- 131,072 SUB/SBC/CMP operand and borrow states;
- 196,608 AND/OR/XOR operand pairs;
- 65,536 unsigned multiply operand pairs;
- 3,073 unary, shift, rotate, test, and clear states;
- all 1,024 accumulator/H/C input states against the DAA table, additionally
  cross-checked from 20,000 valid packed-BCD additions; and
- 1,310,720 16-bit ADDD/SUBD/CPX cases formed by every left operand and ten
  architectural boundary operands.

The test oracles use signed-range properties, arithmetic identities, and a
separate declarative DAA table rather than calling model helpers to predict
their own results.

`m6800.py` is the instruction-level path for M6800, MC6801/MC6803, and
HD6301/HD6303/HD63701. It has its own register/stack organization and executes
all 647 documented encodings in those three architecture maps. Each step emits
an ordered memory-access trace, the documented total cycle count, effective
address, pre/post architectural state, and any manufacturer-undefined flags.
Directed regressions cover wraparound addressing, call and interrupt stack byte
order, SWI/RTI, WAI interrupt entry without double stacking, masking, reset
vectors, and the Hitachi immediate-memory and exchange extensions. The HD6301
profile additionally classifies and executes all 26 documented opcode-error
TRAP values, accepts an explicit instruction-address-error condition, records
the exact 13-cycle entry trace, and preserves the faulting PC for RTI retry.

`m6805.py` is a separate instruction path for M6805 and HD6305. It executes all
417 documented encodings while modeling the eight-bit X register, parameterized
stack-pointer width, bit set/clear and bit-test branches, three indexed forms,
IRQ-pin branches, five-byte interrupt frame, and Hitachi low-power instructions.
The default five-bit stack window wraps within `$0060`–`$007f`, matching the
concrete MC68705P5 behavior; other family members can select their documented
stack width explicitly.

`mc6801_device.py` is a cycle-stepped path for MC6801 Modes 0-7 and the normal
or relocated 2-KiB mask-ROM options. It is organized around register
transactions and E-cycle events rather than either CPU execution state machine.
It models mode-selected registers, RAM/ROM/vector sources, Mode-4 RAM aliases
and one-way Mode-5 transition, normalized external selection, GPIO/address
functions, the capture/compare/overflow timer and ordered flag protocols,
internally clocked NRZ SCI framing/status, and retained IRQ1/IRQ2 requests.
MC6803 users select only its documented Modes 2/3; no behavior is assigned to
the modes which that device's manual leaves undefined.

`hd6301v1_device.py` and `hd6303r_device.py` specialize only documented device
differences. In particular, both select Hitachi's rule that a framing-error
byte is not transferred into RDR, while the MC6801 model selects Motorola's
documented transfer behavior. The Mode-7 model additionally owns the HD6301V1
memory, Port 3/4, strobe, IS3, and address-error facts.
The same profiles select Hitachi's two-byte FRC write and TOF-at-zero behavior;
the base MC6801 profile retains its read-only low byte and TOF-at-`$ffff` rule.
Their independent `standby_reset` transition resets active peripheral state,
preserves physical RAM without inventing lost-supply values, and retains
STBY_PWR only while the modeled standby supply remains valid.

`hd63701v0_device.py` selects the EPROM device's 192-byte `$0040-$00ff` RAM
window and its documented transfer of a misframed receive byte into RDR. For
the manual's contradictory `$0040-$007f` address-error statements, the model
permits execution from physical RAM and reports that policy separately from
verified behavior.

`hd63705v0_device.py` is a separate E-cycle device model for the 14-bit
HD63705V0 boundary. It owns the 192-byte RAM/4-KiB EPROM partition, four GPIO
ports, all primary-timer clock modes, INT/INT2 priority, synchronous SCI and
Timer2 edges, and STOP state changes. It does not reuse the RTL state machine.
The model explicitly resynchronizes TIMER and CK levels while stopped so that
recovery cannot manufacture an edge which occurred while peripheral clocks
were disabled.

`mc68705p5_device.py` independently owns the P5's 11-bit memory partitions,
GPIO/DDR rules, four timer input modes, programmable and MOR-fixed prescalers,
external/timer priority, bootstrap-vector selection, and VPP/PCR-qualified
EPROM address/data latch. It treats the bootstrap program as integration-owned
program memory and does not reproduce Motorola's factory ROM bytes.

`tools/build_mc6801_peripheral_vectors.py` records independent model results
for 768 transactions in each expanded mode. A verification-only bus source
then presents those exact transactions to the peripheral RTL without using the
CPU execution engine as an oracle.
`tools/build_hd63705_peripheral_vectors.py` does the same for 768 HD63705V0
transactions, including a directed protocol prefix and seed `0x63705000`.
`tools/build_mc68705p5_peripheral_vectors.py` records 768 P5 transactions with
seed `0x68705a05`, including all timer source classes, both RAM boundaries,
interrupt acknowledgement, bootstrap vectors, and EPROM latch/program phases.
