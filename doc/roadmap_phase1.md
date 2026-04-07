# S Roadmap: Phase 1

This document translates the "Go first phase" mindset into a practical task
list for S.

Phase 1 is not about building a large standard library or ecosystem. It is
about finishing the smallest complete language-toolchain loop:

- parse source
- check source
- build source
- run basic programs
- support continued self-hosting work

## Success Target

At the end of Phase 1, S should be able to:

- parse and type-check core language examples reliably
- build minimal native executables through a stable command path
- run self-hosting support flows without fragile ad hoc steps
- protect the core toolchain with repeatable regression tests

## P0

These are the tasks that unlock the basic language and toolchain loop.

### 1. Stabilize Lexing, Parsing, and AST

Primary directories:

- `/app/s/src/s`

Tasks:

- stabilize token definitions
- stabilize lexer behavior and diagnostics
- stabilize parser output shape
- stabilize AST node structure for declarations, statements, and expressions
- keep `dump_tokens` and `dump_ast` output deterministic

Done means:

- the same source always produces the same token and AST output
- examples and fixtures stop breaking because of AST churn

### 2. Stabilize Semantic Checking

Primary directories:

- `/app/s/src/cmd/compiler`

Tasks:

- finish basic name resolution
- finish basic type checking
- validate function signatures and returns
- validate control flow constructs such as `if`, `while`, `match`, and `return`
- validate `struct`, `enum`, `trait`, and `impl` consistency

Done means:

- `s check` becomes a reliable gate for "can this compile"
- diagnostics are consistent enough to use in tests

### 3. Make the Build Path Real

Primary directories:

- `/app/s/src/cmd/compiler`
- `/app/s/src/cmd`

Tasks:

- keep `s build` stable for the current example set
- expand backend support only for constructs already needed by examples
- keep `backend_elf64.py` and `backend_elf64.s` behavior aligned
- ensure output-path handling, assembler invocation, and linker invocation are predictable

Done means:

- `hello.s` and `sum.s` build and run reliably
- the command-line build path is no longer fragile

### 4. Keep the Runtime Bridge Minimal and Stable

Primary directories:

- `/app/s/src/runtime`

Tasks:

- keep hosted execution working
- shrink Python bridge responsibilities where possible
- keep intrinsic boundaries explicit
- make the native runner path stable enough for repeated use

Done means:

- runtime support remains a small, well-defined layer instead of becoming a second compiler

### 5. Protect the Core with Tests

Primary directories:

- `/app/s/src/cmd/compiler/tests`
- `/app/s/src/testing`

Tasks:

- keep golden outputs stable
- expand semantic fixtures for common failure cases
- keep build-and-run smoke tests working
- start moving reusable testing helpers into `src/testing`

Done means:

- parser, semantic, and backend changes can be checked quickly and repeatedly

## P1

These tasks make the Phase 1 toolchain cleaner and easier to extend.

### 6. Consolidate Reusable Language Packages

Primary directories:

- `/app/s/src/s`

Tasks:

- keep reusable language-facing code in `src/s`
- separate public language utilities from compiler-private logic
- begin organizing `ast`, `token`, `parse`, `types`, and `format` responsibilities clearly

Done means:

- S has a clean equivalent to Go's reusable `go/*` analysis packages

### 7. Refine Ownership and Borrow Checking

Primary directories:

- `/app/s/src/cmd/compiler`

Tasks:

- tighten move checking
- improve borrow conflict detection
- improve diagnostics for ownership mistakes
- cover more branch and control-flow-sensitive cases

Done means:

- the ownership model becomes trustworthy for everyday compiler work

### 8. Strengthen Command-Line Tooling

Primary directories:

- `/app/s/src/cmd`

Tasks:

- keep `s check` and `s build` stable
- keep `lex_dump`, `ast_dump`, and `test_compiler` usable as internal tools
- reduce reliance on one-off helper scripts for common workflows

Done means:

- developers interact mainly through consistent commands instead of internal entry points

### 9. Keep the Standard Library Minimal but Cohesive

Primary directories:

- `/app/s/src/prelude`
- `/app/s/src/result`
- `/app/s/src/option`
- `/app/s/src/vec`
- `/app/s/src/io`
- `/app/s/src/fs`
- `/app/s/src/env`
- `/app/s/src/process`

Tasks:

- maintain `result`, `option`, `vec`, `io`, `fs`, `env`, `process`, and `prelude`
- fill only the missing pieces required by the compiler and basic programs
- avoid premature expansion into broad application-level libraries

Done means:

- the standard library supports self-hosting needs without becoming a distraction

## P2

These tasks prepare S for the next phase after the core loop is stable.

### 10. Isolate Toolchain-Private Infrastructure

Primary directories:

- `/app/s/src/internal`

Tasks:

- move bootstrap-only code toward `internal/bootstrap`
- organize build configuration under `internal/buildcfg`
- organize host tool invocation under `internal/toolchain`
- isolate platform-specific logic under `internal/platform`
- isolate test-only environment helpers under `internal/testenv`

Done means:

- compiler and runtime packages stay focused instead of collecting every internal helper

### 11. Prepare for Reduced Python Dependence

Primary directories:

- `/app/s/src/runtime`
- `/app/s/src/internal/bootstrap`
- `/app/s/src/cmd/compiler`

Tasks:

- clarify which hosted paths are temporary
- replace temporary Python-hosted logic with S-native logic where realistic
- keep the self-hosting transition incremental and testable

Done means:

- the project is ready to move from a mixed bootstrap model toward deeper self-hosting

## Recommended Execution Order

1. Stabilize `/app/s/src/s`
2. Stabilize semantic checking in `/app/s/src/cmd/compiler`
3. Make the build path solid in `/app/s/src/cmd/compiler` and `/app/s/src/cmd`
4. Keep `/app/s/src/runtime` small and stable
5. Strengthen `/app/s/src/cmd/compiler/tests` and `/app/s/src/testing`
6. Refine ownership and borrow analysis
7. Consolidate reusable package boundaries in `/app/s/src/s`
8. Tighten command-line tooling and minimal standard library support
9. Isolate internal infrastructure in `/app/s/src/internal`
10. Reduce bootstrap dependence on Python

## Short Version

Phase 1 is:

`s  compiler  runtime  cmd  std(min) tests`

The goal is to make that loop solid before chasing a larger library surface or
broader ecosystem work.
