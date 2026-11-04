# Known limitations and release blockers

Production readiness is not established. See audit.md and status.md for evidence.

1. Seed-hosted development/Stage1 integer arithmetic uses a 63-bit tagged carrier and can silently miscompile int64 constants. Frozen Stage3 passes the new 720-case differential, but self-host convergence alone did not expose the seed discrepancy. P0 release blocker.
2. Negative integer switch patterns and minimum int64 literal spelling are rejected by canonical MIR lowering. P1 defects.
3. Native float support is absent in the active SSA supported-type predicate. Float syntax in historical guides is not end-to-end native support.
4. Complete runtime concurrency, scheduling, stack-map and safe-point integration remains unverified. The native GC is a separate single-threaded conservative runtime.
5. Native GC object/library entry mode retains process-lifetime allocations rather than collecting values that may escape to C. Long-running embedding requires an explicit lifetime/root strategy.
6. Linux/amd64 is the verified native target. Other backend directories are not production support claims.
7. Package management/versioning and comprehensive standard-library support remain to be established against the full language mission.
8. Documentation added in this mission describes verified paths and limitations; a complete normative language specification, FFI contract and full-library reference remain outstanding.
9. Final-revision fresh full bootstrap, independent CI, release benchmarks and final review remain required. No new CI was triggered or source pushed.
