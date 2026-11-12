# Native MySQL implementation plan and test matrix

User-selected design: pure S Classic Protocol, no libmysqlclient. Execute continuously in the requested checkout. See design.md and README.md for interfaces and limits.

## Incremental plan
1. Reuse/verify TCP, TLS and crypto. Add independent native/SHA2 vectors and RSA-OAEP interoperability tests before authentication implementation.
2. Implement bounded packet transport, real connection/auth state machine and TLS upgrade; provision isolated MySQL 8.0 and 8.4.
3. Implement query/exec, metadata, exact typed results and bounded buffering; verify real CRUD and recovery after SQL errors.
4. Implement server-side prepare/bind/execute/close, binary results, ownership and transactions; verify exact types and commit/rollback.
5. Deliver API docs/examples, reproducible provisioning/testing/benchmark scripts. Run native stdlib and compiler bootstrap regressions and independent review. Record every unresolved acceptance item.

## Test matrix
| Area | Independent local checks | Real 8.0 and 8.4 |
|---|---|---|
| native/SHA2 auth | known-answer SHA1/SHA256 tokens, unsupported plugin, scramble bounds | correct/wrong password, auth switch, SHA2 cold/full/fast cache |
| RSA | random OAEP ciphertext decrypted independently, PEM/DER bounds | non-TLS full authentication, pinned key/retrieved key, deny untrusted cold auth |
| TLS | existing real SSL-peer certificate tests | native and SHA2 TLS, hostname rejection |
| CRUD | packet/metadata/error codecs | CREATE/INSERT/SELECT/UPDATE/DELETE, SQL error then successful query |
| Values | signed/unsigned extremes, decimal, binary row, temporal precision, malformed rows | BIGINT, DECIMAL, VARCHAR/TEXT, BLOB, DATETIME, NULL/empty, UTF-8/Chinese |
| Prepared | COM_STMT packet and binding fixtures | prepare/reuse/binary query/wrong count/wrong owner/closed duplicate |
| Transactions | lifecycle fixtures | begin/commit/rollback and persisted/rolled back row counts |
| Limits/lifecycle | malformed packet and sequence fixtures | timeout, server KILL, result bounds, repeated close |
| Toolchain | rebuilt Seed protocol/value tests, canonical regression | driver builds and runs with native Stage1/Stage2/Stage3; fresh bootstrap acceptance |
| Performance | no synthetic substitutes | sequential PING/SELECT/prepared SELECT, TCP/TLS, server/compiler identity |

## Execution ledger
- Initial repository status clean; work remains in the requested checkout. User explicitly delegated choices and continuous execution.
- Existing installed Seed/canonical compiler binaries predated source; rebuilt Seed and a native Stage1 from current compiler sources.
- Narrow compiler fix required: annotation of qualified global constants incorrectly inferred namespace prefixes as values. Regression fails before fix and passes after; enum constructors remain enum members.
- Source resolver fixes required for external absolute client paths and unrelated `main` packages. Sibling source preservation has a behavioral regression test.
- Declaration-only trait interfaces isolated in std.database.contracts; common options moved to std.database/types.s so concrete clients can compile without unsupported dynamic traits.
- Existing TLS C startup did not initialize S argc/argv/envp. TLS builder now assembles the canonical raw assembly and supplies process initialization. Independent env regression failed (99), then passed.
- Auth vectors and independent RSA decryption passed in Seed and canonical compiler. Binary value fixture passed in Seed.
- Initial real 8.0/8.4 suite: CRUD, native auth, prepared transactions, ownership, limits, disconnect, timeout and TLS passed. Non-TLS RSA authentication exceeded the test's 2-second connect deadline; optimized modular exponentiation to Montgomery multiplication and rerunning.
- Independent review found fatal malformed-ERR handling and temporal fractional precision issues; fixes and regression coverage in progress.
- Whole native stdlib baseline exposed unrelated Seed collections generic alias failure and missing external Snake source. Existing bootstrap artifact test expects supported if-statements to be rejected; reported separately rather than weakening it.
- Final Stage1 real-server matrix: 21 cases passed on each of MySQL 8.0.46 and 8.4.8; TCP/TLS benchmarks passed. Both example programs executed successfully over TLS; ldd confirms no MySQL client library.
- Montgomery RSA replaced double-and-add after the cold-auth deadline regression; independent canonical RSA encryption/decryption passes and native execution measured 0.307s.
- Review fixes verified: fractional DATETIME/TIME precision retained, malformed ERR closes live connection, ordinary SQL errors remain reusable. Additional regression verifies outbound command bounds preserve synchronization and auth bounds close incomplete connections.
- NeurX before/after suites have identical 3 errors across 16 tests; missing runner and unsupported existing string escape. No NeurX source edits.
- Fresh full bootstrap restarted after the narrow compiler annotation fix; only Seed→Stage1 accepted so far. Stage2/Stage3 and convergence remain pending, with automatic real-server matrices scheduled per emitted stage.

- 2026-11-13: final driver source hashes match across all 6 real-server runs: Stage1/Stage2/Stage3 × MySQL 8.0.46/8.4.8, each 22 cases and TCP/TLS benchmarks passed.
- Added real cross-connection COMMIT visibility, explicit rollback and rollback-on-close/lock-release checks. All three stages passed.
- MySQL-generated PEM terminal NUL reproduced as an auth failure, normalized through a local S binding, then independently decrypted and authenticated successfully in real-server tests. Seed parameters remain immutable.
- Corrected Docker readiness from initialization Unix socket to final TCP listener; the image entrypoint confirms its temporary server uses --skip-networking. Corrected runner separately passed both real versions using Stage3.
- Final Stage3 standard-library run: 88 tests, 1 unchanged Seed collections failure, 1 missing external Snake class error, 22 unconfigured integration skips, 1 explicit known Seed enum-argument expected failure. Final NeurX run: same 3 errors across 16 tests as baseline.
- Stage2 and Stage3 compiler binaries match byte-for-byte (SHA256 783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73). Stage4 code generation still running.

- COMPLETE 2026-11-13: fresh bootstrap script exited 0, Seed -> Stage1 -> Stage2 == Stage3 == Stage4. ELF/assembly convergence, source dependence/execution, and integrity of all 269 compiler inputs passed. Proof archived in verification/bootstrap-results.json and bootstrap-final.log.
- All requested delivery files are present. Final source audits and git diff --check passed. Independent review findings were fixed; no review findings remain deferred. The separately documented baseline failures are not marked green.
