# Seed native HTTP compatibility acceptance

This report supersedes the Seed failure section of the original HTTP milestone
report. Original RED logs are retained rather than rewritten.

## Root causes and fix

1. `borrow_leaf_inner` expired all bindings at every AST block. Tuple-result
   destructuring creates a transparent lowering block, not a source lexical
   scope. Its locally owned record disappeared from the proof before the next
   nested borrowed call. Preserve bindings only for `transparent_scope`, matching
   the existing `borrow_walk` rule. Real lexical scopes still expire.
2. Once borrow preflight passed, Seed merged `std.tcp.local_port` and
   `std.http.local_port` into one bare function namespace. Register package
   identities, preserve only unambiguous legacy aliases, and use collision keys
   consistently for IR definitions, calls, exports and transfer/borrow metadata.
   Ambiguous qualified calls check the exact package signature. Unique legacy
   builtins retain their existing overload rules.

The nested call is semantically valid: it mutably reborrows a live owned local,
with no escape or overlapping exclusive argument. Splitting the source call
cannot repair Seed discarding that local's tuple-derived provenance. No HTTP
implementation, runtime, ownership rule, MIR verifier or Go source was changed
for this correction.

## Reproductions and regression

- [Minimal S reproduction](../../test/http/seed-borrow-repro/reduced/main.s) (path
  from repository root: `test/http/seed-borrow-repro/reduced/main.s`).
- Full no-socket caller: `test/http/seed-borrow-repro/main.s`.
- `test/stdlib-native/test_seed_borrow_integration.py`: valid tuple owner,
  expired lexical owner, wrong nominal owner, aliased exclusive arguments,
  distinct package signatures, same-package duplicate rejection, bare/qualified
  argument mismatch, Seed lexical shadowing, and preservation of existing output
  on compile failure. Full HTTP closed-server fixture executes under both compilers.
- The existing HTTP suite compiles and executes both protocol and complete server.

RED evidence: [full server](seed-compatibility/full-server-red.log),
[tuple owner](seed-compatibility/tuple-red.log),
[namespace](seed-compatibility/namespace-red.log). Valid minimal program was
rejected by Seed (exit 1), accepted/executed by native (exit 0).

## Executed verification

All commands run from the S repository. Real loopback and strace tests use the
explicitly authorized execution environment. MySQL here is compilation regression,
not database authentication or a CRUD runtime claim.

| Status | Command | Result | Exit |
|---|---|---|---|
| PASS | `make seed-compiler-bin` | C Seed rebuilt with warnings as errors | 0 |
| PASS | `python3 test/stdlib-native/test_seed_borrow_integration.py -v` | 6 tests, Seed/native fixtures | 0 |
| PASS | `S_HTTP_COMPILER="$PWD/bin/s_seed" python3 test/stdlib-native/test_http.py -v` | 12/12, real sockets, protocol/server | 0 |
| PASS | `S_HTTP_COMPILER="$work/stage1" python3 test/stdlib-native/test_http.py -v` | fresh Stage1, 12/12 real sockets | 0 |
| PASS | `make http-integration-check` | native compiler, 12/12 real sockets | 0 |
| PASS | `python3 test/stdlib-native/test_tcp.py -v` | 3/3 | 0 |
| PASS | `python3 test/stdlib-native/test_time.py -v` | 6/6 | 0 |
| PASS | `python3 test/stdlib-native/test_tls.py -v` | 4/4 | 0 |
| PASS | `python3 test/stdlib-native/test_mysql_compiler.py -v` | 4/4 | 0 |
| PASS | `bash test/native-bootstrap-diagnostic/canonical_mir_public_check.sh` | MIR closure and native handoff | 0 |
| PASS | `bash test/native-bootstrap-diagnostic/native_record_borrow_check.sh` | ownership negatives, forged IR rejection | 0 |

[Raw logs](seed-compatibility/) retain actual command output.

Compiler SHA-256:

- Seed: `aa4a33be7a7ebabc66c4546daf6feff461e77a15bf4626749541340af725e2a8`
- Installed native: `7ba771c0dc3379845ccc359488f35300fb0035675782d726695a43763d1271e7`

## Bootstrap

The fresh official acceptance chain is still executing. Its observed terminal
result will be recorded here before completion.
The superseded intermediate bootstrap exposed overbroad checking of the existing
`to_string(bool)` builtin (exit 1). The final fix restricts new signature checks
to colliding source leaves and restarts the entire chain.

## Scope and limitations

No new HTTP features. Existing synchronous Linux/amd64 HTTP slice limits remain.
Bare package-local borrowed helpers with colliding leaf names still encounter
Seed's pre-existing ambiguity rejection; qualified HTTP calls are covered and pass.
Native lexical-call shadow behavior is outside this Seed correction; the new
shadow rejection assertion runs only under Seed. No broader compiler parity claim.
Go worktree's pre-existing deleted `src/cmd/compile/profile.sh` is untouched.
