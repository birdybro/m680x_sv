# Compatibility and implementation status

No processor or MCU is currently claimed complete. This matrix fixes the v1
engineering targets and distinguishes CPU-core,
full-device, cycle-count, and bus-trace claims. The authoritative structured
record is `spec/devices.yml`; status changes require passing evidence.

## Architectural boundaries

Primary manuals establish five implementation lineages:

| Architecture | Programming model | Distinguishing facts |
|---|---|---|
| M6800 | A, B, X, SP, PC, HINZVC | Original two-phase-bus MPU and opcode map |
| M6801 | M6800 model plus D=A:B | Entire M6800 ISA plus 16-bit, stack/index, and multiply extensions; faster cycles |
| M6805 | A, 8-bit X, device-sized PC/SP, HINZC | Different controller opcode map, bit operations, device-specific stack/vector geometry |
| HD6301 | M6801 model | Adds AIM/OIM/EIM/TIM, XGDX, SLP, TRAP behavior, and Hitachi cycle counts |
| HD6305 | M6805 model | Adds documented DAA and low-power behavior with Hitachi timing/vector organization |

M6800 and M6805 are not treated as interchangeable. MC6803 is specifically an
MC6801 limited to documented expanded modes. The Hitachi parts are not modeled
as branding aliases: their instructions, traps, memory, timers, serial blocks,
and low-power modes have separate specifications.

## v1 target matrix

| Target | Scope | CPU | Cycle count | Bus trace | Device/MCU integration |
|---|---|---:|---:|---:|---:|
| Motorola MC6800 | physical CPU device | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Motorola MC6801 | full MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Motorola MC6803 | full ROMless MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| normalized M6805 CPU | FPGA core only | PARTIAL | PARTIAL | PARTIAL | NOT_APPLICABLE |
| Motorola MC68705P5 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Hitachi HD6301V1 | full MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Hitachi HD6303R | full ROMless MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Hitachi HD63701V0 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Hitachi HD63705V0 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

The normalized M6805 core is not a silicon-device compatibility claim. A device
profile must provide effective PC width, stack window, vectors, interrupt set,
and low-power features. MC68705P5 and HD63705V0 are the concrete full-MCU v1
profiles for the Motorola and Hitachi 6805-derived lineages.

