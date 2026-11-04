# Compiler subsystem audit — 2026-11-04

This is an initial source/coverage audit, not a certification that every listed subsystem is complete. Active code is identified through the frozen 268-file compiler closure. Files elsewhere in the tree do not establish production support.

| Subsystem | Active implementation / existing checks | Findings and work remaining |
|---|---|---|
| Lexer/parser | parser/syntax/canonical_parser.s; canonical_*_ast and frontend_lexer_native checks | Quoted literals, malformed headers and statement boundaries have tests; broaden malformed input, nesting limits and Unicode coverage. |
| AST/locations | ast; parser/frontend_ast.s; canonical_source_diagnostics | Track exact spans through lowering; verify imported and generated-node diagnostics. |
| Types/inference | semantic/semantic.s, typesys; canonical_typesys and nominal identity checks | Backend supported types are int, bool, string, unit, records, recursive arrays/references. Float lowering is absent from ssa_type_supported. P1 language scope gap. |
| Generics | mono/canonical_annotation.s, monomorphization.s; generic/package specialization checks | Existing tests cover several specializations; recursive specialization limits and trait constraints need stress coverage. |
| Names/semantics | semantic; declaration/type identity and receiver checks | Preserve nominal identity and single evaluation. Text-count semantic helpers exist; establish which are active before diagnosing false positives. |
| Modules/imports | dist/source_imports.py, source_closure.sh; source_closure_import_check | Source graph supported; package manager and version resolution not established. |
| Control flow | compiler lowering, mir/program.s; branch/loop/continue/break/never checks | Add nested exit/cleanup differential cases. |
| MIR | mir/program.s, program_enum.s; public MIR and invalid-input gates | Validation re-runs at SSA boundary; mutated graph rejection needs systematic coverage. |
| SSA | ssa/function_lower.s, program.s; backend SSA interface and dominance cost gates | Tuple source returns lower to aggregates; rejecting multiple physical results is not a source tuple defect. Large SSA directory includes files outside active closure. |
| Optimization | active canonical lowering and SSA path; cost tests | Do not infer an optimizing production pipeline from experimental pass filenames. Establish actual selected passes and benchmark impact. |
| AMD64 | codegen/amd64_program.s; native execution and arithmetic checks | Linux ELF path active; floats/SIMD not established. |
| ABI | codegen/amd64_program.s, native object gate | C-object tests exist. Broaden mixed signatures, stack parameters, aggregates and callee-save checks. |
| Registers/stack | active AMD64 emitter; regalloc checks | Identify actual allocation strategy and live-root safety across calls; directory-level regalloc files are insufficient evidence. |
| Runtime/memory | emitted native runtime and src/runtime/native_gc_amd64.S | Distinguish generated native runtime from S runtime foundation APIs. Allocation failure and arithmetic size-overflow coverage need review. |
| Garbage collector | native GC tests: churn, roots, live graph, C objects | Current tests impose 128/512 MiB address limits and CPU limits; long-running fragmentation and OOM paths need expansion. |
| Standard library | packages in src; imported compiler dependencies | Compiler closure exercises only a subset. Networking, filesystem failure contracts and concurrency support require executable support matrix. |
| Diagnostics | canonical diagnostics/source checks | Missing guides and unsupported-feature messages impede users; validate no output clobber on all failure paths. |
| CLI/build | misc/scripts/s-driver.sh, core/native_build.s | Confirmed P0 source data loss in explicit legacy build through symlink/hardlink/directory alias. Canonical native path already checks inode identity. Regression added; shell fix uses same-file test. |
| Platforms | native_target_supported in core/native_build.s | Only linux/amd64 production native target. Other architecture source directories are not verified production targets. |
| Bootstrap | cleanroom-selfhost.py, bootstrap-acceptance.py, ci-core.sh | Historical full evidence independently re-audited PASS. Fresh controller 21/21 PASS with tracing enabled. New full bootstrap still required after compiler-source changes. |

## Priority backlog

- P0-001: Legacy CLI source overwrite through output aliases. Reproduced three failures; fix and regression under verification.
- P0-002: Seed-hosted development/Stage1 compiler has signed 63-bit tagged integer carriers and silently emits wrong int64 constants. Differential test identifies a concrete miscompile; frozen Stage3 emits correct constants. Must fix seed representation/arithmetic or establish a sound typed raw-int lowering, preserving all object/region semantics.
- P1-004/P1-005: Minimum signed literal and negative integer patterns fail native MIR lowering; reproduce and fix with signed-literal regressions.
- P1-001: Floating-point native support missing despite float in syntax guide. Establish intended numeric semantics and implement end-to-end with ABI tests.
- P1-002: Full runtime concurrency/safe-point/stack-map integration not established; README explicitly distinguishes API contracts from backend implementation. Audit active runtime and language syntax before implementation.
- P1-003: Complete language support matrix needed for pointers, ownership, traits/dynamic dispatch, FFI, error handling, modules and standard library; do not equate self-hosting subset with full language.
- P2-001: Large selfcompile resource cost (historical stage2 ~2.96 GiB RSS); measure current bottlenecks before optimization.
- P2-002: Broaden malformed-input, integer-boundary, evaluation-order, ABI and GC differential tests.
- P3-001: Restore missing compiler/native/platform guides and document actual commands.

Readiness remains **NOT ESTABLISHED** while P1 gaps and required verification remain open.
