# m680x_sv

Clean-room, MIT-licensed SystemVerilog implementations of documented Motorola
M6800/M6801/M6803/M6805 devices and related Hitachi HD6301/HD6303/HD6305
families.

The repository contains synthesizable FPGA RTL, machine-readable architecture
specifications, an independent Python reference model, and deterministic
simulation, formal, and synthesis verification.

## Support

| Target | Scope | Status |
|---|---|---:|
| Motorola MC6800 | Physical CPU device | COMPLETE |
| Motorola MC6801 | Full MCU | COMPLETE |
| Motorola MC6803 | Full ROMless MCU | COMPLETE |
| Motorola M6805 | Normalized FPGA CPU core | COMPLETE |
| Motorola MC68705P5 | Full EPROM MCU | COMPLETE |
| Hitachi HD6301V1 | Full MCU | COMPLETE |
| Hitachi HD6303R | Full ROMless MCU | COMPLETE |
| Hitachi HD63701V0 | Full EPROM MCU | COMPLETE |
| Hitachi HD63705V0 | Full EPROM MCU | COMPLETE |

`COMPLETE` applies to the documented synthesizable digital behavior for that
scope. Architectural results, cycle counts, and exact external bus traces are
tracked separately. Where manufacturer documents omit or contradict a bus
waveform, the affected dimension is explicitly
`UNDEFINED_BY_DOCUMENTATION`—it is not guessed.

See [Compatibility](docs/COMPATIBILITY.md) for the detailed matrix and
[Device specifications](spec/devices.yml) for its machine-readable form.

## Quick start

Required tools are Python 3, GNU Make, Verilator, Icarus Verilog, and Yosys
0.68. The CI Yosys distribution is pinned in `requirements-toolchain.txt`.

```sh
python3 -m venv .tools/yowasp
.tools/yowasp/bin/pip install --requirement requirements-toolchain.txt
PATH="$PWD/.tools/yowasp/bin:$PATH" make quick
```

Useful targets:

```text
make help              list all commands
make quick             lint, model tests, and directed CPU smoke tests
make test              Python model and specification tests
make test-alu          exhaustive Python and RTL ALU verification
make test-cycle        documented instruction-cycle and bus-access tests
make test-interrupts   reset, interrupt, stack, and low-power tests
make test-peripherals  MCU memory, GPIO, timer, serial, and mode tests
make test-random       deterministic model/RTL differential programs
make formal            bounded safety proofs
make synth             synthesis smoke tests for every public top
make ci                authoritative complete gate
```

Native Yosys may be selected with `make YOSYS=yosys`.

## RTL organization

The normalized CPU cores are:

- `m6800_core` for M6800, MC6801/MC6803, and HD6301 instruction profiles;
- `m6805_core` for Motorola M6805 and Hitachi HD6305 profiles.

Device integrations and historically meaningful bus wrappers remain separate
from the reusable execution cores. They cover MC6800 bus control, MC6801/6803,
MC68705P5, HD6301V1, HD6303R, HD63701V0, and HD63705V0.

The normalized bus uses one FPGA clock and a clock enable. `bus_valid_o`
qualifies the address, direction, and write data; `bus_ready_i` can extend a
transfer without advancing architectural state. Active-low reset and interrupt
inputs retain their documented logical polarity.

Port lists, timing contracts, memory boundaries, and wrapper behavior are in
[Architecture](docs/ARCHITECTURE.md).

## Verification at a glance

| Evidence | Count |
|---|---:|
| Explicit opcode classifications | 1,280 |
| Documented encodings executed in model and RTL | 1,064 |
| Python exhaustive ALU cases | 1,839,105 |
| SystemVerilog exhaustive ALU cases | 1,970,177 |
| Exact documented opcode bus traces | 387 |
| Deterministic random programs | 80 |
| Per-retirement random comparisons | 5,120 |
| Peripheral model/RTL cycle comparisons | 3,072 |
| Bounded formal profiles | 21 |
| Synthesis tops | 30 |

Verilator is the primary strict-warning simulator; Icarus provides independent
secondary-simulator coverage. `make ci` validates specifications and generated
sources, runs all model and RTL regressions, then performs formal proofs and
synthesis checks.

Detailed counts, coverage boundaries, properties, and representative resource
statistics are in [Verification](docs/VERIFICATION.md).

## Clean-room policy and references

Implementation facts come only from original manufacturer hardware
documentation. Existing HDL cores and emulator implementations are prohibited
as source, organization, interface, behavioral oracle, or timing oracle.

[Clean-room policy](docs/CLEAN_ROOM.md) contains the full contributor rules.
[Reference provenance](docs/references.yml) records document identities,
subjects, acquisition URLs, filenames, and SHA-256 digests.

```sh
make refs
```

This downloads manuals into the ignored `.reference/` cache and verifies their
digests. Copyrighted manuals are not committed or required by CI.

## Known boundaries

- Reserved opcodes and unresolved manufacturer-document conflicts remain
  `UNDEFINED_BY_DOCUMENTATION`.
- Exact bus-trace claims are limited to cycles published by the manufacturer.
- Analog oscillator, pad, metastability, voltage, EPROM pulse, erasure, and
  retention behavior is outside synthesizable RTL scope.
- The copyrighted MC68705P5 bootstrap ROM image must be supplied by the
  integrator; its documented digital controls and vector behavior are present.

Variant-specific conflicts and normalized FPGA policies are recorded in
[Compatibility](docs/COMPATIBILITY.md), not hidden behind support claims.

## Documentation

- [Architecture and interfaces](docs/ARCHITECTURE.md)
- [Compatibility and limitations](docs/COMPATIBILITY.md)
- [Verification evidence](docs/VERIFICATION.md)
- [Clean-room methodology](docs/CLEAN_ROOM.md)
- [Reference manifest](docs/references.yml)
- [Coding-agent and contributor rules](AGENTS.md)

## License and contributions

Original project code and documentation are licensed under the
[MIT License](LICENSE). Contributions must preserve clean-room provenance,
variant boundaries, strict verification, and permanent regression tests for
discovered defects. Tests must not be weakened to obtain a green build.