`PARTIAL` CPU status means every documented opcode encoding has architectural,
cycle-total, and ordered semantic-bus comparison against the independent model,
while the HD6301 profile also implements every documented opcode-error TRAP map
value. The base MC6800 profile has complete structured and RTL Table-8 traces
for 165 two-cycle, immediate, direct, indexed except JSR, and extended except
JSR encodings, including next-opcode, partial indexed-address, and VMA-low
cycles. Remaining
MC6800 Table-8 groups stay `PARTIAL` while their VMA-low internal cycles are
implemented and checked. The Motorola M6805 profile additionally has complete structured and RTL
bus traces for all 191 encodings with published table-G2 rows: inherent,
accumulator, immediate, relative, bit, direct, both short-indexed forms,
extended stores/call, and indexed-16 reads/jump, including BSR/RTS/RTI/SWI.
The intermediate traces of the 16 otherwise documented extended and indexed-16
encodings whose detailed rows are absent from table G2 are
`UNDEFINED_BY_DOCUMENTATION`; device-specific interrupt sources remain partial.
The MC68705P5 wrapper additionally has
tested RAM/register decode, GPIO, every timer input/prescaler mode in both
software-controlled and fixed-MOR configurations, interrupt priority, the
secure-qualified bootstrap vector, and digital PCR address/data/program
sequencing. All eight rows of Motorola's PCR/VPP table are classified; every
software encoding is directly checked with and without VPP, the invalid PGE/PLE
combination is unreachable, and all 2,048 programming addresses are classified.
The internal-memory dimension is `COMPLETE`: independent classification and
direct RTL checks account for all 2,048 normal-mode addresses, all 112 RAM bytes
are checked before and after reset, and the program/MOR/bootstrap/vector regions
are individually selected. Per-bit latch/direction/pin truth tables exercise all
20 GPIO lines in 160 states, with four reset/normalized-DDR checks and five INT
edge/rearm checks. GPIO remains `PARTIAL` because the manufacturer's
printed-page-13 DDR-read caution conflicts with the all-one values in figures 4
and 16. The wrapper deterministically returns `$ff` but classifies silicon
equivalence for those reads as `UNDEFINED_BY_DOCUMENTATION`. A 768-cycle
independent peripheral model/RTL comparison covers the normalized boundary.
The timer dimension is `COMPLETE` at that boundary: all 256 TCR encodings, all
2,048 counter-value/divider pairs, the 32 source/divider combinations, and all
32 timer-relevant fixed-MOR RTL configurations have direct evidence. The
independent model additionally projects all 256 MOR byte values. Electrical
pad behavior, oscillator physics, and nanosecond minimum pulse widths remain
outside this digital timer claim.
The normalized interrupt-controller dimension is `COMPLETE`. Independent model
and direct RTL matrices cross every external-request, timer-request, and timer-
mask state. Real-core traces verify external priority, edge-latch acknowledge
and rearming, retained timer service, the PCL/PCH/X/A/CCR stack order and data,
both vector reads, and Motorola's exact 11-cycle hardware-interrupt response.
The complete manufacturer sequence is two next-opcode-address reads, five stack
writes, an unused stack read, two vector reads, and a trailing read at vector
low plus one. The stacked PCH has all five unused upper bits set for the
device's 11-bit program counter.
The normalized reset-response bus-trace dimension is also `COMPLETE`: the
independent model and real core agree on the documented eight reads, and the
MC68705P5 wrapper verifies ordinary and bootstrap storage selection across all
six repeated high-vector cycles. Cycle-eight input data remains intentionally
non-comparable because Motorola labels it unusable; its address, direction, and
qualifiers are still checked.
SWI is independently trace-complete for this normalized boundary: its cycle 11
uses the resolved handler address and compares the defined first-opcode byte,
instead of applying the hardware IRQ trailing-read rule.
EPROM voltage/pulse/retention physics and the copyrighted factory bootstrap-ROM
image remain outside the distributable implementation.

The MC6800 device-wrapper claim covers normalized digital HALT/TSC/DBE/VMA/BA
and three-state ownership behavior, including interrupt retention while halted.
A separate four-subphase integration wrapper implements the documented digital
phi1/non-overlap/phi2/non-overlap order, trailing-phi1 control sampling,
post-phi2 CPU advancement, DBE qualification, and compliant TSC phase hold.
Because the historical device receives phi1/phi2 as inputs, its projected
phase outputs are an FPGA integration convention. Nanosecond pulse widths,
electrical clock-pad behavior, and cycles whose detailed bus activity is not
established by the selected manufacturer documentation remain outside the
claim.

The MC6801 device claim covers normalized decode for Modes 0-7 and the 1R/6R
mask-ROM relocation options. Directed model and RTL tests cover register
exclusions, RAM availability and Mode-4 mirroring, normal/relocated program
windows, Mode-0 external-to-internal reset-vector handoff, Mode-5's selected
`$0100-$01ff` window, Mode-4-to-5 transition, single-chip bus suppression, and
mode-selected Port 3/4 GPIO/address functions. The complete peripheral suite
continues to exercise Modes 2/3 and implements Port 1/2 GPIO, the
capture/compare/overflow timer, documented interrupt priority/vectors, and
all four documented Motorola SCI selections. Bi-phase-M transmit/receive uses
boundary transitions, optional one-valued half-bit transitions, transition-
interval decoding, and idle/wake qualification. External NRZ forces P22 to
input and advances one serial bit per eight sampled positive clock edges.

