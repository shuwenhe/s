> Historical HTTP milestone report: the Seed failure and bootstrap status below
> are superseded by [Seed compatibility acceptance](seed-compatibility.md).

# HTTP first-slice results — 2026-11-13

**PASS: native HTTP health-server milestone on Linux/amd64 with the installed
native compiler.** This is bounded synchronous GET/HEAD serving, not full HTTP/1.1
compliance or production readiness. The acceptance command rebuilt the unchanged
compiler before testing. `make http-integration-check` exited **0**, **12 tests**.
See [acceptance.log](acceptance.log) for the complete test output and
[evidence.json](evidence.json) for source/compiler fingerprints.

## 1. Reference roots and Go study

Both verified Git roots: `/home/shuwen/shuwen/go` (read-only) and
`/home/shuwen/shuwen/s`. User corrected the initially unavailable `/home/shuwen/go`.
The Go working tree had an existing `D src/cmd/compile/profile.sh` at audit start;
the final status is identical. No Go source was written or executed by this task.

Studied contracts in the following local files:

| Go source | Functions/contracts studied |
|---|---|
| `src/net/tcpsock.go` | TCPListener.Accept/AcceptTCP/Close/SetDeadline |
| `src/net/tcpsock_posix.go` | accept/newTCPConn, close and listener creation ownership |
| `src/internal/poll/fd_unix.go` | FD.Close, reference lifetime, read/write nonblocking operations |
| `src/internal/poll/fd_mutex.go` | closed bit, read/write locks, increfAndClose and wakeups |
| `src/internal/poll/fd_poll_runtime.go` | SetDeadline/SetReadDeadline/SetWriteDeadline |
| `src/net/http/request.go` | readRequestLimit, request-line/URI parsing, duplicate Host |
| `src/net/http/transfer.go` | readTransfer, body length, transfer coding/framing ambiguity |
| `src/net/http/server.go` | Serve, header caps, deadlines, response length, Shutdown |
| `src/net/http/request_test.go` | bad Host/header serialization tests |
| `src/net/http/serve_test.go` | Host/header validation, timeouts and shutdown cases |
| `src/net/http/transfer_test.go` | truncated body/trailer/framing tests |
| `src/encoding/json/decode.go` | codec boundary, allocations and duplicate-key semantics |
| `src/context/context.go` | cancellation/deadline propagation and cleanup contract |
| `src/sync/mutex.go` | synchronization and no-copy contract |
| `src/crypto/tls/conn.go` | secured-connection layering and handshake synchronization |
| `src/database/sql/sql.go` | pool ownership, limits and cancellation boundaries |

HTTP protocol authority: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html)
(message parsing/framing/connection lifetime) and
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) (method/status/HEAD semantics).
No mechanical Go translation, GC, scheduler or netpoll runtime was introduced.

## 2. S capability audit

Labels apply only to the stated verified scope; source existence is not PASS.

| Result | Capability and exact evidence |
|---|---|
| PASS | `src/std/tcp.s` + `src/runtime/native_tcp.h`: existing `test/stdlib-native/test_tcp.py`, 3 tests with both Seed/native compiler; real listen/accept/read/write/EOF/refusal/partial writes/timeouts/close |
| PASS | `src/std/time.s`: authorized `test/stdlib-native/test_time.py`, 6 tests including real interruptions and strace fault injection |
| PASS | `src/std/tls.s` + `src/runtime/native_tls_openssl.c`: existing `test_tls.py`, 4 real certificate/TLS tests |
| PASS | Native compiler/MIR: `canonical_mir_public_check.sh`; normal MIR/SSA/native artifact verification and source-dependent output |
| PASS | Borrow regression scope: existing `test_seed_borrow_integration.py`, 3 tests including invalid-owner/scope rejection |
| PASS | MySQL compilation scope: existing `test_mysql_compiler.py`, 4 tests; no database records were touched in this HTTP task |
| NOT RUN | Real MySQL integration on this revision during this task; prior thread results are not substituted for a fresh run |
| NOT RUN | Prior `src/net/http/server.s` implementation: inspected and found to only print a listener message, not a functional HTTP server |
| NOT RUN | General JSON codec: inspected `src/encoding/json/encode.s` and `decode.s` are unit-name/ready stubs; health uses constant JSON |
| NOT RUN | Context/sync primitives: inspected `src/context/context.s`, `src/sync/mutex.s` are stubs; `src/net/sroutine_demo.s` exists but concurrency was not validated |
| NOT RUN | Broad heap reclamation, all ownership/lifetime behavior and concurrency safety; passing socket and borrow tests does not establish these |
| PASS | New `src/std/http/{types,protocol,server}.s`: complete installed-native slice acceptance below |

