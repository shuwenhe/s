# ABI Coverage Matrix (amd64 / arm64)

This document tracks scenario coverage beyond baseline ABI notes.

## Integer Argument Passing

| Arg Index | amd64 SysV | arm64 AAPCS64 |
| --- | --- | --- |
| 0 | %rdi | x0 |
| 1 | %rsi | x1 |
| 2 | %rdx | x2 |
| 3 | %rcx | x3 |
| 4 | %r8  | x4 |
| 5 | %r9  | x5 |
| 6 | stack+0 | x6 |
| 7 | stack+8 | x7 |

Current backend enforces availability of mappings for indices `[0..7]`.

## Floating-Point Argument Passing

| Arg Index | amd64 SysV | arm64 AAPCS64 |
| --- | --- | --- |
| 0 | %xmm0 | v0 |
| 1 | %xmm1 | v1 |
| 2 | %xmm2 | v2 |
| 3 | %xmm3 | v3 |
| 4 | %xmm4 | v4 |
| 5 | %xmm5 | v5 |
| 6 | %xmm6 | v6 |
| 7 | %xmm7 | v7 |

Current backend enforces availability of mappings for float indices `[0..7]`.

## Return Registers

- Integer return: amd64 `%rax`, arm64 `x0`
- Floating return: amd64 `%xmm0`, arm64 `v0`

Current backend enforces that both integer and floating return registers are configured.

## Callee-Saved Register Baseline

- amd64 baseline count: 6
- arm64 baseline count: 12

Current backend enforces that each target has a non-empty callee-saved register set.

## Stack Frame Baseline

- amd64: frame pointer based (`push rbp; mov rbp, rsp; leave; ret`).
- arm64: frame pointer and LR saved (`stp x29, x30`, `ldp x29, x30`).

## Covered Scenarios

- Program entry `_start` calls internal `s_main`.
- Exit code return via ABI return register (`%eax` / `x0`).
- Syscall write/exit paths for both architectures.
- Argument register mapping validation for integer arguments 0..7.
- Argument register mapping validation for floating arguments 0..7.
- Return register mapping validation (int + float).
- Callee-saved register set presence validation.

## Remaining Full-Coverage Work

- Floating-point argument and return classification.
- Struct/aggregate passing and return-value ABI classes.
- Caller/callee-saved register preservation checks at all call sites.
- Variadic call ABI handling.
- Stack spill slot layout tied to SSA allocator output.
- Tail-call legality checks.
- Unwind/debug ABI data (CFI / line mappings).

## Validation Contract

Backend build must fail early if ABI mapping table is incomplete for required call width.