The separate Motorola device-pin wrapper implements the documented digital
four-subphase E waveform for all eight modes. It covers AS and Port-3
address/data turnaround in multiplexed Modes 0/1/2/3/6, R/W, Mode-5 IOS and
E-qualified data drive, reset bus release, the single-chip IS3 latch/flag-clear
protocol, Motorola's P3DDR data alias, OS3 from one positive E edge to the
next, and the Mode-4-to-5 transition. During WAI it repeatedly presents the current
post-stack SP as a read, including Mode-5 IOS decode and Port-3 read release.
The response trace retains that read through internal cycles, then performs
the two vector reads and reaches the first handler opcode in five E-cycles for
NMI/IRQ2 or six for IRQ1.
Manufacturer nanosecond limits, oscillator/pad behavior, and electrical pull
strength remain outside the claim.

The MC6803 profile inherits only the manufacturer-stated Modes 2/3 facts and
rejects other public configurations. Its shared Motorola digital multiplexed
bus waveform is implemented. Single-chip Port 3 handshake behavior is not
applicable to the claimed MC6803 Modes 2/3 profile; nanosecond electrical
timing remains outside the partial pin-level claim.
For a framing error, MC6801 transfers the misframed byte into RDR while setting
ORFE without RDRF. This behavior is independently selected and tested rather
than generalized to Hitachi parts.

The HD6303R claim binds the HD6301 instruction profile to the
manufacturer-compatible register, 128-byte RAM, mode-dependent Port 1/2,
timer, SCI, and interrupt integration in every available Mode 1, 2, and 4.
Directed integration tests repeat HD6301-only instructions, opcode TRAP,
continued timer operation in SLP, masked-request wake without vectoring, and
simultaneous NMI/IRQ priority in all three modes.
They also cover E-synchronous STBY entry, high-impedance GPIO/external-bus
qualification, retained RAM/STBY_PWR, and reset-vector recovery. Single-chip
Port 3 handshakes are not applicable to the documented ROMless Modes 1/2/4.
A separate physical wrapper
implements active Mode-1 dedicated address/data timing and the Mode-2/4
four-subphase AS/address/data waveform. It also mirrors internal writes onto
the physical data bus, presents the documented `$ffff` read while SLP leaves E
active, presents `$ffff` with released data during WAI, and stops E while
standby is active. The normalized WAI transaction is invalid to preserve the
handbook's inactive-strobe distinction. RES preserves address drive for two
completed E cycles and releases it on the third, as documented. Nanosecond
limits and oscillator/pad behavior remain unclaimed. The Hitachi SCI table
reserves `CC1:CC0=00`, so the wrapper explicitly
disables Motorola bi-phase rather than leaking that format across variants.
The primary mode table makes Modes 1, 2, and 4 available on HD6303R; Modes 0,
5, 6, and 7 require the disabled mask ROM. Mode 1 exposes the full
non-multiplexed address/data bus on the physical device and makes
`$0000`/`$0002` external while Port 1 drives A0-A7. The RTL exposes that mode at
its normalized external-memory boundary. Modes 2 and 4 are equivalent expanded
multiplexed RAM modes; the implementation explicitly prevents Motorola Mode-4
RAM mirroring and the Mode-4-to-5 transition from leaking into this Hitachi
profile.
Every legal mode also invokes address TRAP for opcode fetches in
`$0000`-`$001f`, even where a mode-specific register exclusion sources the
underlying byte from external memory; normal data accesses do not trap. The
handbook omits Mode 2 from table 2-13-1, so that mode follows its explicitly
documented Mode-4-equivalent classification.
HD6303R follows the HD6301V1-specific framing-error rule: the shift-register
byte is not transferred to RDR when the stop bit is missing.
Both parts also implement Hitachi's writable 16-bit FRC sequence and assert
TOF on rollover to `$0000`, rather than using the MC6801 write/overflow rules.

The HD6301V1 claim covers every legal Mode 0, 1, 2, 4, 5, 6, and 7 at both the
normalized memory boundary and a separate four-subphase digital pin boundary.
Mode-directed tests cover the `$f000`-`$ffff`
mask-ROM selection in Modes 0/5/6/7, external program space in Modes 1/2/4,
Mode-0 external reset-vector handoff, Mode-5 partial decode, Mode-1 Port-1
address function, mode-specific register exclusions, and common internal RAM.
A seven-core integration bench executes the same program from the correct
internal or external source in every mode and compares its architectural
result. The program image remains an integration input.
Mode-directed address checks cover `$0000`-`$001f` in Modes 0/1/2/4/6, the
two Mode-5 non-memory spans, and both Mode-7 spans. Mode 2 again follows the
manual's explicit Mode-2/Mode-4 equivalence because the address-error table
omits a separate Mode-2 row.

