# m680x_sv

`m680x_sv` is an MIT-licensed, independent clean-room SystemVerilog project for
the documented Motorola M6800, MC6801/MC6803, M6805/MC68705 and related Hitachi
HD6301/HD6303/HD6305 processor families. It provides synthesizable FPGA RTL,
machine-readable architecture facts, a structurally independent Python model,
and deterministic verification. The model includes separate CPU-instruction,
MC6801/MC6803 device-cycle, all-legal-mode HD6301V1/HD63701V0, and
HD63705V0 transaction paths.

The project is under active development. Every processor and whole-MCU support
row remains `PARTIAL`; narrowly scoped dimensions become `COMPLETE` only after
exhaustive evidence. MC68705P5 and HD63705V0 internal-memory decode and
normalized digital timer and interrupt-controller functions, plus HD63705V0
GPIO and synchronous SCI/Timer2, are the first such closed dimensions. The
evidence-backed target matrix is in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) and its authoritative structured
form is [spec/devices.yml](spec/devices.yml).

## Clean-room engineering

Implementation facts come only from original manufacturer hardware documents.
Existing HDL cores and emulator implementations are prohibited as source,
organization, test, trace, interface, behavioral oracle, or timing oracle. The
full rules are in [docs/CLEAN_ROOM.md](docs/CLEAN_ROOM.md) and [AGENTS.md](AGENTS.md).

Downloaded manuals are never committed. [docs/references.yml](docs/references.yml)
records their provenance, identity, subjects, filenames, and SHA-256 digests.
Run `make refs` to populate the ignored `.reference/` cache; CI validates the
manifest without downloading or redistributing copyrighted documents.

## Implemented architecture

Two independent CPU state machines currently cover five instruction profiles,
with device wrappers kept at separate integration boundaries:

- `m6800_core`: M6800, MC6801/MC6803, and HD6301-family instruction profiles;
- `m6805_core`: Motorola M6805 and Hitachi HD6305 instruction profiles;
- `mc6800_bus_wrapper`: MC6800 HALT, TSC, DBE, VMA, BA, and three-state bus
  ownership around the normalized M6800 core;
- `mc6800_phased_bus_wrapper`: four non-overlapping FPGA subphases projecting
  digital phi1/phi2 timing, trailing-phi1 control sampling, and post-phi2 CPU
  advancement around the normalized MC6800 device wrapper;
- `mc6801_mcu`: normalized MC6801 Mode 0-7/1R/6R register, RAM, mask-ROM,
  GPIO/address, timer, SCI, interrupt-priority, and memory-selection integration;
  MC6803 uses the same block only in its documented Modes 2/3;
- `mc6801_bus_wrapper`: device-oriented four-subphase E/AS/R/W/IOS and
  Port-3 address/data waveform for every Motorola operating mode, including
  full-E-cycle OS3, the dynamic Mode-4-to-5 pin-role transition, and documented
  post-stack-SP read cycles while WAI is active;
- `hd6301v1_mcu`: every legal HD6301V1 Mode 0/1/2/4/5/6/7 integration with a
  separate 4-KiB FPGA mask-ROM image port, normalized expanded-memory bus,
  executable RAM, mode-dependent ports/strobes, timer/SCI, SLP,
  E-synchronous STBY retention, and per-mode address/opcode TRAP;
- `hd6301v1_bus_wrapper`: all-seven-mode four-subphase Port-1/3/4,
  AS/IOS, R/W/OS3, third-reset-cycle release, WAI/SLP, and standby digital
  pin behavior around the HD6301V1 integration;
- `hd6303r_mcu`: HD6303R legal Mode-1/2/4 ROMless integration with the HD6301
  ISA, opcode TRAP, SLP/STBY behavior, RAM, mode-dependent Port 1, timer, and
  SCI;
- `hd6303r_bus_wrapper`: active-cycle Mode-1 dedicated and Mode-2/4
  multiplexed address/data waveforms, including distinct WAI/SLP `$ffff` idle
  states and standby E suppression;
- `hd63701v0_mcu`: every legal HD63701V0 Mode 0/1/2/5/6/7 integration with
  192-byte RAM, mode-selected ports and normalized external bus, timer/SCI,
  asynchronous STBY retention, per-mode address TRAP, and a separate 4-KiB
  EPROM-image port, plus the documented digital 27256-compatible PROM-mode
  address/data/control boundary;
- `hd63701v0_bus_wrapper`: all-six-mode four-subphase Port-1/2/3/4,
  AS/IOS, R/W/OS3, asynchronous reset entry, E-boundary reset recovery,
  WAI/SLP, and standby digital pin behavior;
