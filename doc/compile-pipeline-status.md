# Compiler pipeline status

Run `make pipeline` from the repository root. The report is written to
`.bootstrap/pipeline/compile-pipeline-check.txt`; individual logs are under
`.bootstrap/pipeline/tmp/`. A failure names the first blocking required stage,
and the execution frontier stops at the last stage actually attempted.

This is a component acceptance pipeline. Its backend checks cover **P0 Native
Linux/amd64**: straight-line integer/void functions, arithmetic, direct calls,
register/stack arguments, relocatable ELF objects, and static executables.
Earlier gates check their respective frontend and ownership contracts. Passing
these checks does not prove a single full-language canonical artifact chain or
native compiler self-hosting. Source, Lexer, and AST standalone gates remain
optional and unproven in this report.

The parser gate gets its inputs from `make compiler-source-list`, the same
`COMPILER_SOURCES` used by `make compiler`. It uses the seed's `--dump-ast`
boundary, so missing dependencies cannot turn a semantic error into a parser
failure. Missing source files and empty closures fail the check.

The native backend gates execute emitted artifacts instead of inspecting the
retired interpreted backend's source. They verify changed source and runtime
inputs, position-based stack slots and call preservation, AMD64 instructions,
ELF symbols and relocations, linking, and executable behavior. Reports retain
the artifact paths used as evidence. The P0 backend does not use the older
linear-scan allocator; its assignment gate reports stack slots explicitly.

Focused regressions:

```sh
bash test/compiler/parser_closure_check.sh
bash test/compiler/runtime_snapshot_check.sh
bash test/native-bootstrap-diagnostic/native_abi_layout_append_check.sh
bash test/native-bootstrap-diagnostic/native_generic_caller_borrow_check.sh
bash test/native-bootstrap-diagnostic/native_array_record_identity_check.sh
bash test/native-bootstrap-diagnostic/native_enum_identity_check.sh
bash test/native-bootstrap-diagnostic/native_backend_bool_boundary_check.sh
bash test/native-bootstrap-diagnostic/native_pattern_payload_identity_check.sh
bash test/native-bootstrap-diagnostic/native_mono_type_args_check.sh
bash test/native-bootstrap-diagnostic/native_alias_return_identity_check.sh
bash test/native-bootstrap-diagnostic/native_extern_result_return_check.sh
bash test/native-bootstrap-diagnostic/native_canonical_type_schema_check.sh
bash test/native-codegen/pipeline-gates-check.sh
bash test/native-build/artifact_gates_check.sh
bash misc/scripts/test-compile-pipeline-check.sh
```

The ABI component's offset/type helpers retain the slice returned by `append`.
Their executable regression covers scalar and paired offsets and the supported
primitive register classifications. It does not establish general aggregate
layout support.

The hosted seed runtime indexes exact field names and record prefixes so eager
array/record argument snapshots do not repeatedly scan every accumulated field.
The snapshot regression checks both repeated-copy cost and value semantics.

The repaired component pipeline and focused regressions pass. A separate run of
the broader C seed unit suite still reports the pre-existing
`test_semantic_qualified_module_call_success` failure; its output is identical
before and after the runtime index change.

Full native self-hosting has a separate acceptance command:

```sh
make selfhost-native-stage1-check
```

On 2026-10-24, the generic result receiver mismatch was repaired by visiting
owned callers during borrow proof and resolving qualified factory return
types. The focused regression executes `is_err` from an owned caller and
checks `unwrap` through native unit compilation. It does not establish native
execution of `unwrap`.

Array `push`, `set`, and indexed assignment now use declaration-aware record
identity, allowing `error_msg` and `compile.internal.base.error_msg` to name
the same record while rejecting records from other packages. The focused
regression checks these operations through native unit compilation.

Non-generic enum constructors now retain their package-qualified declaration
identity. Short local enum names resolve in the current package; qualified
names resolve exactly, and ambiguous unqualified lookups fail. Pattern owners
retain that identity through payload checking, exhaustiveness and lowering.
Comparisons, initialization, assignment and array compatibility use the same
declaration identity. The focused regression checks native unit compilation
with duplicate enum names in both source orders, rejects cross-package enum
arguments and values, and executes scalar-enum operations and an enum-array
return. It does not establish native execution of payload-bearing non-generic
enums.

The misplaced closing brace for `bool_from_value` was moved from EOF to the
end of that function. Later helpers, including `find_binding_index`, are now
top-level declarations, restoring its `int` return type at call sites. The
regression compiles an extracted production helper with a following index
function and checks the full backend's parsed function boundaries.

Non-generic enum constructors and patterns now resolve short payload names in
the enum declaration's package. This prevents syntax AST and IR records such
as `assign_stmt` from sharing the wrong field metadata. Source helpers that
consume syntax AST records now name that package explicitly where IR declares
the same short type name; `function_sig.params` retains its AST parameter type.
The focused regression checks constructors and patterns in both input orders,
checks a unit without generic templates, and rejects a foreign payload field.

Stale `kindargs` accesses now use the declared `type_args` fields throughout
monomorphization, semantic call resolution, and bloop call reconstruction.
The focused regression executes the production cache lookup and key helpers
with a primitive-spelling equality comparator, distinguishing `id[int]` from
`id[string]` and checking a missing instantiation. It does not establish the
type system's alias-normalization behavior.

Aliased calls now prefer their file-local canonical candidate when selecting
an authoritative unit signature, preserving concrete generic return types;
local values still shadow aliases. The focused regression executes both source
orders and rejects an alias shadowed by a local integer. Extern parameter and
return types now cross the same native specialization boundary as wrappers,
so tuple-returning externs and implicit tail returns agree on result identity.
Their regression checks compilation and rejection of incompatible returns;
it does not establish native host-intrinsic ABI execution.

The three name-first fields of `canonical_type` were rewritten type-first,
fixing malformed parser field names (`string` and two `]` fields). The schema
regression checks all four actual parsed field names. This exposes the real
layout cycle: `canonical_type.child` is `option[canonical_type]` by value.

The full-source Stage1 check now fails before native IR emission at
`src/cmd/compile/internal/typesys/canonical_type.s:19` with
`recursive by-value record contract: compile.internal.canonical_type.canonical_type`.
Stage1 execution and Stage2/Stage3 convergence therefore remain unproven.
