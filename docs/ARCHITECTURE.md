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

## MC6801 operating modes and MC6803 expanded-mode integration

`rtl/m6801/mc6801_mcu.sv` surrounds the M6801 CPU profile with the normalized
Mode 0-7 device state specified in `spec/peripherals/mc6801.json`; mask-ROM
parameters also represent the documented 1R/6R relocation options at `$c800`,
`$d800`, or `$e800`. The MC6803 profile in `spec/peripherals/mc6803.json`
inherits the common behavior but restricts public configuration to Modes 2/3,
exactly as section 2.4.2 of the manufacturer manual defines it.

The mode decoder owns register exclusions, RAME-controlled RAM, normal and
relocated ROM windows, vector source selection, and external-bus qualification.
Mode 0 uses the external bus for its two reset-vector reads and then selects
internal ROM at the same addresses. Mode 4 mirrors each physical RAM byte
through every `$xx80-$xxff` range and implements the one-way PCO transition to
Mode 5 until reset. Mode 5 selects external storage only at `$0100-$01ff`;
Modes 4/7 never assert the external select. Port 4 emits the documented low or
high partial address in Modes 5/6, while Modes 4/7 expose Port 3/4 GPIO.

The external memory port deliberately remains a normalized 16-bit FPGA bus.
`spec/interfaces/mc6801_modes.json` defines that boundary; a future physical
pin wrapper owns the half-cycle Port 3 address/data multiplexing, AS, E,
setup/hold, and electrical timing. Undefined output-latch reset state is
assigned deterministic zero only as an FPGA integration choice.

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
The common block has an explicit framing-error transfer parameter: MC6801 and
HD63701V0 transfer a misframed receive byte into RDR while leaving RDRF clear,
whereas HD6301V1 and HD6303R inhibit that transfer. Device wrappers select the
manufacturer-documented rule rather than deriving it from the CPU ISA profile.

Timer counter writes and overflow boundaries are likewise explicit device
parameters. MC6801 keeps FRC low-byte writes ineffective and raises TOF when
the counter reaches `$ffff`. HD6301V1, HD6303R, and HD63701V0 save the high
data byte while presetting `$fff8`, accept the following low-byte write as a
full 16-bit FRC replacement, and raise TOF on the subsequent
`$ffff`-to-`$0000` rollover.

Port-DDR reset timing is another explicit variant parameter. HD6301V1 and
HD6303R clear DDR state on an E edge; HD63701V0 clears it asynchronously with
E so asserting RES immediately returns every port driver to high impedance.
The generated sequential blocks keep this timing distinction synthesizable
without creating a gated clock.

The Hitachi wrappers similarly preserve the documented STBY distinction.
HD6301V1 and HD6303R sample `standby_n_i` at an enabled E boundary;
HD63701V0 applies it asynchronously. Accepted standby resets the CPU and
active peripheral domain, suppresses program/external transactions, and makes
GPIO high impedance. The inferred RAM array and STBY_PWR retained-domain bit
survive while `standby_power_ok_i` remains asserted. Release restarts through
the reset vector; oscillator restart delay and voltage thresholds are outside
the normalized digital boundary.

## HD6301V1 single-chip Mode-7 integration

`rtl/hd6301/hd6301v1_mcu.sv` selects the Hitachi CPU profile and the guarded
Mode-7 path in the common HD6801-compatible device block. The sharing is based
on Hitachi's compatibility statement and is limited by explicit parameters;
the distinct memory map, Port 3/4 registers, strobe state, and address-error
decode are enabled only for this wrapper.

Mode 7 decodes registers at `$0000`-`$001f`, RAME-controlled executable RAM at
`$0080`-`$00ff`, and read-only program space at `$f000`-`$ffff`. Instruction
fetches from `$0000`-`$007f` or `$0100`-`$efff` assert the HD6301 address-error
input and enter the unmaskable TRAP sequence. Ordinary data accesses to those
unusable regions neither trap nor escape onto an invented external bus.

`program_address_o`, `program_read_o`, and `program_data_i` connect the
documented 4-KiB internal mask-ROM window to an integration-owned FPGA image,
including reset and interrupt vectors. The clean-room repository supplies no
copyrighted mask-ROM contents. Reads and writes to RAM and peripheral registers
do not assert `program_read_o`.

Ports 3 and 4 expose separate input, output-latch, and output-enable vectors.
The active-low `is3_n_i` input sets the P3CSR flag and optionally captures Port
3. Reading P3CSR while set arms the documented clear; the following PORT3 read
or write clears it unless a new edge occurs. `os3_n_o` pulses during the
P3CSR-selected PORT3 read or write E-cycle. The exact interface contract and
electrical exclusions are recorded in
`../spec/interfaces/hd6301v1_mode7.json`.

## HD6303R Mode-2 integration

`rtl/hd6301/hd6303r_mcu.sv` selects the HD6301 CPU profile around the common
HD6801-compatible device block in expanded multiplexed Mode 2. This sharing is
grounded in the Hitachi handbook's same-die statement for HD6301V1/HD6303R and
its explicit compatibility claim, rather than device-number similarity. The
wrapper exposes the normalized external-memory boundary; the physical Port 3
address/data and AS waveform remains a separate pin-interface task.

