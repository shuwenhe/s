# ABI Notes (amd64 / arm64)

This document describes the minimal ABI contract used by `compile.internal.backend_elf64`.

## amd64 (System V, Linux)

- Entry symbol: `_start`
- Internal compiler-emitted function: `s_main`
- Integer return register: `%eax`
- Syscall ABI:
  - `%rax`: syscall number
  - `%rdi`, `%rsi`, `%rdx`: first 3 args
- Stack alignment:
  - `_start` aligns `%rsp` to 16 bytes before calling `s_main`
- `s_main` frame policy:
  - Prologue: `push %rbp; mov %rsp, %rbp; sub $16, %rsp`
  - Epilogue: `leave; ret`
- Exit path:
  - `_start` reads `%eax` from `s_main` and exits via syscall 60 (`exit`).

## arm64 (AAPCS64, Linux)

- Entry symbol: `_start`
- Internal compiler-emitted function: `s_main`
- Integer return register: `x0`
- Syscall ABI:
  - `x8`: syscall number
  - `x0`, `x1`, `x2`: first 3 args
- `s_main` frame policy:
  - Prologue: `stp x29, x30, [sp, #-16]!; mov x29, sp`
  - Epilogue: `ldp x29, x30, [sp], #16; ret`
- Exit path:
  - `_start` calls `s_main`, then issues syscall 93 (`exit`) using return value in `x0`.

## Current Scope

- The backend currently emits one internal function (`s_main`) and performs I/O via Linux syscalls.
- This is a minimal ABI implementation intended to make stack-frame and call-convention behavior explicit and stable across amd64/arm64.
- Future work can add argument passing for user-defined calls, callee-saved register tracking, and spill slots tied to SSA regalloc output.
