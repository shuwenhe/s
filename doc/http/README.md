# Native HTTP health-server slice

The HTTP implementation is S code in `src/std/http/`. It uses the existing
native `std.tcp` Linux/amd64 OS boundary, with no Go runtime, external HTTP
server, or TLS bridge dependency. The Python integration suite is only the TCP
client/process harness.

From the S repository root:

```sh
make compiler
bin/s build test/http/health/main.s -o /tmp/s-http-health
/tmp/s-http-health
```

The example binds `127.0.0.1:8080` and prints its bound port. Override the port
with `S_HTTP_PORT` (`0` chooses an ephemeral port). For an application-controlled
one-exchange graceful exit:

```sh
S_HTTP_PORT=8080 S_HTTP_ONCE=1 /tmp/s-http-health
# In another terminal:
curl --http1.1 -i http://127.0.0.1:8080/health
```

Response (actual wire line endings are CRLF):

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15
Connection: close

{"status":"ok"}
```

`make http-unit-check` runs the S protocol fixture. Run
`make http-integration-check` in an environment authorized to use real loopback
sockets. Both use the normal compiler pipeline and verify native artifacts.

## API and ownership

- `listen(options) (server,http_error)`: validate limits and open a listener.
- `local_port(server*) (int,http_error)`: inspect the assigned port.
- `serve_next(server*) (exchange,http_error)`: accept one client, read bounded
  headers, route health/404/405, write one bounded response and close the client.
- `shutdown(server*) http_error`: idempotently close the listener between calls.
- `parse_request(string,options) (request,http_error)` and
  `serialize_response(response,bool) (string,http_error)` expose protocol logic.
- `write_response(socket*,response,bool,int) http_error`: write a serialized
  response under a total network-write deadline. The caller still owns and must
  close that socket; `serve_next` does so on every path.

A live `server`, like a live `std.tcp.socket`, has one owner. Do not copy, share,
or concurrently use it. Configuration and `closed` state are explicit. Protocol
errors are per-client exchanges with an HTTP status, not fatal listener errors.
A nonzero error with status 0 and `peer_eof` true denotes client transport failure;
accept errors have no accepted client and `peer_eof` false. Examples handle accept
110 by polling again, and abort on other listener failures.

Graceful shutdown is synchronous/application-controlled: finish the current
`serve_next`, then call `shutdown`; already-written response bytes remain
available to the peer. There is no asynchronous SIGTERM handler or concurrent
Shutdown/context API. Finite accept and I/O timeouts bound each call; shutdown
does not promise to interrupt a call already running on another thread.

## Explicit boundary

This is a first health-server milestone, **not full HTTP/1.1 compliance or a
production-readiness claim**. It supports GET/HEAD, origin-form ASCII targets
with valid percent escapes, hostname/IPv4 Host authorities with optional numeric
ports, strict CRLF and one response per connection. It rejects duplicate Host
and Content-Length, CL/TE ambiguity, body-bearing requests, unsupported transfer
coding/Expect, folded headers and control characters. `Content-Length` is the
byte length; HEAD preserves the advertised length and suppresses the body.

Defaults: 8192 header bytes, 2048 request-line bytes, 64 headers, 100 ms accept
poll, 5000 ms absolute header deadline and 5000 ms total network-write deadline.
Header cap is configurable up to 1 MiB, with validated positive bounds.

Deferred: bodies/chunked transfer, persistent connections, absolute/authority/
asterisk request targets, IPv6 Host authorities, Date generation, a general
handler/router API, JSON codec, HTTPS, signals/context cancellation and concurrency.
No scheduler, garbage collector or general networking runtime was copied from Go.
No new GC dependency was introduced; this milestone verifies socket lifetimes,
not general heap reclamation or all language ownership guarantees.

See [design.md](design.md) for Go references/architecture and [results.md](results.md)
for exact evidence, including the Seed server preflight limitation. The minimal
Seed caller lives at `test/http/seed-borrow-repro/main.s`; no type/borrow/MIR
validation is disabled to make it pass.
