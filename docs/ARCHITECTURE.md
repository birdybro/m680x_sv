# RTL architecture and public interfaces

## Design boundaries

The repository deliberately separates four kinds of artifact:

1. `spec/` records independently worded architecture and device facts with
   primary-document locators.
2. `tools/build_*` validates those facts and creates decode/test data. Generated
   files are deterministic and checked for staleness.
3. `model/` executes architectural behavior in Python using instruction-level
   control structures chosen for readability.
4. `rtl/` implements cycle-stepped hardware state machines. It does not reuse
   the model's execution organization.

The model and RTL may consume the same factual opcode record, but neither is
generated from the other. Differential verification therefore compares two
independent implementations of the recorded facts.

`rtl/common/m680x_alu_pkg.sv` contains combinational arithmetic functions with
explicit result and flag fields. `rtl/generated/m680x_decode_pkg.sv` classifies
an opcode into an operation, addressing mode, target, length, documented cycle
total, and bit number. Each CPU state machine owns instruction sequencing,
architectural registers, flags, stack, interrupts, and bus behavior.

## Normalized bus contract

Both reusable CPU cores expose the same basic FPGA integration protocol:

| Signal | Direction | Meaning |
|---|---|---|
| `clk_i` | input | Only sequential clock; rising-edge active |
| `reset_n_i` | input | Asynchronous active-low architectural reset |
| `clock_enable_i` | input | Advances one processor cycle when high |
| `bus_ready_i` | input | Completes an active transfer when high |
| `address_o[15:0]` | output | Current byte address |
| `data_i[7:0]` | input | Read data sampled on a completing edge |
| `data_o[7:0]` | output | Write data for the active transfer |
| `write_o` | output | High for writes, low for reads |
| `bus_valid_o` | output | Qualifies address, direction, and write data |
| `opcode_fetch_o` | output | Current valid read is an opcode fetch |
| `retire_o` | output | One-cycle pulse when an instruction completes |

When `clock_enable_i` is low, architectural state and bus outputs remain stable.
When `bus_valid_o` is high and `bus_ready_i` is low, state and bus outputs also
remain stable. No internally generated clock is used. An integration may keep
`bus_ready_i` high for single-cycle FPGA memory or lower it to insert waits.

Debug outputs are passive architectural observations; they do not alter
execution. `debug_instruction_cycles_o` is the documented total for the current
decoded instruction, not a counter of external wait states.

## M6800-lineage core

`rtl/m6800/m6800_core.sv` selects its factual profile with `ARCHITECTURE`:

| Value | Profile |
|---:|---|
| `0` | Motorola M6800 |
| `1` | Motorola MC6801/MC6803 CPU |
| `2` | Hitachi HD6301-family CPU |

The state machine contains A, B, X, SP, PC, and H/I/N/Z/V/C state. It implements
the original M6800 modes, MC6801 D-register/stack/index/multiply extensions, and
the HD6301 immediate-mask, exchange, and sleep instructions. NMI is edge-latched;
IRQ is level-sensitive and masked by I. `interrupt_vector_o` identifies the
selected reset/NMI/IRQ/TRAP class to a future device wrapper. The HD6301 profile
uses vector identifier `3` for TRAP.

`irq_vector_i` supplies the maskable vector address selected by a device
wrapper. A discrete MC6800 wrapper fixes it at `$fff8`; MC6801/MC6803 and
Hitachi integrations can select the documented external, timer, or serial
source before entry. NMI, SWI, reset, and HD6301 TRAP retain their architecture-
fixed vector addresses.

`instruction_address_error_i` is meaningful only for the HD6301 profile. A
device wrapper asserts it with an attempted opcode fetch from its documented
non-memory address space. Either that input or one of the 26 unassigned HD6301
opcode-map values invokes the unmaskable `$ffee:$ffef` TRAP vector. The core
retains the faulting opcode address as the stacked retry PC, so RTI refetches
the opcode. Its verified normalized-bus sequence is the faulting opcode fetch,
a discarded read at PC+1, two reads at `$ffff`, seven descending stack writes,
and the two vector reads: 13 cycles in total. Data accesses do not use the
instruction-address-error input.

The profile also controls the documented I-mask clearing boundary. MC6801
defers a pending maskable interrupt through the following instruction after
CLI or an I-clearing TAP. HD6301 uses its documented two-machine-cycle window.
Setting I remains immediate, and the base M6800 profile does not invent a delay
that its selected manual does not specify.

The normalized core emits documented architectural reads and writes and uses
padding states to preserve instruction totals. The directed MC6800 interrupt
test also checks the primary manual's reset, IRQ, NMI, SWI, WAI, and RTI stack
and vector sequences.

## MC6800 device bus wrapper

`rtl/m6800/mc6800_bus_wrapper.sv` surrounds the base profile with the
device-oriented digital controls specified independently in
`spec/interfaces/mc6800_bus.json`. It exposes separate values and output-enable
signals for the historical address, data, and R/W buses so an FPGA top can
instantiate real tri-state buffers only at the I/O boundary. Opcode-fetch,
retirement, interrupt acknowledgement, wait/halt status, and passive register
observations are passed through for FPGA integration and verification.

