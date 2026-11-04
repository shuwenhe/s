# Native code generation

The active canonical path is source → canonical parser/AST → semantic checks → call annotation → monomorphization → type elaboration → method flattening → MIR → SSA → AMD64 assembly → GNU as/ld → ELF. See internal/compiler/canonical_source.s and internal/core/native_build.s.

MIR and SSA validators run before assembly emission. Executables retain the entry, global initializer roots and their transitive direct calls. Source tuples lower to aggregate records; physical SSA functions use zero or one result. Multiple source tuple returns are covered by canonical_tuple_production_check.sh.

The native backend supports int64 int, bool, string, unit, records, enum representations, arrays and supported references. Actual support is constrained by semantic/lowering validation. Floating-point lowering is not implemented in ssa_type_supported. Do not infer feature support from the presence of architecture or optimization files outside the executable path.

## Integer and startup contracts

Add/subtract/multiply wrap at 64 bits. Signed division truncates toward zero; remainder follows the dividend's sign. Minimum int divided by -1 wraps to minimum int; its remainder is zero. Division by zero exits 86. Array bounds failures exit 87. String byte indexing has a separate established default-value contract, tested by canonical_string_index_production_check.sh.

Standalone startup accepts no-argument main or one int argument with strict full decimal parsing. Invalid input exits 2. The generated executable is native machine code and does not interpret source. GNU as encodes instructions and relocations; GNU ld links the executable.

## ABI and memory

The backend uses stack slots for SSA values and System V AMD64 register/stack argument passing. test/native-codegen/check.sh checks seven/eight arguments, odd/even call stack alignment, callee-saved canaries, integer extremes, and malformed SSA. Native C-object tests exercise object interoperability; this does not imply arbitrary C types or libraries are supported.

The embedded native collector is conservative, nonmoving mark/sweep. Its allocation wrapper spills registers before collecting, scans stack/global roots, and recursively scans object contents. See src/runtime/native_gc.c and native_gc_amd64.S. Object/library entry collection has a separate root-safety policy; see the source and object regression. See [runtime and GC](runtime-gc.md) for root scanning, reclamation, object lifetime and maintenance. The broader S runtime foundation APIs are separate contracts and do not prove backend integration for channels, scheduling or precise stack maps.

## Validation and performance

Run `make selfhost-canonical-production-check` for canonical parser, type, generic, CFG/MIR/SSA, native execution and GC checks. Run `bash test/native-codegen/check.sh` for independent SSA fixture/ABI checks. Full self-host/reproducibility requirements are in [clean-room acceptance](selfhost-verification/cleanroom.md).

Historical self-host measurements are retained in acceptance evidence. Record compiler revision, tool versions, elapsed time and peak RSS for new measurements. No broad performance claim follows from successful self-hosting.
