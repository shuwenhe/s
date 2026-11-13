# Native S REST users milestone

S owns HTTP framing, routing, JSON, validation, prepared MySQL statements and
transactions. Next.js owns the UI and a same-origin fixed-upstream proxy only.
The server remains synchronous, one bounded exchange per connection, with no
keepalive, chunked transfer, concurrent runtime or Go dependency.

## Build and configuration

```sh
make compiler seed-compiler-bin
python3 misc/scripts/build-openssl-client.py test/rest-users/main.s -o /tmp/s-rest-users
# Supply MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE securely in your environment.
# Optional MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306
S_REST_PORT=8080 /tmp/s-rest-users
```

The existing build helper links the existing OpenSSL TLS/crypto OS bridge; Python
only orchestrates compilation, never serves HTTP or executes application SQL.
The existing MySQL driver is entirely S. Credentials have no source defaults.
`MYSQL_ALLOW_PUBLIC_KEY_RETRIEVAL=1` explicitly permits existing driver's RSA
key retrieval for a trusted local test server; use configured TLS for remote
credentials (this demo does not add a remote deployment workflow).

Startup creates **only** `s_rest_users_v1` using CREATE TABLE IF NOT EXISTS.
See [schema.sql](../../test/rest-users/schema.sql). No DROP/ALTER/TRUNCATE,
existing users-table mutation, migration, or root credential changes occur.
The configured account needs CREATE, SELECT, INSERT, UPDATE and DELETE on this
isolated table (CREATE can be omitted only after adapting deployment provisioning;
the demo always performs the idempotent CREATE check). Use a test database.

`S_REST_MAX_REQUESTS` defaults to 0 (continuous serving); a positive value performs
that many accepted HTTP exchanges then closes the listener and exits. Shutdown
is between exchanges; this does not implement asynchronous signal cancellation.
`MYSQL_MAX_RESULT_BYTES` defaults to 1048576; bounds errors become JSON500.
DB timeouts are 2s; HTTP absolute header+body deadline and write deadline are500ms.
Body limit65536 bytes; headers8192, line2048, header count64.

```sh
cd test/rest-users/frontend
npm ci
npm test
npm run typecheck
npm run build
S_API_ORIGIN=http://127.0.0.1:8080 npm start -- --port 3000
```

Open http://127.0.0.1:3000. Proxy routes fix the upstream origin; no open URL
forwarding, cookies, credentials or database logic are added to Next. Request
and response streaming limits are64KiB/1MiB with10s timeout. This local demo
has no authentication, authorization, CSRF or public deployment claim.

## HTTP and ownership

`std.http.options.max_body_bytes=0` preserves the original bodyless default;
REST opts in to a positive bound (hard ceiling16MiB). `parse_request` validates
headers and returns metadata; network `receive` additionally reads exactly the
Content-Length under one absolute deadline. Unsupported Transfer-Encoding is
rejected; TE+CL, duplicate CL, duplicate Host/Content-Type and malformed framing
are rejected and the connection closes. Surplus bytes are not a next request.

`request` contains method/target/path/query/host/body, headers[], content_length
and header_bytes. Header names are normalized; `header_value(request,name)`
returns the first match. The request owns its strings/arrays, independent of
subsequent socket reads. Query decoding is an explicit router operation.

`receive(server*) -> (pending,http_error)` transfers one accepted socket to pending.
For parse errors with HTTP status the pending remains open, so the caller can
send a JSON error. Accept/transport/empty-EOF failures return closed pending.
`pending.accepted` distinguishes accepted-client transport failures (closed) from
listener accept failures. Client resets must not terminate the listener.
Every live pending must be consumed by `respond(pending*,response)` or
`discard(pending*)`; both close deterministically, discard is idempotent.
Never copy live server/pending/socket handles. These are existing S ownership
contracts, not a newly claimed compiler-enforced linear resource system.

`response {status,body,content_type,headers}` defaults Content-Type to JSON.
Serialization computes byte Content-Length, suppresses HEAD bodies even for
parse errors, and emits204 without body or Content-Length. This milestone's204
API rejects custom headers. Custom headers are token/control validated and cannot
override framing, Connection or Content-Type; put Content-Type in its field.
`serve_next` and existing `/health` remain available with their original behavior.

