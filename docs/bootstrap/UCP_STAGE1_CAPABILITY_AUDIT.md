# UCP-1 Stage1 Capability Audit

Status: UCP direction locked, audit only.

Current HEAD:

```text
78320febefefc9c3923fc0dd6975cb53d6387bf8
```

## Scope

This document audits whether the current Stage1 compiler can carry the production compile core:

```text
syntax.parse_source
  -> semantic.check_source_file
  -> mono.monomorphize_file
  -> ir.lower.lower_main_to_mir
```

No source code, build script, or compiler behavior was changed for this audit.

## 1. Verified Entry Graphs

### Observed: top-level `src/cmd/compile/main.s`

Current compile entry is:

```text
src/cmd/compile/main.s
  -> use compile.compiler
  -> compiler_main(host_args())
```

Evidence: `src/cmd/compile/main.s`.

This means the checked-in `src/cmd/compile/main.s` does not directly enter `compile.driver.driver_main`.

### Observed: driver production path exists

The driver path exists and dispatches `build` to the pipeline:

```text
compile.driver.driver_main
  -> parse_arguments
  -> dispatch_command
  -> pipeline_build(input, output, "", false)
```

Evidence: `src/cmd/compile/internal/driver/driver.s`.

### Observed: pipeline delegates to core backend

The pipeline prints authority checkpoints, then calls:

```text
compile.internal.pipeline.pipeline_build
  -> pipeline_prepare
  -> pipeline_compile
  -> compile.internal.core.build
```

Evidence: `src/cmd/compile/internal/pipeline/pipeline.s`.

### Observed: production core compile path

`compile.internal.core.build` performs the production compile sequence:

```text
std.fs.read_to_string(path)
  -> load_source_graph(path, source)
  -> compile.internal.ir.lower.lower_main_to_mir(parsed)
  -> run_midend_pipeline(graph)
  -> build_ssa_pipeline_with_graph_hints_and_margin(...)
  -> dump_ssa_pipeline(...)
  -> validate_ssa_abi_contracts(...)
  -> validate_abi_coverage(...)
  -> compile_writes(...)
  -> compile_exit_code(...)
  -> emit_asm(...)
  -> as
  -> ld
```

`load_source_graph` performs:

```text
compile.internal.syntax.parse_source(source)
  -> append_dependency_items(...)
  -> compile.internal.semantic.check_source_file(...)
  -> compile.internal.mono.monomorphize_file(...)
```

Evidence: `src/cmd/compile/internal/core/backend.s`.

### Observed: bootstrap path is separate

Native bootstrap calls:

```text
bin/s_seed --compile-unit stage1.ir <closure>
stage1 --compile-unit stage2.ir <closure>
stage2 --compile-unit stage3.ir <closure>
```

Evidence: `src/cmd/dist/native-bootstrap-no-manifest.sh`.

`--compile-unit` enters:

```text
compile.compiler.compiler_main
  -> handle_compile_unit
  -> compiler_compile(source)
  -> write result.code to output
```

Evidence: `src/cmd/compile/internal/compiler/main.s`.

This is not the production parser/semantic/mono/lower path.

## 2. Production Frontend Dependency Surface

### Direct imports

`compile.internal.syntax`:

```text
s
std
std.fs
std.result
```

`compile.internal.semantic`:

```text
compile.internal.prelude
compile.internal.typesys
s
std
std.option
std.prelude
```

`compile.internal.mono`:

```text
compile.internal.semantic
compile.internal.typesys
s
std.option
std.prelude
```

`compile.internal.ir.lower`:

```text
compile.internal.mir
s
std
```

`compile.internal.core` imports the wider production backend surface:

```text
compile.internal.abi
compile.internal.dispatch.devirtualize
compile.internal.escape
compile.internal.inline
compile.internal.ir.lower
compile.internal.mir
compile.internal.mono
compile.internal.rewriteresults
compile.internal.safety
compile.internal.semantic
compile.internal.slice
compile.internal.ssa
compile.internal.ssagen
compile.internal.syntax
compile.internal.walk
s
std
std.fs
std.io
std.option
std.prelude
std.process
```

Evidence: import blocks in:

```text
src/cmd/compile/internal/parser/syntax/syntax.s
src/cmd/compile/internal/semantic/semantic.s
src/cmd/compile/internal/mono/monomorphization.s
src/cmd/compile/internal/ir/lower.s
src/cmd/compile/internal/core/backend.s
```

### Runtime and language dependencies

The production frontend surface uses:

```text
result[T, E]
option[T]
arrays and append/push
strings and string concatenation
filesystem reads
process execution in core backend
enum variants and switch matching
method calls such as is_err(), unwrap(), unwrap_err()
package-qualified names
generic containers
```

These are required at runtime, not merely at parse time.

### Closure tool observation

