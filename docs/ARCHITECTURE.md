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
For the base profile, MC6800 System Design Data Table 8 additionally drives
explicit bus-valid reads for every two-cycle inherent/accumulator form, all
8- and 16-bit immediate forms, direct byte/word reads, and extended byte/word
reads and stores plus JMP. The 115 opcode records carry the complete
cycle-address/direction/data-role/VMA sequence; MC6801 and HD6301 retain their
own manufacturer timing profiles. Direct and extended stores expose their
destination address with VMA low before the first write, exactly as Table 8
specifies.

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
remain inactive. The `clk_i` edge is one complete normalized processor cycle.

`rtl/m6800/mc6800_phased_bus_wrapper.sv` is the optional digital timing layer
described by `spec/interfaces/mc6800_phased_bus.json`. A four-times integration
clock advances explicit phi1-high, non-overlap, phi2-high, and non-overlap
subphases, and enables the normalized wrapper only after the final separation.
Address, direction, data, and architectural state consequently remain stable
through projected phi2. IRQ, NMI, and HALT are sampled at trailing phi1 and
held to that boundary. TSC asserted in the documented phi1-high/phi2-low state
holds the phase and releases bus ownership; DBE remains independently gateable
and may be tied to projected phi2 for the manufacturer's normal connection.

The historical MC6800 receives phi1 and phi2 as inputs. The wrapper's `phi1_o`
and `phi2_o` are therefore FPGA digital projections, not claims about original
output pins. It does not model nanosecond pulse widths, non-overlap separation,
setup/hold limits, voltage behavior, dynamic-storage limits, or clock pads.

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

The Motorola profile implements the eight-cycle reset response in the M6805
Family User's Manual table G2: six reads at the high reset-vector address, one
low-vector read, and a final read at address `$0000` whose input data is not
used. The same table drives explicit Motorola-only states for inherent and
relative repeated reads, bit-operation dummy/repeated reads and late branch
displacement, direct-address dummy and repeated reads, BSR/JSR target prefetch
and stack writes, short-indexed next-opcode/offset and dummy reads, documented
extended store/call and indexed-16 read/jump dummy cycles, and the dummy reads before
and after RTS/RTI pulls. These are real bus cycles rather than
unqualified timing padding. The Hitachi profile retains its separately selected
reset and instruction sequencing;
Motorola denotes the long-form dummy address as `$XFF` and defines `X` as
don't-care. The normalized interface drives zero in that upper field, while the
specification/model trace mask exposes that only address bits 7:0 are documented.
Motorola timing is not projected onto it without a Hitachi primary-source
basis.

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

The normalized 16-bit FPGA memory port remains available and is specified by
`spec/interfaces/mc6801_modes.json`. For device-oriented integration,
`rtl/m6801/mc6801_bus_wrapper.sv` advances four explicit subphases from a
`phase_clk_i` running at four times E: low-address/AS-open, AS-close and Port-3
turnaround, E-high data, and E-fall data. The normalized MCU advances once on
the last subphase, so no generated clock is used. Modes 0/1/2/3/6 multiplex
Port 3 and emit the high address on Port 4; Mode 5 emits active-low IOS for
`$0100-$01ff` and gates write-data drive with E; Modes 4/7 preserve the
GPIO/IS3 roles and hold a selected OS3 assertion from one positive E edge to
the next. The active-mode output makes the one-way Mode-4-to-5 pin
transition immediate at its completing E boundary.

In Motorola single-chip modes, an IS3 falling edge optionally captures Port 3
and sets the P3CSR flag. P3CSR-read followed by PORT3 DATA access performs the
ordered clear; P3DDR reads instead return the same live/captured Port-3 data
without affecting that protocol or OS3. Clearing latch-enable makes a stale
captured value transparent immediately. These Motorola DDR-read semantics are
kept separate from Hitachi's write-only `$ff` P3DDR behavior.

WAI is not generalized across the lineage. MC6801RM(AD2) section 5.4.2 states
that the expanded bus repeatedly reads the address seven below the pre-WAI SP,
which is the current post-stack SP. The core and pin wrapper therefore present
that address with read direction until an interrupt is accepted. The base
MC6800 profile retains its separate bus-release behavior. During MC6801 wake,
the SP read remains visible through the internal response and late-priority
cycles before the two vector reads. NMI/IRQ2 reaches the first handler opcode
in five E-cycles; synchronized IRQ1 takes six, matching figure 5-15.

