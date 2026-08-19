# Verification evidence

## Claim levels

Verification results are reported at four distinct levels:

| Level | What a pass establishes |
|---|---|
| Architectural | Registers, defined flags, PC/SP, stack, memory, vectors, and digital outputs match the factual specification |
| Cycle total | Retirement occurs after the documented number of enabled processor cycles |
| Semantic access | Documented operand, data, stack, and vector accesses occur in the expected order |
| External bus trace | Address, direction, validity, and data match every manufacturer-documented external cycle boundary |

The all-opcode tests currently establish the first three levels. They do not
turn padding cycles into guessed external accesses. Detailed external-bus claims
remain `PARTIAL` unless a manufacturer timing diagram provides the sequence.

## Current deterministic regressions

The committed tests cover:

| Area | Current evidence |
|---|---:|
| Explicit opcode classifications | 1,280 (256 in each of 5 profiles) |
| Documented encodings executed in Python and RTL | 1,064 |
| Python exhaustive practical ALU cases | 1,839,105 |
| SystemVerilog exhaustive practical ALU cases | 1,969,155 |
| Python unit tests | 56 |
| M6800 directed core checks | 28 |
| M6805 directed core checks | 13 |
| MC68705P5 integration checks | 11 |
| Deterministic random programs | 80 (16 per architecture profile) |
| Per-retirement randomized comparisons | 5,120 |
| Bounded formal profiles | 5 at depth 10 |
| Synthesis tops | 6 |

The Python ALU total comprises 131,072 ADD/ADC cases, 131,072 SUB/SBC/CMP
cases, 196,608 logic cases, 65,536 multiply cases, 3,073 unary/shift/rotate
cases, all 1,024 DAA input states plus 20,000 valid packed-BCD additions, and
1,310,720 16-bit arithmetic boundary sweeps. The RTL bench uses its own loops
and equations and reaches 1,969,155 cases.

Every documented encoding is executed from a generated initial state and
compared after retirement for architectural state, defined condition codes,
documented cycle total, and ordered semantic memory accesses. Undefined flag
bits are masked only where the primary manufacturer table marks them undefined.

The random corpus uses recorded seeds `0x68000000` through `0x6804000f`, grouped
by profile. Each of the 80 straight-line programs contains 64 instructions.
The model produces committed expected retirement states; the RTL test compares
registers, flags, PC/SP, cycles, and the opcode-fetch access after every
instruction. Control-flow, stack, interrupt, and low-power cases remain in
directed suites rather than being silently excluded from all testing.

## Reset, interrupt, and device tests

Directed M6800-lineage tests cover reset vectors, clock-enable and bus-ready
stalls, arithmetic, stores, branches, calls/returns, SWI/RTI, IRQ, NMI, and WAI
entry without a second stack frame. They check stack byte order and vector bus
addresses. Focused model and RTL traces also prove that MC6801 retires the
instruction following CLI or an I-clearing TAP before accepting IRQ, while
HD6301 waits the documented two machine cycles.

Directed M6805-lineage tests cover reset, stalls, arithmetic, direct writes,
BSR/RTS, the five-byte interrupt frame, vector fetch, and RTI restoration. The
HD6305 profile separately proves that a pending interrupt is accepted only
after the instruction following CLI. The MC68705P5 suite adds register/RAM
decode, DDR behavior, mixed-direction GPIO
reads, timer underflow/mask/request clearing, simultaneous external/timer
priority, distinct vectors, and firmware-memory decode.

## Formal checks

`make formal` uses Yosys bounded SAT over the M6800, MC6801, HD6301, M6805, and
HD6305 profiles. At depth 10 it proves the committed safety properties for all
symbolic input sequences:

- a write is always a valid bus cycle;
- an opcode fetch is a valid read;
- waiting and sleeping/stopped states are mutually exclusive;
- interrupt-vector selection is legal;
- the M6805 stack remains inside `$0060`-`$007f`; and
- architectural state, bus outputs, and status remain stable when clock enable
  is inactive or an active transfer is waiting for `bus_ready_i`.

These bounded safety proofs complement simulation; they are not a liveness or
full instruction-correctness proof.

## Simulation and synthesis tool diversity

Verilator is the primary strict-warning simulator. Icarus Verilog independently
compiles and runs both directed CPU suites and the MC68705P5 device suite from
the generated package-flattened view. Icarus reports its known conservative
`always_*` sensitivity note for constant part-selects; no design warning is
suppressed to hide it.

Representative generic Yosys 0.68 results from the current source are:

| Top/profile | Generic cells | Sequential cells |
|---|---:|---:|
| M6800 | 6,012 | 203 |
| MC6801 | 6,018 | 203 |
| HD6301 | 7,057 | 203 |
| M6805 | 3,609 | 169 |
| HD6305 | 3,611 | 170 |
| MC68705P5 integration | 3,312 | 963 |

Cell counts are tool/version/technology dependent and are smoke-test evidence,
not optimization guarantees. Each synthesis script runs structural `check
-assert`; the recorded run reports no latches, combinational-loop errors, or
structural problems. The P5 RAM has no invented reset and is written in a
separate inference-friendly process because its reset contents are undefined by
the manufacturer.

## Reproducing the gate

`make ci` is the authoritative offline gate. It validates clean-room/reference
metadata, device/peripheral/opcode specifications, generated-file freshness,
strict RTL lint, all Python tests, RTL ALU, every opcode profile, directed CPU
and peripheral suites, the full deterministic random corpus, Icarus
compatibility, bounded formal properties, and all synthesis tops.

GitHub Actions installs only open-source simulators/synthesis tools and runs the
same target. It never downloads the copyrighted reference cache. A failure in
any stage blocks a completion or release claim.