The current Stage1 bootstrap closure is:

```text
src/cmd/compile/internal/compiler/frontend.s
src/cmd/compile/internal/compiler/frontend_core.s
src/cmd/compile/internal/compiler/frontend_stages.s
src/cmd/compile/internal/compiler/main.s
src/cmd/compile/internal/compiler/stages.s
src/cmd/compile/internal/mir/compiler_emit.s
src/cmd/compile/main.s
```

Evidence: `.bootstrap/native-imports/stage1.sources`.

This closure does not include:

```text
src/cmd/compile/internal/parser/syntax/syntax.s
src/cmd/compile/internal/semantic/semantic.s
src/cmd/compile/internal/mono/monomorphization.s
src/cmd/compile/internal/ir/lower.s
src/cmd/compile/internal/core/backend.s
```

Therefore current Stage1 is not proven to contain the production frontend.

Attempting to generate a deeper closure for production core with `source_closure.sh` did not complete quickly during this audit and was interrupted. This is not proof of a compiler failure, but it means the production closure should not be treated as already proven by the current closure script.

## 3. Stage1 Proven and Unproven Capabilities

### Observed proven capability

The native bootstrap closure proves only that Stage1 is built from the current `compile.compiler` package closure listed above.

The simplified frontend has recently been extended enough to pass targeted tests for:

```text
extern declarations
lowercase struct names
type-first/name-first two-token struct fields
```

These tests prove local behavior in `compiler_compile`; they do not prove production frontend execution.

### Observed current Stage1 blocker

The latest Stage1 -> Stage2 IR failure was:

```text
compiler:16: unsupported in no-GC compiler subset:
struct fields require type and name
```

The source line is:

```text
src/cmd/compile/internal/compiler/frontend_core.s:16
string[] names
```

This shows the current bootstrap path still executes the simplified `compiler_compile` parser and is blocked before any production frontend can run.

### Observed simplified frontend boundary

`compiler_compile` lives in:

```text
src/cmd/compile/internal/compiler/frontend.s
```

The file contains explicit no-GC subset diagnostics:

```text
unsupported in no-GC compiler subset
```

It also defines local parsing and type helpers such as:

```text
compiler_type_kind
compiler_parse_struct_decl
compiler_compile
```

This is a separate frontend authority from `compile.internal.syntax.parse_source`.

### Unproven capability

The following are NOT PROVEN for Stage1:

```text
Stage1 can compile production parser/syntax closure.
Stage1 can link symbols from semantic/mono/ir/lower.
Stage1 can execute production parse_source at runtime.
Stage1 can execute semantic.check_source_file at runtime.
Stage1 can execute mono.monomorphize_file at runtime.
Stage1 can execute ir.lower.lower_main_to_mir at runtime.
Stage1 can allocate and manipulate production result/option/vector-heavy data at bootstrap scale.
Stage1 can emit a canonical IR file produced by production IR emitter.
```

## 4. Root Cause Classification

### Observed

Current bootstrap does not enter the production frontend. It enters:

```text
handle_compile_unit -> compiler_compile
```

The Stage1 closure contains `compile.compiler` files, not the production frontend/core modules.

### Observed

Production `core.build` contains a semantic skip rule:

```text
should_skip_semantic_check(path)
```

It returns true for:

```text
/src/cmd/compile/internal/
src/cmd/compile/internal/
/src/cmd/compile/main.s
src/cmd/compile/main.s
```

Evidence: `src/cmd/compile/internal/core/backend.s`.

This means even the production path currently has special handling that skips semantic/mono for compiler-internal paths. It cannot be treated as proof that the full compiler source is semantically checked through the canonical path.

### Hypothesis

The first class of UCP blocker is not the specific `string[]` syntax. The root class is:

```text
Bootstrap entry and production entry use different frontend authorities.
```

The `string[]` failure is a symptom of that split.

### Root cause status

Root cause for repeated Stage1 frontend errors:

```text
PROVEN: bootstrap uses simplified compiler_compile instead of production frontend.
```

Root cause for why Stage1 cannot yet use production frontend:

```text
NOT PROVEN.
```

The likely blockers are dependency closure size, unsupported language features, runtime/container support, and entry/linking integration. They require targeted probes.

## 5. Migration Options

### Option A: Expand Stage1 until it can carry full production frontend

Description:

```text
Keep production frontend as-is.
Teach the seed/Stage1 path to compile and run parser/syntax, semantic, mono, ir/lower, and their dependencies.
Then route --compile-unit to the production compile API.
```

Benefits:

```text
Directly converges on one compiler authority.
Minimizes long-term duplicate frontend code.
Matches the Go-style self-host direction.
```

Risks:

```text
Potentially large Stage1 dependency closure.
May expose many language/runtime gaps at once.
Could require result/option/generic/container/runtime behavior before Stage1 is ready.
May reintroduce hard-to-localize failures if attempted as one big switch.
```

