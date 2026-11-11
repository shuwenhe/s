# Preliminary audit — 2026-11-11

The initial checkout was clean. All three database directories contained README only.

| Area | Observed implementation |
| --- | --- |
| Shared database API | No implementation existed |
| TCP | `src/net/tcpconn_new.s` and `src/net/internal/socket_core.s` contain parse errors |
| TLS / certificates | `src/crypto/tls/{tls,common}.s` contain only `*_unit_name/ready` |
| SHA-1 / SHA-256 / HMAC / random | Corresponding main package files are readiness stubs |
| Binary / Base64 | Corresponding main package files are readiness stubs |
| Byte strings | `src/std/string.s` provides checked byte access, byte creation, slicing |
| Allocation / arrays | Existing standalone runtime supports arrays and binary-safe strings; OS resource allocation is not supplied by these helpers |
| Errors | `option[t]`, `result[t,e]`, and `(value,error_struct)` tuples are established |
| Traits | Non-generic declarations and semantic method checks exist; dynamic calls cannot link |
| Native tests | Python unittest harnesses compile real S sources and execute generated ELF files |
| CI | selfhost.yml and release-acceptance.yml must retain all compiler acceptance gates |

## Reproduced blockers (before database implementation)

1. `make compiler`: compiles 100 S modules to IR, but standalone emission fails:
   `unproven native borrow control flow in amd64_emit_native_intrinsic at IR record 76181 (CALL t21299)`.
   There is no initial `bin/s_compiler`. Build log: `/tmp/s-database-compiler-baseline.log`.
2. Seed compilation of `src/net/tcpconn_new.s src/net/internal/socket_core.s`:
   `PARSE_FAIL at src/net/tcpconn_new.s:111:5: expected expression, got )`.
3. Importing `std.syscall`: `src/std/syscall.s:27:18: use of undeclared symbol 'o100'`.
   A minimal standalone `extern "intrinsic" func __syscall1(int,int) int` call
   compiles to IR but fails ELF linking: `undefined reference to s_fn___syscall1`.
   Thus fixing socket source syntax alone does not supply a native TCP backend.
4. A non-generic trait with `func close() int;` and a matching concrete receiver
   compiles to IR; calling it through the trait fails linking:
   `undefined reference to s_fn__method_close`.
5. Generic traits are absent from the seed's `parse_trait_decl`; it expects `{`
   immediately after the trait name. Do not infer support from stale fixture text.
6. Docker CLI is present but daemon access returns permission denied on
   `/var/run/docker.sock`. MySQL CLI is present; it is not used as an S driver.

These are concrete prerequisites, not optional driver features. Implementing verified
TLS would require a TLS record/handshake stack, authenticated encryption, certificate
path/hostname verification, hashes/HMAC, secure entropy, and working native TCP.
No readiness stub is accepted as any of these. Live driver and real-server acceptance
remain blocked until these prerequisites are implemented and independently tested.

## Protocol references

- [MySQL connection phase](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_connection_phase.html)
- [MySQL caching SHA-2 authentication](https://dev.mysql.com/doc/dev/mysql-server/8.0.46/page_caching_sha2_authentication_exchanges.html)
- [PostgreSQL message formats](https://www.postgresql.org/docs/18/protocol-message-formats.html)
- [PostgreSQL message flow](https://www.postgresql.org/docs/current/protocol-flow.html)

## Additional compiler/runtime findings

A final audit also inspected `src/syscall/syscall_unix.s` and the generated canonical
`native_runtime_extensions.{c,s}`. Basic socket/close/IPv4-connect/string-read/write
implementations **do exist in the canonical backend**. They are not a complete
verified transport: read returns null without errno on failure, connect is blocking,
and the extension target table does not expose the declared deadline/poll/resolve
functions. The canonical compiler cannot currently be built (blocker 1 above).
A direct seed probe of the *correct* `__sys_socket` and `__sys_close` names compiles
to IR, but native emission fails with undefined `s_fn___sys_socket` and
`s_fn___sys_close`. Thus networking is not categorically absent; it is unavailable
through the currently working tested compilation path. No database code or compiler
intrinsic implementation was changed to conceal this mismatch.

The complete relevant crypto/encoding package function inventory contains no
non-readiness production hash/HMAC/random/TLS/certificate/binary/Base64 functions.

Additional measured language restrictions:

- Tuple-return receiver calls fail tuple-layout proof. Buffered rows use tagged
  results, and their callers use tested enum pattern matching instead.
- A `floating(float)` enum payload triggers `unknown native array transfer type:
  float[]` in the seed. Floating values therefore retain textual representations;
  numeric float conversion is not implemented or claimed.
- A generic receiver-forwarding function with explicit type arguments still fails
  with `type 't' has no method 'close'`; substituting static forwarding is not an
  established replacement for the failed trait dispatch.
- Nested fully qualified result receiver helper resolution is incomplete; direct
  pattern matching is tested.
- Hexadecimal byte escapes did not produce the required byte in native execution.
  All protocol marker bytes now use the tested integer-to-byte encoding primitive.
- `strace /bin/true` reports `PTRACE_TRACEME: Operation not permitted`; trace-based
  regression tests cannot run successfully under this sandbox.