- `hd63705v0_mcu`: 14-bit HD63705V0 integration with 192-byte RAM, 31 GPIO,
  an eight-bit timer, synchronous SCI/Timer2, INT/INT2 priority, WAIT/STOP/STBY,
  and all five normalized digital EPROM read/programming states; and
- `mc68705p5_mcu`: an 11-bit device integration with RAM and register decode,
  GPIO, every programmable and MOR-fixed timer source/prescaler selection,
  interrupt priority/vectors, bootstrap-vector selection, and separate FPGA
  firmware/programming ports for EPROM/bootstrap/vector bytes.

The MC68705P5 interrupt boundary crosses all external/timer request and timer-
mask combinations and verifies external priority, complete stack/vector bus
operations, and the manufacturer's exact 11-cycle hardware-interrupt response.
The trace follows the manufacturer's cycle table: two reads at the next opcode
address, five stack writes, one unused stack read, two vector reads, and a final
read at the address following the low vector byte.

All 256 opcode values are explicitly classified for each profile. The current
five maps contain 1,064 documented instruction encodings, 26 HD6301 map values
with documented TRAP behavior, and 190 explicitly reserved or
manufacturer-undefined values. The generated decoder is derived from those
factual maps, while the Python execution model remains independently organized.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for interfaces and design
boundaries.

The normalized CPU bus uses a single FPGA clock and clock enable. A cycle
advances on a rising clock edge when `clock_enable_i` is asserted and either no
bus transfer is active or `bus_ready_i` is asserted. `bus_valid_o` qualifies
`address_o`, `write_o`, and write data; read data is sampled from `data_i` on
the completing edge. Active-low interrupt pins and asynchronous active-low reset
match their documented logical polarity without generating internal clocks.
The low-power steady bus is profile-specific: MC6800 releases its normalized
bus in WAI, MC6801 repeatedly reads the current post-stack SP, and HD6301
presents `$ffff` with an invalid normalized transaction to represent inactive
read/write strobes. MC6801 wake-up preserves the SP read through its internal
response cycles and reaches the first handler opcode in the documented five
E-cycles for NMI/IRQ2 or six for IRQ1.

## Build and verification

The local toolchain is Python 3, GNU Make, Verilator, Icarus Verilog, and Yosys
0.68. The exact Yosys distribution used in CI is pinned in
`requirements-toolchain.txt`. A fresh clone can install it into the ignored
tool directory without modifying the host Python installation:

```text
python3 -m venv .tools/yowasp
.tools/yowasp/bin/pip install --requirement requirements-toolchain.txt
PATH="$PWD/.tools/yowasp/bin:$PATH" make ci
```

Native Yosys 0.68 may instead be selected with `make YOSYS=yosys`. `make help`
lists every target.

```text
make quick             fast lint, model, and directed RTL gate
make test-alu          independent Python plus RTL exhaustive ALU tests
make test-cycle        all documented opcode cycle/access comparisons
make test-interrupts   directed reset and interrupt regressions
make test-peripherals  implemented MCU peripheral profiles
make test-random       deterministic differential programs
make test-iverilog     secondary-simulator compatibility
make formal            bounded safety and stall proofs
make synth             all generic synthesis smoke tests
make ci                authoritative complete committed-source gate
```

The current regressions include 1,839,105 Python ALU cases, 1,969,155 RTL ALU
cases, every documented opcode encoding, 5,120 deterministic CPU model/RTL
retirement comparisons, 1,536 MC6801/MC6803, 768 MC68705P5, and 768 HD63705V0
peripheral cycle comparisons, and directed reset/stack/interrupt/device tests
across two simulators, twenty-one bounded formal profiles, and thirty
synthesis tops. Detailed counts,
coverage limits, formal properties, and representative synthesis statistics are
in [docs/VERIFICATION.md](docs/VERIFICATION.md).

For this project, architectural correctness, total-cycle correctness, ordered
semantic memory accesses, and exact external bus-waveform correctness are
separate claims. A passing cycle total is not described as a verified waveform.
Exact bus-trace status is claimed only where primary documentation supplies the
cycle boundaries being checked.

## Known limitations

