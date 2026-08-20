# m680x_sv

`m680x_sv` is an MIT-licensed, independent clean-room SystemVerilog project for
the documented Motorola M6800, MC6801/MC6803, M6805/MC68705 and related Hitachi
HD6301/HD6303/HD6305 processor families. It provides synthesizable FPGA RTL,
machine-readable architecture facts, a structurally independent Python model,
and deterministic verification. The model includes separate CPU-instruction,
MC6801/MC6803 device-cycle, HD6301V1/HD63701V0 Mode-7, and HD63705V0
transaction paths.

The project is under active development. Every current implementation claim is
`PARTIAL`; no processor or MCU is represented as production-complete. The
evidence-backed target matrix is in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
and its authoritative structured form is [spec/devices.yml](spec/devices.yml).

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
- `mc6801_mcu`: normalized MC6801 Mode 0-7/1R/6R register, RAM, mask-ROM,
  GPIO/address, timer, SCI, interrupt-priority, and memory-selection integration;
  MC6803 uses the same block only in its documented Modes 2/3;
- `hd6301v1_mcu`: HD6301V1 single-chip Mode-7 integration with a separate
  4-KiB FPGA program-image port, executable RAM, four GPIO ports, IS3/OS3,
  timer/SCI, SLP, E-synchronous STBY retention, and device-generated
  address/opcode TRAP;
- `hd6303r_mcu`: HD6303R Mode-2 ROMless integration with the HD6301 ISA,
  opcode TRAP, SLP/STBY behavior, RAM, GPIO, timer, and SCI;
- `hd63701v0_mcu`: HD63701V0 Mode-7 integration with 192-byte RAM, four GPIO
  ports, timer/SCI, asynchronous STBY retention, address TRAP, and a separate
  4-KiB EPROM-image port;
- `hd63705v0_mcu`: 14-bit HD63705V0 integration with 192-byte RAM, 31 GPIO,
  an eight-bit timer, synchronous SCI/Timer2, INT/INT2 priority, WAIT/STOP/STBY,
  and normalized digital EPROM verify/program controls; and
- `mc68705p5_mcu`: an 11-bit device integration with RAM and register decode,
  GPIO, every programmable and MOR-fixed timer source/prescaler selection,
  interrupt priority/vectors, bootstrap-vector selection, and separate FPGA
  firmware/programming ports for EPROM/bootstrap/vector bytes.

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
across two simulators, twelve bounded formal profiles, and thirteen synthesis
tops.
Detailed counts,
coverage limits, formal properties, and representative synthesis statistics are
in [docs/VERIFICATION.md](docs/VERIFICATION.md).

For this project, architectural correctness, total-cycle correctness, ordered
semantic memory accesses, and exact external bus-waveform correctness are
separate claims. A passing cycle total is not described as a verified waveform.
Exact bus-trace status is claimed only where primary documentation supplies the
cycle boundaries being checked.

## Known limitations

Pin-level MC6800 phase generation/electrical timing, physical MC6801/MC6803
bus multiplexing and complete Port 3 handshake timing, Hitachi
MCU modes outside HD6301V1/HD63701V0 Mode 7 and HD6303R Mode 2, analog EPROM
programming physics, bi-phase SCI coding, and complete
manufacturer bus waveforms outside the specifically verified traces remain
incomplete. The copyrighted MC68705P5 bootstrap ROM bytes must be supplied by
the integrator; their externally described vector and programming controls are
implemented without redistributing the firmware image.
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