The 659-check all-mode pin suite covers dedicated and multiplexed address/data,
Port-4 partial-address DDR behavior, AS, exact Mode-5 IOS decode, R/W, internal
write mirroring, and Mode-7 OS3 across one complete E cycle, plus address
release after the third low-RES cycle, distinct WAI/SLP bus state, and
E-synchronous standby.
An independent model exhaustively projects every 16-bit address through all six
address-bus modes and separately checks Mode-7 GPIO/strobes. Mode 7 additionally
covers all four GPIO ports, the IS3 input latch and IRQ1 source, write-only
P3DDR reads, the ordered P3CSR/PORT3 clear protocol, read/write-selected OS3,
common timer/SCI functions, and SLP behavior.
Directed tests verify that instruction fetches in both documented non-memory
ranges enter the 13-cycle address TRAP while normal data accesses do not.
E-synchronous STBY entry, retained RAM/STBY_PWR, high-impedance ports,
reset-vector recovery, and the reserved bi-phase selection are tested.
Nanosecond/oscillator/pad characteristics and actual mask-ROM contents remain
outside this partial claim.
Its tested SCI profile likewise inhibits transfer of a misframed byte into RDR.
The Mode-7 timer regression verifies full-counter double-byte writes and the
documented Hitachi TOF boundary. It also verifies that V1 DDR clearing waits
for the next E edge.

The HD63701V0 claim covers every legal Mode 0, 1, 2, 5, 6, and 7 at both the
normalized transaction and four-subphase digital pin boundaries. Mode-directed tests cover internal EPROM in Modes
0/5/6/7, external program memory in Modes 1/2, Mode-0 external reset-vector
handoff, Mode-5 partial decode, mode-specific register and Port-1/3/4 roles,
RAME-controlled 192-byte RAM at `$0040`-`$00ff`, and every unambiguous
per-mode address-error span. A six-core bench executes the same RAM-using
program from the selected program source, enters address TRAP at `$001f`, and
fetches the handler from the correct vector source in all six modes.

Mode 7 additionally covers four GPIO ports with IS3/OS3, the common Hitachi
timer and interrupts, V0-specific framing-error transfer, SLP, and a separately
supplied `$f000`-`$ffff` EPROM image. The RTL and model execute from both RAM
boundaries and enter the exact 13-cycle address TRAP from unambiguous
non-memory space. Asynchronous STBY entry, retained RAM/STBY_PWR,
high-impedance ports and buses, and reset-vector recovery are tested. Physical
pin tests cover Mode-1 dedicated and Modes 0/2/6 multiplexed address/data,
Mode-5 partial address/IOS, Mode-7 IS3/OS3, R/W, E, internal-write mirroring,
WAI/SLP, asynchronous reset entry, synchronous reset recovery, and standby.
The separate digital PROM interface covers the exact 27256-compatible pin
mapping, stopped-MCU state, all five table-3-1 operations, 4-KiB
`$0000`-`$0fff` array boundary, erased `$ff` extension, read/verify data, and
integration-owned program request. Programming voltage magnitude and pulse
timing, erasure, retention, and nanosecond/oscillator/pad behavior remain
outside the claim. The
reserved `CC1:CC0=00` selection does not enable Motorola bi-phase. The V0
regression also verifies its distinct asynchronous DDR reset.

