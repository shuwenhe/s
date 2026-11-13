# Native Redis design

S-only synchronous RESP2 client using existing TCP/TLS and monotonic deadlines.
A mutable connection owns one TCP socket and optional verified TLS session. Never
copy or concurrently share live handles. No retries. Transport/protocol failures
close the connection. Redis error replies are data with a distinct server category.

Incremental decoding stores nodes in a flat array with parent indices, separating
null bulk/array, empty bulk/array, integers, errors and simple strings. Explicit
bounds cover frame bytes, bulk bytes, array children, depth and total nodes. The
stream parser retains its cursor between reads; pipelined replies stay ordered.

Public API: options, limits, connection, reply/document, error; connect/close,
execute, typed commands, transaction helpers and pipeline. Typed commands reject
queued transaction replies; queue commands through execute. EXEC exposes nested
errors and distinguishes WATCH abort (null array) from an empty array.

IPv4 literals follow std.tcp's existing limitation. TLS server name is separate
and always verified. Authentication and SELECT happen before connect succeeds.
Samples and all S acceptance programs live under test/redis, never examples.

Alternative: restart decoding after every read; rejected because fragmented large
responses would repeatedly parse prefixes. No compiler/runtime changes planned.
