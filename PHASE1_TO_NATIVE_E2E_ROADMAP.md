# S Modular Compiler Pipeline: From Phase 1 to True E2E

## Current State
- ✅ Monomorphization algorithm: complete at AST level
- ✅ Semantic generic inference: working
- ❌ Full native compilation: not yet validated
- ❌ User-facing modular compiler: not functional

## Immediate Next Goals (FROZEN on generics features)

**DO NOT extend monomorphization.s, semantic.s, or generic metadata unless critical bugs found.**

Instead focus on:

### 1. IR Closed-World Gate (CRITICAL)

**File**: `src/cmd/compile/main.s` + verification pass

**Goal**: Prevent emission of invalid IR with undefined symbol references

**Implementation**:
```
for every ir::call(sym) in generated_ir:
    if sym is internal (not mangled):
        require matching ir::func(sym) definition exists
    else:
        require explicit extern/runtime declaration
    if NOT found:
        error: undefined symbol reference
        return
        
proceed to emit-bin only if all calls resolved
```

**Why**: Currently can emit IR referencing non-existent functions, causing linker/runtime failures

**Test Case**: Verify `source_closure` doesn't create dangling symbol references

### 2. Source Closure (BLOCKING for modular)

**File**: `source_closure.sh` (new)

**Goal**: Collect all transitive package dependencies into single compilation unit

**Algorithm**:
```
input: root package + entry point source.s
       
collect(pkg):
    for each use_decl in source files:
        add package to dependency tree
        recurse on dependencies

output:
    ordered file list for s_seed --compile-unit
    all transitive sources needed
```

**Purpose**: Build prerequisite for `--compile-unit` closed-world compilation

**Example**:
```bash
./source_closure.sh /Users/feifei/shuwen/s/src/cmd/compile \
    > /tmp/sources.txt

s_seed --compile-unit $(cat /tmp/sources.txt) \
    -o /tmp/closed.ir
```

### 3. bin/s_modular Integration

**File**: `src/cmd/compile/main.s` (extension)

**Goal**: Connect source closure → s_seed --compile-unit → IR gate → emit-bin

**Pipeline**:
```
main.s build --modular generic_chain.s
       ↓
source_closure(generic_chain.s)
       ↓
collect transitive sources
       ↓
s_seed --compile-unit sources
       ↓
IR closed-world gate
       ↓
emit-bin → bin/s_modular
```

### 4. Native E2E Validation Gate

**File**: `makefile` (new target)

**Goal**: Prove generics work end-to-end: source → native binary → execution

**Target**: `make generic-native-e2e-check`

**Test Program**: `generic_chain.s`
```s
func baz[T](T x) T { return x }
func bar[T](T x) T { return baz(x) }
func foo[T](T x) T { return bar(x) }

func main() int {
    return foo(42)  // Must exit with code 42
}
```

**Full Pipeline**:
```
make generic-native-e2e-check
       ↓
1. build bin/s_modular
2. bin/s_modular build generic_chain.s -o /tmp/generic_chain
3. semantic analysis (infer foo[int], bar[int], baz[int])
4. monomorphization (generate 3 instances)
5. ownership analysis (concrete types)
6. IR lowering (foo__mono_int, bar__mono_int, baz__mono_int)
7. native backend
8. /tmp/generic_chain
9. verify exit code = 42
       ↓
SUCCESS: Phase 1 is TRULY COMPLETE
```

## Why NOT Generic Structs Yet?

Expanding generic features before completing the native pipeline creates:

```
Function generics       ✅ AST pass
Generic structs         ✅ AST pass (hypothetical)
Generic ownership       ✅ AST pass (hypothetical)
          ↓
but
          ↓
bin/s build             ❌ still walks legacy pipeline
```

Result: Growing technical debt, feature bloat without user value.

**Instead**: Complete ONE feature's entire pipeline (generics in modular compiler) before adding more features.

## Implementation Order

1. **IR Closed-World Gate** (1-2 hours)
   - Add verification pass in `src/cmd/compile/main.s`
   - Catch undefined symbol references before emit-bin

2. **Source Closure Script** (1-2 hours)
   - Parse package declarations
   - Recursive transitive collection
   - Handle circular dependencies (build order)

3. **bin/s_modular Integration** (2-3 hours)
   - Wire source_closure into main.s
   - Add --modular flag support
   - Connect to s_seed --compile-unit

4. **Native E2E Gate** (1 hour)
   - Create generic_chain.s test
   - Add make target
   - Validate full pipeline

## Success Criteria

✅ `make generic-native-e2e-check` completes without errors
✅ `/tmp/generic_chain` exits with code 42
✅ No undefined symbol references in any IR
✅ All transitive dependencies correctly closed

Once these pass: **Declare Phase 1 Generics truly COMPLETE**

Then and only then consider Phase 2 features (generic structs, generic ownership).
