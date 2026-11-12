# Verification results — 2026-11-12/13

## Real-server acceptance completed with native Stage1, Stage2 and Stage3

Compilers: `.bootstrap/mysql-final-stages/stage1`, `stage2`, `stage3`, generated through the real Seed → Stage1 → Stage2 → Stage3 chain. Stage1 SHA-256: `75a0a83b61d38820eb6d3af4e0905372aadcc4ef6d5c585d666115a6a49212f6`. Stage2 and Stage3 are byte-for-byte identical: `783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73`. All six runs verified the same final driver source hashes.

| Actual server | Suite per compiler | TCP benchmarks | TLS benchmarks |
| --- | --- | --- | --- |
| MySQL 8.0.46-0ubuntu0.22.04.4 | 22 cases × 3 compilers passed | passed on all stages | passed on all stages |
| MySQL Community Server 8.4.8 | 22 cases × 3 compilers passed | passed on all stages | passed on all stages |

The suite covers real native/SHA2 auth success/failure, cold SHA2 RSA with pinned/retrieved key, warm SHA2 cache, TLS and hostname rejection, CRUD, reusable prepared execution, statement ownership/close, transaction commit visibility from a second connection, rollback and rollback-on-close, signed/unsigned BIGINT limits, exact DECIMAL, VARCHAR/TEXT, BLOB with zero/0xff bytes, DATETIME including fractional precision, NULL/empty values, Chinese, server KILL, read timeout, bounds and authentication cleanup. Three supplemental cases use real loopback fault peers for partial frames, handshake deadlines and blocked writes; these supplement rather than replace real MySQL tests. A transparent fault relay corrupts ERR/PING responses from real MySQL sessions to verify query, prepare and ping invalidation.

Both [CRUD](../../test/mysql/crud/main.s) and [transaction](../../test/mysql/transaction/main.s) examples were built and executed against MySQL 8.4 over certificate-verified TLS. Output: `1: 张三` and `committed transfer; rolled back second change`. `ldd` shows libssl.so.3, libcrypto.so.3 and libc.so.6; no libmysqlclient.

Raw evidence: [all-stage server/compiler results JSON](verification/all-stages-results.json), [8.0 Stage3 test log](verification/mysql80-stage3.log), [8.4 Stage3 test log](verification/mysql84-stage3.log), [environment/source hashes](verification/environment.json), [examples log](verification/examples.log).

## Measured latency

Measured using Stage3; 100 sequential operations per workload, mean microseconds/operation. SELECT: `SELECT 1, '中文', NULL`; prepared SELECT: one bound integer. One established connection per benchmark process; connection establishment and preparation excluded. Measurements include server, transport and S result parsing. Shared host was also compiling bootstrap; these are reproducible observations, not an isolated capacity claim.

| Server | Transport | PING | SELECT | Prepared SELECT |
| --- | --- | ---: | ---: | ---: |
| 8.0.46 | TCP | 29.1 | 86.7 | 74.3 |
| 8.0.46 | TLS | 53.3 | 190.7 | 139.6 |
| 8.4.8 | TCP | 61.8 | 157.2 | 136.1 |
| 8.4.8 | TLS | 70.6 | 182.6 | 149.2 |

Pure S RSA-OAEP encryption with 2048/4096-bit keys (exponent 65537) and a 2048-bit exponent-3 key decrypted correctly using independent Python cryptography/OpenSSL in both Seed and native Stage2; a timed native execution took 0.307 seconds. Raw MySQL-generated PEM contents including their terminal NUL are supported and tested. Randomized OAEP and token tests are separate from real-server acceptance. [Auth/RSA log](verification/auth-rsa.log).

Reproduce:

```sh
# This workspace used extracted OpenSSL development files rather than a system install.
# With libssl-dev installed normally, omit these two exports.
export CPATH=/tmp/s-mysql-build-deps/root/usr/include:/tmp/s-mysql-build-deps/root/usr/include/x86_64-linux-gnu
export LIBRARY_PATH=/tmp/s-mysql-build-deps/root/usr/lib/x86_64-linux-gnu
make mysql-unit-check
python3 test/stdlib-native/run_mysql_matrix.py --image84 mysql:8 \
  --compiler .bootstrap/mysql-final-stages/stage1 \
  --compiler .bootstrap/mysql-final-stages/stage2 \
  --compiler .bootstrap/mysql-final-stages/stage3 --output .bootstrap/mysql-delivery-all-stages
```

