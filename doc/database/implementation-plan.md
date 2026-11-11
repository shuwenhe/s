# Native Database Implementation Plan

**Goal:** implement the shared database foundation, then native MySQL and PostgreSQL
only when transport, crypto and compiler prerequisites are demonstrably usable.
**Architecture:** concrete common data types and explicit lifecycle bookkeeping;
independent bounded protocol codecs; driver contracts use existing S traits.
**Spec:** user mission and `doc/database/design.md`.

## Constraints

Preserve existing changes and compiler checks. No external database client libraries,
no invented language features, no fabricated successful I/O, no unsafe credentials.
Use test-first native compilation and executable tests. Work in the user-designated
checkout; do not commit or change the user's branch as incidental bookkeeping.

## Review focus

Length arithmetic before indexing; SQL NULL versus exhaustion; precision and unsigned
values; ownership transitions after failure; unavailable runtime functions must fail.

## Tasks

- [ ] Audit compiler, networking, crypto, TLS, buffers, errors, native tests and CI;
  preserve exact failing commands in `doc/database/audit.md`.
- [ ] Add `test/stdlib-native/test_database_types.py` and native S fixtures for values,
  buffered rows, checked integer conversion and lifecycle; observe missing-source RED.
  Implement `src/std/database/{types,rows,lifecycle,interfaces}.s`, then execute GREEN.
- [ ] Add bounded byte cursor tests; implement `src/std/database/wire.s` using existing
  string byte/slice primitives; run malformed and boundary inputs as native executables.
- [ ] Add MySQL packet/handshake/result/command codec tests before implementation in
  `src/std/mysql/protocol.s`. Preserve uint64 precision and distinguish NULL.
- [ ] If transport/TLS/compiler prerequisites work, implement MySQL driver and run real
  server tests; otherwise record exact blockers and never imply integration passed.
- [ ] Only after stable shared/MySQL work, implement PostgreSQL. Do not certify live
  behavior until native transport, verified TLS, crypto and real server tests work.
- [ ] Add a dedicated database unit CI job without weakening existing workflows.
  Integration jobs require working drivers; do not create green fake integration jobs.
- [ ] Run existing available seed regression tests, attempt native suite and full
  compiler checks, review diff, report measured results and remaining blockers.


## Execution ledger

- Audit complete with reproduced compiler/runtime prerequisites in `audit.md`.
- Common values/rows/lifecycle tests observed RED, then passed native compilation
  and execution. Wrong API types reject without replacing prior outputs.
- Wire cursor tests observed missing-source RED, then passed native execution.
- MySQL codec tests observed RED, then passed. Boundary tests exposed unsupported
  hex escapes and SQLSTATE validation gaps; both fixed with RED-to-GREEN evidence.
- PostgreSQL codec tests observed RED, then passed. Independent review found the
  parameter count ceiling; 32,768/65,535/65,536 tests observed RED then GREEN after
  fixing the limit and using balanced concatenation. Fatal error severity ordering
  and malformed SQLSTATE/duplicate severity were fixed with failing tests first.
- Added isolated database unit workflow and `make database-unit-check`; existing
  selfhost/release workflows and compiler sources are unchanged.
- Full native standard library run remains failing; all failures, incomplete
  acceptance criteria and exact evidence commands are recorded in `report.md`.
- Live drivers, real-server integration, TLS/authentication, full resource safety,
  cross-driver database semantics and performance certification remain BLOCKED.
