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
| Python unit tests | 199 |
| M6800 directed core checks | 28 |
| MC6800 bus-wrapper checks | 14 |
| MC6800 four-subphase bus-wrapper checks | 321 |
| M6800/MC6801/HD6301 real-core WAI-bus checks | 18 |
| MC6801 exact WAI-response trace checks | 47 |
| MC6801/MC6803 Mode 2/3 integration checks | 50 |
| MC6801 Mode 0-7/1R/6R decode checks | 62 |
| MC6801 real-core mode boot paths | 2 |
| MC6801/HD6301V1/HD63701V0 Port-3 handshake checks | 22 |
| MC6801 four-subphase bus-wrapper checks | 219 |
| MC6801 external-clock SCI checks | 165 |
| MC6801 bi-phase SCI checks | 24 |
| MC6801/MC6803 peripheral model/RTL cycle comparisons | 1,536 |
| HD6301V1 Mode-7 integration checks | 32 |
| HD6301V1 legal-mode decode checks | 105 |
| HD6301V1 seven-mode execution/source checks | 28 |
| HD6301V1 four-subphase bus-wrapper checks | 659 |
| HD6303R Mode-1/2/4 integration checks | 57 |
| HD6303R legal-mode decode checks | 47 |
| HD6303R four-subphase bus-wrapper checks | 180 |
| HD63701V0 Mode-7 integration checks | 33 |
| HD63701V0 legal-mode decode checks | 95 |
| HD63701V0 six-mode execution/source/TRAP checks | 30 |
| HD63701V0 four-subphase bus-wrapper checks | 496 |
| HD63701V0 digital PROM checks | 28 |
| HD63705V0 integration checks | 47 |
| HD63705V0 peripheral model/RTL cycle comparisons | 768 |
| HD63705V0 exhaustive memory-map checks | 16,384 |
| HD63705V0 RAM fill/reset/standby checks | 576 |
| HD63705V0 exhaustive TCR checks | 256 |
| HD63705V0 timer counter/divider checks | 2,048 |
| HD63705V0 timer source/divider checks | 32 |
| HD63705V0 timer request/mask/TDR-access checks | 8 |
| HD63705V0 GPIO truth/fixed-readback/retention checks | 265 |
| HD63705V0 SCI-DDR selection/override checks | 515 |
| HD63705V0 SCI Tx/Rx byte checks | 4,096 |
| HD63705V0 SCI status/rate/protocol checks | 549 |
| HD63705V0 MR/interrupt priority/protocol checks | 611 |
| MC6800 Table-8 opcode encodings with complete structured bus traces | 165 |
| M6805 table-G2 opcode encodings with complete structured bus traces | 191 |
| M6805 directed core checks | 36 |
| MC68705P5 integration checks | 19 |
| MC68705P5 peripheral model/RTL cycle comparisons | 768 |
| MC68705P5 PCR/VPP table checks | 8 |
| MC68705P5 exhaustive memory-map/RAM checks | 2,272 |
| MC68705P5 GPIO truth/reset/normalized-DDR checks | 164 |
| MC68705P5 INT protocol/request-mask checks | 13 |
| MC68705P5 software-timer direct RTL checks | 5,468 |
| MC68705P5 fixed-MOR timer matrix checks | 224 |
| HD6301 exact TRAP trace checks | 3 |
| Deterministic random programs | 80 (16 per architecture profile) |
| Per-retirement randomized comparisons | 5,120 |
| Bounded formal profiles | 21 (15 at depth 10; 4 mode-decode profiles at depth 5; 1 bus wrapper at depth 8; 1 PROM profile at depth 2) |
| Synthesis tops | 30 |

The Python ALU total comprises 131,072 ADD/ADC cases, 131,072 SUB/SBC/CMP
cases, 196,608 logic cases, 65,536 multiply cases, 3,073 unary/shift/rotate
cases, all 1,024 DAA input states plus 20,000 valid packed-BCD additions, and
1,310,720 16-bit arithmetic boundary sweeps. The RTL bench uses its own loops
and equations and reaches 1,969,155 cases.

