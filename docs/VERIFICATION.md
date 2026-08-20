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
| Python unit tests | 103 |
| M6800 directed core checks | 28 |
| MC6800 bus-wrapper checks | 14 |
| MC6801/MC6803 Mode 2/3 integration checks | 50 |
| MC6801 Mode 0-7/1R/6R decode checks | 62 |
| MC6801 real-core mode boot paths | 2 |
| MC6801 external-clock SCI checks | 165 |
| MC6801/MC6803 peripheral model/RTL cycle comparisons | 1,536 |
| HD6301V1 Mode-7 integration checks | 31 |
| HD6303R Mode-2 integration checks | 18 |
| HD63701V0 Mode-7 integration checks | 29 |
| HD63705V0 integration checks | 27 |
| HD63705V0 peripheral model/RTL cycle comparisons | 768 |
| M6805 directed core checks | 13 |
| MC68705P5 integration checks | 21 |
| MC68705P5 peripheral model/RTL cycle comparisons | 768 |
| HD6301 exact TRAP trace checks | 3 |
| Deterministic random programs | 80 (16 per architecture profile) |
| Per-retirement randomized comparisons | 5,120 |
| Bounded formal profiles | 12 (11 at depth 10; mode decode at depth 5) |
| Synthesis tops | 13 |

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

The MC6801 mode suite drives all eight hardware modes plus representative 1R
and 6R relocation options through an independent bus source. Its 62 checks
cover register/RAM/program/external selection, vectors, Mode-4 aliases and
transition, Mode-5 external selection, and Port 3/4 functions. Two real-core
boot paths separately execute the Mode-0 reset-vector handoff and Mode-4
mirrored RAM fetch/data behavior. The MC6801/MC6803 peripheral suite runs
normalized Mode 2 and Mode 3 separately. The
MC6803 applicability is grounded in the manufacturer's explicit functional-
identity statement and the validated profile inheritance, not an inferred
similarity. The suite verifies
external reset-vector decode, expanded-mode register exclusions, physical-pin
GPIO reads, write-only DDR reads, RAME-controlled RAM, Mode 3 external RAM,
synchronized input capture, ordered ICF clearing, output compare, IRQ1-over-
timer priority, distinct vectors, NRZ transmit framing, center-sampled receive,
SCI overrun retention, MC6801 misframed-byte transfer, P22-forced input in
external clock mode, exact eight-positive-edge bit division, simultaneous
external-clock transmit/receive, status-clearing protocols, sticky SCI pin
direction,
and a one-cycle IRQ1 pulse which arrives after IRQ2 entry has started and wins
the documented late vector-priority selection. It also removes a timer source's
identity after latching IRQ2 and verifies the documented default SCI vector.

The independent Python device model has thirteen focused regressions for all-mode
decode, RAM/ROM/vector behavior, physical-pin GPIO behavior and SCI direction overrides,
coherent timer reads and ordered status clears, second-cycle input capture,
overflow/compare events, retained IRQ priority, and internally clocked NRZ
transmit/receive with unread-data overrun retention. The additional external
NRZ regression proves that a stationary P22 clock cannot advance serial state,
then compares the transmitted and received ten-bit frames after exactly eight
positive P22 edges per bit. Its cycle/event structure is separate from the RTL
wrapper.

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
masked-request SLP rule. Model and RTL tests additionally cover E-synchronous
STBY entry, high-impedance GPIO and external-bus suppression, retained RAM and
STBY_PWR, active-state reset, and external reset-vector recovery.

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
semantics. The RTL suite also proves that V1 DDR reset takes effect at an E
edge rather than at asynchronous RES assertion. A sixth model test and the RTL
suite verify E-synchronous STBY sampling, active-domain reset, program/GPIO
suppression, retained RAM/STBY_PWR, and reset-vector restart.

The HD63701V0 Mode-7 suite fetches reset and TRAP vectors from the separate
EPROM image, executes at both `$0040` and `$00ff`, checks OLVL reset, exercises
the 13-cycle TRAP from unambiguous non-memory space, and verifies Port 3/4 GPIO,
Hitachi FRC writes, and V0 framing-error transfer into RDR. Five independent
device-model tests cover the RAM/program partitions, RAME, address-error
classification, timer/GPIO behavior, and SCI difference. Tests deliberately
identify execution at `$0040`-`$007f` as a normalized policy because the
manufacturer manual contradicts itself there. It separately checks the
V0-specific asynchronous DDR clear before another E edge occurs. Model and RTL
tests also verify asynchronous STBY entry, immediate program/GPIO suppression,
retained RAM/STBY_PWR, active-state reset, and reset-vector restart.

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
after the instruction following CLI. The MC68705P5 suites add register/RAM
decode, DDR behavior, mixed-direction GPIO reads, all four timer sources and
all prescalers, TOPT/MOR-fixed timer behavior, timer request clearing,
simultaneous external/timer priority, distinct vectors, secure-qualified
bootstrap selection, and PCR/VPP address/data/program sequencing. Five focused
Python model tests and seed `0x68705a05` provide 768 cycle-by-cycle comparisons
of memory decode, GPIO, timer, interrupts, bootstrap selection, and programming
controls without sharing the RTL control structure.

