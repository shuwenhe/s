# Native S REST acceptance — 2026-11-13

PASS: the required native REST milestone executed successfully. A real hydrated
Next.js/React browser client performed all five operations against native S
business logic and real MySQL 8.0.46. Final integration process exit code: 0.

## Implementation and evidence

[Public API, ownership, configuration and limits](README.md),
[implementation ledger](plan.md), [raw evidence](evidence/).

The application database table is `shuwen.s_rest_users_v1` for this run.
Authentication succeeded over127.0.0.1:3306 as the configured test account
`shuwen@localhost`, with password supplied only through the environment.
No authentication plugin name is asserted: account plugin inspection was NOT RUN.
The existing native MySQL driver performs the protocol/authentication; no Python,
Node or Go code executes application SQL. The existing OpenSSL build bridge is
used for the driver's established native TLS/crypto boundary.

The existing `shuwen.users` table checksum and row count were compared before
and after final CRUD acceptance: identical (exit0). Its count remained5.
The isolated REST table had0 records remaining after cleanup. Test cleanup only
uses IDs created by the same run. The isolated empty schema remains available.
See [database metadata](evidence/database.log),
[before](evidence/existing-users.before.txt) and
[after](evidence/existing-users.after.txt).

## Commands, actual results and exit codes

Commands run from the S repository unless the frontend directory is specified.
Socket/browser/strace/DB tests ran in the authorized network-enabled environment.
No skipped required tests are counted as PASS.

