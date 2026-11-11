# Native database implementation report — 2026-11-11

The mission is **incomplete**. This change implements concrete shared foundations
and independently executable MySQL/PostgreSQL protocol codecs. It does not provide
working native database connections or production-ready drivers. Exact prerequisites
and failing compiler probes are documented in [audit.md](audit.md).

## Architecture and files

- `src/std/database/types.s`: explicit NULL/value representations, exact integer and
  decimal validation, row values, execution metadata and structured portable errors.
- `src/std/database/lifecycle.s`: checked local resource/transaction bookkeeping;
  explicit close preflight. No native OS acquisition or cleanup is simulated.
- `src/std/database/rows.s`: validated owned buffered rows and explicit cursor close.
- `src/std/database/interfaces.s`: lowercase database/connection/query/exec/transaction/
  prepared-statement contracts; dynamic dispatch is a known compiler blocker.
- `src/std/database/wire.s`: generic bounded byte cursor, endianness, uint64 decimal
  decoding and checked integer encoding; sticky errors and overflow-safe boundaries.
- `src/std/mysql/protocol.s`: independent MySQL packet, handshake, metadata, row and
  prepared-command codecs. See [mysql.md](mysql.md) for implemented/unsupported paths.
- `src/std/postgresql/protocol.s`: independent PostgreSQL framing/startup/extended
  query/row/error/status codecs. See [postgresql.md](postgresql.md).
- `test/stdlib-native/database_test_support.py`, `test_database_{types,wire,contracts}.py`,
  `test_mysql_protocol.py`, `test_postgresql_protocol.py`, and the corresponding
  `database_*.s`, `mysql_*.s`, `postgresql_*.s` fixtures: real source compilation,
  native ELF execution, malformed-input/boundary/ownership tests and type rejection.
- `makefile`: additive `database-unit-check` target.
- `.github/workflows/database.yml`: dedicated native database protocol unit job.
- `doc/database/{design,audit,api,mysql,postgresql,implementation-plan,report}.md`:
  design, resource contracts, evidence and accurate feature limitations.

No compiler sources or existing selfhost/release workflows were changed by this work.
Existing changes and externally updated git state were preserved; no reset, stash,
branch change, merge, push or task-created commit was performed.

## Implemented functionality and SQL compatibility

MySQL: packet/sequence validation, full uint64 length-encoded integer parsing,
protocol-v10 handshake parsing, authentication-switch *parsing*, OK/ERR metadata,
ColumnDefinition41, text row framing, prepare-response parsing and actual protocol
parameter encoding for NULL/bool/int64/uint64/text/binary/decimal. Packet fragmentation,
full result stream state and binary result decoding are not implemented.

PostgreSQL: protocol-3.0 framing, SSLRequest/Startup, simple Query and Parse/Bind/
Describe/Execute/Close/Sync/Terminate encoding, all 65,535 parameters, RowDescription
with native OIDs, raw text/binary/NULL DataRow decoding, ParameterStatus,
CommandComplete counts, authentication-message *parsing*, ReadyForQuery statuses,
and error parsing with stable nonlocalized fatal severity.

The common value enum represents all requested value categories plus native future
values. These representations do not establish server type compatibility. Unsigned
integers and decimals preserve precision as text. Floats and temporal/JSON/UUID values
also retain text; their conversion/validation is unimplemented. Row decoders retain
raw text/binary plus metadata rather than claiming automatic numeric conversion.

Authentication mechanisms **completed: none**. No mysql_native_password,
caching_sha2_password, PostgreSQL MD5 or SCRAM/PLUS proof or full exchange exists.
No password bytes are sent or logged by this implementation.

TLS **not implemented**: encoding SSLRequest is not TLS negotiation, certificate
verification, hostname verification or channel binding. There is no insecure
credential fallback and no external database client library/process substitution.

## Verification results

| Check | Measured result |
| --- | --- |
| `make database-unit-check` | PASS: 5 shared database, 5 MySQL, 4 PostgreSQL tests; native seed compilation and executable assertions |
| `python3 test/stdlib-native/test_seed_borrow_integration.py -v` | PASS: 3 existing seed borrow/import tests |
| `python3 test/native-bootstrap-diagnostic/native_seed_int64_check.py` | PASS: existing signed-width/arithmetic/aggregate test |
| Database workflow YAML parsing | PASS locally; remote GitHub Actions not run |
| `make compiler` | FAIL before implementation: existing native borrow proof error; no `bin/s_compiler` emitted |
| `python3 -m unittest discover -s test/stdlib-native -p 'test*.py' -v` | FAIL: 22 tests, 4 failures and 7 errors; all database tests in this run passed |
| `python3 -m unittest discover -s test/bootstrap-reproducibility -v` | FAIL: 28 tests, 1 failure and 2 errors, all trace-related |
| MySQL real-server integration | NOT RUN: no working connection/TLS/authentication path |
| PostgreSQL real-server integration | NOT RUN: no working connection/TLS/authentication path |
| Full selfhosting convergence and release acceptance | NOT CERTIFIED: prerequisite compiler build is red |