Every documented encoding is executed from a generated initial state and
compared after retirement for architectural state, defined condition codes,
documented cycle total, and ordered semantic memory accesses. Undefined flag
bits are masked only where the primary manufacturer table marks them undefined.
For 165 base-MC6800 encodings, the generated opcode regression compares every
documented Table-8 cycle for VMA, address, direction, and defined data. The
closed groups cover every two-cycle inherent/accumulator operation, every
immediate and direct form, every indexed form except JSR, and every extended
form except JSR. Checks include the no-carry indexed address cycle, VMA-low
read-modify-write and store phases, and TST's VMA-low R/W-low final cycle.
MC6801/HD6301 traces remain separate rather than inheriting MC6800 bus timing.

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
direction, exact Motorola bi-phase boundary/half-bit transitions, transition-
interval receive, one-bit idle qualification, and ten-mark bi-phase wake-up,
including the distinct framing-error transfer path,
and a one-cycle IRQ1 pulse which arrives after IRQ2 entry has started and wins
the documented late vector-priority selection. It also removes a timer source's
identity after latching IRQ2 and verifies the documented default SCI vector.

The independent Python device model has fourteen focused regressions for all-mode
decode, RAM/ROM/vector behavior, physical-pin GPIO behavior and SCI direction overrides,
coherent timer reads and ordered status clears, second-cycle input capture,
overflow/compare events, retained IRQ priority, and internally clocked NRZ
transmit/receive with unread-data overrun retention. The additional external
NRZ regression proves that a stationary P22 clock cannot advance serial state,
then compares the transmitted and received ten-bit frames after exactly eight
positive P22 edges per bit. Its cycle/event structure is separate from the RTL
wrapper. The bi-phase regression independently verifies the Figure 6-7 line
code for every bit of a frame, reconstructs a different byte from measured
transition intervals, and exercises the encoded wake-up delimiter.

Two recorded seeds, `0x68030002` and `0x68030003`, drive 768 E-cycle
transactions per mode through a verification-only CPU bus source. After every
cycle, the RTL is compared with model-generated internal read data, external
decode, RAM/control state, GPIO value and direction, timer/capture/compare
state, SCI state and pins, interrupt requests, retained request latches, and
late priority vector. Directed protocol sequences precede the deterministic
random register/pin traffic. These checks establish peripheral transaction and
state timing at the normalized E-cycle boundary. A separate 22-check Port-3
bench distinguishes Motorola's data-returning P3DDR alias from both Hitachi
profiles' write-only `$ff` read, and checks the latch, ordered flag clear,
transparent disable, side-effect exclusions, and both OSS selections. A
separate 219-check four-subphase bench verifies the manufacturer-documented
physical digital ordering across all eight modes: E low/high phases, AS
closure, Port-3 address
and bus turnaround, E-qualified write data, Mode-0 internal-read monitoring,
Mode-5 IOS endpoints, reset pin states, single-chip pin roles, clock-enable
stall, and the Mode-4-to-5 transition. Its independent Python pin model checks
every mode/phase combination and exhaustively classifies all 65,536 Mode-5 IOS
addresses. Both paths also check that MC6801 WAI repeatedly reads the
post-stack SP, preserves Mode-5 IOS decoding, and releases Port 3 during the
read-data phase. It also permanently regresses that the Mode-7 OS3 output
starts after a selected positive E edge, remains active through E fall and the
following low phase, and ends after the next positive E edge. A
separate real-core bench enters WAI in all three
M6800-lineage profiles and makes 18 steady-state/stall checks distinguishing
MC6800 bus release, MC6801 post-stack-SP reads, and HD6301 inactive-strobe
`$ffff`. A separate 47-check real-core trace bench drives NMI, an IRQ2-class
peripheral vector, and IRQ1. It verifies every post-stack-SP/internal read,
both vector addresses, no second stack frame, the exact five/five/six-cycle
latencies, and the first handler opcode fetch. Neither path claims nanosecond
electrical limits.

The HD6301 TRAP suite independently exercises an unassigned opcode and an
instruction-address-error input. It compares the exact 13-cycle normalized bus
trace documented by handbook figure III-8: faulting opcode, discarded PC+1,
two `$ffff` reads, seven stack writes, and `$ffee:$ffef` vector reads. It checks
the complete stacked state, unmaskable I-bit update, RTI restoration of the
faulting PC, and immediate retrap when the invalid opcode remains present.