MC6800 nanosecond phi1/phi2 and electrical clock-pad timing, MC6801/MC6803
nanosecond setup/hold and oscillator/pad behavior, HD6301V1/HD6303R
nanosecond/oscillator/pad timing, HD63701V0 nanosecond Port 3 handshake timing,
EPROM programming-voltage/pulse/erasure/retention physics, SCI clock-skew/electrical
tolerance, and complete manufacturer bus waveforms outside the specifically
verified traces remain
incomplete. The copyrighted MC68705P5 bootstrap ROM bytes must be supplied by
the integrator; their externally described vector and programming controls are
implemented without redistributing the firmware image. Its normalized digital
boundary covers all eight documented PCR/VPP table rows, prevents software from
entering either invalid PGE/PLE encoding, and exposes latch/program
requests while leaving voltage and pulse physics to the integrator. Its complete
11-bit memory partition and all 112 RAM bytes are exhaustively checked, including
RAM retention across reset. All 20 GPIO pin truth tables and INT edge/rearm
behavior are also exhaustively directed-tested. The wrapper's deterministic
`$ff` DDR-read value follows two manufacturer figures, but conflicting prose in
the same manual leaves silicon-equivalent DDR read data undefined; GPIO status
therefore remains `PARTIAL`.
The normalized digital timer dimension is `COMPLETE`: every TCR encoding,
counter value, prescaler, source mode, and timer-relevant fixed MOR
configuration is directly checked. This claim excludes the separately marked
oscillator, pad, and analog minimum-pulse-width behavior.
The HD63705V0 digital programming boundary does implement all five documented
read/output-disable/program/verify/disable states; separate +5-V-read and VPP
qualifiers avoid conflating voltage states while leaving their analog
thresholds to the integrator.
Its internal-memory dimension is `COMPLETE`: all 16,384 physical addresses and
all 192 RAM bytes are directly checked, including RAM retention across reset
and standby. The manufacturer-prohibited `$0013`-`$001f` IC-test range and all
other unused ranges receive deterministic `$ff` reads and ignored writes only
as an FPGA normalization, not as a silicon-equivalence claim. Figure 2-18's
STOP register values conflict with section 2.9 prose and table 2-5 retention
language; the implementation follows the figure, records the discrepancy, and
keeps low-power status `PARTIAL`.
The HD63705V0 normalized primary-timer dimension is also `COMPLETE`: all 256
TCR encodings, 2,048 counter/divider pairs, all 32 source/divider combinations,
request/mask behavior, active TDR reads/writes, reset, rising external edges,
and the WAIT-specific vector are directly checked. This does not extend to
oscillator, TIMER-pad, or analog minimum-pulse-width behavior.
Its normalized GPIO dimension is `COMPLETE`: every latch/direction/pin
combination for all 31 GPIO bits, Port D's fixed readback bit, all 512
SCR/initial-DDR combinations, SCI direction overrides and retained DDR values,
reset, WAIT/STOP retention, and standby high impedance are directly checked.
This regression exposed and fixed a prior bug where SCI changed the output
enable but did not update the stored DDRD bits required by Hitachi QA635-302A.
Pad drive and electrical timing remain outside the digital claim.
Its normalized synchronous-SCI/Timer2 dimension is `COMPLETE`: direct RTL and
independent model tests exhaust all 256 transmit bytes and all 256 receive
bytes, all 256 SSR writes, all 16 transfer-clock widths under both serial-clock
source selections, exact eighth-rising-edge completion, falling-edge transmit,
post-completion holdoff, common-clock simultaneous transfer, SDR prescaler
initialization, and the documented access protocol. The regression exposed and
fixed receive rearming after completion, missing external-mode prescaler reset,
and failure to latch the Q&A-defined mid-transfer access disable until reset.
QA635-308A does not guarantee partially shifted data after that prohibited
access; cancelling the partial transfer is therefore a deterministic FPGA
normalization, not a silicon-data claim. Oscillator, CK-pad, and electrical
timing remain excluded.
Its normalized interrupt-controller dimension is `COMPLETE`: the model crosses
all 1,024 request/mask/WAIT priority combinations and both initial MR7 states
with all 256 MR writes, while direct RTL performs 512 MR checks, 96 ordered
priority stages, and edge/level/standby-return protocols. Real-core regressions
verify simultaneous and repeated service, masked retention, CLI delay, normal
versus timer-from-WAIT vectors, rejected WAIT/STOP entry with a pending source,
masked-source low-power entry, complete stack frames, and RTI. This audit found
and fixed both a one-cycle false low-power entry (which could select the wrong
timer vector) and false INT/INT2 falling edges when a pin was already low at
standby recovery. Oscillator stabilization remains outside the digital claim,
and the independently recorded STOP-register documentation contradiction keeps
the broader low-power dimension `PARTIAL`.
Manufacturer-undefined reset values, reserved opcodes, analog oscillators,
EPROM voltage physics, pad strength, and metastability are not assigned invented
silicon behavior. These limitations are tracked as `PARTIAL`,
`NOT_IMPLEMENTED`, or `UNDEFINED_BY_DOCUMENTATION`, never hidden behind a
support claim.

## License and contribution

Original code and documentation are licensed under the [MIT License](LICENSE).
Contributions must preserve reference provenance, architecture boundaries, the
independence of model and RTL, strict warnings, and permanent regressions for
every discovered bug. Tests and expected traces must not be weakened to obtain
a green build.
