# Native S MySQL driver

`std.mysql` implements MySQL Classic Protocol in S. TCP, authentication, RSA-OAEP, packets, result decoding, binding and transactions do not use libmysqlclient. TLS uses the existing `std.tls` OpenSSL bridge (`libssl`/`libcrypto`). Current platform: Linux amd64, IPv4 literals; `localhost` maps to `127.0.0.1`.

See [results.md](results.md) for verification status. The implementation alone is not evidence that every compatibility target passed.

## Build and examples

Requirements: native S compiler, C compiler, Python 3, OpenSSL development headers/libraries. This workspace now has the verified native Stage3 compiler at `bin/s_compiler`; the bootstrap commands below are only needed to rebuild the compiler. Build clients with the existing TLS linker, which discovers S source dependencies:

```sh
make seed-compiler-bin
# Rebuild the self-hosted compiler if bin/s_compiler predates the sources.
S_SOURCE_ROOT="$PWD" bash src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/mysql-stages
export S_TEST_COMPILER="$PWD/.bootstrap/mysql-stages/stage3"
python3 misc/scripts/build-openssl-client.py test/mysql/crud/main.s -o /tmp/s-mysql-crud
python3 misc/scripts/build-openssl-client.py test/mysql/transaction/main.s -o /tmp/s-mysql-transaction
export MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 MYSQL_USER=app MYSQL_DATABASE=app
export MYSQL_TLS_HOST=db.example.com MYSQL_CA=/path/to/ca.pem
# Supply MYSQL_PASSWORD via your shell's secret-management mechanism.
/tmp/s-mysql-crud
/tmp/s-mysql-transaction
```

Both examples use temporary tables and explicitly close the connection on failure. They require table-creation permission within the selected database.

## Public API

Import `std.mysql` and `std.database`. Functions return ordinary S tuples `(value,std.database.error)`. `error.code == 0` means success. Check errors before using returned values.

| Function | Return |
| --- | --- |
| `connect(std.database.options config)` | `(connection,error)`; connects and authenticates |
| `ping(connection* client)` | `error` |
| `query(connection* client,string sql)` | `(std.database.rows,error)` |
| `exec(connection* client,string sql)` | `(std.database.result,error)` |
| `prepare(connection* client,string sql)` | `(prepared_statement,error)` |
| `statement_query(connection*,prepared_statement*,std.database.value[])` | `(std.database.rows,error)` |
| `statement_exec(connection*,prepared_statement*,std.database.value[])` | `(std.database.result,error)` |
| `close_statement(connection*,prepared_statement*)` | `error`, idempotent for the same handle |
| `begin(connection*)`, `commit(connection*)`, `rollback(connection*)` | `error` |
| `close(connection*)` | `error`, idempotent; sends COM_QUIT and releases TLS/TCP |

Use `?` placeholders only with `prepare`, then pass `std.database.value` parameters. The driver sends COM_STMT_EXECUTE binary bindings; it never interpolates or escapes SQL parameters. `query`/`exec` accept complete SQL strings, not parameter arrays.

Connections and statement handles have one owner and must not be copied. Execute sequentially. Each statement belongs to its original connection; closed statements and wrong argument counts are rejected before sending. Closing the connection releases all server statements and rolls back outstanding uncommitted work through server disconnect semantics. Errors with `fatal: true` close the connection; create a fresh connection rather than retrying on it. Server SQL errors preserve `native_code`, `sqlstate` and `message`; the next command may still be used after a nonfatal server error. A lost connection during commit has an unknown transaction outcome; the driver does not automatically replay commands.

`begin` rejects nested transactions. Server status tracks transaction state, including implicit commits; DDL follows MySQL's implicit-commit rules. `commit`/`rollback` reject an inactive transaction. No connection pool, automatic retry or concurrent commands.

Results are owned buffered `std.database.rows`; inspect `column_data` and `data`, or use `next()`, `columns()` and `close()`. NULL is `std.database.value.null`, distinct from empty text, empty binary and exhausted rows. `result.affected_rows` and `last_insert_id` are optional decimal strings, preserving the full unsigned 64-bit range. `query` rejects a command that returns no rows, and `exec` rejects a result set after consuming it.

## Configuration

`std.database.options` fields:

