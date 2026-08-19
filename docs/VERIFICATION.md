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
| HD6301 opcode values with documented TRAP behavior | 26 |
| Python exhaustive practical ALU cases | 1,839,105 |
| SystemVerilog exhaustive practical ALU cases | 1,969,155 |
| Python unit tests | 81 |
| M6800 directed core checks | 28 |
| MC6800 bus-wrapper checks | 14 |
| MC6801/MC6803 Mode 2/3 integration checks | 50 |
| MC6801/MC6803 peripheral model/RTL cycle comparisons | 1,536 |
| HD6301V1 Mode-7 integration checks | 22 |
| HD6303R Mode-2 integration checks | 12 |
| M6805 directed core checks | 13 |
| MC68705P5 integration checks | 11 |
| HD6301 exact TRAP trace checks | 3 |
| Deterministic random programs | 80 (16 per architecture profile) |
| Per-retirement randomized comparisons | 5,120 |
| Bounded formal profiles | 8 at depth 10 |
| Synthesis tops | 10 |

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

The MC6801/MC6803 MCU suite runs normalized Mode 2 and Mode 3 separately. The
MC6803 applicability is grounded in the manufacturer's explicit functional-
identity statement and the validated profile inheritance, not an inferred
similarity. The suite verifies
external reset-vector decode, expanded-mode register exclusions, physical-pin
GPIO reads, write-only DDR reads, RAME-controlled RAM, Mode 3 external RAM,
synchronized input capture, ordered ICF clearing, output compare, IRQ1-over-
timer priority, distinct vectors, NRZ transmit framing, center-sampled receive,
SCI overrun retention, MC6801 misframed-byte transfer, status-clearing
protocols, sticky SCI pin direction,
and a one-cycle IRQ1 pulse which arrives after IRQ2 entry has started and wins
the documented late vector-priority selection. It also removes a timer source's
identity after latching IRQ2 and verifies the documented default SCI vector.

The independent Python device model has eight focused regressions for Mode 2/3
decode and RAM, physical-pin GPIO behavior and SCI direction overrides,
coherent timer reads and ordered status clears, second-cycle input capture,
overflow/compare events, retained IRQ priority, and internally clocked NRZ
transmit/receive with unread-data overrun retention. Its cycle/event structure
is separate from the RTL wrapper.

Two recorded seeds, `0x68030002` and `0x68030003`, drive 768 E-cycle
transactions per mode through a verification-only CPU bus source. After every
cycle, the RTL is compared with model-generated internal read data, external
decode, RAM/control state, GPIO value and direction, timer/capture/compare
state, SCI state and pins, interrupt requests, retained request latches, and
late priority vector. Directed protocol sequences precede the deterministic
random register/pin traffic. These checks establish peripheral transaction and
state timing at the normalized E-cycle boundary; they do not claim the physical
Port 3 multiplexed waveform.

The HD6301 TRAP suite independently exercises an unassigned opcode and an
instruction-address-error input. It compares the exact 13-cycle normalized bus
trace documented by handbook figure III-8: faulting opcode, discarded PC+1,
two `$ffff` reads, seven stack writes, and `$ffee:$ffef` vector reads. It checks
the complete stacked state, unmaskable I-bit update, RTI restoration of the
faulting PC, and immediate retrap when the invalid opcode remains present.

The HD6303R Mode-2 suite executes through the integrated device wrapper. It
checks external reset vectors, internal RAM exclusion from the external bus,
AIM and XGDX, timer continuity while sleeping, masked IRQ release from SLP
without stacking or vectoring, simultaneous NMI/IRQ priority, and opcode-error
TRAP through the external `$ffee:$ffef` vector. It also verifies that a framing
error leaves RDR unchanged, with a separate HD6303R peripheral-model regression.
RTL and model tests cover the Hitachi full-counter write sequence and TOF at
rollover to `$0000`. The instruction model has a matching regression for the
masked-request SLP rule.

The HD6301V1 Mode-7 suite fetches reset and interrupt vectors through the
internal program-image interface, executes from both the 4-KiB program window
and 128-byte RAM, and verifies a 13-cycle address TRAP from documented
non-memory space. It checks Port 3/4 DDRs and pin reads, the IS3 input latch,
P3CSR's ordered flag-clear protocol, read- and write-selected active-low OS3
pulses, masked IS3 release from SLP, and enabled IS3 vectoring through the IRQ1
priority slot. Three independent Python model tests cover the Mode-7 address
partition, program-select/address-error distinction, GPIO, latch, flag, strobe,
and interrupt state. A fourth model test and the RTL suite verify that a
framing error sets ORFE without transferring the misframed byte into RDR. A
fifth model test and the RTL suite verify the Hitachi FRC write and rollover
semantics.