`phase_reset_n_i` is an FPGA integration reset for the subphase counter and is
separate from historical `reset_n_i`; the latter resets the device while E
continues. This wrapper models documented digital ordering, not oscillator,
pad, pull strength, or nanosecond setup/hold/propagation limits. Undefined
output-latch reset state is assigned deterministic zero only as an FPGA
integration choice. `spec/interfaces/mc6801_phased_bus.json` records the exact
pin contract and primary-manual locators.

The 16-bit timer implements coherent counter reads, the FFF8 test preset,
one-cycle compare inhibition, synchronized input capture, output-level
transfer, all three ordered flag-clear protocols, and distinct timer vectors.
IRQ1 remains above capture, compare, overflow, and SCI in device priority.
Separate IRQ1 and IRQ2 request flip-flops retain sampled requests until I is
set. The core resamples the wrapper's priority vector after stacking, matching
the documented late encoder and its default-SCI result when software removes
the identity of an already latched IRQ2 request.

The Motorola SCI profile implements all three NRZ clock selections—internal,
internal with the bit clock exported on P22, and external 8x input on P22—and
the internally clocked bi-phase-M selection. The bi-phase transmitter always
changes level at a bit boundary, adds the documented half-bit transition for a
one, and emits the toggling idle pattern. Its independent receiver measures
transition intervals against the documented six-of-eight-subinterval boundary,
requires the documented idle qualification, and decodes wake marks. The exact
six-subinterval case is not assigned a silicon-equivalence claim because the
manual defines only intervals more or less than six.

The SCI also includes all four internal divisors, an eight-edge external
divider, nine-mark transmitter preamble, LSB-first ten-bit frames, ordered
TDRE/RDRF/ORFE clearing, center-sampled NRZ receive, overrun/framing status,
wake-mark counting, pin overrides, and shared interrupt. The Hitachi SCI tables
reserve `CC1:CC0=00`; an explicit device parameter disables Motorola bi-phase
in HD6301V1, HD6303R, and HD63701V0 wrappers.
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

## HD6301V1 Mode-0/1/2/4/5/6/7 integration

`rtl/hd6301/hd6301v1_mcu.sv` selects the Hitachi CPU profile and the guarded
paths in the common HD6801-compatible device block for every legal operating
mode. The sharing is based on Hitachi's compatibility statement and is limited
by explicit parameters. `HITACHI_NEW_MODES` selects Hitachi's non-multiplexed
Mode 1 and Mode-2-equivalent Mode 4 meanings. Distinct Mode-7 Port 3/4 and
strobe behavior remains separately guarded, while another explicit parameter
enables the manufacturer's per-mode instruction-address classifier.

Modes 0, 5, 6, and 7 select the 4-KiB `$f000`-`$ffff` internal mask-ROM image.
Mode 0 initially obtains its two reset-vector bytes from the external boundary
before later vector reads select the internal image. Modes 1, 2, and 4 disable
the ROM and expose all program space externally. Mode 5 selects only external
`$0100`-`$01ff`, Mode 6 provides its multiplexed partial-decode bus, and Modes
0/1/2/4 provide their documented full expanded spaces. Every legal mode keeps
RAME-controlled RAM at `$0080`-`$00ff`; mode-specific register exclusions and
Port 1/3/4 functions follow table 2-2-1.

Mode 7 decodes registers at `$0000`-`$001f`, RAME-controlled executable RAM at
`$0080`-`$00ff`, and read-only program space at `$f000`-`$ffff`. Instruction
fetches from `$0000`-`$007f` or `$0100`-`$efff` assert the HD6301 address-error
input and enter the unmaskable TRAP sequence. Ordinary data accesses to those
unusable regions neither trap nor escape onto an invented external bus.
Modes 0/1/4/6 trap opcode fetches in `$0000`-`$001f`, and Mode 5 traps
`$0000`-`$007f` plus `$0200`-`$efff`; Mode 2 uses the Mode-4 classifier because
the handbook explicitly calls those expanded multiplexed RAM modes equivalent
but omits a separate Mode-2 row from address-error table 2-13-1.

