# Minimal `backend_elf64` Design

This document defines the smallest executable backend we want for
[`backend_elf64.s`](/app/s/compiler/backend_elf64.s).

The goal is not a general-purpose optimizer or a full code generator.
The goal is to make the S compiler's own `build` path real with the
smallest Linux `x86_64` ELF backend that can compile the current examples.

## Target

- OS: Linux
- Architecture: `x86_64`
- Output: static ELF executable
- Entry: `_start`
- Toolchain contract: emit assembly, then invoke host `as` and `ld`

## MVP Scope

The first executable version only needs to support the subset already used by:

- [hello.s](/app/s/examples/s/hello.s)
- [sum.s](/app/s/examples/s/sum.s)

That means:

- `package main`
- `func main()`
- integer literals
- string literals
- local variable declarations
- assignment
- `i++`
- binary `+`
- binary `<=`
- `for (init; cond; step) { ... }`
- `println(...)`
- `eprintln(...)`
- integer return from `main`

Anything outside this subset can return `BackendError` during MVP.

## Backend Strategy

The minimal backend should stay intentionally simple:

1. Evaluate the current front-end AST with a tiny compile-time executor
2. Record observable effects as a linear program
3. Lower that linear program to Linux syscalls in assembly
4. Call `as` and `ld`

This is the same shape as the current Python backend in
[`backend_elf64.py`](/app/s/compiler/backend_elf64.py), but rewritten as an
explicit S-side backend contract.

## Why This Shape

This is the fastest path to a real self-hosted `build`.

Instead of first building a full register allocator, instruction selector,
stack frame layout, and relocation model, we start with a backend that only
needs to emit:

- write-to-stdout
- write-to-stderr
- process exit

That is enough for the current example programs.

## Execution Model

The MVP backend has two layers.

### Layer 1: Compile-Time Executor

It walks the checked AST and produces a linear list of operations:

- `WriteStdout(text)`
- `WriteStderr(text)`
- `Exit(code)`

Suggested S-side shape:

```s
enum ProgramOp {
    WriteStdout(WriteOp),
    WriteStderr(WriteOp),
    Exit(ExitOp),
}
```

Supporting structs:

```s
struct WriteOp {
    String text,
}

struct ExitOp {
    int code,
}
```

The executor only needs an environment of local integer/string values.

Suggested value model:

```s
enum Value {
    Int(int),
    String(String),
    Bool(bool),
    Unit(()),
}
```

### Layer 2: Assembly Emitter

It lowers those `ProgramOp` values into assembly text.

For each write operation:

- put payload bytes into `.data`
- emit syscall `write(1|2, ptr, len)`

For exit:

- emit syscall `exit(code)`

## Assembly Contract

The generated assembly can stay extremely small.

Expected structure:

```asm
.global _start

.section .data
message_0:
    .byte ...

.section .text
_start:
    mov $1, %rax
    mov $1, %rdi
    lea message_0(%rip), %rsi
    mov $LEN, %rdx
    syscall

    mov $60, %rax
    mov $0, %rdi
    syscall
```

Syscall numbers:

- `1`: `write`
- `60`: `exit`

## Required S-Side Functions

The backend file should eventually split into these functions:

- `build_executable(source, output_path)`
- `compile_program(source)`
- `find_main(source)`
- `execute_function(func)`
- `execute_stmt(stmt, env, ops)`
- `eval_expr(expr, env)`
- `emit_asm(program)`
- `emit_data_section(ops)`
- `emit_text_section(ops)`
- `assemble_and_link(asm_text, output_path)`

## Host Interface

There is one unavoidable host boundary in the MVP:

- writing temporary assembly/object files
- running `as`
- running `ld`

So the S backend should depend on a tiny standard-library host contract:

- `std.fs.WriteTextFile(path, contents)`
- `std.process.RunProcess(argv)`
- `std.fs.MakeTempDir(prefix)`

These should be modeled as runtime intrinsics or standard-library host calls,
not hidden logic inside the parser or CLI.

## Semantic Restrictions

The backend should reject unsupported constructs explicitly.

Examples:

- non-`main` entry expectations
- unsupported calls other than `println` / `eprintln`
- unsupported expression operators
- unsupported non-constant side effects
- unsupported heap values or closures

That means MVP failure mode should be:

```text
backend error: unsupported <feature>
```

not silent miscompilation.

## Immediate Implementation Plan

### Phase 1

Match the current Python backend exactly:

- evaluate `main`
- collect stdout/stderr writes

There is now also a native bootstrap runner in
[`runner.s`](/app/s/runtime/runner.s) that proves the current
`hello.s` / `sum.s` subset can be built without Python, while still staying far
smaller than the eventual full S runtime.

The current transitional native bootstrap template now lives under the backend
implementation itself at
[`backend_elf64_runner_bootstrap.c`](/app/s/compiler/backend_elf64_runner_bootstrap.c),
instead of under `runtime/`, so the bootstrap path is anchored in the backend
rather than in runtime-specific scaffolding.
- collect exit code
- emit one `.s`
- invoke `as`
- invoke `ld`

### Phase 2

Remove direct AST interpretation assumptions:

- isolate a backend-side `Value`
- isolate an explicit `ProgramOp`
- isolate environment mutation helpers

### Phase 3

Replace “compile-time execution” with a real lowerer:

- lower AST/MIR to explicit backend ops
- keep the same assembly emission path

## Acceptance Criteria

The MVP is complete when all of these are true:

- `s build /app/s/examples/s/hello.s -o /tmp/hello` succeeds
- `/tmp/hello` prints `hello, world`
- `s build /app/s/examples/s/sum.s -o /tmp/s_sum` succeeds
- `/tmp/s_sum` prints `5050`
- unsupported constructs fail with `BackendError`
- no Python-only backend logic is required to describe the backend algorithm

## Current Gap

Right now:

- [main.s](/app/s/compiler/main.s) already has a `build` command path
- [backend_elf64.s](/app/s/compiler/backend_elf64.s) is still a stub
- the runnable implementation still lives in
  [backend_elf64.py](/app/s/compiler/backend_elf64.py)

So the next engineering step is straightforward:

move the algorithm from `backend_elf64.py` into explicit S-side functions,
then leave only the host syscall/toolchain boundary in Python or runtime
intrinsics until the runtime layer is ready.
