# PostgreSQL implementation status

`src/std/postgresql/protocol.s` implements protocol 3.0 message codecs, **not a
connection driver**. It is independent of the MySQL package. No authentication,
verified TLS or live-server compatibility is claimed.

Implemented and tested with native S executable fixtures:

- Exact single-message framing and size bounds; SSLRequest and StartupMessage.
- Simple Query, Parse, Bind, Describe-statement, Execute, Close-statement, Sync and
  Terminate encoders. Bind separates parameter bytes from SQL and carries explicit
  text/binary formats and NULL lengths. Parse/Bind support all 65,535 parameters;
  balanced concatenation avoids quadratic copying of these large parameter lists.
- RowDescription parsing retaining native OIDs, type sizes, modifiers, attribute and
  table identifiers and text/binary format codes.
- DataRow length validation and NULL/text/binary preservation without guessing types.
- ParameterStatus, CommandComplete row counts, and ReadyForQuery I/T/E status.
- ErrorResponse parsing with SQLSTATE validation; fatal/nonfatal classification uses
  nonlocalized severity independently of field ordering.
- Authentication message parsing for Ok, cleartext requests, MD5 salt, SASL mechanism
  lists, SASL continue and SASL final. Parsing these is not authenticating.

Not implemented: TCP/deadlines, TLS negotiation/certificate verification, BackendKeyData
and cancellation, password responses, MD5 proof, SCRAM-SHA-256/PLUS and channel binding,
connection recovery/state machine, named statement ownership, portal suspension,
transaction commands/recovery, numeric/temporal/UUID/JSON typed conversion or binary
numeric decoding. Binary parameters require callers to provide bytes matching the
Parse OID. The current Bind encoder requests text results. Supported message size
limits are configurable up to 16 MiB; this is a bounded codec, not large-result
streaming. No live integration or database performance results exist.

The reference is the [official PostgreSQL message formats](https://www.postgresql.org/docs/18/protocol-message-formats.html).
