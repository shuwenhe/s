# Real database connectivity execution plan — 2026-11-11

Preserve the existing uncommitted documentation/interface changes and all database
codec tests. Work in the requested checkout, without changing branches or committing.

1. Reproduce canonical compiler failure; reduce to a regression using actual
   compiler-source-list; make the smallest build/semantic correction and verify
   make compiler plus compiler and all 14 database tests.
2. Trace Seed intrinsic resolution, ABI and runtime linkage. Reuse existing OS
   operations; implement a checked TCP interface for both compiler ABIs and test
   real loopback connect/accept/read/write/partial/EOF/close/refusal/timeouts.
3. Add crypto primitives and published known-answer tests; use OS secure entropy.
4. Evaluate a documented OpenSSL runtime dependency with certificate/hostname and
   expiry tests; never replace validation with initialization-only success.
5. Implement MySQL connection state over existing codecs and verify a real server.
6. Then implement PostgreSQL connection/authentication and real-server acceptance.

Each implementation starts with a failing executable regression. Existing gates
remain intact. Record exact environmental or implementation blockers, with commands;
keep local tests, remote CI and integration evidence distinct. Stop only on a concrete
reproducible blocker, not after a design-only handoff.

## Progress

- Canonical root cause: explicit make compiler manifest omitted generated
  native_runtime_extensions.s, leaving two actual function callees undefined.
  Added manifest-based executable regression; observed RED then GREEN after adding
  the single missing source. Borrow checking is unchanged. make compiler now emits
  bin/s_compiler successfully.