The HD6303R pin suite independently checks all three legal operating modes.
Its 180 RTL assertions cover Mode-1 dedicated low/high address pins,
Mode-2/4 AS and multiplexed Port-3 turnaround, read release, E-qualified
writes, physical mirroring of internal writes, R/W, historical-reset E
continuation, address drive through the first two reset cycles, exact release
on the third E-fall, distinct WAI and SLP `$ffff` bus states with E still
active, E-synchronous standby entry/exit, standby bus release, and E
suppression. The separate Python model exhaustively projects all 65,536
addresses onto both physical organizations and independently checks the reset,
WAI, SLP, and STBY distinctions. Nanosecond/electrical behavior remains outside
the verified claim.

The HD6303R suite executes through the integrated device wrapper separately in
each legal Mode 1, 2, and 4. Every profile checks external reset vectors,
internal RAM exclusion from the external bus, AIM and XGDX, timer continuity
while sleeping, masked IRQ release from SLP without stacking or vectoring,
simultaneous NMI/IRQ priority, and opcode-error TRAP through the external
`$ffee:$ffef` vector. It also verifies that a framing error leaves RDR unchanged,
with a separate HD6303R peripheral-model regression.
An additional 47-check bus-source suite verifies the mode-specific register
exclusions, internal RAM, external program/vector space, Mode-1 Port-1 address
function, mode-latch readback, and lack of Motorola Mode-4 RAM mirroring or
Mode-5 transition behavior. It also checks the `$0000`-`$001f` instruction-
address region in every legal mode. The independent model rejects every unavailable
mode and checks the same memory partition independently.
RTL and model tests cover the Hitachi full-counter write sequence and TOF at
rollover to `$0000`. The instruction model has a matching regression for the
masked-request SLP rule. Model and RTL tests additionally cover E-synchronous
STBY entry, high-impedance GPIO and external-bus suppression, retained RAM and
STBY_PWR, active-state reset, external reset-vector recovery, and explicit
rejection of the Motorola-only bi-phase selection.

The 659-check HD6301V1 physical-wrapper suite verifies all seven legal modes
over the four E subphases. It covers dedicated and multiplexed address/data,
AS-open/close turnaround, full and DDR-selected partial address pins, exact
Mode-5 IOS decode, E-qualified writes, full-E-cycle Mode-7 OS3,
internal-write mirroring, the third-reset-cycle bus release, distinct WAI/SLP
`$ffff` pin state, and
E-synchronous standby bus release and E suppression. The independent Python
pin model exhaustively projects all 65,536 addresses through every address-bus
mode and separately checks all-seven-mode phase, GPIO, reset, standby, and
low-power behavior.
Nanosecond, oscillator, pad, and electrical behavior is not claimed.

The 105-check HD6301V1 mode suite verifies every legal Mode 0/1/2/4/5/6/7
memory partition, register exclusion, Port-1/4 address role, mask-ROM source,
Mode-0 reset-vector handoff, Mode-5 partial-decode window, and each per-mode
address-error region. A separate
seven-core bench executes the same RAM-using program in every mode and performs
28 checks of retire progress, architectural result, vector source, and program
source. The independent model rejects Mode 3 and verifies each legal partition.

The HD6301V1 Mode-7 suite fetches reset and interrupt vectors through the
internal program-image interface, executes from both the 4-KiB program window
and 128-byte RAM, and verifies a 13-cycle address TRAP from documented
non-memory space. It checks Port 3/4 DDRs and pin reads, Hitachi's write-only
`$ff` P3DDR read with no handshake side effects, the IS3 input latch and
transparent disable, P3CSR's ordered flag-clear protocol, read- and
write-selected active-low OS3 pulses, masked IS3 release from SLP, and enabled
IS3 vectoring through the IRQ1 priority slot. Three independent Python model
tests cover the Mode-7 address
partition, program-select/address-error distinction, GPIO, latch, flag, strobe,
and interrupt state. Additional model and RTL tests verify framing-error RDR
inhibition, Hitachi FRC write/rollover semantics, E-edge DDR reset, synchronous
STBY sampling and retention, and rejection of reserved `CC1:CC0=00` bi-phase
behavior.

