# Native S MySQL driver design

Implement the user mission: pure S Classic Protocol, native/SHA2 authentication, TLS, CRUD, prepared binding and transactions. Reuse current TCP, TLS and cryptographic code; no libmysqlclient. Alternatives considered were a system-client wrapper (rejected by user) and native protocol (selected).

Public API uses concrete std.mysql.connection and prepared_statement types because dynamic std.database trait dispatch is not currently supported. Errors and buffered rows reuse std.database. Linux amd64/IPv4 follows existing TCP support. TLS uses the existing explicitly linked OpenSSL bridge with certificate validation. Non-TLS caching_sha2_password full authentication uses pure S RSA OAEP; a configured pinned PEM is preferred, server-key retrieval requires explicit opt-in. Passwords are never sent clear over TCP.

Connections and statement handles have one owner and must not be copied. Sequential commands only; no pool or concurrency. Results are bounded and buffered. No local-infile, compression or multi-statements are negotiated. Unsupported responses invalidate the connection when draining safely cannot be guaranteed. Timeouts cover whole command IO, not just individual fragments. Query type conversions preserve decimal and unsigned precision, NULL, binary bytes and UTF-8.

Acceptance requires real 8.0 and 8.4 servers, auth success/failure, TLS/plaintext, CRUD, prepared execution, transactions, listed data types, Chinese, timeout/disconnect, compiler-stage and bootstrap regression evidence. Protocol fixtures supplement these tests. Performance numbers must name the server/compiler and workload. Unavailable acceptance items remain explicitly unverified.
