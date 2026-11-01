# Parser harness recovery: first failure

Run from the repository root:

```sh
bash test/parser-harness/diagnose.sh
```

This is a diagnostic of the existing Seed path, not a recovered parser test
executor. Exit 0 means that all three reported limitations were reproduced;
it does **not** mean that parser assertions or pointer calls passed. A change
to those limitations makes the diagnostic fail, prompting reassessment.

The script builds a temporary C probe against the current Seed sources. It
does not invoke `bin/s_seed`, generate a new compiler stage, change parser
sources, or rewrite the real lexer's IR. Artifacts remain in the printed
temporary directory: input hashes, HEAD, build command, actual lexer IR,
diagnostic output and exit status.

The probe parses and lowers the actual `parser/syntax/lexer.s` to inspect the
failing IR. This is deliberately a phase-only experiment: it does not run
semantic checking on the lexer module, and does not claim a checked program.
It invokes `lexer_new` with a zero sentinel, which is never read before the
failure. This invocation is not evidence of valid pointer marshalling.

## Observed failures

1. The real `lexer_new` produces an unquoted
   `ARG|compile.internal.parser.syntax.syntax_lexer|_|_`, followed by a call to
   `alloc`. The runtime fails resolving that ARG, before allocator dispatch.
2. An independent, hand-authored IR control supplies a quoted type-name
   string. Value resolution then succeeds, but dispatch reports
   `unknown function: alloc`. Quoting is not a fix and is not applied to the
   lexer's IR.
3. A separate source-level address-of probe is rejected by Seed semantic
   checking with `unsupported unary operator`, before IR generation.

The runtime defines integer, float, string and array values; record fields are
represented via aliases. That is not evidence of native pointer support.
Consequently, this error cannot be described as a machine ABI failure: the
observed failure is inside the hosted IR evaluator.

## Required next implementation boundary

A harness that simply invokes this hosted evaluator cannot exercise the
unchanged pointer-based parser. The execution toolchain must first support
typed allocation, array allocation, references and cross-call field mutation,
with an explicit memory model. Merely defining the type-name operand or
removing its package qualifier cannot provide those semantics.

The diagnostic adds no allocator stub, parser replacement, source rewriting,
or fallback. It intentionally leaves these acceptance gates unfulfilled:

```text
Parser Harness          = BLOCKED
Pointer/Struct Calling  = NOT VERIFIED
AST Assertions          = NOT REACHED
Negative AST Assertions = NOT REACHED
Function Payload        = NOT PROVEN
```

## Existing execution paths

Run `bash test/parser-harness/audit-capabilities.sh` to observe the current
native build, hosted C emitter, and saved Stage1 C emitter. The script records
commands, source/compiler hashes, each phase's exit status, and logs in its
printed artifact directory. Its exit status only reports whether the audit
ran; the TSV is an observation matrix, not a Parser acceptance result.

`S_HARNESS_COMPILER=/absolute/path/to/compiler` selects a candidate compiler
for native and hosted-C observations; saved Stage1 remains a separate path.

An isolated rebuild for testing is available via:

```sh
bash test/parser-harness/build-test-compiler.sh
bash test/parser-harness/check-existing-references.sh /printed/path/compiler
```

The rebuild explicitly uses Seed as Stage0 to build the existing 253-source
compiler closure and its hosted IR runner. It does not replace `bin/s_compiler`
or a Stage1 artifact. This is not independent S bootstrap evidence.

The existing C emitter supports `box`, `ref`, and `mutref`. Its main state
initializer omitted `function_param_names`, causing helper declarations to
abort inside the hosted executor. Initializing that table restores the
existing helper path without adding allocator/reference semantics.

The regression script executes shared-reference reads, mutable-reference
writes, cross-call writes to a pair's boxed field (checking both fields),
the existing `test/compiler/functions.s` and `test/compiler/pair.s`, a
shared-reference write rejection, and a deliberately false assertion.
During H1 the broader `pair.s` case failed with
`compiler:20: conflicting field borrow: p`. H2 resets field-loan facts when
binding fresh objects; both the minimized case and `pair.s` now execute.

## H1 owned allocation slice

The confirmed lifecycle decision is ownership management with move/borrow/drop,
not GC allocation. The S C emitter now handles a real type operand for
`alloc(int)` and `alloc(LocalStruct)` / `alloc(current.package.LocalStruct)`.
Leaf structs may contain integer/bool or string fields. Default values are
zero and the empty string. Allocation uses existing typed owner constructors
and drop glue; consuming an owner moves it, borrowing preserves identity,
and explicit or scope-exit drop releases it. Owning/reference fields are
explicitly rejected by this initial slice.

Run the new execution and semantic-rejection tests with the isolated compiler:

```sh
bash test/parser-harness/check-owned-allocation.sh /printed/path/compiler
ASAN_OPTIONS=detect_leaks=0 S_HARNESS_SANITIZE=1 \
  bash test/parser-harness/check-owned-allocation.sh /printed/path/compiler
```

The tests cover real allocation, type identity, default fields, scalar writes,
move, shared/mutable borrowing of an allocated integer, explicit/automatic
drop and negative lifetime/type cases. ASan/UBSan execution passed with the
recorded options. LeakSanitizer could not run in this ptrace environment;
allocation-count assertions are additional checks, not a claim that LSan ran.

This does not implement `alloc_array(Type,n)`, recursive/reference fields or a
generic `Type*` parameter. H1 as a whole and
the real Parser Harness remain unproven. There is no Parser source migration,
Seed extension or automatic fallback.

## H2 local scalar/string reference slice

The S C emitter supports `&local` / `&mut local` for integers and strings, and
for scalar fields of owned structs. These are actual addresses of the original
storage; dereferencing a mutable reference updates that storage. Shared
references can be copied, mutable references require reborrowing, and local
reassignment/read operations respect active loans.

Existing `ref` / `mutref` integer parameters also accept borrowed scalar
locals and fields. String-reference parameters use `ref string name` and
`mutref string name`. Statement calls use the same argument typing and loan
handling as expression calls, including void calls. Void results cannot be
bound as values. The string helper return ABI retains the string type.

Reference returns are restricted to borrowed parameters: returning the address
of a local, copied value parameter or consumed owner parameter is rejected.
Storing a reference in a struct constructor is explicitly unsupported until
field lifetime tracking exists.

```sh
ASAN_OPTIONS=detect_leaks=0 S_HARNESS_SANITIZE=1 \
  bash test/parser-harness/check-reference-semantics.sh /printed/path/compiler
```

This suite passes 11 executable positive cases and 17 semantic rejection cases,
including the original `len(*reference)` string-source probe. It does not
execute `parser.syntax`, implement arbitrary `Type*` parameters, or prove the
full Parser Harness. The Seed diagnosis still reproduces its original errors;
the verified reference path is the explicitly selected S C emitter.
