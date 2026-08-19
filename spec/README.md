# Machine-readable specifications

Specification files use the JSON-compatible subset of YAML. This keeps the
files readable as YAML while allowing deterministic validation with Python's
standard library.

`devices.yml` separates architectural facts from device integration facts.
Each device names an architecture and therefore inherits that architecture's
register set, condition-code layout, addressing modes, stack rules, base reset
and interrupt behavior, and opcode lineage. Device records then supply address
width, physical vectors, memory, peripherals, modes, pins/bus behavior, clocks,
and device-specific exceptions.

Status values have evidentiary meaning:

- `COMPLETE`: implemented and covered by the verification level named by the
  field;
- `PARTIAL`: some documented behavior is implemented and the missing portion
  is stated explicitly;
- `NOT_IMPLEMENTED`: no support claim is made;
- `NOT_APPLICABLE`: the hardware feature does not exist or lies outside the
  scope of a core-only integration target; and
- `UNDEFINED_BY_DOCUMENTATION`: the permitted primary references do not define
  the behavior strongly enough to implement or verify it.

Opcode and peripheral files cite reference IDs from `docs/references.yml` plus precise
printed-page, table, figure, or section locators. Generated validators reject
missing or duplicate opcode values and incomplete factual records.

Expanded opcode classifications live in `spec/opcodes/`. Run `make spec-build`
after changing the compact primary-manual tables in
`tools/build_opcode_specs.py`; `make spec-check` fails if the committed outputs
are stale or if any architecture has anything other than one validated record
for each value from `00` through `FF`.
