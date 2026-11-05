# std.time engineering acceptance — 2026-11-05

Implemented the real Linux/amd64 time API, shared raw kernel boundary, validated MIR/SSA intrinsic signatures and tagged standalone seed adaptors. No sleeping subprocess, C++ application or busy wait implements these operations.

Observed results:

- `python3 test/stdlib-native/test_time.py -v`: 6 tests PASS. Expanded run includes canonical and standalone-seed success, EINTR/EIO propagation, exact maximum nanosecond interval, first overflow, negative fields, and reset failure preserving timer state.
- Actual native 200 ms sleep: 202.035 ms wall / 1.606 ms CPU in the expanded run. Seed: 200.763 ms wall / 0.295 ms CPU. Reported monotonic durations were 200.189/200.199 ms respectively. These are acceptance measurements on this host, not nanosecond precision promises.
- Actual repeated SIGALRM every 50 ms interrupted the S native object during sleeping. It completed in 202.037 ms wall / 1.437 ms CPU. Restarting the original 160 ms request would never complete under those repeated signals; the implementation consumes kernel remaining time.
- Injected EINTR completed with >=200 ms reported sleep in both native and seed paths. EIO propagated through clock/sleep/reset without false success. Exact `(9223372036,854775807)` timespec reached the kernel under injected success; the next nanosecond is rejected before sleeping.
- `test_seed_borrow_integration.py`: actual imported mutable call accepts tuple-derived owners, rejects wrong nominal owner and expired lexical scope, preserving failed output.
- `make -o compiler selfhost-canonical-production-check`: exit 0 in `.bootstrap/stdlib-mission-20261105/time-production.exit`; every existing recipe retained, with time/generator/borrow regressions added.
- Independent read-only review found no definite time-runtime correctness defect. Its real-EINTR, exact-boundary and seed error-path coverage requests were implemented and passed.

Retained evidence: `.bootstrap/stdlib-mission-20261105/time-acceptance-expanded.log`, `seed-borrow-v2.log`, `time-production.log`, and all earlier failing attempts. The initial missing-module, seed tuple dependency, receiver spelling, builtin alias and borrow-proof failures were diagnosed rather than skipped.

Seed integration fixes preserve the existing safety checks: package-qualified mutable calls select an actual declaration only when the import root is not lexically shadowed; transparent tuple-binding blocks preserve their declared lexical scope. The independent IR ownership proof still runs. Existing input/owner/lifetime negatives are not relaxed.

Remaining certification: fresh full staged rebuild at the final integrated standard-library revision; terminal/input/Snake and the remaining approved core/advanced modules. A passing time increment is not production-readiness certification for the entire library. Boxed future clock timestamps outside the current clock epoch have no synthetic clock-source test; full int64 packing is covered separately by existing seed integer regressions.
