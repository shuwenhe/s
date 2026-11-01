# P1.2-H execution capability audit

The audited toolchains do not yet provide an execution path for the unchanged
pointer-based `parser.syntax`. Parser AST assertions have not executed.

## Reproducible observations

| Path | Observed capability | First missing parser requirement |
| --- | --- | --- |
| `bin/s_compiler build` | Integer control compiled and ran, exit 0 | `alloc(Cell)`: `unknown callee: harness_alloc.alloc` |
| `bin/s_compiler --emit-c` (saved binary) | Control and deliberately false assertion ran, exits 0 and 17 | `alloc`: unresolved; local-string address rejected; helper parameter-name storage missing |
| `.bootstrap/native-imports/stage1 --emit-c` | Same control and false assertion ran | Same missing allocator and helper storage observed |
| Isolated rebuild after initialization repair | Shared reads, mutable writes and cross-call boxed-field mutation executed | Typed allocation was still missing |
| Isolated rebuild with H1 slice | `alloc(int)` and scalar-field struct allocation, move/borrow/drop executed | `alloc_array`, recursive/reference fields, generic pointer parameters and local-string address unsupported |
| Isolated rebuild with H2 slice | Local integer/string and scalar-field references; typed string-reference calls; source-reference probe executed | `alloc_array`, recursive/reference fields and arbitrary `Type*` parameter APIs unsupported |
| Seed phase/runtime diagnostic | Actual lexer lowered; `lexer_new` invoked until the failing ARG | Type operand treated as value; no allocator dispatch; address-of rejected semantically |

The saved binaries were hashed separately. Their behavior is not inferred
from the current source tree. The rebuilt compiler used the resolved
253-source closure, Stage0 Seed, and the hosted IR executor; it is not a
standalone self-hosted compiler.

## Implemented repairs

`compiler_compile` did not initialize `compiler_state.function_param_names`.
Declaring a helper wrote an indexed element of that absent array and stopped
the hosted executor before generating C. Initialize the table to the existing
empty local-name array capacity.

Following the user's lifecycle decision, the S frontend now recognizes `alloc`
with a type operand. The first slice supports `int` and scalar-field local
structs, including a checked current-package qualifier. It reuses the existing
typed constructors, owner identities, move checks and drop glue. Scalar field
assignment preserves normal value copying and type/borrow checks. Generated
empty field-destructors explicitly mark their parameter used; the C runtime
header includes the string declaration required for string-field assertions.
There are no Seed, Parser or production-dispatch changes.

Before the fix, `check-existing-references.sh` returned 1 with:

```text
unknown index-set target: s.function_param_names
```

After rebuilding into a temporary directory:

| Executed program | Actual exit | Evidence |
| --- | --- | --- |
| `box_reference.s` | 0 | A helper reads the caller's borrowed box |
| `box_mutation.s` | 0 | Caller observes the helper's write |
| `box_field_mutation.s` | 0 | Caller observes the changed left field and unchanged right field |
| Existing `test/compiler/functions.s` | 42 | Existing calls, ownership, shared/mutable references and allocation-count assertions ran |
| `shared_reference_write.s` | Compiler exit 1 | Exact semantic diagnostic: `write requires an owner or mutable reference` |
| `assertion_failure.s` | 17 | False runtime assertion produces the expected nonzero status |
| Existing `test/compiler/pair.s` | Compiler exit 1 | `compiler:20: conflicting field borrow: p` |

The H1 broader regression script returned **1**, not PASS. The minimized
`independent_field_borrows.s` fails with the same field-borrow conflict in the
saved binary and the rebuild, establishing a pre-existing failure independently
of helper parameter storage. Do not infer generic pointers from the working
box/reference cases.

H2 subsequently resets field-loan counters for fresh object bindings, including
nested field facts. Both the minimized case and existing `pair.s` now execute
with the expected exits. The final broader regression script returns **0**.

## H2 reference checks

The current slice borrows the actual storage of integer/string locals and
scalar struct fields. It preserves pointee types in generated C, tracks shared
and mutable loans, supports typed string-reference parameters (`ref string` /
`mutref string`), and uses one argument/loan path for expression and statement
calls. It also fixes string helper return types and distinguishes void return
metadata from an unresolved function.

