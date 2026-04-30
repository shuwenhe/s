# S Stdlib Top 20 Implementation Plan

Program goal:
- Deliver industrial-grade baseline for 20 priority packages aligned with Go usage patterns.
- Keep command-line toolchain behavior stable with reproducible acceptance checks.

## Current Baseline (Repository Scan)

All requested package roots already exist under src:
- P0: fmt, errors, strings, strconv, bytes, io, os, path/filepath, time, context
- P1: sync, sync/atomic, net, net/http, net/url, encoding/json
- P2: testing, log, runtime/pprof, compress/gzip

Interpretation:
- Existing directories do not guarantee production-ready semantics.
- Priority is to freeze MVP API contracts and pass stable smoke tests per package.

## Delivery Strategy

- Phase 1: P0 package contract freeze + smoke green
- Phase 2: P1 service stack behavior + integration green
- Phase 3: P2 observability/testing/tooling reliability

Definition of done for each package:
- API MVP list documented
- At least 1 package smoke test in stable suite
- At least 1 failure-mode test (invalid input or edge case)
- No command behavior drift in s build, s run, s test, s fmt, s lint

---

## P0 (Direct Usability)

### 1. fmt
MVP:
- print, println, sprintf-like formatting for int, string, bool
- deterministic formatting for composite values
Acceptance:
- hello app output stable
- format mismatch tests fail predictably

### 2. errors
MVP:
- new, wrap, unwrap, is semantics
Acceptance:
- wrapped error chain assertion test

### 3. strings
MVP:
- contains, has_prefix, has_suffix, split, join, trim_space
Acceptance:
- utf-8 safe baseline for common operations

### 4. strconv
MVP:
- atoi, itoa, parse_int, format_int, parse_bool
Acceptance:
- invalid parse errors are stable and typed

### 5. bytes
MVP:
- buffer append/read/reset
Acceptance:
- deterministic byte growth behavior and bounds checks

### 6. io
MVP:
- reader, writer, copy semantics
Acceptance:
- copy loop correctness with EOF behavior

### 7. os
MVP:
- args/env/file open/read/write/stat/remove
Acceptance:
- path and permission failure tests stable

### 8. path/filepath
MVP:
- join, clean, base, dir, ext
Acceptance:
- cross-platform path normalization tests

### 9. time
MVP:
- now, unix conversion, duration arithmetic, sleep
Acceptance:
- duration and parse/format consistency tests

### 10. context
MVP:
- background, with_cancel, with_timeout, cancellation propagation
Acceptance:
- cancellation timing behavior under scheduler stress

---

## P1 (Service and Engineering)

### 11. sync
MVP:
- mutex, rwlock, once, waitgroup
Acceptance:
- no-race smoke with deterministic join points

### 12. sync/atomic
MVP:
- add/load/store/cas for int and pointer-like values
Acceptance:
- monotonic counter under contention

### 13. net
MVP:
- tcp dial/listen minimal path
Acceptance:
- loopback server/client smoke test

### 14. net/http
MVP:
- server, client get/post, status and header handling
Acceptance:
- handler + client integration smoke

### 15. net/url
MVP:
- parse, query encode/decode, resolve reference
Acceptance:
- reserved character round-trip tests

### 16. encoding/json
MVP:
- marshal/unmarshal for primitives, structs, arrays, maps
Acceptance:
- invalid json error diagnostics stable

---

## P2 (Testing and Operations)

### 17. testing
MVP:
- test runner hooks, assertions, subtests baseline
Acceptance:
- package-level test orchestration stability

### 18. log
MVP:
- leveled text output and timestamp formatting
Acceptance:
- deterministic line format and writer redirection

### 19. runtime/pprof
MVP:
- cpu and memory profile capture hooks
Acceptance:
- profile files generated and parseable

### 20. compress/gzip
MVP:
- compress/decompress stream path
Acceptance:
- round-trip integrity and invalid stream errors

---

## Unified Acceptance Matrix

Global acceptance command set (must pass before release candidate):
- s fmt src
- s lint src
- s test
- s test --all

Package smoke command template:
- s test <fixtures_root_for_package>

Release gate:
- P0 all green is mandatory for industrial baseline claim.
- P1 and P2 can be staged, but each package requires explicit stability label.

## Recommended Execution Order (8-12 Weeks)

Week 1-2:
- Freeze P0 API surface and complete fmt/errors/strings/strconv

Week 3-4:
- Complete bytes/io/os/path/filepath/time/context and lock smoke tests

Week 5-8:
- Complete P1 net stack and json + concurrency primitives

Week 9-12:
- Complete P2 testing/log/pprof/gzip and finalize release gate docs