## Router

`std.rest.new()` creates a data-only router. Registration is value-returning:
`next,error := std.rest.add(routes,"GET","/api/users/:id",handler_id)`.
`std.rest.match(routes,method,path)` returns status/handler_id/Allow/parameters;
`param_value` accesses decoded parameters. Handler IDs are dispatched by S code;
no callback or unsupported dynamic language feature is required.

Literal segments take precedence over parameters independently of registration.
Equivalent/ambiguous same-method patterns and duplicate parameter names fail.
HEAD uses an explicit handler first, else GET. 405 derives Allow from the selected
path, ordered GET,HEAD,POST,PUT,DELETE. Invalid UTF8/percent escapes, controls,
encoded slash/backslash and query-in-path fail; paths are separate from queries.
`parse_query` bounds raw input8192 bytes and64 pairs, decodes + and percent bytes,
retains duplicate order; `query_value` returns the first. These are deliberate
policies, not full Go ServeMux compatibility.

## JSON

`std.json.parse(string,limits) -> (document,error)` produces an immutable-by-contract
flat node document with root0. `kind/text/get/at` inspect objects, arrays and
scalars; missing indices return-1/empty. `quote` validates UTF8 and escapes a string.
`serialize` revalidates and preserves parsed source spelling; documents are not
mutable object builders. String building for app responses uses quote, not raw
untrusted concatenation. Numeric spelling is preserved, without float rounding.

Strict UTF8 scalar validation, surrogate-pair decoding, number grammar, escaped
controls, trailing data and duplicate object keys are covered. Zero limits mean
1MiB/64 depth/4096 nodes; hard ceilings16MiB/256/65536. REST uses64KiB/16/64.
Large string handling has bounded chunk accumulation and memory-limit regressions.
This is a bounded JSON document API, not reflection-based Go encoding/json.

## Users API and repository

- GET `/api/users`: `{users:[...]}`, optional q name LIKE substring pattern and limit1..100.
- GET `/api/users/:id`: user or404.
- POST `/api/users`: JSON name/email/optional age ->201.
- PUT `/api/users/:id`: full replacement ->200, including unchanged values.
- DELETE `/api/users/:id`:204; missing ->404.

User JSON: `{id:"123",name:"张三",email:"unique@example.test",age:null}`.
IDs are decimal strings to preserve signed64-bit integers across JS; invalid,
zero and overflowing IDs reject400. Name1..200 UTF8 bytes, email3..254 ASCII bytes
with one nonterminal @, age integer0..150 orNULL. Unknown fields reject400. This
email check is a demo policy, not complete RFC mailbox validation. q retains
MySQL LIKE wildcard meanings for % and _; it remains a bound value.

Validation400; unsupported media415; duplicate email409; body overflow413;
missing routes404; unsupported methods405; database/internal failures500.
Errors have `{error:{code,message}}`; database diagnostics/credentials are not
sent to clients. HEAD/204 have no body.

The app uses explicit array-binding semicolons and prebound parameter arrays for
existing Seed parser/borrow portability. Complete app compilation/execution uses
the installed native compiler; see acceptance limitations for optional Seed TLS
closure checking.

All user input enters bound parameters. Each repository statement closes before
returning buffered data. Each business request owns and closes its connection;
UPDATE/DELETE use a transaction plus SELECT FOR UPDATE, committing only a successful
response and rolling back failures/missing rows. INSERT verifies affected_rows1
and generated ID; DELETE verifies affected_rows1. An unchanged UPDATE is valid
because existence was checked separately. No ORM or dynamic SQL identifiers.

## Verification

```sh
make rest-unit-check
make rest-http-check                # real local sockets
make rest-frontend-check            # npm registry access for npm ci
# Supply test DB env above; frontend production build must exist.
make rest-integration-check         # real MySQL8 + Next production server
```

Install the browser used by the real UI acceptance once:

```sh
cd test/rest-users/frontend
PLAYWRIGHT_BROWSERS_PATH=/tmp/s-rest-playwright npx playwright install chromium
```

The harness uses Python only as HTTP/process client, starts real S and Next
binaries, creates unique test records in the isolated table, and deletes only
those records. See [acceptance.md](acceptance.md) for executed results/exitcodes.
