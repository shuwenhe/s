# Native S Redis

`std.redis` implements RESP2 directly in S over `std.tcp` and verified `std.tls`.
No Redis client library, hiredis, Go or Python is used by the Redis test path.
Every file under `test/redis` is S: assertions, configuration, TLS checks and
adversarial TCP peers. External shell build tooling invokes the S compiler,
assembler and C linker, starts isolated Redis processes and cleans them up.
The native `std.process` API cannot launch processes yet; it is not used or
changed. TLS links the existing verified OpenSSL bridge and its normal startup
adapter. No Redis protocol or test logic is implemented in C or shell.

## Run on the local machine

Prerequisites: Linux amd64, built `bin/s_compiler` and `bin/s_seed`, POSIX shell,
`make`, `timeout`, `redis-server`, a C compiler, binutils and OpenSSL development
headers/libraries. Python is not required to build or run these tests.

From the S repository:

```sh
make redis-check
# Or individual groups:
make redis-protocol-check
make redis-integration-check
```

Tests bind random loopback ports, use temporary password/ACL configurations and
disable RDB/AOF persistence. They never connect to your existing Redis instance,
flush databases, or change system Redis configuration. Temporary servers and
TLS certificates are cleaned up. Tests fail if dependencies are absent.

Protocol tests run through both Seed and native compiler ABIs. Complete TCP/TLS
acceptance uses the native compiler and existing OpenSSL bridge. The direct S
entry point is `test/redis/run.s`; build it without Python:

```sh
sh misc/scripts/build-redis-test.sh suite /tmp/s-redis-tests
/tmp/s-redis-tests
```

The executable defaults to protocol checks. `S_REDIS_TEST=integration`, `tls` or
`fault` selects other S checks; the Make targets supply isolated servers and the
required environment. Integration expects the test-only default password
`local-test-secret` and ACL user `tester` / `acl-test-secret`. TLS checks require
`REDIS_TLS=1`, `REDIS_TLS_CA_FILE` and `REDIS_TLS_WRONG_CA_FILE`. Do not point the
integration suite at an existing database: it intentionally writes fixed test keys.

Full Seed client compilation remains blocked by its record-borrow proof boundary;
see results.md and evidence/seed-integration-blocked.log. Protocol-only Seed tests
pass. No compiler/runtime changes or borrow checks were disabled.

## Smoke test an existing Redis

The sample lives under `test/redis/basic`, with no examples directory:

```sh
sh misc/scripts/build-redis-test.sh basic /tmp/s-redis-smoke
REDIS_HOST=127.0.0.1 REDIS_PORT=6379 /tmp/s-redis-smoke
```

For authentication, set `REDIS_PASSWORD` and optionally `REDIS_USER` in the process
environment. For TLS set `REDIS_TLS=1`, `REDIS_TLS_SERVER_NAME` to the certificate's
DNS name and optionally `REDIS_TLS_CA_FILE` to a trusted PEM CA. The sample uses a
unique key with a 60-second TTL, checks binary SET/GET, then deletes that key. It
prints only fixed diagnostics, never credentials or values.

## Connection and ownership

`connect(options) (connection,error)` defaults to `127.0.0.1:6379` and 5000 ms
connect/read/write timeouts. Host addresses must be IPv4 literals, following the
existing TCP API; DNS resolution and IPv6 are unsupported. Zero timeout fields
select defaults; negative or greater-than-INT32_MAX values are rejected. `database`
zero selects the server default; positive values issue SELECT before connect
returns. A nonempty username requires a password. A password without username
uses password-only AUTH; username/password uses ACL AUTH.

Set `use_tls`, `tls_server_name`, and optionally `tls_ca_file` for TLS. Verification
is mandatory, with system trust when the CA path is empty. There is no insecure
mode and no plaintext fallback. The standard OpenSSL builder is required because
TLS symbols are linked even if a particular connection uses plain TCP.

Keep exactly one mutable owner of each live connection. Never copy it or share it
concurrently. A `busy` flag rejects reentrant work; it is not synchronization.
Pass `c*` to operations and call `close(c*)`, which is idempotent. TLS closes before
TCP. Failed connect/auth/select returns an already closed handle. Do not mutate
connection internals or parsed document nodes.

Each write has one total deadline including partial writes. Each reply read has
one total deadline including all fragmented reads. A pipeline shares one read
deadline for all replies. TCP connect and TLS handshake each receive the configured
connect timeout; AUTH/SELECT use normal read/write deadlines. There are no retries.

## Commands and results

All commands are encoded as arrays of explicit-length binary bulk strings. Bind
array/option expressions to local variables before passing a borrowed connection,
as required by S's existing borrow rules. See integration.s for compilable calls.