`program_address_o`, `program_read_o`, and `program_data_i` connect the
documented 4-KiB internal mask-ROM window to an integration-owned FPGA image,
including reset and interrupt vectors. The clean-room repository supplies no
copyrighted mask-ROM contents. Reads and writes to RAM and peripheral registers
do not assert `program_read_o`. The `external_*` signals expose the independent
normalized full-address transaction for expanded-mode FPGA integration.

`rtl/hd6301/hd6301v1_bus_wrapper.sv` is the separate device-pin projection. It
uses four FPGA-clock subphases per E cycle: address/AS-open, AS-close and
Port-3 turnaround, E-high data, and E-fall data/MCU advancement. Modes 0/2/4/6
multiplex low address and data on Port 3; Mode 1 drives dedicated low address
on Port 1; Mode 5 drives DDR-selected low-address bits on Port 4 and decodes
active-low IOS exactly for `$0100`-`$01ff`; Mode 7 retains GPIO and IS3/OS3.
The wrapper also implements address-bus release after the third completed
low-RES E cycle, the distinct WAI/SLP `$ffff` inactive-strobe state, and
E-synchronous standby bus release and E suppression. It creates no generated
clock. Manufacturer nanosecond limits, oscillator stabilization, pad behavior,
and electrical characteristics remain outside synthesizable RTL. The exact
contract and primary-manual locators are in
`../spec/interfaces/hd6301v1_phased_bus.json`.

In Mode 7, Ports 3 and 4 expose separate input, output-latch, and output-enable
vectors. The active-low `is3_n_i` input sets the P3CSR flag and optionally
captures Port 3. Clearing latch-enable makes a captured input transparent.
Reading P3CSR while set arms the documented clear; the following PORT3 DATA
read or write clears it unless a new edge occurs. P3DDR is write-only, reads
`$ff`, and has none of those side effects. `os3_n_o` pulses for the
P3CSR-selected PORT3 DATA read or write E-cycle. The normalized
Mode-7 contract is recorded in `../spec/interfaces/hd6301v1_mode7.json`; the
physical wrapper holds that strobe between consecutive positive E edges.

## HD6303R Mode-1/2/4 integration

`rtl/hd6301/hd6303r_mcu.sv` selects the HD6301 CPU profile around the common
HD6801-compatible device block in each documented legal mode. This sharing is
grounded in the Hitachi handbook's same-die statement for HD6301V1/HD6303R and
its explicit compatibility claim, rather than device-number similarity.
`HITACHI_NEW_MODES` prevents equal numeric mode values from importing Motorola
behavior: Hitachi Mode 1 disables Port-1 registers and internal ROM while
driving Port 1 as A0-A7, and Hitachi Mode 4 remains an expanded multiplexed RAM
mode equivalent to Mode 2 rather than mirroring RAM or switching to Mode 5.
The normalized wrapper exposes a full-address memory boundary. The separate
`rtl/hd6301/hd6303r_bus_wrapper.sv` advances four subphases per E cycle without
generating a clock. Mode 1 drives dedicated A0-A7 on Port 1, A8-A15 on Port 4,
and E-qualified write data on Port 3. Modes 2/4 drive low address on Port 3
while AS is high, release it between AS and E, and use it as the E-high data
bus. Every write, including an internal-RAM/register write, remains visible on
the physical data bus as the handbook specifies. Accepted STBY releases the
address/data buses and holds E low; SLP leaves E active and presents a
read-direction `$ffff` idle address, with the multiplexed data phase released.
Inherited WAI instead follows Hitachi Q&A III.4.5: `$ffff` remains on the
address pins, data is released, and the documented read/write strobes are
inactive. At the normalized interface this is an invalid cycle with address
`$ffff`; the physical wrapper keeps R/W high without asserting a data drive.
The exact normalized and pin boundaries are recorded in
`../spec/interfaces/hd6303r_modes.json` and
`../spec/interfaces/hd6303r_phased_bus.json`.

The pin wrapper counts completed E cycles while RES remains low. Address pins
remain enabled for the first two cycles and become high impedance at the third
E-fall boundary, matching section 2.8 and figure 2-8-1. The FPGA-only phase
reset selects the safe released condition without advancing that historical
counter. Oscillator stabilization, nanosecond setup/hold, and pad behavior
remain outside the active-cycle digital claim.

