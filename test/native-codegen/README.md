# Independent SSA AMD64 code generation

Run `./test/native-codegen/check.sh` with the existing `bin/s_seed`, GNU as/ld,
readelf/objdump, a C compiler, and Python 3 on Linux/amd64. The script prints and
retains its artifact directory, input hashes, tool versions, ELF metadata and
disassembly. The seed hosts the S generator; the generated application objects
and standalone executables contain no seed runtime or interpreter.

The backend consumes a `function_ssa_program` directly, validates the entire
program before producing output, selects AMD64 instructions in S, and emits GNU
assembler syntax. **GNU as performs instruction encoding, ELF object generation
and relocations; GNU ld performs standalone executable linking.** This milestone
is not an in-S assembler/linker or a complete self-hosting claim.

`generate.s` constructs SSA fixtures without a source scanner, MIR-to-C emitter,
or AST evaluator. The C files only call the exported System V `s_native_entry`
ABI of an assembled object; the generated application is never converted to C.
Several runtime integers are passed to each of the same linked binaries.

Coverage includes live values across forward and nested calls, reversed parameter
storage order, seven/eight register-plus-stack parameters, odd/even outgoing
stack alignment, callee-saved register canaries, sparse trillion-sized value IDs,
uncalled function preservation, arbitrary source-symbol punctuation, int64
minimum/maximum constants, wrapping add/subtract/multiply, signed division and
remainder, division overflow and division-by-zero exit 86, void calls/returns,
invalid SSA/unsupported operations/types/arities, and no partial assembly on
errors. Additional test-only instrumentation checks rsp alignment at every
function entry; the original unmodified objects are also executed independently.

The standalone startup fixtures are assembled and linked by `as` and `ld` with
no C harness. They test zero-argument and one-int entry points, exact argc,
optional decimal signs, minimum/maximum int64, full-string parsing, empty/sign-only
inputs, trailing junk and overflow, invalid-input exit 2, void exit 0, and the
absence of ELF INTERP/dynamic sections. Other entry signatures are rejected.

The initial RED command was:

```
./bin/s_seed --compile-unit /tmp/s-amd64-first-red.ir \
  src/cmd/compile/internal/ssa/program.s \
  src/cmd/compile/internal/codegen/amd64_program.s \
  test/native-codegen/red_probe.s
```

Before implementation it exited 1 with `failed to open input:
src/cmd/compile/internal/codegen/amd64_program.s`. The retained API probe now
checks both APIs return errors and empty output for invalid program identity.

The supported backend scope is single-block straight-line functions with int64
`int` parameters/values and zero or one int result. Values use position-based
stack slots; all incoming parameters are saved before the body. Multi-block
control flow, other scalar/object types, external linkage and multiple results
remain outside this slice.
