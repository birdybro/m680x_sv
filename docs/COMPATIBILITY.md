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
| Motorola MC6801 | full MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |
| Motorola MC6803 | full ROMless MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |
| normalized M6805 CPU | FPGA core only | PARTIAL | PARTIAL | PARTIAL | NOT_APPLICABLE |
| Motorola MC68705P5 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| Hitachi HD6301V1 | full MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |
| Hitachi HD6303R | full ROMless MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |
| Hitachi HD63701V0 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |
| Hitachi HD63705V0 | full EPROM MCU | PARTIAL | PARTIAL | PARTIAL | NOT_IMPLEMENTED |

The normalized M6805 core is not a silicon-device compatibility claim. A device
profile must provide effective PC width, stack window, vectors, interrupt set,
and low-power features. MC68705P5 and HD63705V0 are the concrete full-MCU v1
profiles for the Motorola and Hitachi 6805-derived lineages.

`PARTIAL` CPU status means every documented opcode encoding has architectural,
cycle-total, and ordered semantic-bus comparison against the independent model,
while the HD6301 profile also implements every documented opcode-error TRAP map
value. Detailed manufacturer bus-waveform coverage and remaining device-specific
interrupt sources are not yet complete. The MC68705P5 wrapper additionally has
tested RAM/register decode, GPIO, base timer behavior, and interrupt priority;
EPROM programming physics, every timer input/prescaler mode, and bootstrap-mode
integration remain incomplete.

The MC6800 device-wrapper claim covers normalized digital HALT/TSC/DBE/VMA/BA
and three-state ownership behavior, including interrupt retention while halted.
It does not claim pin-level phi1/phi2 generation, electrical timing, or complete
external waveforms for cycles whose detailed bus activity is not established by
the selected manufacturer documentation.

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
- HD63701V0 substitutes 4 KiB EPROM, has 192 bytes RAM, and retains HD6301 ISA
  extensions and TRAP behavior.
- HD63705V0 has a 14-bit PC, stack top `00FF`, 192 bytes RAM, 4 KiB EPROM,
  31 GPIO lines, two timer functions, synchronous SCI, and wait/stop/standby
  modes. Its vector region is `1FF4`-`1FFF`.

The normalized HD6301 CPU accepts a wrapper-generated instruction-address-error
request and implements the documented 13-cycle TRAP entry, complete state
stack, `$ffee:$ffef` vector, and retry PC. A full MCU claim still requires each
device wrapper to decode its own non-memory space and generate that request.

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