The wrapper keeps all vectors external, decodes the common internal register
window and RAME-controlled 128-byte RAM, and leaves all program space external.
Its CPU profile adds AIM/OIM/EIM/TIM, XGDX, SLP, Hitachi timing, and
opcode-error TRAP. Opcode fetches in `$0000`-`$001f` also invoke address TRAP
in every legal mode; ordinary accesses still use each address's documented
internal/external selection. Mode 2 follows Mode 4 for this classification by
the same documented equivalence noted above. During SLP the CPU state stops
while the timer and SCI remain
clocked. An enabled request vectors normally; a masked request releases sleep
at the following instruction without stacking, as the manufacturer specifies.
The wrapper also presents the shared E-synchronous STBY boundary, suppressing
the external transaction qualifier and GPIO drive during reset-state standby
while retaining supplied RAM and STBY_PWR state.

## HD63701V0 Mode-0/1/2/5/6/7 integration

`rtl/hd6301/hd63701v0_mcu.sv` selects the documented Hitachi CPU/timer lineage
while independently configuring every legal Mode 0, 1, 2, 5, 6, and 7, the
V0's `$0040`-`$00ff` 192-byte RAM, V0 SCI framing-error transfer, and 4-KiB
EPROM interface. Modes 3 and 4 are marked not used. The common shell reserves
one 256-byte FPGA RAM page; device decode exposes exactly 128 or 192 bytes as
appropriate, and address subtraction maps the selected physical window without
leaking one variant's address range into another wrapper.

Modes 0/5/6/7 select the program-image signals for normal read-only MCU accesses
to `$f000`-`$ffff`; Modes 1/2 expose that range externally. Mode 0 obtains the
initial reset-vector pair externally, then selects EPROM for later reads of the
same addresses. Mode 5 limits external memory to `$0100`-`$01ff`; Modes 0/1/2/6
provide their documented expanded selections. The `external_*` interface is a
normalized full-address transaction; the separate
`rtl/hd6301/hd63701v0_bus_wrapper.sv` projects historical digital pin phases.

The same MCU boundary also implements the separately selected digital
27256-compatible PROM mode. `prom_mode_i` stops CPU/peripheral execution and
repurposes Port 1 as A7:A0, P40 as A8, IRQ as A9, P45:P42 as A13:A10, P41 as
A14, P46 as active-low OE, P47 as active-low CE, and Port 3 as D7:D0. PROM
addresses `$0000`-`$0fff` map to the integration-owned `$f000`-`$ffff` image;
the unused `$1000`-`$7fff` extension reads as erased `$ff` and cannot issue a
program request. Read, output-disable, high-performance-program, verify, and
program-inhibit implement table 3-1 exactly at the digital boundary. Voltage
magnitude, programming-pulse timing, erasure, and retention physics are not
modeled. Three VPP/CE/OE combinations absent from table 3-1 are safe-inactive
and remain `UNDEFINED_BY_DOCUMENTATION` for silicon behavior.

Section 3.1 prints a `$0000`-`$00ff` PROM range in prose but calls the array
4 KiB in the same sentence, and figure 3-3 explicitly maps `$0000`-`$0fff`.
The implementation follows the mutually consistent 4-KiB/`$0fff` facts and
preserves the conflicting prose in the structured specification. The complete
PROM contract is `../spec/interfaces/hd63701v0_prom.json`.

The handbook's memory map and prose make `$0040`-`$007f` physical internal RAM,
while its Mode-5 and Mode-7 address-error rows contradictorily list the range
as a TRAP source. The wrapper permits execution from the whole RAM window.
Modes 0/1/2/6 trap `$0000`-`$001f`; Mode 5 traps `$0000`-`$003f` and
`$0200`-`$efff`; Mode 7 traps `$0000`-`$003f` and `$0100`-`$efff`. The RAM
choice is an explicit normalized integration policy, not a silicon-equivalence
claim for the disputed range; the structured specifications preserve the
discrepancy.
The V0-specific wrapper accepts `standby_n_i` asynchronously, immediately
removes GPIO/program/external-bus activity, retains supplied RAM/STBY_PWR, and
performs the mode-selected reset-vector restart when standby is released. The
complete normalized interface is recorded in
`../spec/interfaces/hd63701v0_modes.json`.

