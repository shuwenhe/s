# Known limitations and release blockers

Production readiness is not established. See audit.md and status.md for evidence.

1. The seed int64 carrier defect is fixed in 340862598 with immutable wide boxes. Direct seed and rebuilt native differential tests pass 900 cases, bounded loop memory tests pass, and the full production suite passes. Fresh staged verification is running; release closure remains pending.
2. Negative integer patterns and minimum int64 literal spelling are fixed in 3f0906e35. Boundary/overflow/output-preservation tests and the full production suite pass. Final-revision staged verification remains required.
3. Native float support is absent in the active SSA supported-type predicate. Float syntax in historical guides is not end-to-end native support.
4. Complete runtime concurrency, scheduling, stack-map and safe-point integration remains unverified. The native GC is a separate single-threaded conservative runtime.
5. Native GC object/library entry mode retains process-lifetime allocations rather than collecting values that may escape to C. Long-running embedding requires an explicit lifetime/root strategy.
6. Linux/amd64 is the verified native target. Other backend directories are not production support claims.
7. Package management/versioning and comprehensive standard-library support remain to be established against the full language mission.
8. Documentation added in this mission describes verified paths and limitations; a complete normative language specification, FFI contract and full-library reference remain outstanding.
9. Final-revision fresh full bootstrap, independent CI, release benchmarks and final review remain required. No new CI was triggered or source pushed.

10. Seed enum payload mismatches and unresolved payloads were incorrectly accepted. Strict validation, permanent rejection tests and a missing compiler source import are implemented; full production and broader record checks are running. Native fixed enum payloads of float or any remain unsupported end-to-end even with the original seed.
