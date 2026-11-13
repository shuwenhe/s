# Native Redis local acceptance results

Date: 2026-11-13 (Asia/Shanghai). Scope: Linux amd64, this checkout's native and
Seed compiler binaries, local Redis 7.0.15 and the installed OpenSSL. Exact hashes
and versions are in evidence/toolchain.sha256 and evidence/environment.txt.

## Current S-only test path

All seven files under `test/redis` are now `.s` source files. Removed the five
Python helpers and the two Redis Python discovery wrappers. The Make targets
invoke `misc/scripts/check-redis.sh`, which builds native S executables through
`misc/scripts/build-redis-test.sh`. Shell only manages compiler/server processes,
temporary certificates and cleanup; assertions and adversarial TCP peers are S.
The builder uses the existing verified OpenSSL runtime bridge and the same startup
adapter as the repository's earlier builder. Compiler/runtime sources are unchanged.

`make redis-check` exited 0 with `python` and `python3` shadowed by executable
guards that fail with exit 125. See `evidence/s-only-make-check.log`. Both protocol
compiler ABIs, TCP integration, standalone sample, all nine S fault peers, TLS
integration and certificate/hostname rejection pass. An independent reviewer also
ran `sh misc/scripts/check-redis.sh all` successfully and found no lost assertions
or correctness issue. The initial failed entry-point migration is recorded in
`evidence/s-only-red.log`; the passing migration run is `s-only-acceptance.log`.

The older logs below preserve the original implementation history; they are not
instructions to use the deleted Python files. Current commands are in README.md.

## Verified

- Before implementation: TCP (3), TLS (4), JSON (1, both compiler ABIs), database
  types (3), database wire (1), MySQL protocol (5) passed. See baseline.json.
- RESP2 protocol assertions pass with both Seed and native compilers: every RESP2
  kind, nested arrays/errors, null versus empty, NUL/CRLF/non-UTF-8 bulk data,
  byte-at-a-time input, signed integer endpoints and overflow, optional positive
  integer sign, invalid length signs, framing, trailing/truncated input, and
  frame/bulk/array/depth/node bounds.
- Real isolated Redis TCP and TLS: authentication success/failure, ACL username
  auth, SELECT, PING, SET/GET/missing/empty/64-KiB/binary/UTF-8 values, DEL/EXISTS,
  EXPIRE/TTL/PERSIST/TYPE, EX/PX and NX/XX, hash/list/set wrappers, MULTI/EXEC,
  DISCARD, empty EXEC, WATCH conflict, nested command errors, queue errors and
  EXECABORT, ordered pipelining including error replies, and connection reuse.
- Actual TLS Redis rejects a wrong certificate hostname and an untrusted CA.
- Fault peers validate fragmented frames, malformed bulk terminators, oversized
  length, truncated data, disconnect, total read timeout under a slow trickle,
  unexpected typed reply, nonfatal Redis errors and peer-observed socket close.
- Existing regression suites pass after implementation: TCP (3), TLS (4), JSON
  (1), database types (3), database wire (1), MySQL protocol (5), imported borrow
  ownership (6), existing service validator (1). See regressions.json and logs.
- Standalone sample compiles through the native compiler/OpenSSL bridge.
  `make redis-check` also builds and runs it against isolated local Redis.
- Independent read-only review found no critical or important correctness issue.
  Final command results, rather than the reviewer's overlapping test run, provide
  the validation evidence.

`evidence/make-redis-check.log` is the original Make entry-point run before migration.
`evidence/acceptance.log` records the four direct runner groups. Python counts
represent grouped test programs, not counts of every S assertion.

## RED to GREEN

Tests were written before protocol/client implementation. Initial absent-module
failures are in protocol-red.log and integration-red.log. Subsequent focused RED
runs caught plus-signed integers, malformed negative length spellings, command
name bounds and TLS failure handle state. The first TLS failure returned a stale
copy of the connection before cleanup; cleanup now finishes before constructing
that return tuple. Logs: signed-integer-red.log, length-grammar-red.log,
command-bounds-red.log, tls-red.log. Final Make acceptance covers all fixes.

## Limits and blocked coverage

Full client compilation with Seed is BLOCKED at its record borrow proof boundary
(`std.redis.close`/existing networking helpers); protocol-only Seed compilation
passes. A compile-only reproduction is recorded in seed-integration-blocked.log.
The existing rest/http evidence independently documents the networking borrowed
helper ambiguity. No compiler/runtime code was changed, and no validation was
bypassed. Official bootstrap was not run because there was no compiler/runtime
change. This is not a claim of complete Seed client compatibility.

No Redis version matrix, cluster service, DNS/IPv6, production load benchmark,
concurrency safety or general heap reclamation certification was performed.
The parser's bounded accumulated string may be recopied on fragmented feeds;
there is no claim of linear total copying or production throughput certification.
The checked-in CI workflow was added but not run on a remote CI service.

All Redis servers used for tests were temporary loopback processes with no disk
persistence. Real credentials, existing Redis data and unrelated repositories
were not used. No examples directory was created.