The HD63705V0 directed suite executes real CPU transactions through both RAM
boundaries and the complete register map. Its 27 checks cover reset/vector
fetch, readable DDRs, mixed GPIO reads, the rising-edge primary timer and its
dedicated WAIT vector, simultaneous INT/INT2 priority and software clearing,
eight-bit external-clock synchronous Tx/Rx, documented STOP field changes and
external wake, STBY high impedance with RAM retention, and normalized EPROM
verify/program controls. Five independent model tests exercise the same factual
areas without sharing RTL control structure.

Seed `0x63705000` adds 768 normalized E-cycle comparisons. A directed prefix
precedes deterministic register, pin, memory, interrupt, and low-power traffic;
after every edge the bench compares read/decode, all GPIO values/directions,
timer/serial state, requests, vector priority, and synchronous serial pins. This
corpus found and permanently regresses a model-only STOP recovery defect in
which a CK/TIMER transition during stopped clocks could have appeared as a new
edge on resume.

## Formal checks

`make formal` uses Yosys bounded SAT over the M6800, MC6801, HD6301, M6805, and
HD6305 profiles plus the MC6800 bus wrapper, MC6801 Mode 3 integration and
Mode-0/Mode-4 decode,
MC68705P5, HD6301V1 and HD63701V0 Mode-7 integrations, and the HD63705V0 MCU. At
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
- MC6801 Mode 0 never selects program and external storage together and drives
  internal program data onto Port 3; the Mode-4/5 path never selects program
  and external storage together and confines external selection to
  `$0100-$01ff`.
- MC68705P5 physical PC/SP/address geometry remains legal, bootstrap vector
  remapping respects secure mode, program reads stay within internal storage,
  VPP qualifies programming controls, and disabled-cycle state stalls.
- HD6301V1 program reads occur only in `$f000`-`$ffff`, non-memory instruction
  fetches never select program memory, OS3 is confined to PORT3 accesses, and
  complete digital device state is stable while clock enable is inactive.
- HD63705V0 PC/SP and physical-address geometry remain legal, interrupt vectors
  stay in the documented set, EPROM verify/program qualification is coherent,
  standby/EPROM mode disables GPIO drive, and disabled-cycle state stalls.

These bounded safety proofs complement simulation; they are not a liveness or
full instruction-correctness proof.

## Simulation and synthesis tool diversity

Verilator is the primary strict-warning simulator. Icarus Verilog independently
compiles and runs both directed CPU suites, the HD6301 TRAP trace, the interrupt
delay traces, the MC68705P5, HD6301V1, HD6303R, HD63701V0, and HD63705V0
device suites, both MC6801/MC6803 peripheral differential profiles, and the
MC6801 all-mode/direct-boot suites plus the MC68705P5 and HD63705V0 peripheral differential corpora from generated
package-flattened views. Icarus reports its known conservative `always_*`
sensitivity note for constant part-selects; no design warning is suppressed to
hide it.

Representative generic Yosys 0.68 results from the current source are:

| Top/profile | Generic cells | Sequential cells |
|---|---:|---:|
| M6800 | 6,213 | 217 |
| MC6800 bus wrapper | 6,274 | 223 |
| MC6801 | 6,165 | 217 |
| MC6801 Mode 2 integration | 11,099 | 1,436 |
| MC6801 Mode 4/5 integration | 10,980 | 1,475 |
| HD6301 | 7,289 | 218 |
| HD6301V1 Mode 7 integration | 12,129 | 1,485 |
| HD6303R Mode 2 integration | 12,236 | 1,447 |
| HD63701V0 Mode 7 integration | 13,902 | 1,996 |
| M6805 | 3,609 | 169 |
| HD6305 | 3,611 | 170 |
| MC68705P5 integration | 6,940 | 1,144 |
| HD63705V0 integration | 9,969 | 1,858 |

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