The HD63705V0 claim covers its distinct 14-bit CPU/device boundary, physical
`$00c0`-`$00ff` stack window with one-filled unused PCH bits,
`$0040`-`$00ff` RAM, `$1000`-`$1fff` EPROM,
31 GPIO lines, all four primary-timer clock selections and eight prescalers,
INT/INT2 sensing and documented vector priority, synchronous SCI/Timer2,
WAIT/STOP/STBY digital state changes, and normalized EPROM verify/program
controls. The programming boundary distinguishes ordinary +5-V reads from
VPP operations and implements all five digital states in table 2-9, including
CE-don't-care verification. Directed integration checks, an exhaustive
4,096-address programming model, formal control proofs, and 768 independent
model/RTL E-cycle comparisons cover these features. Oscillator/STOP recovery
time, electrical pin timing, EPROM voltage/pulse/retention physics, and silicon
values on unused memory reads remain outside the partial digital claim. Its
internal-memory dimension is separately `COMPLETE`: the regression classifies
all 16,384 physical addresses and performs 576 read checks across every one of
the 192 RAM bytes after fill, reset, and standby. Q&A QA635-338A identifies
`$0013`-`$001f` as manufacturer-prohibited IC-test space without defining a
stable result; `$ff` reads and ignored writes there and in unused space are a
deterministic FPGA policy only. Figure 2-18 resets TDR and selected TCR/SSR
fields on STOP, while section 2.9 prose and table 2-5 say registers are retained
except TCR6/TCR7. The implementation follows figure 2-18, records the conflict
as `UNDEFINED_BY_DOCUMENTATION`, and keeps low-power status `PARTIAL`. Its
normalized primary-timer dimension is `COMPLETE`: direct RTL and independent
model tests cover all 256 TCR encodings, all 2,048 counter/divider pairs, all
32 source/divider combinations, request/mask control, TDR access during active
countdown, reset, the Q&A-confirmed rising external edge, and the dedicated
WAIT vector. Oscillator and TIMER-pin electrical timing remain excluded. The
normalized GPIO dimension is also `COMPLETE`: 265 direct RTL checks cover every
one of the 248 per-pin latch/direction/input combinations and Port D's fixed
readback bit plus WAIT/STOP retention, while 515 SCI-DDR checks cover every SCR
value from both all-input and all-output initial directions plus active override
cases. The independent model repeats the same factual state space. QA635-302A's requirement that SCI
selection writes and later retains D3-D5's DDR values is implemented; D0-D2/D6
remain independent as QA635-303A requires. Analog pad behavior remains excluded.
The normalized synchronous-SCI/Timer2 dimension is `COMPLETE`: direct RTL and
independent model tests exhaust all 256 Tx bytes, all 256 Rx bytes, every SSR
value, and every one of the 16 internal widths under both serial source
selections. They verify falling-edge Tx, rising-edge Rx and eighth-edge request,
final-bit/data retention, post-completion clock holdoff, simultaneous transfer,
SDR/SSR access rules, Timer2 request timing, and the reset-only recovery from a
prohibited mid-transfer SDR access specified by QA635-305A through QA635-313A.
The undefined partial-data result of that prohibited access is deterministically
cancelled without a silicon-equivalence claim. Oscillator, CK-pad, and
electrical timing remain excluded.
The normalized interrupt-controller dimension is `COMPLETE`. Exhaustive model
and direct RTL matrices cover MR7 clear-only behavior, every request/mask
priority combination, INT edge and level modes, INT2 falling-edge retention,
masked/unmasked delivery, shared and timer-from-WAIT vectors, simultaneous and
repeated service, complete stack/RTI state, and Q&A-defined low-power entry and
standby-return behavior. QA635-329A prevents WAIT/STOP entry when an unmasked
request is already pending; a pending timer therefore uses `$1ff8`, not the
`$1ff6` vector reserved for a timer arising after WAIT entry. QA635-325A also
requires that an already-low standby-return pin not be invented as a falling
edge. Both behaviors have direct real-core regressions. Oscillator recovery and
the separately disputed STOP register state remain outside this closed digital
controller dimension.
The manual's `$0000`-`$00ff` programming-range sentence conflicts with its 4-KiB,
twelve-address-input, and `$1000`-`$1fff` memory-map facts; the interface uses
the mutually consistent `$0000`-`$0fff` programmer range and preserves the
discrepancy in `spec/devices.yml`.

