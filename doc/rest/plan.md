# Native REST API Implementation Plan

> Execution: continuous implementation authorized by user; independent JSON/router tasks run in parallel, integration and final review remain coordinated.

**Goal:** Next.js -> native synchronous S REST users service -> real MySQL prepared CRUD.
**Architecture:** extend HTTP with explicit accepted-exchange ownership and bounded body receive/respond; preserve serve_next health behavior. Data-only router returns a handler ID. Bounded native JSON uses flat node storage (no unsupported recursive ownership). S service owns DB connection and statements; Next.js only proxies and renders.
**Tech stack:** existing S Seed/native, std.tcp/std.mysql, Next.js/TypeScript, Python client-only test harness.
**Spec:** user attachment 9d278ee6-0283-425a-a333-702efa798e29/Pasted text.txt.

## Constraints / rulings
- No compiler/runtime/Go changes unless an essential defect is reduced and proven; bootstrap required if changed.
- Preserve 12 legacy HTTP cases, TCP/time/TLS/MySQL/MIR/borrow baselines.
- No concurrency, keepalive, chunked transfer, auth system, ORM or migrations.
- DB credentials only environment; new table s_rest_users_v1 in configured test DB; never touch existing users rows/tables. Setup CREATE IF NOT EXISTS only, test records identified by unique per-run email.
- Explicit body/header/JSON limits and absolute read/write deadlines; close exchange exactly once on all outcomes.
- GET/POST/PUT/DELETE plus HEAD legacy health; static routes precede parameters; duplicate/conflicting patterns rejected; 405 Allow derived from matching paths.
- GET collection bounded by max rows; IDs decimal strings at JSON boundary to preserve >2^53 integers; nullable fields JSON null.
- Work in specified checkout, preserve pre-existing doc/http changes; no automatic merge or commit.

## Review focus
Framing disagreement/duplicate length -> reject and close; Unicode/surrogates -> validate; route ambiguity -> deterministic; duplicate email -> 409; disconnect/DB error -> cleanup with no leaked statements.

## Tasks
- [x] JSON: src/std/json/*.s; test/rest/json.s + test/stdlib-native/test_rest_json.py. parse(string,limits)->document,error; get/at/quote/serialize. RED missing module, GREEN real S fixtures under Seed/native; malformed UTF-8, escapes, numbers, duplicates and size/depth limits.
- [x] Router: src/std/rest/router.s; test/rest/router.s + test/stdlib-native/test_rest_router.py. add(router*,method,pattern,id), match(router,method,path)->match,error; params/query decoding; RED missing module then Seed/native positives and negatives.
- [x] HTTP: src/std/http/{types,protocol,server}.s. receive(server*) -> pending,error; respond(pending*,response)->error; discard(pending*). Keep serve_next wrapper. RED body fixture rejects POST JSON; GREEN body/header/query limits, truncation, timeouts, no-body statuses and injection-safe headers, legacy12.
- [x] Repository/app: test/rest-users/{repository,main}.s; schema.sql. Prepared statements only; all 5 operations; explicit connection/statement cleanup; transaction for update/delete read-modify response and existence checks; uniform JSON status mapping.
- [x] Frontend: test/rest-users/frontend Next.js/TS same-origin fixed-upstream proxy and CRUD page; no DB dependency. Pin supported versions with lockfile; execute real Next server end-to-end to S/MySQL.
- [x] Acceptance: real raw HTTP malformed/oversize/truncated/timeout/disconnect/SQL injection/UTF8/repeat tests; Next proxy CRUD; required regressions; independent review; exact logs/exit codes and file list doc/rest/acceptance.md. Preserve FIRST RED.

## Executed rulings and ledger
- User explicitly authorized continuous implementation and waived design confirmations.
- Pure value-returning router registration avoids unsupported mutable-array borrowed calls.
- Prefix new private helpers _json_/_rest_ to preserve Seed namespace limitations; public APIs unchanged.
- Explicit parameter-array bindings and semicolons satisfy existing borrow/parse rules; no semantic bypass.
- Bind rollback error result to keep if/else statement tail types consistent.
- Preserve HEAD method on framing failures; distinguish accepted-client transport errors from listener failures.
- Iterate JSON document.count, not allocated nodes capacity; positive validation regression retained.
- Forward query and Content-Type through fixed-origin Next proxy; never silently alter S validation inputs.
- Real browser, direct HTTP and Next proxy CRUD all executed with real MySQL8 and isolated records.
- Optional full Seed app compile stops at pre-existing TCP/TLS/crypto borrowed-helper ambiguity; verified modules/compiler left unchanged. Native application and required regressions pass.
- See acceptance.md and evidence/ for exact commands/status/exit codes.
