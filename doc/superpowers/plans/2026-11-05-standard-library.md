# Standard library implementation plan

Goal: implement the attached first-class standard-library mission, directly on main, without pushes or feature branches. User explicitly authorizes autonomous design/implementation; preserve existing sources and bootstrap evidence.

## Design decisions

- Add verified public packages as `src/std/time.s`, `terminal.s`, `input.s`. Existing `src/time/time.s` and syscall/runtime experiments remain compatibility history, not public native support claims.
- Use existing S structs, int64 int, explicit result/error tuples, receiver methods and arrays. Errors carry positive Linux errno; zero denotes success. No pointer-as-integer user API or hidden external executable supplies time/input behavior.
- Minimal typed compiler intrinsics bridge to a shared freestanding Linux/amd64 assembly implementation. Generate identical raw OS routines into the canonical runtime string and seed runtime; adapt tagged integers only at seed boundaries. Keep the frozen 268-S-file compiler closure count unchanged.
- Clocks return checked int64 nanoseconds; elapsed timers use CLOCK_MONOTONIC. nanosleep validates timespec and retries EINTR with remaining time; no busy waits. Explicitly bound representable durations and report overflow.
- Terminal/input own explicit sessions and restoration, bounded output/escape buffers, errno/EOF/nonblocking distinctions. Real PTY integration tests verify restoration and arrows. Snake is S application logic with no ncurses/C++ dependency.
- Public driver must resolve real imported module sources; low-level --compile-unit remains explicit and receives the same sources in stage tests.

## Implementation and acceptance

1. Audit all library sources/public signatures/imports/intrinsics/placeholders; retain inventory and support matrix with execution coverage separate from source presence.
2. Write failing real-compiler time API/native execution tests. Implement typed OS boundary, time API, CPU/elapsed/boundary/EINTR/injected-error tests. Verify native development and standalone seed paths, relevant MIR/SSA/ABI regressions, full production; commit.
3. Implement terminal byte output/dimensions/session restoration and input polling/raw mode/escape parsing. Add PTY, short-write/EINTR, EOF/error and restoration tests; commit tested increments.
4. Integrate actual module imports and S Snake example, fixed-seed/headless logic plus PTY application tests; commit.
5. Complete approved fundamental/advanced packages by the same red/green/native/error/performance cycle, preserving existing conventions and rejecting false-success stubs.
6. Document exact APIs, error/lifetime/platform/version policy; run broader regressions, staged compatibility and fresh bootstrap. Keep reports/receipts under ignored .bootstrap/stdlib-mission-20261105.

## Review focus

- EINTR must not turn sleeps into immediate success or corrupt remaining timespec.
- Nanosecond arithmetic must not wrap into an apparent timestamp/error.
- Linux syscall register/stack ABI must preserve caller/callee contracts in seed and canonical paths.
- Raw terminal restoration must preserve the original settings on normal exit and handled failures.
- Normal imported user builds must exercise real library sources and native compiler, without fallback to C or a host application.

## Ledger

- Starting tree clean on main at 85dc9ba71. No AGENTS.md currently exists at repository/parent paths; main-only user instruction remains binding.
- Retained baseline .bootstrap/production-mission-20261105/baseline-full/evidence/ACCEPTED.json independently inspected: all eight full bootstrap/production gates PASS at its frozen revision. No new source certification inferred.
- Initial inventory: src/time/time.s uses package src.time, unverified syscall/float/channel dependencies, fake date formatting, empty duration formatting, nil timers and success-like timezone fallback. std.syscall passes zero pointers for path/buffer/process parameters. These do not satisfy the requested time or I/O contracts.
- Time implementation: shared raw OS routines generated into existing compiler S file and seed assembly; exact MIR/SSA signatures; duration/timespec/errno/timer APIs. Six acceptance tests pass including real repeated signals, injected errors, CPU and seed paths. Complete production run exited 0, evidence time-production.exit.
- Seed integration: fixed missing primitive aliases, typed clock/sleep borrow-flow contracts, static qualified borrowed calls with shadow guard and transparent tuple scope. Explicitly qualified public duration receiver spelling keeps existing seed/canonical declaration identities compatible.
- Source VERSION was deliberately removed in current history. Reproduced existing CLI/installation failures, added development-identity fallback without recreating the source VERSION file; 16 CLI tests passed. Commit 7d3ce6ba4 on main.
- Public module orchestration under implementation: std.time normal build/run/test, local package helpers and dependency output aliases have red/green tests. Review found merging unrelated cwd/project sources; regression added and resolver changed to first-root precedence.