The manufacturer manual is internally inconsistent for Mode-5 and Mode-7
instruction fetches at `$0040`-`$007f`: every mode's memory map and the
address-error prose identify the range as internal RAM, but table 2-13-1
includes it in both modes' address-error spans.
The normalized implementation permits execution throughout physical RAM,
consistent with the memory map, and classifies silicon TRAP behavior for this
range as `UNDEFINED_BY_DOCUMENTATION`. No verified bus-trace claim depends on
that choice.

## Device differences relevant to implementation

- MC6800 has no internal RAM or MCU peripherals. Its normalized device wrapper
  implements VMA, BA, DBE, HALT, TSC, and bus ownership. A separate digital
  four-subphase wrapper projects non-overlapping phi1/phi2 integration timing;
  nanosecond and electrical clock-pad behavior remain outside the claim.
- MC6801 has 128 bytes of RAM, 2 KiB of mask ROM where enabled, four ports, a
  three-function 16-bit timer, SCI, and eight hardware-selected modes. Idle
  cycles in expanded modes appear as reads of `FFFF`; there is no MC6800 VMA.
- MC6803 has the MC6801 CPU and peripherals but is documented only as modes 2
  or 3 (plus manufacturing mode 0 with undefined ROM contents).
- MC68705P5 has an 11-bit PC, a fixed 31-byte usable stack window, 112 bytes of
  RAM, 1804 user-EPROM bytes, bootstrap ROM, 20 GPIO lines, and an 8-bit timer.
  It has no general external-memory bus.
- HD6301V1 provides 4 KiB ROM and 128 bytes RAM; HD6303R is the ROMless 40-pin
  member. Both use the HD6301 ISA, timer, SCI, low-power modes, and TRAP.
- HD63701V0 substitutes 4 KiB EPROM, has 192 bytes RAM, retains HD6301 ISA
  extensions and TRAP behavior, transfers a framing-error byte into RDR, and
  provides a stopped-MCU 27256-compatible digital PROM mode.
- HD63705V0 has a 14-bit PC, stack top `00FF`, 192 bytes RAM, 4 KiB EPROM,
  31 GPIO lines, two timer functions, synchronous SCI, and wait/stop/standby
  modes. Its vector region is `1FF4`-`1FFF`.

The normalized HD6301 CPU accepts a wrapper-generated instruction-address-error
request and implements the documented 13-cycle TRAP entry, complete state
stack, `$ffee:$ffef` vector, and retry PC. A full MCU claim still requires each
device wrapper to decode its own non-memory space and generate that request.
The HD6301V1 wrapper implements its table-defined per-mode regions and keeps
Mode-7 vector reads on the internal program interface. HD63701V0 uses
`$0000`-`$003f` plus `$0100`-`$efff` in Mode 7, and `$0000`-`$003f` plus
`$0200`-`$efff` in Mode 5; the conflicting physical-RAM range is explicitly
unverified as described above. Modes 0/1/2/6 on both V0 and V1, Mode 4 on V1,
and all HD6303R modes trap opcode fetches in `$0000`-`$001f`. Opcode-error TRAP
remains independently active in every Hitachi CPU profile.

## Deferred documented variants

The reference set also identifies MC68701, multiple MC6805/MC68705 P/R/T/U
members, HD6301/HD6303 X and Y members, HD63701 X/Y members, and numerous
HD6305 X/Y/low-voltage parts. They are `NOT_IMPLEMENTED` and outside v1 because
their manuals show materially different memory sizes, stack windows, port
counts, timers, serial behavior, bus expansion, or low-voltage peripherals.
Their existence does not imply compatibility with a selected v1 device.

## Undefined or non-digital behavior

Unassigned opcode results remain `UNDEFINED_BY_DOCUMENTATION` unless a primary
manufacturer source defines a trap. EPROM retention, programming voltage
margins, oscillator analog behavior, pad drive strength, and metastability are
not synthesizable digital-equivalence claims. Digital programming modes,
register effects, pin multiplexing, and documented cycle boundaries remain in
scope for full-MCU targets.