The device-pin wrapper advances address, AS-close/turnaround, E-rise data, and
E-fall data subphases on one FPGA integration clock. Mode 1 drives dedicated
Port-1/4 address pins; Modes 0/2/6 multiplex Port 3 under AS; Mode 5 decodes
IOS and drives DDR-selected low-address bits; Mode 7 retains GPIO and qualifies
OS3 between consecutive positive E edges. RES asynchronously releases all four
ports while E continues, then active roles recover only at a completing E
boundary. WAI and SLP present
the documented `$ffff` read-inactive expanded state, whereas STBY immediately
releases the ports and stops E. The exact contract and primary-manual locators
are in `../spec/interfaces/hd63701v0_phased_bus.json`.

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
integration-owned storage programmer. The complete printed-page-17 PCR table is
represented: absent VPP disconnects the PCR from the array, `PLE=0,PGE=1`
latches address/data, `PLE=0,PGE=0` requests programming, and `PLE=1` permits
reads. Software writes attempting either invalid `PGE=0,PLE=1` row are coerced
to `PGE=1`, as required by the register description.
During reset, the wrapper keeps the accepted bootstrap selection across all six
logical `$07fe` high-vector reads, maps the low-vector read to `$07f7`, and
releases the remap before later ordinary vector-region accesses. The eighth
reset cycle is an internal read at `$0000`; it does not select firmware storage
and its returned byte is architecturally unusable.
`model/mc68705p5_device.py` independently models these transactions, memory,
GPIO, timer, and interrupt state. The normal memory map partitions all 2,048
addresses into 16 I/O, 112 RAM, and 1,920 program/MOR locations without a hole
or overlap; the RTL separately sweeps every address and reads all RAM bytes on
both sides of reset. Separate directed checks exhaust every per-bit
latch/direction/pin combination on all 20 GPIO lines and exercise INT assertion,
vector acknowledgement, held-low suppression, and rearming. All eight
external/timer request and timer-mask states are crossed in both model and RTL.
The Motorola core takes exactly 11 cycles from the interrupt-recognition
boundary through two next-opcode-address reads, the five PCL/PCH/X/A/CCR stack
writes, an unused read at the decremented stack pointer, two vector reads, and a
trailing read at the address following the low vector byte. Eleven-bit return
addresses stack PCH with its five unused upper bits set, as required by the
manufacturer's cycle table.
The synchronous SWI path has its own table-G2 ending: after the same five-byte
frame, unused stack read, and two software-vector reads, cycle 11 reads the
first handler opcode at the resolved vector address. It does not reuse the
hardware IRQ's vector-low-plus-one trailing address.
DDR reads are
normalized to `$ff`, following figures 4 and 16; conflicting printed-page-13
prose makes their silicon-equivalent value `UNDEFINED_BY_DOCUMENTATION`. A
generated 768-cycle corpus compares every exposed state boundary. Timer-directed
checks cover all TCR values, counter values, prescalers, source modes, and the
complete timer-relevant MOR fixed-option matrix. The digital timer is complete
at normalized processor-cycle boundaries; manufacturer nanosecond pulse limits,
pad behavior, and oscillator physics remain outside that claim. The interface
contract is
[spec/interfaces/mc68705p5_mcu.json](../spec/interfaces/mc68705p5_mcu.json).

## HD63705V0 integration

`rtl/hd6305/hd63705v0_mcu.sv` configures the independent M6805-lineage core
for Hitachi decoding, a 14-bit PC/address boundary, stack window
`$00c0`-`$00ff`, and vectors at `$1ff4`-`$1fff`. The wrapper decodes registers
at `$0000`-`$0012`, 192 bytes of retained RAM at `$0040`-`$00ff`, and the
integration-owned 4-KiB EPROM image at `$1000`-`$1fff`. Sixteen-bit effective
addresses produced inside the generic core are deliberately truncated to the
fourteen physical address bits at this device boundary; the two unused upper
PCH bits are written as ones in subroutine and interrupt frames. Direct regressions
classify all 16,384 physical addresses and check every RAM byte after fill,
reset, and standby. Q&A QA635-338A reserves `$0013`-`$001f` for IC test and
prohibits software access without defining a stable result; deterministic
`$ff` reads and ignored writes in that and other unused regions are explicitly
an FPGA normalization.