The wrapper keeps all vectors external, decodes the common internal register
window and RAME-controlled 128-byte RAM, and leaves Mode-2 program space
external. Its CPU profile adds AIM/OIM/EIM/TIM, XGDX, SLP, Hitachi timing, and
opcode-error TRAP. During SLP the CPU state stops while the timer and SCI remain
clocked. An enabled request vectors normally; a masked request releases sleep
at the following instruction without stacking, as the manufacturer specifies.
The wrapper also presents the shared E-synchronous STBY boundary, suppressing
the external transaction qualifier and GPIO drive during reset-state standby
while retaining supplied RAM and STBY_PWR state.

## HD63701V0 single-chip Mode-7 integration

`rtl/hd6301/hd63701v0_mcu.sv` selects the documented Hitachi CPU/timer lineage
while independently configuring the V0's `$0040`-`$00ff` 192-byte RAM, V0 SCI
framing-error transfer, and 4-KiB EPROM interface. The common shell reserves
one 256-byte FPGA RAM page; device decode exposes exactly 128 or 192 bytes as
appropriate, and address subtraction maps the selected physical window without
leaking one variant's address range into another wrapper.

The program-image signals represent normal read-only MCU accesses to
`$f000`-`$ffff`. They do not model the separate 27256-style analog programming
mode, VPP, programming margins, or retention. Reset and interrupt vectors are
included in this image as normal internal EPROM reads.

The handbook's memory map and prose make `$0040`-`$007f` physical internal RAM,
while its Mode-7 address-error table contradictorily lists the range as a TRAP
source. The wrapper permits execution from the whole RAM window and traps
`$0000`-`$003f` and `$0100`-`$efff`. This is an explicit normalized integration
policy, not a silicon-equivalence claim for the disputed range; the structured
device and peripheral specifications preserve the discrepancy.
The V0-specific wrapper accepts `standby_n_i` asynchronously, immediately
removes GPIO/program activity, retains supplied RAM/STBY_PWR, and performs the
documented reset-vector restart when standby is released.

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
- the PCR's digital control state, immutable `MASK_OPTION` parameter,
  high-voltage bootstrap selection, and latched EPROM program address/data.

`program_address_o`, `program_read_o`, and `program_data_i` connect the user
EPROM, bootstrap ROM, and vector regions to an FPGA firmware memory. This keeps
copyrighted Motorola bootstrap bytes outside the repository and lets the system
choose its ROM initialization mechanism. Analog VPP/EPROM programming physics
are excluded. `bootstrap_voltage_i` selects the documented `$07f6:$07f7`
bootstrap vector unless MOR secure mode is set. The PCR/VPP-qualified latch and
program outputs carry a stable user-EPROM/MOR/vector address and byte to an
integration-owned storage programmer. `model/mc68705p5_device.py` independently
models these transactions, memory, GPIO, timer, and interrupt state; a generated
768-cycle corpus compares every exposed state boundary. The interface contract
is [spec/interfaces/mc68705p5_mcu.json](../spec/interfaces/mc68705p5_mcu.json).

## HD63705V0 integration

`rtl/hd6305/hd63705v0_mcu.sv` configures the independent M6805-lineage core
for Hitachi decoding, a 14-bit PC/address boundary, stack window
`$00c0`-`$00ff`, and vectors at `$1ff4`-`$1fff`. The wrapper decodes registers
at `$0000`-`$0012`, 192 bytes of retained RAM at `$0040`-`$00ff`, and the
integration-owned 4-KiB EPROM image at `$1000`-`$1fff`. Sixteen-bit effective
addresses produced inside the generic core are deliberately truncated to the
fourteen physical address bits at this device boundary.

Ports A-C have eight latch/direction bits and Port D has seven. D3/D4/D5 are
overridden by synchronous Tx/Rx/CK when SCR enables them, while the separately
named `int2_n_i` represents the interrupt function shared by the D6 package
pin. The eight-bit down-counter implements internal, gated-internal, stopped,
and rising-edge external clock modes plus all eight prescale ratios. INT is
edge-latched or edge-and-level sensed; INT2 is falling-edge latched and
software-cleared. The priority encoder selects INT, timer/INT2, the separate
timer-from-WAIT vector, and SCI/Timer2 without conflating their status flags.

The synchronous SCI changes LSB-first transmit data on CK falling edges and
samples receive data on rising edges. A 15-bit interval counter plus clock
phase generates all sixteen documented internal widths; Timer2 sets its request
on each internal negative edge even when serial shifting selects external CK.
SDR access implements request clearing, transmitter load, and initial receive
arming. `model/hd63705v0_device.py` uses a separate transaction/event structure,
and a generated 768-cycle corpus compares every visible state boundary.

WAIT stops only CPU execution and preserves timer/SCI operation. On STOP entry,
the wrapper resets only the documented TDR, timer request/mask, and SCI/Timer2
request/mask state, then permits only INT or enabled INT2 to wake the core.
`standby_n_i` provides the documented register-reset, RAM-retention, and GPIO
high-impedance digital boundary. EPROM mode holds the MCU reset and exposes the
twelve-bit programming address, verify data/output enable, input data, and the
CE/OE/VPP-qualified program request. Voltage, pulse width, charge retention,
and oscillator recovery remain analog exclusions.

## Generated synthesis views

Verilator consumes the package-based source; Icarus and Yosys use a checked
package-flattened view because their frontends do not accept all package
constructs used by the maintained source. Therefore
`tools/build_yosys_sources.py` creates checked, package-flattened views under
`rtl/generated/`. These files preserve the maintained core source and package
bodies; they are not alternative implementations. `make spec-check` fails when
they do not exactly match their inputs.
