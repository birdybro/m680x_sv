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
value. Detailed manufacturer bus-waveform coverage and remaining device-specific
interrupt sources are not yet complete. The MC68705P5 wrapper additionally has
tested RAM/register decode, GPIO, every timer input/prescaler mode in both
software-controlled and fixed-MOR configurations, interrupt priority, the
secure-qualified bootstrap vector, and digital PCR address/data/program
sequencing. A 768-cycle independent peripheral model/RTL comparison covers the
normalized boundary. EPROM voltage/pulse/retention physics and the copyrighted
factory bootstrap-ROM image remain outside the distributable implementation.

The MC6800 device-wrapper claim covers normalized digital HALT/TSC/DBE/VMA/BA
and three-state ownership behavior, including interrupt retention while halted.
It does not claim pin-level phi1/phi2 generation, electrical timing, or complete
external waveforms for cycles whose detailed bus activity is not established by
the selected manufacturer documentation.

The MC6801/MC6803 device claim currently covers the normalized expanded-bus
Mode 2 and Mode 3 boundary. Mode 2 has tested RAME-controlled 128-byte RAM;
Mode 3 keeps that window external. Both profiles implement the common register
subset, Port 1/2 GPIO and pin overrides, the capture/compare/overflow timer,
documented interrupt priority/vectors, and internally clocked NRZ SCI. The
MC6803 profile inherits those facts under the manufacturer's explicit
functional-identity statement and rejects modes beyond 2/3. MC6801 Modes
0/1/4/5/6/7, mask ROM, Port 3 handshakes, physical multiplexed-bus waveforms,
bi-phase SCI, and external-clock SCI remain outside this partial claim.
For a framing error, MC6801 transfers the misframed byte into RDR while setting
ORFE without RDRF. This behavior is independently selected and tested rather
than generalized to Hitachi parts.

The HD6303R claim currently binds the HD6301 instruction profile to the
manufacturer-compatible register, 128-byte RAM, Port 1/2, timer, SCI, and
interrupt integration in expanded multiplexed Mode 2. Directed integration
tests cover HD6301-only instructions, opcode TRAP, continued timer operation in
SLP, masked-request wake without vectoring, and simultaneous NMI/IRQ priority.
Modes 1/5, standby entry, Port 3 handshakes, the physical multiplexed waveform,
bi-phase SCI, and external-clock SCI remain outside this partial claim.
HD6303R follows the HD6301V1-specific framing-error rule: the shift-register
byte is not transferred to RDR when the stop bit is missing.
Both parts also implement Hitachi's writable 16-bit FRC sequence and assert
TOF on rollover to `$0000`, rather than using the MC6801 write/overflow rules.

The HD6301V1 claim covers single-chip Mode 7: its internal register window,
RAME-controlled executable 128-byte RAM, four GPIO ports, IS3 input latch and
IRQ1 source, read/write-selected OS3, common timer/SCI functions, SLP behavior,
and the `$f000`-`$ffff` internal program/vector window. The program image is an
integration input. Directed tests verify that instruction fetches in both
documented non-memory ranges enter the 13-cycle address TRAP while normal data
accesses do not. Expanded modes, standby entry, bi-phase/external-clock SCI,
physical timing, and actual mask-ROM contents remain outside this partial claim.
Its tested SCI profile likewise inhibits transfer of a misframed byte into RDR.
The Mode-7 timer regression verifies full-counter double-byte writes and the
documented Hitachi TOF boundary. It also verifies that V1 DDR clearing waits
for the next E edge.

The HD63701V0 claim covers its single-chip Mode 7 digital boundary: the
`$0000`-`$0014` register block, RAME-controlled 192-byte RAM at
`$0040`-`$00ff`, four GPIO ports with IS3/OS3, common Hitachi timer and
interrupts, the V0-specific framing-error transfer, SLP, and a separately
supplied `$f000`-`$ffff` EPROM image. The RTL and model execute from both RAM
boundaries and trap representative fetches in the unambiguous non-memory
range. Expanded modes, explicit asynchronous STBY entry, alternate SCI clock
formats, physical timing, and EPROM programming mode remain outside the claim.
The V0 regression verifies its distinct asynchronous DDR reset at the digital
boundary.

The HD63705V0 claim covers its distinct 14-bit CPU/device boundary, physical
`$00c0`-`$00ff` stack window, `$0040`-`$00ff` RAM, `$1000`-`$1fff` EPROM,
31 GPIO lines, all four primary-timer clock selections and eight prescalers,
INT/INT2 sensing and documented vector priority, synchronous SCI/Timer2,
WAIT/STOP/STBY digital state changes, and normalized EPROM verify/program
controls. Directed integration checks and 768 independent model/RTL E-cycle
comparisons cover these features. Oscillator/STOP recovery time, electrical
pin timing, EPROM voltage/pulse/retention physics, and silicon values on unused
memory reads remain outside the partial digital claim.

The manufacturer manual is internally inconsistent for Mode-7 instruction
fetches at `$0040`-`$007f`: the memory map and address-error prose identify the
range as internal RAM, but table 2-13-1 includes it in an address-error span.
The normalized implementation permits execution throughout physical RAM,
consistent with the memory map, and classifies silicon TRAP behavior for this
range as `UNDEFINED_BY_DOCUMENTATION`. No verified bus-trace claim depends on
that choice.

## Device differences relevant to implementation

- MC6800 has no internal RAM or MCU peripherals. Its normalized device wrapper
  implements VMA, BA, DBE, HALT, TSC, and bus ownership; phase-clock generation
  and electrical timing remain outside the current claim.
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
  extensions and TRAP behavior, and transfers a framing-error byte into RDR.
- HD63705V0 has a 14-bit PC, stack top `00FF`, 192 bytes RAM, 4 KiB EPROM,
  31 GPIO lines, two timer functions, synchronous SCI, and wait/stop/standby
  modes. Its vector region is `1FF4`-`1FFF`.

The normalized HD6301 CPU accepts a wrapper-generated instruction-address-error
request and implements the documented 13-cycle TRAP entry, complete state
stack, `$ffee:$ffef` vector, and retry PC. A full MCU claim still requires each
device wrapper to decode its own non-memory space and generate that request.
The HD6301V1 Mode-7 wrapper now performs this decode for `$0000`-`$007f` and
`$0100`-`$efff` and keeps its vector reads on the internal program interface.
The HD63701V0 wrapper uses `$0000`-`$003f` plus `$0100`-`$efff`, while the
conflicting `$0040`-`$007f` range is explicitly unverified as described above.
HD6303R Mode 2 spans external memory around the internal register/RAM windows,
so the manufacturer's address-error table defines no non-memory fetch region
for that implemented profile; opcode-error TRAP remains active.

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