The 95-check HD63701V0 mode suite verifies every legal Mode 0/1/2/5/6/7 memory
partition, register exclusion, port/address role, internal-EPROM source,
Mode-0 reset-vector handoff, Mode-5 partial-decode window, and every
unambiguous address-error region. A six-core bench performs 30 retire,
architectural-result, reset/program/TRAP-source, stack-pointer, and TRAP
acknowledgment checks while executing the same RAM-using program into a common
address error in every legal mode. The independent model rejects Modes 3/4 and
verifies the same partitions.

The HD63701V0 Mode-7 suite fetches reset and TRAP vectors from the separate
EPROM image, executes at both `$0040` and `$00ff`, checks OLVL reset, exercises
the 13-cycle TRAP from unambiguous non-memory space, and verifies Port 3/4 GPIO,
Hitachi FRC writes, and V0 framing-error transfer into RDR. Six independent
device-model tests cover the RAM/program partitions, RAME, address-error
classification, timer/GPIO behavior, and SCI difference. Tests deliberately
identify Mode-5/7 execution at `$0040`-`$007f` as a normalized policy because
the manufacturer manual contradicts itself there. It separately checks the
V0-specific asynchronous DDR clear before another E edge occurs. Model and RTL
tests also verify asynchronous STBY entry, immediate program/GPIO suppression,
retained RAM/STBY_PWR, active-state reset, and reset-vector restart.
The real-core bench enters PROM mode during execution, verifies immediate
MCU/peripheral suppression, and checks a fresh Mode-7 reset-vector restart on
release.
The wrapper suite separately checks that the reserved bi-phase selection is
disabled.

The 496-check HD63701V0 physical-wrapper suite verifies all six legal modes
over four digital E subphases. It covers Mode-1 dedicated address/data,
Modes 0/2/6 multiplexed address/data and AS turnaround, Mode-5 DDR-selected
low address and exact IOS decode, Mode-7 GPIO/IS3 plus OS3 across a complete
E cycle, R/W, E-qualified writes,
internal-write mirroring, WAI/SLP `$ffff` pin state, asynchronous all-port RES
entry, E-boundary recovery, and STBY bus/E suppression. Its independent Python
model exhaustively projects all 65,536 addresses through every address-bus
mode and separately checks reset-table, phase, GPIO, standby, and low-power
behavior. Nanosecond, oscillator, pad, and electrical behavior is not claimed.

The 28-check HD63701V0 PROM suite verifies the exact 27256-compatible address
pin permutation, stopped-MCU and high-impedance non-PROM activity, all five
documented table-3-1 states, `$0fff`/`$1000` physical-array boundary,
read/verify storage mapping, erased `$ff` extension, qualified program data,
and safe suppression for the three undocumented control combinations. An
independently organized Python model exhaustively checks all 32,768 PROM
addresses. A symbolic proof covers every address, data byte, voltage
qualification, CE, and OE combination. The tests deliberately do not claim
programming voltage magnitude, pulse duration, erasure, or retention physics.

The 47-check HD63705V0 integration suite includes every digital row of table
2-9: ordinary +5-V read, output disable, VPP programming, VPP verification
with both CE values, and program/verify disable. It also checks the exact
`$1000`/`$1fff` storage endpoints and safe inactivity without a qualified
TIMER/VPP level. The independent model projects all 4,096 programmer
addresses and separately classifies the five documented control states; the
formal profile proves the same read, output-enable, program, and address
equations for arbitrary inputs.

The MC6800 device-wrapper suite verifies reset bus controls, TSC ownership and
state stalling, HALT completion and stable bus release, single-instruction
release, NMI retention on the exact HALT-entry boundary, RTI/re-halt behavior,
masked IRQ retention through release and CLI, DBE-suppressed and enabled
writes, WAI bus release, and IRQ wake-up. It checks the independently recorded
digital contract. A separate 321-check real-core bench verifies the exact
phi1/non-overlap/phi2/non-overlap projection, stable address/direction/state
through phi2, post-phi2 CPU advancement, write data only in a DBE-qualified
phi2 window, TSC phase hold and bus release, and trailing-phi1 HALT sampling.
An independent Python phase model checks the same four boundaries and control
sampling without sharing RTL control structure. Neither path claims nanosecond
or electrical clock-pad behavior.

