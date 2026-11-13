# Native HTTP first vertical slice

Reference repository: `/home/shuwen/shuwen/go`, read-only, verified Git root.
S repository: `/home/shuwen/shuwen/s`, verified Git root. User mission is the
specification; implement one bounded native health-server slice, with real TCP
integration and no semantic/runtime shortcuts.

## Audit and choice

Existing `std.tcp` has real native listen/accept/IPv4/partial I/O/EOF/close and
monotonic operation deadlines (`src/std/tcp.s`, `src/runtime/native_tcp.h`). Its
3 integration tests passed for both Seed and installed compiler on this revision.
It requires one owner per live socket; the API documents that sockets must not
be copied. This slice keeps the listener in its server and each accepted socket
in one synchronous call; it never shares a live socket between workers.
`src/net/http/server.s` only prints; `src/encoding/json/{encode,decode}.s`,
`src/context/context.s`, `src/sync/mutex.s` are placeholders, not verified modules.
The health JSON is a constant: a JSON codec is not a prerequisite for this endpoint.
TLS is a separate existing OpenSSL boundary (`src/std/tls.s`), not used here.
S native ownership/MIR regression checks remain applicable; broad concurrency
and general memory-safety claims are NOT RUN. No compiler changes are planned.

Options considered: implement a general concurrent HTTP stack (depends on
unverified synchronization/cancellation APIs); change TCP ownership/runtime
(first prove a blocker; current tested single-owner contract suffices here);
implement bounded synchronous HTTP on existing TCP (selected, least new machinery
for the requested endpoint). Do not alter TCP ownership, networking security,
compiler checks, or Go sources to make tests pass.

## API and behavior

New `std.http` package: `types.s`, `protocol.s`, `server.s`.
`options`, `server`, `request`, `response`, `http_error`, `exchange` records.
`listen(options) (server,http_error)`, `local_port(server*) (int,http_error)`,
`serve_next(server*) (exchange,http_error)`, `shutdown(server*) http_error`.
`parse_request(string,options) (request,http_error)`,
`serialize_response(response,bool) (string,http_error)` and
`route(request) response` (health and 404/405, no general callback router yet).

Header bytes/line length/header count are bounded. Require CRLF, valid method
and header tokens, origin-form target, exactly one valid nonempty Host and
HTTP/1.1. Reject obsolete folding, controls, invalid/duplicate Content-Length,
Transfer-Encoding + Content-Length, unsupported body/transfer encoding and
Expect. Reject malformed percent escapes and fragments. Close after every
response; never reuse surplus bytes as a second request. Health body is exactly
`{"status":"ok"}` (15 bytes), with application/json and calculated byte length.
Support GET and HEAD for health; HEAD has the same length and no body.

Read deadline is absolute across fragmented headers, not reset by each byte;
write_all uses TCP's total deadline. All accepted sockets close on success,
protocol rejection, timeout, EOF and transport failure. Listener close is
idempotent. Shutdown is synchronous/application-controlled: the application calls
it after `serve_next` returns, with the previous exchange already drained to the
bounded write operation and closed. No asynchronous signal handling or concurrent
shutdown promise is introduced. The caller can poll accept with a finite timeout
and decide when to stop. Never expose an unauthenticated shutdown HTTP route.

Default: IPv4 loopback, port 0 allowed, backlog 128; header cap 8192 bytes,
request-line cap 2048, 64 headers, finite accept/read/write timeouts. Tests use
small deadlines and ephemeral ports. Configured limits are validated before
listening. Protocol errors are per-client outcomes; they must not poison the
listener. All error returns are explicit and nonzero where applicable.

## Go contracts studied

`net/tcpsock.go`: Accept/Close/SetDeadline; `net/tcpsock_posix.go`: fd ownership.
`internal/poll/fd_unix.go`: Close/reference lifecycle, nonblocking read/write;
`fd_poll_runtime.go`: deadlines; `fd_mutex.go`: synchronization contract.
`net/http/request.go`: readRequestLimit/parseRequestLine, Host validation;
`transfer.go`: readTransfer and framing ambiguity; `server.go`: bounded headers,
read/write deadlines, response framing, Serve and Shutdown.
`request_test.go`, `serve_test.go`, `transfer_test.go`: malformed headers,
Host, Content-Length, timeout and shutdown tests.
Go's netpoll/goroutine/GC/context machinery is intentionally not translated.
Other requested directories (JSON/context/sync/TLS/database/sql) are inspected
for architectural boundaries, not copied or expanded in this milestone.

Authority: RFC 9112 sections 2, 3, 5, 6 and 9; RFC 9110 semantics for
Host, status codes, Content-Length and HEAD. Unsupported transfer coding and
body/persistence features are documented limitations, not full conformance.

## Acceptance

Write tests first and observe missing std.http fail. Build native ELF using
normal compiler pipeline, verify freestanding artifact, run S protocol fixtures
and real loopback clients. Cover fragmented health, JSON/length/CRLF, HEAD,
404/405, Host and framing attacks, limits, EOF/reset, slow header timeout,
continued serving after errors, FD cleanup and graceful shutdown/refused connect.
Run TCP, time, relevant compiler/MIR/ownership regressions. No bootstrap PASS
without actually running it; source compiler modifications would require full
Seed->Stage4 verification. Preserve the Go working-tree baseline (an existing
`D src/cmd/compile/profile.sh` is not ours).