Verification:

```text
A standalone Stage1 probe calls syntax.parse_source on a tiny valid program.
Then semantic.check_source_file.
Then mono.monomorphize_file.
Then ir.lower.lower_main_to_mir.
Each step must run under Stage1, not only compile under seed.
```

### Option B: Shrink the canonical frontend bootstrap surface

Description:

```text
Extract a small canonical compile API and minimal production frontend subset.
Both production and bootstrap call the same API and same parser/semantic/lowering semantics.
Keep dependency surface small enough for Stage1, but do not create a second language implementation.
```

Benefits:

```text
Lower immediate bootstrap risk.
Allows staged migration from compiler_compile to canonical frontend.
Can preserve one language authority if the subset is factored from production code rather than copied.
```

Risks:

```text
If implemented by copying logic, it recreates the second-frontend problem.
May require careful module splitting around parser, AST, type data, and IR emission.
Could delay full production frontend adoption.
```

Verification:

```text
Both s build and --compile-unit call the same canonical parse/type/lower functions.
Tests reject any path where --compile-unit calls compiler_compile.
Generated stage2.ir must come from the canonical IR emitter.
```

## 6. Recommendation

Recommended minimum migration boundary:

```text
Create or identify a canonical compile-unit API that can emit IR from source using production parser/semantic/lowering semantics.
Do not route native bootstrap directly to all of core.build yet.
First prove Stage1 can execute the frontend-only sequence:
  syntax.parse_source
  -> semantic.check_source_file
  -> mono.monomorphize_file
  -> ir.lower.lower_main_to_mir
  -> canonical IR emitter
```

This is closer to Option B initially, but only if the code is factored from the production frontend. It must not become a new parser or new semantic implementation.

The old `compiler_compile` path should remain as a legacy bootstrap mechanism until the canonical Stage1 probe passes, but no new syntax features should be added to it except to keep an existing verified baseline alive.

## 7. Next FIRST RED

The next UCP FIRST RED should not be `compiler:16`.

The next FIRST RED should be a new targeted UCP probe:

```text
Can Stage1 call production syntax.parse_source on a tiny source file and emit a real parsed success/failure result?
```

If that passes, advance one layer:

```text
syntax.parse_source
semantic.check_source_file
mono.monomorphize_file
ir.lower.lower_main_to_mir
canonical IR emit
```

Only after this sequence is proven should `handle_compile_unit` be migrated.

## 8. Reproducible Commands

Audit commands used:

```bash
cd /home/shuwen/shuwen/s

git status --short
git rev-parse HEAD

sed -n '1,120p' src/cmd/compile/main.s
sed -n '1,120p' src/cmd/compile/internal/driver/driver.s
sed -n '1,130p' src/cmd/compile/internal/pipeline/pipeline.s
sed -n '280,330p' src/cmd/compile/internal/core/backend.s
sed -n '2520,2580p' src/cmd/compile/internal/core/backend.s
sed -n '2630,2655p' src/cmd/compile/internal/core/backend.s

sed -n '1,60p' src/cmd/compile/internal/parser/syntax/syntax.s
sed -n '1,40p' src/cmd/compile/internal/semantic/semantic.s
sed -n '1,60p' src/cmd/compile/internal/mono/monomorphization.s
sed -n '1,60p' src/cmd/compile/internal/ir/lower.s
sed -n '333,370p' src/cmd/compile/internal/ir/lower.s

cat .bootstrap/native-imports/stage1.sources

rg -n 'should_skip_semantic_check|is_compiler_runtime_entry|build_compiler_runtime_launcher|compiler_compile\(|handle_compile_unit|--compile-unit|--emit-bin' \
  src/cmd/compile/internal src/cmd/dist/native-bootstrap-no-manifest.sh

rg -n '^import \(|^\s*"|^use ' \
  src/cmd/compile/internal/parser/syntax/syntax.s \
  src/cmd/compile/internal/semantic/semantic.s \
  src/cmd/compile/internal/mono/monomorphization.s \
  src/cmd/compile/internal/ir/lower.s \
  src/cmd/compile/internal/core/backend.s \
  src/cmd/compile/internal/pipeline/pipeline.s \
  src/cmd/compile/internal/driver/driver.s
```

## 9. UCP Stage Exit Note

UCP-1 does not eliminate a compiler implementation blocker yet. It eliminates an architectural ambiguity:

```text
The current Stage1 self-host path is not using the production frontend.
```

New independent compile authority introduced:

```text
No.
```

Canonical frontend unification:

```text
NOT PROVEN.
```

Stage1 production frontend execution:

```text
NOT PROVEN.
```

Self-host fixed point:

```text
NOT PROVEN.
```