Directed M6805-lineage tests cover reset, stalls, arithmetic, direct writes,
BSR/RTS, the five-byte interrupt frame, vector fetch, and RTI restoration. The
Motorola reset regression checks all eight table-G2 cycles: six high-vector
reads, the low-vector read, and the address-`$0000` trailing read. Every address,
read direction, bus-valid qualifier, and non-opcode-fetch qualifier is exact;
only the manufacturer-labelled unusable input byte on cycle eight is excluded
from data comparison. The MC68705P5 integration repeats the trace for normal and
bootstrap vector selection, including all six remapped high-byte reads. The
Motorola profile also checks the MC68705P5 manual's exact 11-cycle hardware-
interrupt response and the M6805 Family User's Manual table-G2 bus trace: two
next-opcode-address reads, five ordered stack writes, one unused stack read, two
vector reads, and the trailing read at vector low plus one. It also checks that
an 11-bit return PC stacks the unused upper five PCH bits as ones. This audit
marks only the trailing cycle's manufacturer-labelled unusable input data as
non-comparable for hardware IRQ while still checking its address and direction.
SWI has a separate 11-cycle directed trace whose final cycle compares the
defined first handler opcode at the resolved vector address. One hundred ninety-one opcode
records now carry complete machine-readable table-G2 traces, and focused model
and RTL assertions check the exact cycles for inherent/accumulator, immediate,
relative, bit-operation, direct, indexed-no-offset, indexed-8, BSR, RTS, RTI,
documented extended stores/call, indexed-16 reads/jump, and SWI forms. The checks include both repeated
next-instruction reads, subroutine-target prefetch, ordered stack direction and
data, and irrelevant pre/post-stack reads. Table G2's `$XFF` notation is checked
with an explicit `$00ff` address-defined mask because the table note defines `X`
as don't-care; the normalized core drives those upper bits low. The other 16
documented extended/indexed-16 encodings remain `PARTIAL` because the table does
not provide detailed rows for them; their intermediate bus sequences are
`UNDEFINED_BY_DOCUMENTATION`, not inferred from neighboring rows. This audit found
and fixed the prior two-cycle reset response, bootstrap remap drop after the first
high-vector cycle, eight-cycle interrupt response, zero-filled PCH, and the
incorrect reuse of the hardware-IRQ trailing address for SWI. The
HD6305 profile separately proves that a pending interrupt is accepted only
after the instruction following CLI. The MC68705P5 suites add register/RAM
decode, DDR behavior, mixed-direction GPIO reads, all four timer sources and
all prescalers, TOPT/MOR-fixed timer behavior, timer request clearing,
simultaneous external/timer priority, distinct vectors, secure-qualified
bootstrap selection, and PCR/VPP address/data/program sequencing. Thirteen
focused Python model tests classify every manufacturer PCR-table row, exhaustively
project both normal and programming address partitions, and cover memory, GPIO,
timer, interrupt, and bootstrap behavior. Seed `0x68705a05` provides 768
cycle-by-cycle comparisons without sharing the RTL control structure; eight
additional direct RTL checks exercise every software PCR encoding both with and
without VPP. A 2,048-address RTL sweep proves program-memory selection and data
source at every location, then 224 checks read every RAM byte before and after
reset to prove decode and retention. An additional 164 GPIO checks exhaust each
pin's latch/direction/input truth table, reset direction, and the declared `$ff`
DDR-read normalization; thirteen interrupt checks add all eight external/timer
request and timer-mask combinations to falling-edge assertion, vector
acknowledgement, held-low suppression, and high-to-low rearming. The real-core
suite checks both vector pairs, external priority, complete frame bytes, and
exact 11-cycle entry for both external and retained timer requests. Because the
manual's DDR-read prose conflicts with two of its figures, the normalized read
value is tested without claiming documented silicon equivalence.
The timer extension directly checks all 256 TCR writes; every 8-bit counter
value under each of the eight divide selections; all four source modes crossed
with every divider; disabled, gated-low, held-high, and falling-edge intervals;
request assertion and masking; and wraparound. A 32-instance RTL matrix crosses
both documented fixed clock sources, all prescalers, and both values of the MOR
TIE bit that TOPT makes irrelevant. The independent model separately checks all
256 complete MOR bytes. These tests establish normalized cycle-boundary digital
behavior, not the manual's electrical or nanosecond pulse-width limits.

