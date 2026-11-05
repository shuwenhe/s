# String engineering acceptance — 2026-11-05

`python3 -u test/stdlib-native/test_string.py -v`: **3 tests PASS**, exit 0 in `.bootstrap/stdlib-mission-20261105/string-scaled-acceptance-v4.log`. Each API fixture executes both canonical native ELF and standalone seed binaries. The fixture includes 3,937 exhaustive binary-string searches, signed int64 endpoints/overflows, invalid decimal spelling, binary NUL, checked slicing/bytes, immutable-array snapshot behavior, 32 KiB repetitive-pattern search and a 16,385-field split/join. Another 100 deterministic cases compare search/split/replace with Python. Wrong intrinsic array types fail in native and seed validation while preserving prior output.

Separate retained native executable measurements (`/usr/bin/time`, same fixture):

| Path | 32 KiB needle search | Dense split plus join | Entire fixture peak RSS | Entire fixture wall |
|---|---:|---:|---:|---:|
| Native | 2.632 ms | 8.881 ms | 16,884 KiB | 0.02 s |
| Seed | 16.203 ms | 51.510 ms | 2,704 KiB | 0.09 s |

These are observations on this host, not cross-machine performance promises. Logs: `string-native-benchmark.log`, `string-seed-benchmark.log`. Actual ELF binaries and IR are retained under the same evidence directory.

Independent review caught quadratic KMP prefix-table allocation and separator-heavy array append copies. Both were removed: constant-space Two-Way matching plus balanced output assembly. Follow-up review found no additional concrete ABI, bounds, complexity or signature defect in the shared concat implementation. Raw assembly uses the existing allocator callback with header-specific native/seed adapters and checks overflow/allocation failure. Exhaustion terminates with status 12 rather than silently returning an empty result.

Earlier failing logs are retained. Two Seed boundary issues were fixed: qualified source declarations take precedence over legacy runtime leaf aliases across proof/analysis/emission, and the new two-array intrinsic loads evaluated ARG slots rather than re-evaluating an allocating second literal over the first register argument. The intrinsic also triggers mandatory independent IR type proof in units without mutable borrows. A generic `api.slice`/`api.byte_at` regression is retained in `test_seed_borrow_integration.py`.

The Seed subset requires local mutable copies of parameters and does not reliably lower tuple reassignment or effectful array-literal items. The portable fixture uses fresh tuple bindings and evaluates array items before constructing a literal. These syntax limitations are not advertised as fixed. The complete production recipe and final integrated self-hosted stage certification remain separate gates.
