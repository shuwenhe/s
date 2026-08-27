# S bootstrap contract

The trusted bootstrap boundary is the C seed compiler (`bin/s_seed`).  Its job
is limited to compiling the frozen bootstrap S subset into the first static
Linux/amd64 executable.  No C compiler code or IR interpreter may be linked
into a self-hosted stage.

The intended stage chain is:

```text
C seed -> static S stage1 -> static S stage2 -> static S stage3
```

A bootstrap is complete only when all of the following are true:

1. stage1 is produced from S source by the seed standalone backend;
2. stage1 produces the complete stage2 executable without invoking the seed;
3. stage2 produces the complete stage3 executable without invoking the seed;
4. stage2 and stage3 are byte-identical;
5. stage2 passes `misc/scripts/verify_true_selfhost.sh`;
6. stage2 compiles and runs the bootstrap conformance programs.

IR convergence alone is not self-hosting.  In particular, an executable that
embeds `seed_compile_source_text`, `runtime_execute_text`, or a path to another
compiler is a seed-hosted launcher.

## Frozen implementation slices

Bootstrap work is added in independently executable slices:

- Slice 0: standalone runtime plus the pure-S lexer.  Its token stream must be
  identical to the seed lexer and its ELF must pass the strict dependency
  audit.
- Slice 1: `src/cmd/compile/selfhost/compiler.s`.  It reads an S source file and
  emits `SSEED-TARGET-V1` without using the C frontend.  The initial grammar is
  one `main` function returning a non-negative integer expression composed of
  local constant bindings, zero/one-argument integer functions, parentheses, identifiers, and precedence-aware
  arithmetic/comparison/logical operations, short-circuit evaluation, plus nested `if/else` return paths. Its `--emit-bin` path
  directly writes a static ELF64 executable from S; stage0 is not used to lower
  the program. The `--emit-native-expr` path recursively lowers arithmetic
  expressions to real amd64 stack-machine instructions rather than folding the
  result into the ELF image. `--emit-native-control` additionally emits compare,
  condition-code, and relative branch instructions for `if/else`.
  `--emit-native-locals` emits a real frame pointer and stack-slot loads/stores
  for local bindings. `--emit-native-call` lays out multiple functions in the
  ELF image, passes up to six integer arguments through the SysV integer
  registers, and emits internal `call/ret` machine instructions.
  `--emit-native-loop` emits
  mutable stack slots plus forward and negative relative jumps for `while`.
  `--emit-native-string` appends decoded string data to the static ELF image and
  emits a direct Linux `write` syscall with its address and length. The unified
  `--emit-native` entry selects among all implemented native lowering slices;
  conformance tests use this entry rather than the specialized debug flags.
  Fixed-size integer array literals and constant indexing are lowered to
  contiguous stack slots by the native array slice. The multi-call slice assigns
  deterministic 512-byte code slots to an arbitrary sequence of functions,
  preserves parameters in stack frames, and resolves nested parameterized
  calls without a C linker. The argv
  file-I/O slice reads Linux process arguments and emits direct `openat`, `read`,
  and `write` syscalls, including multi-buffer reads, short-write recovery, and
  syscall failure exits, providing the source-input/output foundation for stage2.
- Slice 2: declarations, calls, control flow, strings, arrays, and the complete
  syntax needed to compile the bootstrap compiler source.
- Slice 3: general amd64 instruction encoding, relocations, and static ELF64
  writing. The slice-1 ELF writer handles constant bootstrap probes only; at
  slice 3 stage1 can emit the complete stage2 compiler without help from stage0.

Run the implemented slices with:

```sh
make selfhost-lexer-check
make bootstrap-slice1-check
make pure-s-bootstrap-check
```

`make true-selfhost-check` remains the final gate and must not be weakened while
later slices are incomplete.