The MC6800 device-wrapper suite verifies reset bus controls, TSC ownership and
state stalling, HALT completion and stable bus release, single-instruction
release, NMI retention on the exact HALT-entry boundary, RTI/re-halt behavior,
masked IRQ retention through release and CLI, DBE-suppressed and enabled
writes, WAI bus release, and IRQ wake-up. It checks the independently recorded
digital contract; it does not infer phi1/phi2 electrical timing from normalized
cycles.

Directed M6805-lineage tests cover reset, stalls, arithmetic, direct writes,
BSR/RTS, the five-byte interrupt frame, vector fetch, and RTI restoration. The
HD6305 profile separately proves that a pending interrupt is accepted only
after the instruction following CLI. The MC68705P5 suite adds register/RAM
decode, DDR behavior, mixed-direction GPIO
reads, timer underflow/mask/request clearing, simultaneous external/timer
priority, distinct vectors, and firmware-memory decode.

## Formal checks

`make formal` uses Yosys bounded SAT over the M6800, MC6801, HD6301, M6805, and
HD6305 profiles plus the MC6800 bus wrapper, MC6801 Mode 3 integration, and
HD6301V1 Mode-7 integration. At
depth 10 it proves the committed
safety properties for all symbolic input sequences:

- a write is always a valid bus cycle;
- an opcode fetch is a valid read;
- waiting and sleeping/stopped states are mutually exclusive;
- a masked request releases HD6301 SLP without leaving the core asleep;
- interrupt-vector selection is legal;
- the M6805 stack remains inside `$0060`-`$007f`; and
- architectural state, bus outputs, and status remain stable when clock enable
  is inactive or an active transfer is waiting for `bus_ready_i`.
- TSC and BA never coexist with bus drive or VMA, DBE low prevents data drive,
  and every wrapper data drive is a qualified write owned by the processor.
- MC6801 external fetches are qualified reads, internal register addresses do
  not escape onto the expanded bus, SCI overrides force documented Port 2
  directions, and MCU state is stable while clock enable is inactive.
- HD6301V1 program reads occur only in `$f000`-`$ffff`, non-memory instruction
  fetches never select program memory, OS3 is confined to PORT3 accesses, and
  complete digital device state is stable while clock enable is inactive.

These bounded safety proofs complement simulation; they are not a liveness or
full instruction-correctness proof.

## Simulation and synthesis tool diversity

Verilator is the primary strict-warning simulator. Icarus Verilog independently
compiles and runs both directed CPU suites, the HD6301 TRAP trace, the interrupt
delay traces, the MC68705P5, HD6301V1, and HD6303R device suites, and both MC6801/MC6803
peripheral differential profiles from the generated
package-flattened view. Icarus reports its known conservative `always_*`
sensitivity note for constant part-selects; no design warning is suppressed to
hide it.

Representative generic Yosys 0.68 results from the current source are:

| Top/profile | Generic cells | Sequential cells |
|---|---:|---:|
| M6800 | 6,213 | 217 |
| MC6800 bus wrapper | 6,274 | 223 |
| MC6801 | 6,165 | 217 |
| MC6801 Mode 2 integration | 10,783 | 1,422 |
| HD6301 | 7,289 | 218 |
| HD6301V1 Mode 7 integration | 11,936 | 1,471 |
| HD6303R Mode 2 integration | 11,893 | 1,423 |
| M6805 | 3,609 | 169 |
| HD6305 | 3,611 | 170 |
| MC68705P5 integration | 6,711 | 1,122 |

Cell counts are tool/version/technology dependent and are smoke-test evidence,
not optimization guarantees. Each synthesis script runs structural `check
-assert`; the recorded run reports no latches, combinational-loop errors, or
structural problems. The P5 RAM has no invented reset and is written in a
separate inference-friendly process because its reset contents are undefined by
the manufacturer. The MC6801 RAM follows the same rule; the technology-neutral
post-map total shows flip-flops because generic `synth` maps the asynchronous-
read array before reporting statistics.

## Reproducing the gate

`make ci` is the authoritative offline gate. It validates clean-room/reference
metadata, device/peripheral/interface/opcode specifications, generated-file freshness,
strict RTL lint, all Python tests, RTL ALU, every opcode profile, directed CPU
and peripheral suites, the full deterministic random corpus, Icarus
compatibility, bounded formal properties, and all synthesis tops.

GitHub Actions installs only open-source simulators/synthesis tools and runs the
same target. It never downloads the copyrighted reference cache. A failure in
any stage blocks a completion or release claim.
