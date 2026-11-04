# Mission: Finish the S Compiler — Do Not Stop Until Production-Ready

You are the lead compiler engineer responsible for completing the S programming language and its self-hosting compiler.

Your mission is to take the S compiler from its successfully verified self-hosting state to a complete, reliable, production-ready compiler.

**Do not stop after producing a plan, identifying issues, fixing one bug, or passing the bootstrap. Continue implementing, testing, debugging, and improving until all completion criteria are satisfied.**

## 1. Establish the current verified baseline

First inspect the repository, current Git commit, working tree, CI results, acceptance reports, and compiler architecture.

The previous milestone reported:

- C Seed → Stage1 → Stage2 → Stage3 successfully completed.
- Stage2, Stage3, and rebuild outputs are byte-identical.
- Clean-room bootstrap passed.
- All 82 production recipes executed.
- All 21 controller tests passed.
- GitHub Actions acceptance passed.
- No known blockers remained.

Verify these claims against actual repository evidence. Do not blindly repeat completed work or overwrite accepted artifacts.

Preserve the successful baseline and all historical evidence.

## 2. Perform a complete compiler engineering audit

Inspect every major subsystem:

1. Lexer and parser.
2. AST and source-location tracking.
3. Type system and type inference.
4. Generic programming and specialization.
5. Semantic analysis and name resolution.
6. Module system and imports.
7. Control-flow analysis.
8. MIR generation and validation.
9. SSA construction and verification.
10. Optimization passes.
11. Native AMD64 code generation.
12. Calling conventions and ABI.
13. Register allocation and stack management.
14. Runtime and memory management.
15. Garbage collector.
16. Standard library.
17. Error reporting and diagnostics.
18. Compiler CLI and build system.
19. Cross-platform and cross-architecture support.
20. Bootstrap and reproducible build infrastructure.

For each subsystem, identify:

- Missing functionality.
- Known limitations.
- Incorrect behavior.
- Performance bottlenecks.
- Memory safety risks.
- Incomplete implementations.
- Missing regression tests.
- Architectural weaknesses.

Create a prioritized engineering backlog.

## 3. Fix all critical compiler defects

Work through the backlog in priority order:

P0: Correctness, compiler crashes, memory corruption, invalid code generation, ABI violations and bootstrap regressions.

P1: Missing essential language functionality, type-system correctness, generics, modules, runtime and garbage collection.

P2: Optimization quality, compilation speed, memory efficiency and diagnostics.

P3: Developer experience, documentation, tooling and ecosystem.

For every fix:

- Reproduce the problem.
- Create a regression test.
- Implement the smallest correct solution.
- Run the relevant tests.
- Run the complete production regression suite.
- Verify self-hosting remains intact.
- Preserve reproducibility.

Never hide failures, weaken assertions, skip tests, or change expected results merely to obtain PASS.

## 4. Complete the S language

Evaluate the language against a modern systems programming language.

Pay particular attention to:

- Variables, constants and primitive types.
- Arrays, slices, strings and structures.
- Enums and pattern matching.
- Functions and multiple return values.
- Pointers and references.
- Ownership and borrowing semantics.
- Generics and specialization.
- Interfaces and methods.
- Modules and package management.
- Error handling.
- Concurrency and synchronization.
- Memory allocation and garbage collection.
- FFI and C interoperability.
- Runtime initialization and shutdown.

Do not introduce incompatible syntax or silently change established S language semantics.

Use existing language specifications and accepted implementation conventions as the source of truth.

## 5. Improve native compilation

Verify that generated native code is correct and efficient.

Investigate:

- AMD64 ABI compliance.
- Register allocation.
- Stack alignment.
- Function prologues and epilogues.
- Integer and floating-point operations.
- SIMD opportunities.
- Bounds and safety checks.
- Optimization passes.
- Linker integration.
- Debug information.
- Executable and object-file generation.

Benchmark representative programs and compare compiler performance, generated assembly, memory usage and execution speed.

Only accept optimizations that preserve correctness.

## 6. Strengthen memory management

Audit the garbage collector and runtime.

Verify:

- Root registration.
- Global roots.
- Stack and register roots.
- Nested object references.
- Mutable references.
- Pointer stability.
- Allocation and reclamation.
- Memory reuse.
- Stress behavior.
- Out-of-memory handling.
- Long-running process stability.

Run memory-constrained and large-scale tests.

Investigate every memory leak, unbounded allocation and unexpected RSS increase.

## 7. Build a comprehensive test suite

Expand testing beyond the existing 82 production recipes and 21 controller tests.

Include:

- Lexer and parser tests.
- Semantic and type-system tests.
- Generic specialization tests.
- MIR and SSA verification.
- ABI and native execution tests.
- Garbage collection stress tests.
- Runtime tests.
- FFI tests.
- Negative compilation tests.
- Large-project compilation tests.
- Performance benchmarks.
- Differential tests where an independent reference is available.
- Clean-room reproducibility tests.

Every discovered defect must become a permanent regression test.

## 8. Maintain genuine self-hosting

Self-hosting is a permanent acceptance requirement.

Whenever compiler source changes:

1. Build from the frozen source baseline.
2. Produce Stage1.
3. Compile Stage1 into Stage2.
4. Compile Stage2 into Stage3.
5. Rebuild from Stage3.
6. Compare the appropriate outputs byte-for-byte.
7. Run the complete execution and regression suites.
8. Verify CI independently.

Never claim self-hosting success based solely on an existing binary or cached artifact.

## 9. Documentation and release engineering

Complete:

- S language specification.
- Compiler architecture documentation.
- Installation instructions.
- Build-from-source instructions.
- Language tutorial.
- Standard library documentation.
- CLI reference.
- Runtime and GC documentation.
- FFI guide.
- Troubleshooting guide.
- Contribution guidelines.
- Release notes.

Ensure a new developer can clone the repository, build the compiler, compile an S program and run it without undocumented manual intervention.

## 10. Autonomous execution rules

This is an execution mission, not a planning exercise.

You must:

- Continue from the current repository state.
- Work in small, verifiable engineering increments.
- Maintain a persistent task checklist.
- Record completed tasks and remaining blockers.
- Keep detailed logs and reproducible evidence.
- Commit logically complete changes.
- Run tests after each significant change.
- Preserve all existing successful behavior.
- Never silently discard concurrent changes.
- Never claim PASS without actual evidence.
- Never replace a real fix with a workaround that weakens correctness.

When a test fails, investigate and fix the underlying cause. Then resume the remaining backlog.

If a task is blocked, investigate alternative technically sound solutions and continue with independent tasks.

Do not ask me for routine engineering decisions. Use sound compiler engineering judgment.

Ask for authorization only when an action genuinely requires external permission, destructive changes, publishing a release, or another consequential operation outside the existing authorization.

Do not stop merely because a milestone is completed.

## 11. Definition of DONE

The mission is complete only when:

- [ ] All critical compiler correctness defects are resolved.
- [ ] Core S language functionality is implemented and documented.
- [ ] Type system and generics are reliable.
- [ ] MIR and SSA verification are comprehensive.
- [ ] Native code generation and ABI tests pass.
- [ ] Runtime and garbage collector pass stress testing.
- [ ] Production regression suite passes.
- [ ] No known P0 or P1 defects remain.
- [ ] Clean-room self-hosting passes.
- [ ] Stage2/Stage3/rebuild reproducibility is verified.
- [ ] CI independently passes.
- [ ] Installation and usage documentation is complete.
- [ ] A new developer can build and use S from a clean checkout.

## 12. Final deliverables

Produce:

1. Production readiness report.
2. Completed and outstanding engineering checklist.
3. Full test and CI results.
4. Bootstrap reproducibility evidence.
5. Compiler performance benchmarks.
6. Known limitations document.
7. S language specification and documentation.
8. Release-ready source commit.

At the end, provide a clear report distinguishing implemented features, tested features, verified features and remaining limitations.

**FINAL INSTRUCTION: Do not stop at the first successful milestone. Continue the engineering loop: AUDIT → IMPLEMENT → TEST → DEBUG → OPTIMIZE → VERIFY → DOCUMENT. Repeat until every applicable completion criterion is satisfied.**