The HD63705V0 directed suite executes real CPU transactions through both RAM
boundaries and the complete register map. Its 47 checks cover reset/vector
fetch, readable DDRs, mixed GPIO reads, the rising-edge primary timer and its
dedicated WAIT vector, simultaneous INT/INT2 priority and software clearing,
eight-bit external-clock synchronous Tx/Rx, normalized figure-2-18 STOP field
changes and external wake, STBY high impedance with RAM retention, and all five normalized
EPROM control states. Twenty-one independent model tests exercise the same factual
areas and exhaustively project the EPROM address space without sharing RTL
control structure. A direct extension classifies all 16,384 physical addresses
and performs 576 checks over every RAM byte after fill, reset, and standby. It
treats `$0013`-`$001f` as manufacturer-prohibited IC-test space and tests `$ff`
only as the deterministic FPGA normalization. The STOP expectation follows
figure 2-18; the conflicting section 2.9/table 2-5 retention language is
preserved as an unresolved primary-document discrepancy.

The primary-timer extension checks all 256 TCR writes, every 8-bit counter value
under each of the eight divide selections, and all four source modes crossed
with every divider. It separately verifies stopped and gated-low intervals,
rising-only external events, request preservation/clearing and masking, and the
Q&A-defined nondestructive read/restart-on-write TDR behavior. Formal assertions
tie the interrupt output to TCR7/TCR6 and prove reset values for TDR and TCR.
This establishes normalized E-cycle digital behavior, not oscillator or TIMER
pin electrical timing.

The GPIO extension crosses latch, direction, and physical input values for all
31 port bits (248 combinations), then checks Port D's fixed-one readback bit.
WAIT and STOP each preserve four latches and four direction vectors, adding 16
retention checks; the existing standby suite proves high-impedance entry.
Every one of 256 SCR values is applied from both all-input and all-output DDRD
states, followed by SCI disable to prove retained direction; active internal and
external clock overrides are checked separately. This found and regresses a
real implementation defect: SCI had overridden output enables without writing
the D3-D5 DDRD bits mandated by QA635-302A. Formal checks independently require
the active Tx/Rx/CK output-enable relationships and reset/standby high impedance.

The synchronous-SCI extension directly verifies 2,048 falling-edge Tx bit
positions across every byte, 2,048 rising-edge Rx bit positions across every
byte, all 256 SSR writes, all 32 Timer2 source/rate combinations, and 261 SDR
protocol cases. It checks exact eighth-rising-edge request assertion, final-bit
and receive-data retention, post-completion clock holdoff, disabled-mode general
register behavior, simultaneous transfer, prescaler initialization even with
external CK selected, SSR-clear-without-rearm, and reset-only recovery after a
prohibited mid-transfer SDR access. This regression found and permanently fixes
three implementation defects: automatic Rx rearming after completion, failure
to reset the Timer2 prescaler on external-mode SDR access, and failure to latch
the documented transfer-fault disable. QA635-308A leaves partial shifted data
undefined after the prohibited access, so deterministic cancellation is tested
without a silicon-data claim. Both Verilator and Icarus run the same direct
matrix.

The interrupt-controller extension crosses both initial MR7 states with every
one of 256 MR writes (512 direct RTL and 512 independent-model cases). The model
then checks all 1,024 combinations of INT, INT2/timer/SCI/Timer2 request and
mask state with both normal and WAIT vector selection; the RTL independently
walks 96 source-clear stages across all 16 peripheral-mask combinations. Three
direct protocol sequences and independent model cases verify edge-only and
edge-plus-level INT, INT2 masking and clear-only retention, held-low suppression,
high-to-low rearming, and the QA635-325A rule that pins already low at standby
recovery do not create an edge. Real-core checks cover simultaneous INT/INT2,
priority and repeated service, software clearing, the instruction-after-CLI
delay, timer entry from established WAIT, and complete PC/X/A/CCR stack frames.
Pending timer and INT cases prove QA635-329A's four-cycle WAIT/STOP completion
without low-power entry; the timer takes normal `$1ff8`, while a request arising
inside WAIT takes `$1ff6`. A masked timer plus masked INT2 case proves that
retained masked requests still permit STOP. This audit found and fixes both the
false one-cycle low-power state/wrong-vector defect and synthesized edges on
already-low standby-return pins.