| Field | Default / behavior |
| --- | --- |
| `host`, `port` | `127.0.0.1`, `3306`; IPv4 literals only |
| `user`, `password`, `database_name` | User required; empty password/database permitted |
| `connect_timeout_ms` | 5000 when zero; positive milliseconds for dial and authentication |
| `read_timeout_ms`, `write_timeout_ms` | 5000 when zero; positive milliseconds |
| `tls_server_name` | Empty selects TCP without TLS; nonempty requires verified TLS, with no downgrade |
| `tls_ca_file` | Empty uses system trust; nonempty uses this CA file; requires TLS name |
| `server_public_key` | Optional pinned RSA public key **PEM contents**, SPKI `BEGIN PUBLIC KEY`; MySQL’s terminal NUL is accepted |
| `allow_public_key_retrieval` | false; explicit opt-in for retrieving an unauthenticated RSA key over non-TLS TCP |
| `max_packet_bytes` | 16,777,214; accepted range 1024..16,777,214 |
| `max_result_bytes` | 16,777,214 wire payload bytes; at most 1 GiB |
| `max_rows` | 100,000; at most 1,000,000 |

Authentication implements `mysql_native_password` and `caching_sha2_password`, including auth switch, SHA2 fast cache authentication, TLS full authentication and non-TLS RSA-OAEP/SHA1 full authentication. For cold SHA2 authentication over non-TLS TCP, use a pinned key or explicitly enable retrieval. Retrieval alone does not authenticate server identity; prefer verified TLS or a key obtained through a trusted channel. No cleartext password is sent without TLS. RSA public keys are bounded to 2048..4096 bits. MySQL 8.4 disables `mysql_native_password` by default; testing that plugin requires starting the server with `--mysql-native-password=ON`.

Individual reads/writes are bounded by their configured timeout, and an overall command deadline (read + write timeout) prevents an indefinitely slow sequence of packets. Partial reads, sequence errors, packet/result limits, EOF and transport failures invalidate and close the connection. TLS certificate/hostname errors fail the connection. The maximum packet limit currently excludes 0xffffff continuation packets; larger fragmented messages are rejected.

## Values

| MySQL type | S value |
| --- | --- |
| Signed integer types, BIGINT | `integer(int)` including -9223372036854775808 |
| Unsigned integer types | `unsigned_integer(string)` including 18446744073709551615 |
| DECIMAL | `decimal(string)`, no floating-point rounding |
| VARCHAR/TEXT (including utf8mb4) | `text(string)` |
| Binary-character-set strings/BLOB/BIT | `binary(string)`, binary-safe including zero bytes |
| DATE / TIME / DATETIME,TIMESTAMP | `date` / `time` / `timestamp` strings; no timezone conversion |
| JSON | `json(string)` |
| NULL | `null` |

Prepared parameters support null, boolean, signed/unsigned integer, decimal, text, binary, date/time/timestamp, JSON, UUID and floating decimal strings. Temporal/string-like parameters are bound as protocol strings and converted by MySQL according to the target type. Binary integer bindings preserve the full range. Text-protocol FLOAT/DOUBLE results preserve server text; binary FLOAT/DOUBLE results currently return an explicit unsupported error (use `CAST(... AS DECIMAL)` or `CHAR` in prepared queries).

No compression, local-infile upload, multi-statements, multiple result sets, server cursors or streaming results. These capabilities are not negotiated; unexpected local-infile/multiple-result responses close the connection.

The old declaration-only database traits live under `std.database.contracts` (source `interfaces.s`); they are not dynamically dispatched by this concrete driver. `std.database` retains common values, options, errors and buffered results, and can be compiled without those unsupported trait declarations.

## Reproducible tests and benchmark

```sh
python3 -m unittest discover -s test/stdlib-native -p 'test_database*.py' -v
python3 -m unittest discover -s test/stdlib-native -p 'test_mysql_auth.py' -v
python3 test/stdlib-native/test_mysql_values.py -v
S_TEST_COMPILER="$PWD/.bootstrap/mysql-stages/stage3" python3 test/stdlib-native/test_mysql_compiler.py -v
python3 test/stdlib-native/run_mysql_matrix.py --image84 mysql:8.4 \
  --compiler .bootstrap/mysql-stages/stage1 \
  --compiler .bootstrap/mysql-stages/stage2 \
  --compiler .bootstrap/mysql-stages/stage3 \
  --output .bootstrap/mysql-results
```

The matrix checks actual server versions, provisions dedicated temporary databases/users, flushes authentication caches between cases, tests real MySQL 8.0/8.4, and stops only the servers it creates. Python `cryptography` and Docker are test dependencies, not S driver runtime dependencies. The standalone suite skips when `S_MYSQL_PORT` is absent; a skipped suite is not integration evidence. The matrix always sets it and writes logs/results JSON. It benchmarks sequential PING, SELECT and prepared SELECT against both servers over TCP and TLS; benchmark values include client parsing and server/transport latency, not connection establishment.