- Terminal/input: native and seed shared OS boundary, exact PTY restoration, signal-safe short writes and bounded parser implemented. Terminal11/input9/time6 tests pass after integration; see doc/stdlib/terminal-input-acceptance-20261105.md. External commits through4b0041d68 captured module implementation without branch changes.
- Native S Snake: public import build and deterministic game rules plus PTY rendering/input/timing test pass (3). Fundamental/advanced modules and final staged certification remain open.

## Fundamental increment: std.string

Audit found only placeholder src.strings; std.prelude already provides native integer formatting, byte character access and slicing. Reuse those exact intrinsics. Add byte-oriented checked slicing/access, lexicographic comparison, constant-space Two-Way search, prefix/suffix/contains, split/join/replace, ASCII trimming/case conversion and strict signed decimal conversion. No Unicode normalization claim. Tuples use string_error errno conventions; empty split/replace separators reject EINVAL, missing search returns -1. Build joins with balanced recursion to avoid repeatedly copying the whole prefix. Validate against Python-generated deterministic cases and native/seed int64 boundaries, embedded NUL and repetitive-search and dense-split benchmarks. No compiler change is intended.

- String review caught quadratic prefix-table and split array copies. Replaced prefix-table KMP with constant-space critical factorization; split now uses balanced immutable string-array concat with exact MIR/SSA and Seed proof signatures. Dense split and exhaustive matching checks added. Seed two-array allocation argument reload bug and missing proof trigger reproduced; fixing before acceptance.

- String scaled acceptance: all3tests pass (native/seed,3937exhaustive searches,100Pythoncases,32KiBneedle,16385fields,negative signatures); native search2.632ms/split+join8.881ms/peak16884KiB, seed16.203ms/51.510ms/2704KiB. Independent follow-up review found no additional concrete defect. See string-acceptance-20261105.md.

## Fundamental increment: std.collections

The legacy std.vec implementation has unverified intrinsic storage and mutability contracts; ordinary native arrays copy on append/set. Implement immutable AVL maps with string keys and generic values, sets and indexed vectors with structural sharing: child links are zero/one-element node arrays, updates rebuild only the O(log n) search path. Use the map for vector/stack and a pair of stacks for FIFO queues. Iterators hold a persistent map snapshot and select by stored subtree counts, avoiding eager quadratic key arrays. Explicit typed errors protect index/size boundaries. Existing option represents absent entries and empty pops. Native and seed functionality plus randomized model traces, balance/count checks, snapshot preservation, invalid types and scaling are acceptance gates. Numeric vector indices use fixed-width decimal keys in the shared ordered tree. Constructors infer value types from typed arrays, using supported S syntax. This increment adds no new runtime primitive.

- User steering: keep Snake only in external /root/shuwen/snake. Repository example deletion is preserved. The PTY harness now takes S_SNAKE_SOURCE (default external snake_native.s), copies that selected source into an isolated test directory, and builds via the public driver. External application integration is an explicit make target, separate from the self-contained distribution production recipe.
- String full production: frozen dd8e8e210 complete recipe exit0 in string-production-v2.exit. Initial run reached final cost gates but lacked copied compiler.ir; preserved failure, copied matching IR and reran the entire recipe successfully.
- Parallel writer: user requested temporary suspension after repeated source restoration/deletion. Matching VS Code AgentHost log identified another AI session; paused AgentHost544198/Copilot544269 with SIGSTOP, retained resume commands and identities in .bootstrap/stdlib-mission-20261105/paused-conflicting-writer.json. Current Codex and bootstrap processes continue.