Ports A-C have eight latch/direction bits and Port D has seven. D3/D4/D5 are
overridden by synchronous Tx/Rx/CK when SCR enables them, while the separately
named `int2_n_i` represents the interrupt function shared by the D6 package
pin. SCI selection also writes the corresponding stored DDRD direction and
later deselection retains it, as clarified by QA635-302A; D0-D2 and D6 remain
ordinary GPIO. Exhaustive checks cover all 31 common-port truth tables and all
SCR/initial-DDR combinations. The eight-bit down-counter implements internal,
gated-internal, stopped, and rising-edge external clock modes plus all eight
prescale ratios. Its
exhaustive regression covers every TCR encoding and counter/divider pair, every
source/divider combination, software request clearing/masking, and TDR access
during active countdown. INT is edge-latched or edge-and-level sensed; INT2 is
falling-edge latched and
software-cleared. The priority encoder selects INT, timer/INT2, the separate
timer-from-WAIT vector, and SCI/Timer2 without conflating their status flags.
Masked requests retain their source flags. INT edge mode clears its private
latch on the INT vector fetch while level mode continues to reflect a low pin;
INT2 remains in clear-only MR7. A reset/standby recovery arm captures the first
active INT/INT2 levels without manufacturing a falling edge, as required by
QA635-325A. The core completes a pending-request WAIT/STOP in four cycles but
transitions directly to interrupt stacking without exposing the low-power state,
which preserves the normal `$1ff8` timer vector before WAIT and reserves
`$1ff6` for a timer request arising after WAIT is established (QA635-329A).

The synchronous SCI changes LSB-first transmit data on CK falling edges and
samples receive data on rising edges. The eighth rising edge sets the SCI
request, after which the final Tx bit or received byte is held and further
external clocks are ignored until another SDR access. A 15-bit interval counter
plus clock phase generates all sixteen documented internal widths; Timer2 sets
its request on each internal negative edge even when serial shifting selects
external CK. Every selected-SCI SDR access clears the SCI request and initializes
that prescaler. A write starts Tx only when SCR7 is selected and an access arms
Rx only when SCR6 is selected; clearing SSR7 itself does not rearm either path.
An SDR access during an active transfer latches the Q&A-defined SCI-disable
state until reset and deterministically cancels the partial shift because the
manufacturer leaves the partial data result undefined. `model/hd63705v0_device.py`
uses a separate transaction/event structure, and a generated 768-cycle corpus
compares every visible state boundary. Exhaustive direct cases cover all byte,
status, rate/source, and access-protocol combinations.

WAIT stops only CPU execution and preserves timer/SCI operation. On STOP entry,
the wrapper follows figure 2-18 by resetting TDR, timer request/mask, and
SCI/Timer2 request/mask state, then permits only INT or enabled INT2 to wake the
core. Section 2.9 prose and table 2-5 instead say registers are retained except
TCR6/TCR7, so this explicit normalization is not a claim about the disputed
silicon register state.
`standby_n_i` provides the documented register-reset, RAM-retention, and GPIO
high-impedance digital boundary. EPROM mode holds the MCU reset and exposes the
twelve-bit programming address, input data, separate ordinary +5-V and VPP
qualifiers, CE/OE-qualified read/verify data, and the CE/OE/VPP-qualified
program request. The interface implements all five rows of handbook table 2-9.
Voltage thresholds, pulse width, charge retention, and oscillator recovery
remain analog exclusions.

Section 2.10(3) prints a `$0000`-`$00ff` programmer range while identifying the
same array as 4 KiB; table 2-7 exposes twelve address inputs and figure 2-24
maps MCU EPROM at `$1000`-`$1fff`. The implementation follows the mutually
consistent twelve-bit/4-KiB facts and records the conflicting prose in the
structured device specification.

## Generated synthesis views

Verilator consumes the package-based source; Icarus and Yosys use a checked
package-flattened view because their frontends do not accept all package
constructs used by the maintained source. Therefore
`tools/build_yosys_sources.py` creates checked, package-flattened views under
`rtl/generated/`. These files preserve the maintained core source and package
bodies; they are not alternative implementations. `make spec-check` fails when
they do not exactly match their inputs.
