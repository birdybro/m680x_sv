# Durable engineering instructions

These rules apply to every human contributor and coding-agent session in this
repository.

1. Read `docs/CLEAN_ROOM.md` before architecture, RTL, model, or verification
   work. Use only primary manufacturer hardware documentation and properly
   identified archival scans of such documentation.
2. Never inspect, search for, clone, translate, compare against, or use source,
   tests, traces, interfaces, organization, or generated artifacts from another
   CPU implementation or software emulator. They are not permitted behavioral
   or timing oracles.
3. Record every source in `docs/references.yml`, acquire it with `make refs`, and
   cite the reference ID plus exact page/table/figure/section in derived specs
   and engineering notes. Keep `.reference/` and all OCR out of Git.
4. Do not infer compatibility from similar part numbers. Keep M6800,
   MC6801/MC6803, M6805, and Hitachi extensions separated wherever the primary
   documents show different behavior.
5. Classify all 256 opcodes for every claimed architecture. A reserved or
   undocumented encoding must be explicit; no missing entry is acceptable.
6. Verify architectural results and documented cycle behavior independently.
   Keep architectural-result, total-cycle, and external-bus-trace claims
   separate when documentation supports different levels of evidence.
7. The Python model and SystemVerilog RTL must be structurally independent.
   Neither may be a mechanical translation of the other. Tests should derive
   expectations from documented facts and independent equations, not duplicate
   the implementation under test.
8. Add a focused permanent regression for every discovered bug. Do not disable
   assertions, delete difficult cases, lower coverage, reclassify documented
   behavior, suppress broad warning classes, or change a known-correct expected
   result merely to make a build pass.
9. Use synthesizable, vendor-neutral SystemVerilog with explicit state and clock
   enables. Avoid inferred latches, generated internal clocks, combinational
   loops, simulation-only constructs in RTL, and unexplained numeric literals.
10. Before each meaningful commit, run the relevant tests, inspect the diff,
    run `git diff --check`, check for secrets/generated files/manuals, then make
    a small coherent commit and push it. Never force-push or rewrite published
    history.
11. Do not claim a device or peripheral as supported until the implementation
    and corresponding directed, boundary, interrupt, and timing tests pass.
    Classify unresolved facts as `UNDEFINED_BY_DOCUMENTATION` and record the
    research performed.
12. `make ci` is the authoritative release gate. Do not tag a release while it
    has failures, hidden stubs, incomplete claimed functionality, or unsupported
    warnings.