This host lacked OpenSSL headers. `apt-get download libssl-dev` was extracted under `/tmp/s-mysql-build-deps`; CPATH and LIBRARY_PATH pointed there, with libssl.so.3/libcrypto.so.3 symlinks to installed system libraries. No system MySQL client library was added. The Docker readiness check waits for TCP, avoiding the image’s temporary `--skip-networking` initialization server; the corrected runner passed a separate full Stage3 matrix. [Runner verification](verification/runner-readiness-results.json). On a normal build machine, install the OpenSSL development package. The existing local Docker tag `mysql:8` was inspected and the test runner verified its server was **8.4.8**; tags alone are not treated as version evidence.

## Other regression results

- Seed: common positive database, existing MySQL protocol, auth/RSA and binary-value fixtures passed. A previously masked enum-parameter type-check gap is now an explicit expected failure, rather than a false positive. [Seed database log](verification/database-seed.log).
- Canonical native Stage1: database rows/values/lifecycle/wire and negative type checks, auth/RSA, binary values, qualified-global compiler regression, TLS environment-startup regression and source resolver regression passed. [Native database log](verification/database-native.log), [compiler/startup regressions](verification/compiler-regressions.log).
- Source-closure import acceptance and canonical mutation/store regression passed.
- Entire native standard-library discovery using the final Stage3 compiler: **88 tests**, **1 failure**, **1 class setup error**, **22 skipped**, **1 expected failure**. MySQL integration cases intentionally skip without their real-server environment; the separately executed suite above provides their evidence. The expected failure explicitly records the pre-existing Seed enum-parameter type-check gap (previously masked by a test that also had an invalid return type). Remaining failure: unchanged `test_collections.NativeCollectionsTests.test_native_and_seed_collection_contracts` Seed branch (`std.option.option[v]` versus `option[v]`). Setup error: missing external `/root/shuwen/snake/snake_native.s`. [Full log](verification/stdlib.log).
- Existing `selfhost-protocol-check` stops at `native_artifact_check.sh` because it expects an ordinary supported `if` statement to be rejected. Existing `selfhost-native-record-check` stops at `native_generic_pattern_ref_check.sh` with an unproven Seed borrow-flow error; its extracted semantic source was not changed by this driver. `selfhost-native-unit-check` passes its typed MIR/SSA/ELF pipeline check, then fails in a separate extracted unit at `mir/program.s:1051` because `std` is undeclared. These checks are reported as failures, not silently relaxed. [Protocol log](verification/bootstrap-protocol-check.log), [record log](verification/bootstrap-record-check.log), [unit log](verification/bootstrap-unit-check.log).
- NeurX native suite using the final Stage3 compiler: **16 tests**, **3 errors**, with identical failing classes before/after using a compiler built from the pre-fix source snapshot versus the updated compiler. NativeHFNumerics and NativeServing fail on an existing unsupported string escape; LegacyImports lacks `artifact/build/s_runner/s_ir_runner`. [Before](verification/neurx-before.log), [after](verification/neurx-after.log). CPU runtime target cannot build because the referenced `test/tensor_runtime_native_test.cpp` is absent. No NeurX source was changed.

## Toolchain bootstrap acceptance passed

Fresh full bootstrap command:

```sh
S_SOURCE_ROOT="$PWD" bash src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/mysql-final-stages
```

The fresh script exited **0**: **Seed → Stage1 → Stage2 == Stage3 == Stage4**. All stages passed native ELF checks; Stage2/Stage3/Stage4 assembly and executables converge byte-for-byte; source-dependent compilation/execution checks passed at each of those three stages; all 269 compiler source hashes stayed unchanged. Stage1/Stage2/Stage3 each also passed the 22-case suites and TCP/TLS benchmarks on both real MySQL versions. [Bootstrap proof JSON](verification/bootstrap-results.json), [final convergence/execution log](verification/bootstrap-final.log).

The separate legacy-target and external-fixture failures above remain reported failures; bootstrap convergence does not erase them.

## Review and implementation choices

Independent review identified fatal malformed-ERR invalidation and binary temporal fractional precision; both were fixed with local regression and live-server checks (the temporal precision regression was observed failing before its fix). The review's direct-test entry-point issue was also fixed. Local outbound validation is nonfatal for a synchronized connection, while any authentication failure closes the incomplete connection.

The concrete connection API avoids unsupported dynamic traits; declaration-only contracts are now under `std.database.contracts`. Results are buffered with limits; continuation packets, multi-results and binary FLOAT/DOUBLE conversion are explicit limits documented in [README.md](README.md). Those limits are not advertised as supported.