HALT completes the current instruction before asserting BA, lowering VMA, and
removing address, data, and R/W drive. A high pulse on HALT releases exactly one
instruction; keeping it high resumes normal execution. IRQ levels and NMI
falling edges observed while halted are retained through the first enabled
boundary, including an NMI coincident with HALT entry. A retained IRQ remains
pending if I is set and is cleared only after the matching acknowledge, so a
halted pulse survives ordinary execution until software unmasks it. WAI uses
the core's already-stacked wait state and presents the same documented
BA/bus-release condition without stacking again on interrupt recognition.

TSC stalls the normalized core, disables address and R/W drive, and forces VMA
and BA low. DBE gates only write-data drive. During reset the wrapper presents
the reset-vector-high address and read direction while VMA, BA, and data drive
remain inactive. The `clk_i` edge is still one complete normalized processor
cycle: the wrapper does not synthesize the historical non-overlapping phi1/phi2
waveforms or claim their electrical setup, hold, width, or voltage behavior.

## M6805-lineage core

`rtl/m6805/m6805_core.sv` uses `HITACHI_PROFILE` to select Motorola M6805 or
Hitachi HD6305 decoding. Parameters independently define PC masking, stack base,
stack wrap mask/top, SWI vector, and reset vector.

The hardware request input `irq_n_i` is separate from `interrupt_pin_n_i`.
This is required because BIL/BIH sample the physical interrupt pin while an MCU
timer or serial block may assert the combined request without changing that pin.
`irq_vector_i` lets a concrete device wrapper select the vector according to its
documented pending-source priority before interrupt entry begins.

The M6805 path contains A, eight-bit X, device-shaped SP/PC, and H/I/N/Z/C
state. It implements the distinct M6805 opcode map, bit operations, three indexed
forms, fixed-window stack arithmetic, five-byte interrupt frame, and the
documented Hitachi additions. It does not share the M6800 execution state machine.
The Hitachi profile defers maskable interrupt recognition until the instruction
following CLI retires, independently of the Motorola profile.

## MC6801 expanded-mode integration

`rtl/m6801/mc6801_mcu.sv` surrounds the M6801 CPU profile with the normalized
Mode 2/3 device state specified in
`spec/peripherals/mc6801.json`. Its external memory port deliberately remains a
normalized 16-bit FPGA bus; a later pin wrapper owns Port 3 multiplexing, AS,
E, and electrical timing.

The current integration implements the mode-dependent exclusion of Port 3/4
register addresses, RAME-controlled 128-byte RAM in Mode 2, the external RAM
window in Mode 3, physical-pin reads and DDR/output state for Ports 1/2, and
the documented P20/P21/P22:P24 timer/SCI overrides. Undefined output-latch
reset state is assigned deterministic zero only as an FPGA integration choice.

The 16-bit timer implements coherent counter reads, the FFF8 test preset,
one-cycle compare inhibition, synchronized input capture, output-level
transfer, all three ordered flag-clear protocols, and distinct timer vectors.
IRQ1 remains above capture, compare, overflow, and SCI in device priority.
Separate IRQ1 and IRQ2 request flip-flops retain sampled requests until I is
set. The core resamples the wrapper's priority vector after stacking, matching
the documented late encoder and its default-SCI result when software removes
the identity of an already latched IRQ2 request.

The SCI presently implements the two internally clocked NRZ modes, all four
internal divisors, nine-mark transmitter preamble, LSB-first ten-bit frames,
ordered TDRE/RDRF/ORFE clearing, center-sampled receive, overrun/framing status,
wake-mark counting, pin overrides, and shared interrupt. Bi-phase coding and
external 8x clock mode are not approximated and remain outside the claim.

## MC68705P5 integration

`rtl/m6805/mc68705p5_mcu.sv` configures the M6805 core for an 11-bit PC, stack
window `$0060`-`$007f`, and vector region `$07f8`-`$07ff`. Its independently
specified register map is [spec/peripherals/mc68705p5.json](../spec/peripherals/mc68705p5.json).

The wrapper currently implements:

- 112-byte RAM and the documented internal address decode;
- Ports A/B and the lower four bits of Port C, output latches, write-only DDRs,
  mixed input/output reads, and reset-to-input behavior;
- the eight-bit wrapping down-counter, seven-bit programmable prescaler,
  TOPT-dependent TCR reads/writes, timer mask/request, and input-mode selection;
- falling-edge-latched external INT above timer interrupt priority; and
- the PCR's digital control state plus an immutable `MASK_OPTION` parameter.

`program_address_o`, `program_read_o`, and `program_data_i` connect the user
EPROM, bootstrap ROM, and vector regions to an FPGA firmware memory. This keeps
copyrighted Motorola bootstrap bytes outside the repository and lets the system
choose its ROM initialization mechanism. Analog VPP/EPROM programming physics
are excluded; the digital PCR control outputs are exposed for integration.

## Generated synthesis views

Verilator consumes the package-based source; Icarus and Yosys use a checked
package-flattened view because their frontends do not accept all package
constructs used by the maintained source. Therefore
`tools/build_yosys_sources.py` creates checked, package-flattened views under
`rtl/generated/`. These files preserve the maintained core source and package
bodies; they are not alternative implementations. `make spec-check` fails when
they do not exactly match their inputs.
