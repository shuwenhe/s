# minimal `backend_elf64` design

this document defines the smallest executable backend we want for
[`backend_elf64.s`](/app/s/src/cmd/compile/internal/backend_elf64.s).

the goal is not a general-purpose optimizer or a full code generator.
the goal is to make the s compiler's own `build` path real with the
smallest linux `x86_64` elf backend that can compile the current examples.

## target

- os: linux
- architecture: `x86_64`
- output: static elf executable
- entry: `_start`
- toolchain contract: emit assembly, then invoke host `as` and `ld`

## mvp scope

the first executable version only needs to support the subset already used by:

- [hello.s](/app/s/misc/examples/s/hello.s)
- [sum.s](/app/s/misc/examples/s/sum.s)

that means:

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

anything outside this subset can return `backenderror` during mvp.

## backend strategy

the minimal backend should stay intentionally simple:

1. evaluate the current front-end ast with a tiny compile-time executor
2. record observable effects as a linear program
3. lower that linear program to linux syscalls in assembly
4. call `as` and `ld`

this is the same shape as the current python backend in
[`backend_elf64.py`](/app/s/src/compiler/backend_elf64.py), but rewritten as an
explicit s-side backend contract.

## why this shape

this is the fastest path to a real self-hosted `build`.

instead of first building a full register allocator, instruction selector,
stack frame layout, and relocation model, we start with a backend that only
needs to emit:

- write-to-stdout
- write-to-stderr
- process exit

that is enough for the current example programs.

## execution model

the mvp backend has two layers.

### layer 1: compile-time executor

it walks the checked ast and produces a linear list of operations:

- `writestdout(text)`
- `writestderr(text)`
- `exit(code)`

suggested s-side shape:

```s
enum programop {
    writestdout(writeop),
    writestderr(writeop),
    exit(exitop),
}
```

supporting structs:

```s
struct writeop {
    string text,
}

struct exitop {
    int code,
}
```

the executor only needs an environment of local integer/string values.

suggested value model:

```s
enum value {
    int(int),
    string(string),
    bool(bool),
    unit(()),
}
```

### layer 2: assembly emitter

it lowers those `programop` values into assembly text.

for each write operation:

- put payload bytes into `.data`
- emit syscall `write(1|2, ptr, len)`

for exit:

- emit syscall `exit(code)`

## assembly contract

the generated assembly can stay extremely small.

expected structure:

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
    mov $len, %rdx
    syscall

    mov $60, %rax
    mov $0, %rdi
    syscall
```

syscall numbers:

- `1`: `write`
- `60`: `exit`

## required s-side functions

the backend file should eventually split into these functions:

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

## host interface

there is one unavoidable host boundary in the mvp:

- writing temporary assembly/object files
- running `as`
- running `ld`

so the s backend should depend on a tiny standard-library host contract:

- `std.fs.writetextfile(path, contents)`
- `std.process.runprocess(argv)`
- `std.fs.maketempdir(prefix)`

these should be modeled as runtime intrinsics or standard-library host calls,
not hidden logic inside the parser or cli.

## semantic restrictions

the backend should reject unsupported constructs explicitly.

examples:

- non-`main` entry expectations
- unsupported calls other than `println` / `eprintln`
- unsupported expression operators
- unsupported non-constant side effects
- unsupported heap values or closures

that means mvp failure mode should be:

```text
backend error: unsupported <feature>
```

not silent miscompilation.

## immediate implementation plan

### phase 1

match the current python backend exactly:

- evaluate `main`
- collect stdout/stderr writes

there is now also a native bootstrap runner in
[`runner.s`](/app/s/src/runtime/runner.s) that proves the current
`hello.s` / `sum.s` subset can be built without python, while still staying far
smaller than the eventual full s runtime.

the current transitional native bootstrap template now lives under the backend
implementation itself at
[`backend_elf64_runner_bootstrap.c`](/app/s/src/compiler/backend_elf64_runner_bootstrap.c),
instead of under `runtime/`, so the bootstrap path is anchored in the backend
rather than in runtime-specific scaffolding.

the full script-level flow is documented in
[`bootstrap_flow.md`](/app/s/doc/bootstrap_flow.md). in short:

1. build `stage1` with `python3 -m compiler build` and `s_disable_selfhosted=1`
2. pass that `stage1` compiler through `s_compiler`
3. build `runner.s` without python fallback
4. install the self-host launcher and native runner artifacts

- collect exit code
- emit one `.s`
- invoke `as`
- invoke `ld`

### phase 2

remove direct ast interpretation assumptions:

- isolate a backend-side `value`
- isolate an explicit `programop`
- isolate environment mutation helpers

### phase 3

replace “compile-time execution” with a real lowerer:

- lower ast/mir to explicit backend ops
- keep the same assembly emission path

## acceptance criteria

the mvp is complete when all of these are true:

- `s build /app/s/misc/examples/s/hello.s -o /tmp/hello` succeeds
- `/tmp/hello` prints `hello, world`
- `s build /app/s/misc/examples/s/sum.s -o /tmp/s_sum` succeeds
- `/tmp/s_sum` prints `5050`
- unsupported constructs fail with `backenderror`
- no python-only backend logic is required to describe the backend algorithm

## current gap

right now:

- [main.s](/app/s/src/cmd/compile/internal/main.s) already has a `build` command path
- [backend_elf64.s](/app/s/src/cmd/compile/internal/backend_elf64.s) is still a stub
- the runnable implementation still lives in
  [backend_elf64.py](/app/s/src/compiler/backend_elf64.py)

so the next engineering step is straightforward:

move the algorithm from `backend_elf64.py` into explicit s-side functions,
then leave only the host syscall/toolchain boundary in python or runtime
intrinsics until the runtime layer is ready.