The first time-suite attempt in the default sandbox executed and failed with 11
subcase failures caused by `strace: PTRACE_TRACEME: Operation not permitted`.
Those cases were `test_eintr_restarts_remaining_sleep`,
`test_exact_int64_duration_boundary_reaches_os_without_wrapping` and
`test_kernel_errors_are_propagated`. The supported approved execution request
then ran the unchanged suite successfully (6 tests, exit 0). No test or security
code was weakened to evade that restriction.

## 3–4. Selection and architecture

Selected HTTP because its synchronous TCP prerequisites passed real integration.
A concurrent general stack would depend on unverified synchronization/context
support. Reworking TCP was not justified by a demonstrated blocker in its tested
single-owner use. General JSON is unnecessary for the constant health payload.

Go uses goroutines, netpoll, fd locks/reference counting, context and GC-managed
request objects. S reuses its existing `std.tcp` name/conventions rather than
inventing a `std.net` compatibility facade. A server owns one listener and each
synchronous exchange owns one accepted connection; every outcome closes that
connection. Read deadlines remain absolute across progress and scheduler pauses;
TCP write_all provides a total write deadline. Polling accept returns control to
the application, which calls shutdown between exchanges.

Shutdown acceptance is specifically owner-controlled, after a completed exchange:
full response reaches the client, accepted connection closes, listener closes,
second shutdown succeeds, serve-after-close returns errno 9, reconnect fails.
There is no claim of asynchronous shutdown interrupting an active call.

## 5–6. Implementation and tests

- `src/std/http/types.s`: limits/options, request/response/error/exchange/server,
  configuration validation and ownership contract.
- `src/std/http/protocol.s`: bounded strict-CRLF parsing, method/header tokens,
  Host validation, CL/TE ambiguity checks, fixed health routing, response byte
  lengths, HEAD and safe fixed response headers/statuses.
- `src/std/http/server.s`: listener, incremental header scan, absolute deadline
  including a post-read clock check, bounded response writing, per-client cleanup
  and owner-controlled shutdown.
- `test/http/protocol.s`: native S protocol/UTF-8/framing assertions.
- `test/http/server.s`: native S real-socket lifecycle/deadline fixture.
- `test/http/health/main.s`: executable example using ordinary import resolution.
- `test/http/seed-borrow-repro/main.s`: minimal caller exposing Seed FIRST RED.
- `test/stdlib-native/test_http.py`: 12 native protocol/real-TCP acceptance tests.
- `makefile`: `http-unit-check` and `http-integration-check` targets.
- `doc/http/`: design, plan, usage, evidence and result documentation.

No compiler, runtime, TCP, TLS, MySQL or other standard-library implementation
was modified. A source commit (`edfa2ae51 fix:net`) appeared externally during the
work; the final gate ran against the actual current source plus remaining edits.
This task did not create commits, reset, merge or alter that external commit.

TDD evidence:

- [first-red.log](first-red.log): protocol fixture fails compilation before
  std.http implementation exists (missing API causes undefined semantic bindings).
- [host-red.log](host-red.log): five malformed Host authority cases accepted
  before strict authority validation; all now rejected with 400.
- [deadline-red.log](deadline-red.log): real child-process scheduler pause lets
  final completed headers exceed the deadline; expected 408, observed 200 before
  the fix. New post-read monotonic check makes the regression pass.
- Response-write fixture first failed compilation before `write_response` existed;
  it now verifies errno 110 with a nonreading real TCP peer and a 16 MiB response.

## 7. Executed acceptance and regression results

