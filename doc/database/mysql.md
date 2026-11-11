# MySQL implementation status

`src/std/mysql/protocol.s` implements standalone protocol codecs, **not a connection
driver**. No authentication, TLS or real-server compatibility is claimed.

Implemented and tested with native S executable fixtures:

- Single physical packet encode/decode with configured limits and sequence checks.
- Length-encoded integers, including unsigned 64-bit maximum, and nullable strings.
- Protocol v10 / protocol 4.1 handshake parsing, capability/status/version discovery,
  supported 20-byte authentication scrambles and plugin names.
- Authentication-switch parsing; this does not implement the requested plugin.
- Protocol 4.1 ERR and OK payloads, SQLSTATE validation, affected rows, inserted IDs,
  warnings, status and non-session-track info.
- ColumnDefinition41 and COM_STMT_PREPARE response metadata.
- Text row framing retaining text bytes and explicit SQL NULL.
- COM_QUERY, COM_STMT_PREPARE, COM_STMT_CLOSE payload encoding.
- COM_STMT_EXECUTE with real parameter separation and NULL bitmap; supported parameter
  types are NULL, bool, signed int64, unsigned uint64, text, binary and fixed-point
  decimal. Signed minimum and unsigned maximum are tested. Unsupported variants
  produce errors instead of fabricated encoding success.

Not implemented: native TCP, negotiated TLS, certificate verification, capability
negotiation response, mysql_native_password or caching_sha2_password proof/exchange,
RSA/full authentication, result stream state machine, typed text conversion, binary
result decoding, EOF-deprecation/session-tracking negotiation, logical packet
fragment assembly, statement/transaction owners, live transactions and autocommit.
Physical payloads must be below 0xffffff bytes. There are no live integration tests
and no performance/FD-leak guarantees. Handshake compatibility is deliberately
limited; unsupported scramble lengths and legacy protocol versions are rejected.

The protocol definition is the [official MySQL client/server protocol](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_PROTOCOL.html).
