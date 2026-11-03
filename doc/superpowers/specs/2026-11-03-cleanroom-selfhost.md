# Mission: Establish Reproducible, Clean-Room Self-Hosting

## Objective

Turn the current S compiler self-hosting achievement into a fully reproducible, independently verifiable build process.

The priority is reliability and reproducibility, NOT compiler performance optimization.

The final acceptance criterion is:

**A clean checkout must independently build C Seed → Stage1 → Stage2 → Stage3, pass all required tests, and produce byte-identical Stage2 and Stage3 compiler artifacts where the bootstrap design requires convergence.**

## Phase 1 — Freeze and Commit the Verified Source

1. Inspect the current Git branch, working tree, staged changes, and recent commits.
2. Identify all source changes and regression tests required for the current verified bootstrap.
3. Run the complete core production regression suite.
4. Verify that no required changes are missing or accidentally excluded.
5. Commit the verified source and regression tests.
6. Record:
   - Git commit SHA
   - Compiler source closure (all 268 files)
   - SHA256 of every source file
   - Build configuration
   - Host compiler and target architecture
   - Regression test results

Do not overwrite or discard existing evidence.

Preserve all previous bootstrap checkpoints and logs.

## Phase 2 — Independent Clean-Room Bootstrap

Create a completely new build directory.

Do not reuse:
- Existing Stage1 binaries
- Existing Stage2 binaries
- Existing Stage3 binaries
- Previous generated assembly
- Previous object files
- Cached compiler outputs
- Previous build checkpoints

Build the complete chain:

C Seed → Stage1 → Stage2 → Stage3

Requirements:

1. Build Stage1 exclusively from the committed source using C Seed.
2. Build Stage2 exclusively using the newly generated Stage1.
3. Build Stage3 exclusively using the newly generated Stage2.
4. Ensure each stage uses the exact same frozen source closure.
5. Record the exact command, exit code, duration, peak RSS, and output hashes for every stage.
6. Preserve complete stdout and stderr logs.
7. Verify that each generated compiler can independently execute and compile representative S programs.

If any stage fails, stop the acceptance process, preserve evidence, identify the root cause, fix it, and restart from a fresh directory.

Do not silently fall back to an existing checkpoint.

## Phase 3 — Verify Bootstrap Convergence

Perform independent artifact comparisons.

Verify:

- Stage2 and Stage3 compiler artifacts are byte-identical where convergence is expected.
- Native assembly hashes match.
- Source manifests match.
- All expected reachable functions are present.
- No unexpected missing or extra compiler outputs exist.
- Generated binaries pass execution tests.
- All stage transitions are documented and reproducible.

Do not assume identical source inputs automatically imply identical outputs.

Distinguish compiler artifact convergence from ordinary source compilation success.

## Phase 4 — Establish Continuous Integration

Add a CI workflow with two levels.

### Pull Request / Every Commit

Run:
- Compiler build smoke tests
- Parser regressions
- Semantic analysis regressions
- Type checking
- Generic specialization
- MIR lowering
- MIR/SSA verification
- ABI and native backend tests
- Existing production regression suite

### Scheduled Full Bootstrap

Run:
- Fresh C Seed build
- Stage1 generation
- Stage2 generation
- Stage3 generation
- Artifact convergence checks
- Source manifest verification
- Representative execution tests

Upload complete logs, manifests, compiler artifacts, and failure diagnostics.

The full bootstrap must never silently use cached stage binaries.

## Phase 5 — Expand Real-World Compiler Usage

After clean-room bootstrap passes:

1. Use Stage3 to compile the standard library.
2. Compile representative real-world S applications.
3. Test imports, generics, methods, records, arrays, tuples, error handling, and external interfaces.
4. Identify missing language features and standard-library gaps.
5. Add every discovered issue as a reproducible regression test.
6. Fix correctness issues before considering performance improvements.

## Engineering Constraints

- Do not perform speculative compiler optimizations.
- Do not refactor working compiler architecture without a demonstrated correctness requirement.
- Preserve the existing S language syntax and ABI contracts.
- Preserve the frozen source snapshot throughout each bootstrap run.
- Do not modify source files while a verification run is consuming them.
- Do not kill existing processes without verifying their identity and obtaining authorization.
- Never report a stage as PASS based on an earlier checkpoint when the current run did not build it.
- Clearly distinguish PASS, FAIL, BLOCKED, and NOT RUN.

## Final Deliverables

Produce:

1. A committed source revision.
2. A clean-room bootstrap script.
3. A reproducible bootstrap manifest.
4. Complete Stage1/Stage2/Stage3 build logs.
5. SHA256 source and artifact manifests.
6. Byte-comparison results.
7. CI configuration.
8. Regression test results.
9. A final self-hosting verification report.

## Definition of Done

The mission is complete only when:

- [ ] Source revision is committed and frozen.
- [ ] Clean-room C Seed → Stage1 succeeds.
- [ ] Fresh Stage1 → Stage2 succeeds.
- [ ] Fresh Stage2 → Stage3 succeeds.
- [ ] Required Stage2/Stage3 artifacts converge byte-for-byte.
- [ ] All production regressions pass.
- [ ] Stage3 successfully compiles representative real S programs.
- [ ] CI automatically validates the required checks.
- [ ] All evidence is preserved and independently auditable.

Start with Phase 1. Proceed sequentially. Do not declare self-hosting reproducible until every acceptance criterion has been verified.