| Status | Executed command | Actual result | Exit |
|---|---|---|---|
| PASS | `make rest-unit-check` | JSON, router, actual S business validator; each Seed+native | 0 |
| PASS | `make rest-http-check` | 7 test methods, real sockets on both Seed+native | 0 |
| PASS | `make http-integration-check` | original native HTTP12/12 | 0 |
| PASS | `S_HTTP_COMPILER="$PWD/bin/s_seed" python3 test/stdlib-native/test_http.py -v` | original Seed HTTP12/12 | 0 |
| PASS | `python3 -u test/stdlib-native/test_rest_integration.py` | all7 integration test methods, actual browser/Next/S/MySQL | 0 |
| PASS | frontend `npm test` | 10 proxy/method/header/query/limit tests | 0 |
| PASS | frontend `npm run typecheck` | TypeScript | 0 |
| PASS | frontend `NEXT_TELEMETRY_DISABLED=1 npm run build` | Next production build | 0 |
| PASS | `python3 test/stdlib-native/test_tcp.py -v` | 3/3 | 0 |
| PASS | `python3 test/stdlib-native/test_time.py -v` | 6/6 | 0 |
| PASS | `python3 test/stdlib-native/test_tls.py -v` | 4/4 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_compiler.py -v` | 4/4 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_protocol.py -v` | 5/5 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_values.py -v` | 1/1 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_auth.py -v` | 2/2 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_closure.py -v` | 1/1 | 0 |
| PASS | `sh test/mysql/run.sh` | existing S prepared temporary-table CRUD assertions | 0 |
| PASS | `bash test/native-bootstrap-diagnostic/canonical_mir_public_check.sh` | canonical MIR closure/native handoff | 0 |
| PASS | `bash test/native-bootstrap-diagnostic/native_record_borrow_check.sh` | escape/alias/effect/forgedIR rejection | 0 |
| PASS | `python3 test/stdlib-native/test_seed_borrow_integration.py -v` | 6/6 | 0 |
| PASS | `sha256sum -c doc/http/seed-compatibility/bootstrap-source-sha256.txt` | all269 compiler source hashes unchanged | 0 |
| PASS | `git diff --check` | tracked whitespace checks | 0 |
| FAIL | optional full application Seed `--compile-native-unit` with resolved closure | existing TCP/TLS/crypto borrowed-helper ambiguity | 1 |
| NOT RUN | full application runtime using Seed | optional compile above does not pass | — |
| NOT RUN | fresh full Seed→Stage4 bootstrap in this REST milestone | no compiler/runtime sources changed; conditional gate not triggered | — |

The previous official bootstrap remains historical PASS, documented at
[Seed acceptance](../http/seed-compatibility.md). This report does not claim a new
full bootstrap or REST application runtime on all bootstrap generations.

## Final actual integration output

The complete unedited run is [integration.log](evidence/integration.log), including
actual ephemeral ports and every browser network assertion. Terminal excerpt:

```text
browser: PASS — hydrated React CRUD, Unicode, duplicate 409, empty 204; test email ...@s-rest.invalid
PASS client reset isolated; listener remains live
PASS real database result-limit error -> JSON500 and cleanup
PASS 400/404/405/413/415 and JSON/ID/query validation
PASS parameter binding and duplicate update rollback
PASS all5 CRUD, Unicode, NULL/integer, generatedID, conflict, repeat via ...
PASS all5 CRUD, Unicode, NULL/integer, generatedID, conflict, repeat via ...
PASS S deterministic shutdown exit=0
Ran 7 tests in 57.477s
OK
```

The excerpt abbreviates only generated email/ports; the linked log is raw.

Browser assertions execute the production Next page with Chromium/Playwright:
GET list, POST201 (UTF8 data and stringID), GET item while editing, PUT200 to李四,
duplicatePOST409 visibly displayed, DELETE204 with empty body. Cleanup runs in
finally. Direct-S and Next-proxy HTTP clients each repeat all five CRUD operations
twice, preserve NULL/integer data, validate generated IDs, check duplicate conflicts,
and test unchanged updates plus missing-after-delete404. Real duplicateUPDATE409
is followed by GET confirming transaction rollback. Parameter-injection strings
remain data. The S INSERT/DELETE paths assert affected_rows1; the existing S CRUD
baseline separately asserts INSERT/UPDATE/DELETE1, last_insert_id1 and UTF8 values.

Real database500 uses a second instance configured with max_result_bytes1, causing
an actual native driver result-limit failure, followed by healthy shutdown. It does
not stop MySQL, alter credentials, damage schemas or substitute a fake database.

## RED → GREEN fixes

- Missing APIs: [HTTP RED](http-first-red.log), [router RED](router-red.log),
  [JSON RED](json-red.log), [service RED](service-first-red.log).
- HEAD errors originally sent a body: six native/Seed failures for413/400/408;
  preserve method on read errors; all seven HTTP test methods now pass.
  [Evidence](http-network-first-red.log).
- Real valid JSON users rejected: loop used preallocated node capacity instead
  of document.count; corrected with positive and negative business regressions.
  [Validator RED](validator-red.log), [CRUD RED](crud-first-red.log).
- Client reset killed the app with exit8: accepted-client failures are now
  distinguished from listener accept failures. [Reset RED](reset-red.log).
- JSON escaped/large strings initially timed out under a256MiB guard; raw span
  copying and balanced chunks fix quadratic accumulation. Both compilers execute
  the memory-capped large-string regressions.
- Prefix new private JSON/router helpers to avoid existing Seed leaf ambiguity;
  no compiler or established TCP/TLS/crypto edits. [Combined RED](combined-seed-red.log).
- Bind rollback return and parameter arrays before borrowing; explicit array
  semicolons retain Seed parsing compatibility. No check bypasses.
- Next proxy initially dropped query data and overwrote Content-Type; preserved
  both on a fixed upstream origin, with targeted failing regressions before fix.
  Proxy RED logs are retained in the frontend directory.

An initial frontend readiness test expected the wrong page title and an initial
restricted-sandbox socket test failed with EPERM. Both are harness/environment
failures, not claimed product failures or PASS results. Authorized network runs
and the corrected readiness check produced the final results above.

## Toolchain

- Installed native compiler SHA256:
  `7ba771c0dc3379845ccc359488f35300fb0035675782d726695a43763d1271e7`.
- Seed SHA256:
  `aa4a33be7a7ebabc66c4546daf6feff461e77a15bf4626749541340af725e2a8`.
- Node22.22.2; Next16.4.6; React19.3.1; TypeScript7.0.2;
  Playwright1.65.0; official Chromium158.0.8127.18.
- MySQL8.0.46-0ubuntu0.24.04.3.
- Versions/dependencies pinned in frontend package.json/package-lock.json.

## Files and repository boundaries

- Modified core: `src/std/http/types.s`, `protocol.s`, `server.s`.
- Added core: `src/std/http/lifecycle.s`, `src/std/rest/router.s`, `src/std/json/json.s`.
- Added application: `test/rest-users/main.s`, `repository.s`, `schema.sql`.
- Added frontend: `test/rest-users/frontend/` (Next routes/UI/proxy/config,
  package/lock, proxy tests and actual browser test; generated dependencies/build
  outputs ignored).
- Added tests: `test/rest/{http,json,router,server,users}.s` and
  `test/stdlib-native/test_rest_{http,integration,json,router,users}.py`.
- Added Make targets: rest-unit-check/rest-http-check/rest-frontend-check/
  rest-integration-check.
- Added documentation/RED/raw logs: `doc/rest/`.
- Existing uncommitted `doc/http/` work from the previous mission is preserved.
- No compiler/runtime edits. Go is read-only; its pre-existing deletion of
  `src/cmd/compile/profile.sh` is unchanged.

Read-only Go references: net/http/pattern.go (deterministic pattern conflicts),
net/http/transfer.go (length/framing/body ownership), encoding/json/scanner.go
(grammar/depth). The S implementation uses the existing bounded synchronous
model, without copying Go runtime, concurrency or garbage collection features.

## Remaining limits

The complete application is verified with the native compiler. Optional full Seed
compilation stops at `src/std/tcp.s:85:51`, unproven record borrow, because existing
TCP/TLS/crypto helpers share `_error`. A temporary source-only namespace experiment
then reaches another existing TLS intrinsic borrow-proof limitation. These verified
modules and the compiler were not changed to expand optional Seed TLS support.
[Exact actual failure](evidence/optional-seed-app.log).

Linux/amd64 IPv4, one connection/request, synchronous handling, fixed limits,
no chunked bodies, keepalive, concurrency, HTTPS, auth/authorization or public
production-deployment claim. Collection limited to100; no pagination beyond
bounded limit. q uses bound LIKE wildcard semantics. JSON documents are read-only
parse results with preserved-source serialization, not reflection or mutable builders.
The normal runtime owns general heap reclamation; no new whole-language memory
safety or linear-resource guarantee is asserted.