The 11 positive execution cases cover scalar and string-source addresses,
`len(*reference)`, cross-call reads/writes, ignored-result and void calls,
shared-reference copying, reborrowing, integer/string fields, scope-ending
field borrows and independent function-local loans. The 17 negative cases
cover invalid addresses, shared writes, conflicting loans/arguments, mutation
or reads through a conflicting alias, mutable-reference copies/upgrades,
type mismatch, local/value-parameter/owner-parameter dangling returns, owner
drop during a field loan, unsupported stored-reference lifetimes and void
values. A copied or consumed parameter is not a valid source for a returned
reference; the new regression cases were accepted before this fix.

All 11 positive cases ran with ASan/UBSan under the previously documented
`ASAN_OPTIONS=detect_leaks=0` environment limitation. H1's 6 positive and 11
negative cases also passed again, and the existing reference regression suite
is green. These results concern the explicitly selected S C emitter. They do
not establish a canonical MIR/SSA handoff or native production self-hosting.

## H1 type and lifetime checks

`check-owned-allocation.sh` passed 6 executable positive cases and 11 semantic
rejection cases. The positive cases check zero/empty initialization, typed
field access, scalar assignment, explicit/automatic drop, allocation counts,
move without a second allocation, qualified type lookup, and shared/mutable
borrowing of an allocated integer. Negative cases cover an unknown type,
a value used as a type, arity, foreign package qualifier, use after move,
double drop, dropping a borrowed owner, incompatible struct identities,
field type/name errors, and unsupported owning fields.

The generated programs ran with AddressSanitizer and UndefinedBehaviorSanitizer.
LeakSanitizer failed in this environment because it cannot operate under ptrace;
the successful run explicitly used `ASAN_OPTIONS=detect_leaks=0`. Do not report
that as successful leak-sanitizer verification.

## Evidence directories from this run

- Initial capability matrix: `/tmp/s-parser-capabilities.VjHKaPjp`.
- Regression RED: `/tmp/s-existing-references.h2BP5DhU`.
- Isolated compiler build: `/tmp/s-harness-compiler.wcz4w9UB`.
- Rebuilt capability matrix: `/tmp/s-parser-capabilities.8c33EhYH`.
- Full regression observations, including pair failure and assertion exit:
  `/tmp/s-existing-references.qnled1Jv`.
- Latest H1 compiler: `/tmp/s-harness-compiler.8ZoSpDlu`.
- Latest H1 execution/rejection tests with ASan/UBSan:
  `/tmp/s-owned-allocation.pmQvfczH`.
- Latest capability matrix: `/tmp/s-parser-capabilities.Y68SRIVP`.
- Latest broader regressions (exit 1): `/tmp/s-existing-references.7Ac0aSFp`.
- Pre-fix minimized borrow failure, with complete recorded audit commands:
  `/tmp/s-parser-capabilities.qFkXpUEz`; the post-initialization-fix comparison
  is `/tmp/s-parser-capabilities.QbfNNT4C`.
- Final H2 compiler: `/tmp/s-harness-compiler.X3dqrAxn`.
- Final H2 suite (exit 0): `/tmp/s-reference-semantics.94yQK7SS`.
- H1 recheck after H2 (exit 0): `/tmp/s-owned-allocation.86aVQ33M`.
- Final existing-reference regressions (exit 0):
  `/tmp/s-existing-references.Vq8k4sRx`.
- Final capability matrix: `/tmp/s-parser-capabilities.KRDI9mpv`.

Each audit/build directory contains the commands, exit statuses and hashes
needed to distinguish compilation failure from execution failure. Temporary
paths are local evidence and are not checked-in bootstrap artifacts.

## Decision boundary

The existing owner/reference path is reusable only for its documented subset.
The implemented H1 slice extends it without changing Parser source. Adapting
the full Parser to this subset would require a separate source/API migration.
Implementing raw typed allocation in Seed would require an actual reference
value representation, typed allocation IR, field access and lifetime handling;
adding an ordinary `alloc` function cannot provide those semantics.

The user explicitly chose ownership management with move/borrow/drop for
`alloc(T)` and `alloc_array(T,n)`. This is the lifecycle contract for subsequent
work; the first slice implements it for scalar/leaf allocations only.

```text
H1 Scalar/Leaf Allocation Slice = EXECUTED AND CHECKED
H1 Complete Parser Allocation   = NOT PROVEN
H2 Scalar/String Reference Slice = EXECUTED AND CHECKED
H2 Parser Reference Semantics  = NOT PROVEN
H3 Raw Pointer Mutation        = NOT PROVEN
Existing Box/Reference Probes  = EXECUTED
Broader Reference Regressions  = PASS
Real Parser Execution         = NOT REACHED
Two-file AST Assertions        = NOT REACHED
Function Payload               = NOT PROVEN
Full Self-hosting              = NOT PROVEN
```