| Result | Command/check | Exit/evidence |
|---|---|---|
| PASS | `make http-integration-check` | 0, 12 tests; compiler rebuild included |
| PASS | Health JSON/CRLF/Content-Length | 200, body exactly `{"status":"ok"}`, 15 bytes |
| PASS | Fragmentation, query target, HEAD and routing | complete responses, 404/405, Allow header, HEAD no body |
| PASS | Malformed Host/header/framing and limit matrices | 400/413/414/417/431/501/505 as asserted |
| PASS | Accept timeout, idle/slow headers, scheduler pause | errno 110/HTTP 408 without progress-based deadline extension |
| PASS | Response backpressure timeout | 16 MiB response to nonreading peer -> errno 110 |
| PASS | EOF, peer reset and subsequent healthy request | listener remains usable |
| PASS | 48 success/error exchanges in one process | no accumulating descriptors; pipeline never served as another request |
| PASS | Native S protocol fixture | UTF-8 `你好` response length 6, exact wire assertions |
| PASS | `bin/s build test/http/health/main.s -o /tmp/s-http-health` | 0; normal source closure and true-selfhost verification |
| PASS | Documented health example with real TCP client | exit 0, `SHUTDOWN`, subsequent connection refused |
| PASS | Existing TCP suite | 0, 3 tests, Seed and installed-native ABI cases |
| PASS | Existing authorized time suite | 0, 6 tests |
| PASS | Existing TLS suite | 0, 4 tests |
| PASS | Existing MySQL compiler suite | 0, 4 tests |
| PASS | Existing Seed imported borrow regression | 0, 3 tests |
| PASS | `canonical_mir_public_check.sh` | 0 |
| PASS | `git diff --check` | 0 |

Actual health-example output (CRLF shown as separate lines):

```text
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15
Connection: close

{"status":"ok"}
SHUTDOWN
HEALTH_EXAMPLE_EXIT_CODE=0
PASS: listener closed after application-controlled shutdown
```

## 8. Compiler and bootstrap status

Installed/rebuilt native compiler SHA-256:
`7ba771c0dc3379845ccc359488f35300fb0035675782d726695a43763d1271e7`.

- **PASS**: installed native compiler builds/executes the complete slice;
  artifact verifier accepts both protocol/server binaries and the example.
- **PASS**: Seed separately compiles and executes the S protocol fixture
  (types/protocol/TCP/time/result/prelude sources, exit 0).
- **FAIL**: Seed full-server compile exits 1 at
  `src/std/http/server.s:79:5`, nested `_read_request(connection*,config)`,
  `unproven record borrow: escaping handle or unsupported call/body`.
  See [seed-first-red.log](seed-first-red.log). The minimal caller creates an
  already-closed server and never opens a socket; it executes with exit 0 using
  the installed native compiler. Root cause within Seed's proof pipeline is not
  resolved here; it is not asserted to be a safe operation merely because the
  other compiler accepts it. No Seed-server compatibility is claimed.
- **BLOCKED**: Seed end-to-end HTTP execution by that preflight rejection.
- **NOT RUN**: fresh Seed->Stage1->Stage2->Stage3->Stage4 bootstrap/convergence.
  No compiler or runtime source changed, so the conditional compiler-change
  bootstrap gate was not invoked. Historical bootstrap results are not reused.
- **NOT RUN**: the whole repository's unrelated test targets; the relevant gates
  above are the executed verification scope.

## 9–10. Limitations and next milestone

Only Linux/amd64 IPv4, hostname/IPv4 Host authorities, origin-form targets,
GET/HEAD and one bodyless exchange per connection. Bodies/chunking, persistent
connections, Date generation, IPv6 Host, HTTPS, general JSON, callbacks/general
routing, asynchronous signals/context shutdown and concurrent serving remain
outside this milestone. No throughput or production-readiness claim is made.
Socket ownership is an API contract consistent with std.tcp; this is not a new
compiler-enforced linear resource system. Heap-wide reclamation and general
memory-safety claims are NOT RUN.

Recommended next milestone: isolate and resolve Seed full-server borrow-proof
compatibility with its own regression and the full bootstrap gate if compiler
changes are needed. Bounded bodies/chunked framing can follow separately. Do not
start either work item automatically. This first native health slice stops at
the verified acceptance boundary.