Seed `0x63705000` adds 768 normalized E-cycle comparisons. A directed prefix
precedes deterministic register, pin, memory, interrupt, and low-power traffic;
after every edge the bench compares read/decode, all GPIO values/directions,
timer/serial state, requests, vector priority, and synchronous serial pins. This
corpus found and permanently regresses a model-only STOP recovery defect in
which a CK/TIMER transition during stopped clocks could have appeared as a new
edge on resume.

## Formal checks

`make formal` uses Yosys bounded SAT over the M6800, MC6801, HD6301, M6805, and
HD6305 profiles plus the MC6800 normalized and four-subphase bus wrappers,
MC6801 Mode 3 integration and
Mode-0/Mode-4 decode, the MC6801 four-subphase bus wrapper, HD6303R and its
physical bus wrapper, HD6301V1 and its four-subphase physical bus wrapper,
HD63701V0 legal-mode decode, four-subphase physical bus, and digital PROM
boundary, MC68705P5,
HD6301V1 and HD63701V0 Mode-7 integrations, and the HD63705V0 MCU.
The core/device, MC6800 phase, HD6301V1 physical-wrapper, and HD63701V0
physical-wrapper profiles run at depth 10, the four mode-decode profiles at
depth 5, the MC6801 physical bus wrapper at depth 8, and the purely
combinational HD63701V0 PROM profile at depth 2; together
they prove the committed safety properties for all symbolic input sequences
within those bounds:

- a write is always a valid bus cycle;
- an opcode fetch is a valid read;
- waiting and sleeping/stopped states are mutually exclusive;
- WAI bus state follows the selected profile: released for M6800, a valid read
  at post-stack SP for MC6801, and invalid `$ffff` for HD6301;
- a masked request releases HD6301 SLP without leaving the core asleep;
- interrupt-vector selection is legal;
- accepted M6805 reset cycles expose six high-vector reads, one low-vector
  read, and one address-zero read, while HD6305 retains its two vector reads;
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
- The MC6801 physical wrapper sequences all four phases under clock enable,
  asserts E only in its two data phases, presents and releases multiplexed
  Port 3 around AS, and confines Mode-5 IOS and write drive to their documented
  address and E windows. Its Mode-7 OS3 state can change only at positive E
  edges and is otherwise stable, including clock-enable stalls.
- The HD6303R physical wrapper holds Mode-1 dedicated address pins, sequences
  Mode-2/4 AS and Port-3 turnaround, permits data drive only for E-high writes,
  presents the SLP `$ffff` read without stopping E, releases every address/data
  bus in standby, and suppresses E while standby is active.
- The HD6301V1 physical wrapper sequences every phase, confines Mode-5 IOS to
  `$0100`-`$01ff`, never drives multiplexed read data, releases address buses
  after three completed low-reset E cycles and in standby, keeps WAI/SLP data
  released, suppresses E while standby is active, and permits Mode-7 OS3
  changes only at positive E edges.
- MC68705P5 physical PC/SP/address geometry remains legal, bootstrap vector
  remapping respects secure mode, program reads stay within internal storage,
  the PCR never reaches either manufacturer-invalid `PGE=0,PLE=1` row, VPP and
  PCR bits exactly qualify latch/program outputs, and disabled-cycle state
  stalls.
- HD6301V1 program reads occur only in `$f000`-`$ffff`, Mode 1 never selects
  program memory and drives its full address, Mode-5 external selection remains
  in `$0100`-`$01ff`, expanded selections do not overlap the mask-ROM port,
  non-memory Mode-7 fetches never select program memory, OS3 is confined to
  PORT3 accesses, and complete digital device state is stable while clock
  enable is inactive.
- HD63701V0 Mode 0 never overlaps external and EPROM selection and exposes
  only its initial reset vectors externally within `$f000`-`$ffff`; Mode 5
  likewise prevents selection overlap and confines external cycles to
  `$0100`-`$01ff`.