- `execute(c*, string[] arguments)` returns `(document,error)`.
- `ping`, `auth`, `select` return `error`.
- `get`, `hget`, `lpop`, `rpop` return `(optional_string,error)`; `present` separates
  NULL from an empty `value`.
- `set(c*,key,value,set_options)` returns `(bool,error)`; false with no error means
  NX/XX did not apply. `ex_seconds` and `px_milliseconds` are mutually exclusive;
  `nx` and `xx` are mutually exclusive. Zero expiration means no expiration option.
- `del`, `exists`, `ttl`, `hset`, `hdel`, `lpush`, `rpush`, `sadd`, `srem` return
  `(int,error)`, preserving Redis counts and TTL's -1/-2 sentinel values.
- `expire`, `persist`, `hexists`, `sismember` return `(bool,error)`.
- `type` returns `(string,error)`.
- `hgetall`, `lrange`, `smembers` return `(document,error)` with a validated flat
  array of bulk strings. HGETALL additionally validates alternating key/value
  pairs; collection/set ordering is Redis-defined. LPUSH/RPUSH and set/hash mutation
  wrappers accept one element/field per call; use execute for variadic forms.

Check `error.code == 0` before using results. Categories distinguish invalid input,
bounds, closed/state errors, malformed protocol, server errors, timeout and
transport failures. `native_code` retains an underlying errno when available.
`fatal` means the connection was invalidated and closed. Top-level Redis error
replies return `error_server` without closing a correctly framed connection.
Never log authentication arguments; server error text is untrusted data.

## RESP and bounds

Nodes have `kind`, `text`, `integer`, `parent`, and `length`. Root index is zero;
root parent is -1. Kinds are `simple`, `error`, `integer`, `bulk`, `null_bulk`,
`array`, `null_array`. Arrays record immediate child count in `length`. Flat nodes
retain nested errors inside EXEC; nested errors do not become transport failures.
`decode(wire,limits)` requires exactly one complete frame. Streaming callers use
`new_decoder`, `feed`, `advance`, `complete`, `position`, and `failure`; incomplete
input is separate from malformed input until EOF/finalization. Node indices stay
stable. The connection keeps unread bytes for ordered pipeline replies.

| Limit | Default | Hard ceiling |
|---|---:|---:|
| Frame bytes | 1 MiB | 16 MiB |
| Bulk bytes | Frame limit | Frame limit |
| Immediate array length | 4096 | 65536 |
| Nesting depth (root = 1) | 64 | 256 |
| Nodes per reply | 8192 | 65536 |

Zero selects defaults; negative and above-ceiling limits fail. Parsers allocate
bounded flat storage, check lengths before bulk allocation and reject signed
64-bit overflow. Receive read-ahead is bounded; `feed` allows at most frame limit
plus 64 KiB for subsequent replies. Decoder construction allocates the configured
node capacity; returned connection replies are compacted to their actual node
count. Callers should keep conservative limits for untrusted endpoints.

## Transactions and pipelines

`multi`, `discard`, `watch(c*,key)` and `unwatch` return `error`.
`exec` returns `(document,error)`: a `null_array` root means WATCH aborted the
transaction; an `array` with length zero means successful empty EXEC. Check each
nested `error` node for command failures. Queue commands with `execute` and inspect
`QUEUED`; typed ordinary commands reject active MULTI before sending. Queue errors
keep MULTI active until EXEC/EXECABORT or DISCARD. Transport/protocol errors close
the connection, so an unknown transaction outcome can never be retried implicitly.

`pipeline(c*, command[] commands)` returns `(batch,error)` with ordered replies.
It requires an idle, unwatched connection and prevalidates the entire request.
Limits are 1..128 commands, frame-limit total request bytes, frame-limit total
response bytes and node-limit total response nodes. A top-level error reply is an
`error` node in its reply slot; later replies are still drained. Partial failure
returns only completed replies with a fatal error and closes the connection.
State-changing AUTH/SELECT/transaction commands are excluded from pipelines.

RESP3 negotiation, Pub/Sub, MONITOR, replication, CLIENT stream controls, RESET,
QUIT and SHUTDOWN are rejected before I/O. Cluster redirections are ordinary server
errors; there is no cluster routing, pooling, reconnect or concurrent client API.
Buffer concatenation during fragmented input has bounded size but can copy prefixes
repeatedly; this version has no throughput/latency certification. Passing these
local tests is not a general production deployment certification.

## References

Framing and integer grammar follow the official
[RESP specification](https://redis.io/docs/latest/develop/reference/protocol-spec/).
Transaction behavior is checked against the real local Redis instance.
