# Shared database API contracts

This is a tested foundation and independent protocol codecs. It is **not yet a
working database client**. `driver`, `database`, `connection`, `query`, `exec`,
`transaction`, and `prepared_statement` are contract declarations. Dynamic trait
calls do not link with the current standalone compiler (see [audit](audit.md)).
There are no fake open/connect/ping/authentication implementations.

## Types and return conventions

All types use lowercase S names. `std.database.error` carries a portable `code`,
message, SQLSTATE, native code, driver name and fatal-connection indication.
Code zero means success for completed local operations only. Nonzero error results
must be checked before using the accompanying value. A parser's error-zero means
that a payload decoded; it never means a server accepted a command.

`std.database.result` is execution metadata. It is distinct from the language's
`std.result.result[t,e]`. `affected_rows` and `last_insert_id` are `option[string]`
containing unsigned decimal counts. `none` means unavailable; `some("0")` is a
reported zero. `warning_count` and `command_tag` retain execution information.
PostgreSQL INSERT OIDs are not treated as generated IDs; obtaining an ID requires
an explicit RETURNING query once a connection implementation exists.

Free functions use the existing `(value,error)` tuple convention. Receiver methods
and driver contracts use tagged `std.result.result[t,error]` returns. The seed
cannot currently destructure receiver-method tuple returns. Pattern matching the
returned enum is tested; generic `is_err`/`unwrap` receiver resolution for nested,
fully qualified result types is another current compiler limitation.

`statement` contains SQL and a `value[]` parameter list. Parameters must be sent in
native protocol fields, never substituted into SQL by concatenation. Connection
query/exec cannot be used while its previous result is active. Prepared statements
must validate parameter counts and ownership before sending an execution message.

## Values

| Variant | Representation and contract |
| --- | --- |
| `null` | SQL NULL, distinct from exhaustion, empty strings/bytes, zero and false |
| `boolean` | S bool |
| `integer` | signed S int; `parse_integer` rejects invalid digits and overflow |
| `unsigned_integer` | exact unsigned 64-bit decimal text; `unsigned_value` validates range |
| `floating` | exact textual floating representation; native float conversion is not implemented |
| `decimal` | exact fixed-point text; `decimal_value` validates syntax without rounding |
| `text` | server text bytes; character-set conversion is not implemented |
| `binary` | binary-safe string, including embedded NUL; never interpreted as text |
| `date`, `time`, `timestamp`, `timestamp_tz` | exact driver-supplied text; temporal validation and conversion are not implemented |
| `json`, `uuid` | exact driver-supplied text; semantic validation is not implemented |
| `native` | driver type name, bytes and binary/text format for future extension |

Constructors on the public enum do not enforce invariants. Drivers/encoders must
validate before consuming externally constructed numeric variants. The MySQL
prepared encoder validates unsigned/decimal parameters accordingly. No implicit
NULL-to-zero or text-to-integer conversion is performed by `as_integer`.

## Rows

`buffered_rows(columns,data)` validates every row width. It creates an owned buffered
cursor, not a streaming socket result. Inputs are transferred by contract: callers
must not mutate their arrays afterward. Immutable sharing is permitted. `next()`
returns `result[option[row],error]`; `ok(none)` is repeatable exhaustion, and
`ok(some(row))` can contain SQL NULL. `row.get(index)` rejects negative/out-of-range
indices with `error_bounds`. `columns()` returns owned metadata.

`rows.close()` is idempotent and releases its references to columns and rows. An
already returned row/cell stays valid. Accessing the cursor after close produces
`error_closed`. This does not assert that the underlying runtime immediately returns
all allocation pages to the OS. Bounded codecs do not establish global leak freedom.

## Resource ownership

- A database owner owns its connections; a connection owns its statements,
  transactions and active server results. No implicit pooling is promised.
- Driver resources must have exactly one live owner. Live OS resource state must
  not be copied. The current language cannot enforce this rule for public structs;
  drivers must encapsulate owners and validate handles. No such driver exists yet.
- Close results and statements before their parent. Explicit transaction close means
  rollback while active/failed, never an implicit commit. Commit/rollback may update
  local status only after the server response is validated. Failed PostgreSQL
  transactions permit rollback, not ordinary queries or commit.
- `resource_state` and its helpers are bookkeeping, not OS operations. Use
  `can_close_resource` before native cleanup; on cleanup success call
  `close_resource`. Cleanup failure must preserve/report actual resource state.
  Repeated local closure succeeds without acquiring or closing an OS handle.
- `start_command` rejects closed/busy state; `finish_command` rejects absent work.
  `retain_child`/`release_child` validate the count and prevent arithmetic overflow.
  A busy owner or one with live children refuses ordinary close.
- Fatal transport/authentication failure requires native cleanup and invalidation of
  all affected children, regardless of ordinary close restrictions. Future drivers
  must implement this failure path; the bookkeeping alone does not implement it.
- Byte cursor inputs are immutable owned strings, not borrowed mutable receive
  buffers. Reads check bounds before indexing and latch errors. Check `code` before
  trusting a read's zero/empty return. Payloads returned as slices remain valid under
  the existing runtime's value ownership rules.

## Security and transport contract

Verified TLS, hostname verification, credential exchange, entropy, deadlines and
socket cleanup are prerequisites for live drivers. There is no allow-insecure option
or plaintext-password encoder. Merely decoding an SSL/authentication message does
not establish TLS, authenticate the peer, or permit sending a password. Unsupported
binary parameter types and fragmented MySQL messages return explicit errors.

See [the test fixtures](../../test/stdlib-native/database_rows.s) for compiled,
executed examples rather than hypothetical live-database examples.
