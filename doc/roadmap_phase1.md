# s roadmap: phase 1

this document translates the "go first phase" mindset into a practical task
list for s.

phase 1 is not about building a large standard library or ecosystem. it is
about finishing the smallest complete language-toolchain loop:

- parse source
- check source
- build source
- run basic programs
- support continued self-hosting work

## success target

at the end of phase 1, s should be able to:

- parse and type-check core language examples reliably
- build minimal native executables through a stable command path
- run self-hosting support flows without fragile ad hoc steps
- protect the core toolchain with repeatable regression tests

## p0

these are the tasks that unlock the basic language and toolchain loop.

### 1. stabilize lexing, parsing, and ast

primary directories:

- `/app/s/src/s`

tasks:

- stabilize token definitions
- stabilize lexer behavior and diagnostics
- stabilize parser output shape
- stabilize ast node structure for declarations, statements, and expressions
- keep `dump_tokens` and `dump_ast` output deterministic

done means:

- the same source always produces the same token and ast output
- examples and fixtures stop breaking because of ast churn

### 2. stabilize semantic checking

primary directories:

- `/app/s/src/cmd/compile/internal/compiler`

tasks:

- finish basic name resolution
- finish basic type checking
- validate function signatures and returns
- validate control flow constructs such as `if`, `while`, `switch`, and `return`
- validate `struct`, `enum`, `trait`, and `impl` consistency

done means:

- `s check` becomes a reliable gate for "can this compile"
- diagnostics are consistent enough to use in tests

### 3. make the build path real

primary directories:

- `/app/s/src/cmd/compile/internal/compiler`
- `/app/s/src/cmd`

tasks:

- keep `s build` stable for the current example set
- expand backend support only for constructs already needed by examples
- keep `backend_elf64.py` and `backend_elf64.s` behavior aligned
- ensure output-path handling, assembler invocation, and linker invocation are predictable

done means:

- `hello.s` and `sum.s` build and run reliably
- the command-line build path is no longer fragile

### 4. keep the runtime bridge minimal and stable

primary directories:

- `/app/s/src/runtime`

tasks:

- keep hosted execution working
- shrink python bridge responsibilities where possible
- keep intrinsic boundaries explicit
- make the native runner path stable enough for repeated use

done means:

- runtime support remains a small, well-defined layer instead of becoming a second compiler

### 5. protect the core with tests

primary directories:

- `/app/s/src/cmd/compile/internal/tests`
- `/app/s/src/testing`

tasks:

- keep golden outputs stable
- expand semantic fixtures for common failure cases
- keep build-and-run smoke tests working
- start moving reusable testing helpers into `src/testing`

done means:

- parser, semantic, and backend changes can be checked quickly and repeatedly

## p1

these tasks make the phase 1 toolchain cleaner and easier to extend.

### 6. consolidate reusable language packages

primary directories:

- `/app/s/src/s`

tasks:

- keep reusable language-facing code in `src/s`
- separate public language utilities from compiler-private logic
- begin organizing `ast`, `token`, `parse`, `types`, and `format` responsibilities clearly

done means:

- s has a clean equivalent to go's reusable `go/*` analysis packages

### 7. refine ownership and borrow checking

primary directories:

- `/app/s/src/cmd/compile/internal/compiler`

tasks:

- tighten move checking
- improve borrow conflict detection
- improve diagnostics for ownership mistakes
- cover more branch and control-flow-sensitive cases

done means:

- the ownership model becomes trustworthy for everyday compiler work

### 8. strengthen command-line tooling

primary directories:

- `/app/s/src/cmd`

tasks:

- keep `s check` and `s build` stable
- keep `lex_dump`, `ast_dump`, and `test_compiler` usable as internal tools
- reduce reliance on one-off helper scripts for common workflows

done means:

- developers interact mainly through consistent commands instead of internal entry points

### 9. keep the standard library minimal but cohesive

primary directories:

- `/app/s/src/prelude`
- `/app/s/src/result`
- `/app/s/src/option`
- `/app/s/src/vec`
- `/app/s/src/io`
- `/app/s/src/fs`
- `/app/s/src/env`
- `/app/s/src/process`

tasks:

- maintain `result`, `option`, `vec`, `io`, `fs`, `env`, `process`, and `prelude`
- fill only the missing pieces required by the compiler and basic programs
- avoid premature expansion into broad application-level libraries

done means:

- the standard library supports self-hosting needs without becoming a distraction

## p2

these tasks prepare s for the next phase after the core loop is stable.

### 10. isolate toolchain-private infrastructure

primary directories:

- `/app/s/src/internal`

tasks:

- move bootstrap-only code toward `internal/bootstrap`
- organize build configuration under `internal/buildcfg`
- organize host tool invocation under `internal/toolchain`
- isolate platform-specific logic under `internal/platform`
- isolate test-only environment helpers under `internal/testenv`

done means:

- compiler and runtime packages stay focused instead of collecting every internal helper

### 11. prepare for reduced python dependence

primary directories:

- `/app/s/src/runtime`
- `/app/s/src/internal/bootstrap`
- `/app/s/src/cmd/compile/internal/compiler`

tasks:

- clarify which hosted paths are temporary
- replace temporary python-hosted logic with s_arm64 logic where realistic
- keep the self-hosting transition incremental and testable

done means:

- the project is ready to move from a mixed bootstrap model toward deeper self-hosting

## recommended execution order

1. stabilize `/app/s/src/s`
2. stabilize semantic checking in `/app/s/src/cmd/compile/internal/compiler`
3. make the build path solid in `/app/s/src/cmd/compile/internal/compiler` and `/app/s/src/cmd`
4. keep `/app/s/src/runtime` small and stable
5. strengthen `/app/s/src/cmd/compile/internal/tests` and `/app/s/src/testing`
6. refine ownership and borrow analysis
7. consolidate reusable package boundaries in `/app/s/src/s`
8. tighten command-line tooling and minimal standard library support
9. isolate internal infrastructure in `/app/s/src/internal`
10. reduce bootstrap dependence on python

## short version

phase 1 is:

`s  compiler  runtime  cmd  std(min) tests`

the goal is to make that loop solid before chasing a larger library surface or
broader ecosystem work.