- The HD63701V0 physical wrapper follows the four-phase sequence, immediately
  releases every port for RES/STBY, recovers only at a completing E boundary,
  confines multiplexed address and write drive to their documented phases,
  projects the `$ffff` WAI/SLP state without stopping E, and permits Mode-7
  OS3 changes only at positive E edges.
- HD63701V0 PROM mode suppresses MCU/external activity, maps all fifteen
  address bits to the documented pins, selects storage only for the physical
  4-KiB array, drives data only for read/verify, returns erased `$ff` outside
  the array, and issues a program request only for the documented qualified
  state within the array.
- HD63705V0 PC/SP and physical-address geometry remain legal, interrupt vectors
  stay in the documented set, all five table-2-9 EPROM states use exact
  ordinary-read/VPP/CE/OE qualification, standby/EPROM mode disables GPIO
  drive, disabled-cycle state stalls, SCI/Timer2 interrupt output is exactly
  its two request/mask equations, INT2 delivery is exactly MR7 and not MR6,
  interrupt-vector priority follows the documented source order, and SCI
  control/status reset values are exact.

These bounded safety proofs complement simulation; they are not a liveness or
full instruction-correctness proof.

## Simulation and synthesis tool diversity

Verilator is the primary strict-warning simulator. Icarus Verilog independently
compiles and runs both directed CPU suites, the MC6800 four-subphase bus suite,
the HD6301 TRAP trace, the interrupt
delay traces, the MC68705P5, HD6301V1, HD6303R, all-mode and PROM HD63701V0, and
HD63705V0 device suites, both MC6801/MC6803 peripheral differential profiles,
and the MC6801 all-mode/direct-boot and four-subphase bus suites, the HD6301V1
all-mode, HD6303R Mode-1/2/4, and HD63701V0 all-mode phased-bus suites, plus the
MC68705P5 and HD63705V0 peripheral differential corpora from generated
package-flattened views. Icarus reports its known conservative `always_*`
sensitivity note for constant part-selects; no design warning is suppressed to
hide it.

Representative generic Yosys 0.68 results from the current source are:

| Top/profile | Generic cells | Sequential cells |
|---|---:|---:|
| M6800 | 6,406 | 225 |
| MC6800 bus wrapper | 6,402 | 231 |
| MC6800 four-subphase integration wrapper | 6,407 | 236 |
| MC6801 | 6,344 | 218 |
| MC6801 Mode 2 integration | 11,434 | 1,447 |
| MC6801 Mode 4/5 integration | 11,438 | 1,494 |
| MC6801 four-subphase bus wrapper | 11,579 | 1,450 |
| HD6301 | 7,453 | 218 |
| HD6301V1 Mode 0 integration | 12,134 | 1,438 |
| HD6301V1 Mode 1 integration | 12,113 | 1,421 |
| HD6301V1 Mode 4 integration | 12,155 | 1,437 |
| HD6301V1 Mode 5 integration | 12,141 | 1,445 |
| HD6301V1 Mode 6 integration | 12,249 | 1,446 |
| HD6301V1 Mode 7 integration | 12,236 | 1,485 |
| HD6301V1 four-subphase bus wrapper | 12,423 | 1,451 |
| HD6303R Mode 1 integration | 12,126 | 1,421 |
| HD6303R Mode 2 integration | 12,406 | 1,439 |
| HD6303R Mode 4 integration | 12,147 | 1,437 |
| HD6303R four-subphase bus wrapper | 12,380 | 1,443 |
| HD63701V0 Mode 0 integration | 13,986 | 1,949 |
| HD63701V0 Mode 1 integration | 13,886 | 1,932 |
| HD63701V0 Mode 2 integration | 14,113 | 1,950 |
| HD63701V0 Mode 5 integration | 13,947 | 1,956 |
| HD63701V0 Mode 6 integration | 14,051 | 1,957 |
| HD63701V0 Mode 7 integration | 14,079 | 1,996 |
| HD63701V0 four-subphase bus wrapper | 14,218 | 1,960 |
| M6805 | 4,210 | 192 |
| HD6305 | 4,021 | 172 |
| MC68705P5 integration | 7,440 | 1,162 |
| HD63705V0 integration | 10,293 | 1,862 |

Sequential counts include every synthesized DFF primitive and inferred memory
bit. Cell counts are tool/version/technology dependent and are smoke-test
evidence,
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