The current unit tests were written before their corresponding implementation or
bug fix and observed failing. They include malformed/truncated lengths, every
handshake prefix, packet sequences, uint64/int64 limits, prepared NULL bitmap byte
boundaries, byte-string NULs, separate SQL/parameter fields, closure, parent/child
counts and failed transaction rules. No mock fixture is presented as integration.

### Existing standard-library failures (not hidden/skipped)

Failures:

- `test_collections.NativeCollectionsTests.test_native_and_seed_collection_contracts`
  (`seed=False`): existing compiler build error.
- The same test (`seed=True`): `src/std/collections.s:90:63`, expected
  `std.option.option[v]`, got `option[v]`.
- `test_string.NativeStringTests.test_api_boundaries_and_repetitive_search_native_and_seed`
  (`seed=False`): existing compiler build error.
- `test_string.NativeStringTests.test_deterministic_search_split_replace_against_python`:
  existing compiler build error.

Errors:

- `test_collections.NativeCollectionsTests.test_wrong_generic_values_and_keys_preserve_previous_outputs`
  (`seed=False`, both generic-value and key subcases): missing `bin/s_compiler`.
- `test_input.NativeInputTests.setUpClass`: missing `bin/s_compiler`.
- `test_snake.NativeSnakeTests.setUpClass`: existing compiler prerequisite unavailable.
- `test_string.NativeStringTests.test_intrinsic_wrong_array_type_is_rejected_without_replacing_output`:
  missing `bin/s_compiler`.
- `test_terminal.NativeTerminalTests.setUpClass`: missing `bin/s_compiler`.
- `test_time.NativeTimeTests.setUpClass`: missing `bin/s_compiler`.

Bootstrap reproducibility errors:

- `test_cleanroom.CleanroomTests.test_trace_accepts_canonical_host_assembler_symlink`.
- `test_cleanroom.CleanroomTests.test_trace_keeps_full_long_executable_paths`.
- Failure: `test_cleanroom.CleanroomTests.test_trace_rejects_delegation_to_another_compiler_or_program`.

Each trace case fails before its intended trace assertion; an independent strace
probe reports PTRACE_TRACEME denied by the sandbox. No tests were disabled or relaxed.

Logs from this execution are in `/tmp/s-database-unit.log`,
`/tmp/s-database-stdlib-final.log`, `/tmp/s-database-bootstrap-regressions.log`,
`/tmp/s-database-compiler-baseline.log`, `/tmp/s-database-seed-borrow-final.log`,
`/tmp/s-database-int64-regressions.log`, and `/tmp/s-database-audit/`.

## Safety, performance, CI and remaining blockers

Length and integer bounds, malformed packets, NULL distinctions, busy state,
child-count overflow checks, close states and terminal transaction checks execute
as native tests. Ownership rules are explicit but live handle safety, socket leak
freedom, interrupted I/O, deadlines, authentication-failure cleanup and connection
reuse cannot be certified without drivers and transport. No such guarantees are
inferred from local bookkeeping tests. Public structs cannot enforce unique OS
resource ownership; future drivers must encapsulate it.

Database throughput/latency, large live result sets, memory profiling, descriptor
leak testing, TLS adversarial tests, real-server version matrices and cross-driver
semantics were **not measured**. A large PostgreSQL parameter codec test is an
executable boundary test, not a database benchmark. MySQL encoder/row accumulation
is bounded but is not yet optimized for very large lists/results.

The added CI unit command passes locally. No remote CI run, integration job result
or full selfhost/release pass is claimed. Existing compiler acceptance gates remain
unchanged. Adding green "integration" jobs without live drivers would misrepresent
completion and has deliberately not been done.

The next required work is to fix the existing compiler build, make the native TCP
path usable with errno-preserving reads and deadlines, implement/verify TLS and
crypto/entropy prerequisites, and resolve or replace unavailable trait dispatch.
Then implement complete driver state machines, typed codecs and resource owners,
followed by real MySQL acceptance, real PostgreSQL acceptance and cross-driver,
security, memory and performance validation. These are outstanding mission criteria.
