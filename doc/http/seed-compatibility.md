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

## Files changed in this correction

- `src/cmd/compile/seed/semantic/native_borrow.h`: transparent lowering scope lifetime.
- `src/cmd/compile/seed/semantic/analyzer.c`: package function identity and exact
  signature checks for ambiguous source leaves.
- `src/cmd/compile/seed/intermediate/ir.c`: collision keys and matching metadata/calls.
- `test/http/seed-borrow-repro/reduced/main.s`: minimal regression fixture.
- `test/http/seed-borrow-repro/main.s`: update the full-closure fixture description.
- `test/stdlib-native/test_seed_borrow_integration.py`: focused positive/negative tests.
- `doc/http/seed-compatibility.md`, `doc/http/seed-compatibility/*`,
  `doc/http/README.md`, `doc/http/results.md`: acceptance evidence and historical links.

Existing worktree changes to `makefile`, `test/http/server.s`,
`test/stdlib-native/test_http.py`, `doc/http/plan.md`, and prior milestone artifacts
were present before this correction and are preserved.

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
| PASS | `S_HTTP_COMPILER="$work/stage2" python3 test/stdlib-native/test_http.py -v` | fresh Stage2, 12/12 real sockets | 0 |
| PASS | `S_HTTP_COMPILER="$work/stage3" python3 test/stdlib-native/test_http.py -v` | fresh Stage3, 12/12 real sockets | 0 |
| PASS | `S_HTTP_COMPILER="$work/stage4" python3 test/stdlib-native/test_http.py -v` | fresh Stage4, 12/12 real sockets | 0 |
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

PASS: the official fresh chain completed on 2026-11-13, exit 0.

```sh
work=$(mktemp -d "$PWD/.bootstrap/http-seed-compat.XXXXXX")
S_SOURCE_ROOT="$PWD" S_BOOTSTRAP_PROGRESS=0 S_BOOTSTRAP_TIMEOUT=7200 \
  bash src/cmd/dist/native-bootstrap-no-manifest.sh "$work"
```

Actual output directory: `.bootstrap/http-seed-compat.vMZ9WC`.
[Full bootstrap output](seed-compatibility/bootstrap.log).
All stages passed native artifact verification. Stage2/3/4 assembly and binaries
converged; the official source-dependent execution probes passed at each stage;
source hashes matched after execution; `.complete` exists (checked exit 0).

Actual final output:

```text
Native bootstrap verified: seed -> stage1 -> stage2 == stage3 == stage4
```

SHA-256:

- Stage1: `75a0a83b61d38820eb6d3af4e0905372aadcc4ef6d5c585d666115a6a49212f6`
- Stage2 = Stage3 = Stage4: `ddba78e8b1e03271d7f6f288c53d55df06d7f6b91c58eb5418a3d8ea1d5b2583`

Superseded experiments are not counted as acceptance: an earlier run was stopped
(exit 143) after further changes were needed; an intermediate run failed (exit 1)
on overbroad checking of the existing `to_string(bool)` builtin. The final fix
restricts new signature checks to colliding source leaves, and the successful
chain above was restarted from Seed. An external commit (`daba2618f`) captured
working-tree changes during testing; no history was rewritten and the official
source integrity check passed.

## Scope and limitations

No new HTTP features. Existing synchronous Linux/amd64 HTTP slice limits remain.
Bare package-local borrowed helpers with colliding leaf names still encounter
Seed's pre-existing ambiguity rejection; qualified HTTP calls are covered and pass.
Native lexical-call shadow behavior is outside this Seed correction; the new
shadow rejection assertion runs only under Seed. No broader compiler parity claim.
Go worktree's pre-existing deleted `src/cmd/compile/profile.sh` is untouched.
