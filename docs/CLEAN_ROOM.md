# Clean-room engineering policy

## Purpose

`m680x_sv` is an independent, MIT-licensed SystemVerilog implementation of
documented members of the Motorola M6800/M6801/M6803/M6805 families and the
related Hitachi HD6301/HD6303/HD6305 families. The project exists to provide
traceable FPGA RTL, a deliberately independent executable model, and
verification evidence derived from hardware facts rather than another
implementation.

Clean-room integrity has priority over schedule, code reuse, performance, and
convenience. A device is not described as supported until its claimed behavior
is implemented and verified.

## Permitted sources

Design facts may be obtained from primary hardware documentation:

- original Motorola, Freescale, NXP, Hitachi, or Renesas data sheets, user
  manuals, programming manuals, reference manuals, application notes,
  databooks, timing diagrams, and errata;
- manufacturer-derived successor documentation when its provenance is clear;
- publicly documented physical schematics; and
- observations measured directly from physical devices, provided that the
  device, mask/revision, fixture, stimulus, instrumentation, raw results, and
  interpretation are recorded.

An archival scan of an original manufacturer publication is acceptable when a
manufacturer-hosted copy cannot be found. The archive is only the acquisition
location; the original manufacturer, title, document identifier, revision, and
date remain the authority.

## Prohibited sources

Contributors and automated coding agents must not inspect or use any existing
implementation of a target processor. This prohibition includes third-party
Verilog, SystemVerilog, VHDL, FPGA cores, emulator source, translated or
decompiled implementations, implementation-derived patches or generated
artifacts, historical versions, forks, snippets, state-machine descriptions,
microcode, interfaces, naming, directory layouts, tests used as behavioral
oracles, or timing traces produced by such implementations.

Do not search public source hosting for target-CPU implementations. An existing
implementation must not be used as an architectural, behavioral, timing, or
cycle oracle, even if its license would otherwise permit reuse.

General-purpose tooling such as simulators, assemblers, compilers, waveform
viewers, and formal engines is permitted when it does not embed an
implementation of a target processor as an oracle.

## Acquisition and provenance

Reference metadata lives in `docs/references.yml`. Although the file has a YAML
extension, it intentionally uses the JSON-compatible subset of YAML so the
standard-library fetcher can validate it without an external package. Each
entry records the original publisher and document identity, its acquisition
status and URL, the local cache filename, a fixed SHA-256 digest, the subjects
used, and the project artifacts that depend on it.

The acquisition procedure is:

1. Look for a manufacturer-hosted copy.
2. If none is available, locate a scan whose cover and front matter identify an
   original manufacturer publication.
3. Inspect the cover, publication data, revision, table of contents, and
   relevant pages. Do not infer identity only from an archive filename.
4. Add the metadata and expected digest to the manifest.
5. Run `make refs`; the fetcher downloads into `.reference/` and rejects any
   content whose digest differs.
6. Record the precise document section/page in each derived specification
   record or engineering note.

Source conflicts are never silently resolved. Record the competing references,
affected variants and revisions, the selected interpretation (if one can be
justified), and tests that distinguish it. A conflict may reflect a silicon
revision, device variant, operating mode, erratum, or different meanings of a
cycle boundary.

## Copyrighted material

`.reference/` is excluded from Git. Copyrighted manuals, scans, wholesale OCR,
and substantial copied prose must not be committed unless redistribution rights
are explicit and recorded. The repository contains only independently written
factual tables, concise citations, specifications, test vectors, and analysis.
Quotations are avoided unless necessary, kept short, and attributed.

`make refs` is an optional local acquisition operation. CI validates the
manifest without downloading manuals, so building or testing the repository
does not redistribute or require copyrighted documents.

## From documents to implementation

Every architectural decision must be traceable to a manifest reference and a
page, table, figure, or section. Machine-readable specifications state facts in
original project wording and classify every opcode, including reserved and
undefined encodings. RTL, model, and tests may consume the same factual
specification, but the executable model must not be a mechanical translation of
the RTL and the RTL must not be a mechanical translation of the model.

Expected results are derived from documented equations, tables, and timing
diagrams. Tests must not be weakened to accommodate an implementation. When a
test exposes a defect, preserve a focused regression and fix the component that
is wrong.

## Undocumented behavior

When behavior is absent or ambiguous, search additional manufacturer manuals,
databooks, application notes, errata, and revision-specific documents. If that
does not resolve the question, classify the behavior as
`UNDEFINED_BY_DOCUMENTATION`; do not guess and do not consult an existing
implementation. Physical-device characterization may later establish a
revision-specific observation, but an observation is not generalized beyond
the tested hardware without evidence.

Claims distinguish architectural-result, cycle-count, and external-bus-trace
verification. A total cycle count is not evidence for undocumented intermediate
bus cycles.

## Contributor and coding-agent rules

Before contributing, every human or automated agent must:

- read this policy and `AGENTS.md`;
- disclose any accidental exposure to prohibited implementation material and
  avoid contributing affected design work until maintainers determine a safe
  clean-room boundary;
- add provenance before using a new hardware document;
- cite implementation decisions at document-section or page granularity;
- keep downloaded references and generated artifacts out of Git;
- add permanent regressions for discovered defects;
- preserve variant boundaries rather than assuming similar part numbers are
  compatible; and
- describe uncertainty honestly instead of expanding support claims.

Reviewers must reject changes whose facts cannot be traced to permitted
hardware evidence or whose structure appears derived from a prohibited
implementation.
