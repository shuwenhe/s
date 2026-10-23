> Current verification (2026-10-23): complete native self-hosting has not
> passed. Strict generic record/function specialization now exists in the
> seed; the full 253-file build stops at a concrete generic result enum borrow
> in `src/result/result.s:18`. The S native frontend/MIR/SSA also still support
> only a restricted subset. Passing unchecked IR to a linker is not ownership
> validation or three-stage convergence. See [the verified implementation
> status](selfhost-implementation.md) for the tested boundary.

# S Compiler Bootstrap Architecture

## Current Status

The S compiler bootstrap has reached a fundamental architectural limitation:

**Stage Achieved**: Seed compiler → stage1.ir (IR validation passes)  
**Blocker**: IR backend cannot generate native code for generic methods  
**Undefined References**: 28 unresolved generic method calls in linker

## Problem Analysis

### What Works
- Seed compiler (C-based): ✅ Compiles 253 S modules to IR
- Import resolution: ✅ Automatic dependency tracking
- IR validation: ✅ All type checks, borrow checking, layout validation pass
- Hosted compiler: ✅ Can compile S code with full type checking

### What Fails
When the seed compiler's native backend tries to link stage1.ir:

```
undefined reference to `s_fn_option_t___is_none`
undefined reference to `s_fn_option_t___unwrap`
undefined reference to `s_fn_result_t_e___unwrap`
... (28 total)
```

### Root Cause

The IR contains generic function definitions like:
```
FUNC_BEGIN|option[t].is_none|_|_
FUNC_BEGIN|option[t].unwrap|_|_
```

But NOT monomorphized (concrete) versions like:
```
FUNC_BEGIN|option[string].is_none|_|_
FUNC_BEGIN|option[type].is_none|_|_
```

The native code generator expects monomorphized versions with actual symbol names like `s_fn_option_t___is_none` which are never generated.

### Why This Happens

1. **S language design**: Uses generics pervasively
   - Error handling: `option[t]`, `result[t,e]`
   - Memory: `box[t]`
   - Collections: `[]t`, `map[k]v`
   - **Compiler code** heavily uses these

2. **Seed compiler** (C-based bootstrap):
   - No monomorphization pass in IR generation
   - Cannot specialize generic code before code generation
   - Native backend has no generic support

3. **Monomorphization code exists** but only in hosted compiler:
   - `src/cmd/compile/internal/mono/monomorphization.s`
   - Used by hosted compiler for final optimization
   - Not available during seed compiler bootstrap

### Comparison with Go

Go has two relevant differences:

1. **Timeline**: Generics added in Go 1.18, AFTER bootstrap infrastructure
   - Go 1.5+ already had two-stage bootstrap working
   - Generics code is NOT used during bootstrap

2. **Scope**: Go's type parameters used conservatively
   - Minimal generics in stdlib/compiler
   - Bootstrap code avoids them

S is fundamentally different:
- Generic types are core language feature from day 1
- Compiler code cannot be written without them
- No way to avoid generics during bootstrap

## Solutions

### Option 1: Monomorphization in Seed Compiler ⭐ RECOMMENDED

**Idea**: Add monomorphization pass to seed compiler's IR generation

**Implementation**:
1. When generating FUNC_BEGIN for generic function, analyze call sites
2. For each specialized type parameter combination used:
   - Create monomorphized version with concrete type names
   - Generate concrete symbol names like `s_fn_option_string___is_none`
3. Collect all needed specializations and emit them

**Pros**:
- Fixes IR generation at source
- No runtime dependency on hosted compiler
- Pure native bootstrap works
- Compiler gets optimization pass benefit

**Cons**:
- ~1-2 weeks of C work in seed compiler
- Requires understanding S type system semantics
- Need to handle recursive generics carefully

**Files to modify**:
- `src/cmd/compile/seed/code/generator.c` - Add mono pass
- `src/cmd/compile/seed/code/native_backend.c` - Support concrete symbols
- Possibly: `src/cmd/compile/seed/semantic/analyzer.c` - Type collection

### Option 2: Hosted Bootstrap with Native Backend Fix

**Idea**: Skip native linking, use hosted compiler to emit C instead

**Implementation**:
1. Seed compiler generates stage1.ir (current state)
2. Use hosted compiler: `s_compiler --emit-c stage1.ir -> stage1.c`
3. Compile C to binary: `gcc stage1.c -o stage1_bin`
4. Use stage1_bin for stage2 (self-host)

**Pros**:
- No seed compiler changes needed
- Can start immediately
- Uses existing hosted compiler features

**Cons**:
- Requires hosted compiler at bootstrap time
- IR→C path might not be fully implemented
- Not a pure native bootstrap
- Creates dependency on hosted compiler toolchain

**Status**: Partially implemented in `src/cmd/dist/hosted-bootstrap.sh`  
**Next step**: Verify hosted compiler can actually emit C from IR

### Option 3: Eliminate Generics from Bootstrap Code

**Idea**: Rewrite compiler code without using generic types

**Example refactoring**:
```s
// Before:
func find_declaration(name string) option[string] { ... }

// After:
enum option_string { some(string), none }
func find_declaration(name string) option_string { ... }
```

**Pros**:
- Simple fix to bootstrap problem
- Works immediately with seed compiler

**Cons**:
- Major code rewrite (NxM explosion of types)
- Loses type safety of generics
- Harder to maintain
- Divergence between bootstrap and hosted compiler

### Option 4: Complete IR Backend Redesign

**Idea**: Implement full generic support in IR backend

**Implementation**:
- Extend IR type system for generic parameters
- Implement monomorphization in code generator
- Add polymorphic linking support

**Pros**:
- Most complete solution
- No divergence between bootstrap stages
- Enables advanced optimizations

**Cons**:
- Very large effort (~4-6 weeks)
- Complex type system changes
- High risk of introducing bugs
- Not urgently needed if Option 1 works

## Recommended Path Forward

### Immediate (this session)
1. ✅ Understand architectural limitation
2. ✅ Document problem and solutions
3. Create proof-of-concept for Option 2 (hosted bootstrap)
   - Test if `s_compiler --emit-c` works on stage1.ir
   - Measure compile time impact

### Short term (next 2-3 days)
1. **Implement Option 1** (mono in seed compiler):
   - Start with simple approach: scan all call sites
   - Collect type specializations needed
   - Emit monomorphized methods
   - Test with basic example

2. **Fallback to Option 2** if Option 1 proves complex:
   - Complete hosted bootstrap implementation
   - Make it production-ready

### Medium term (after bootstrap works)
1. Clean up duplicated monomorphization code
   - Currently: seed compiler + hosted compiler
   - Goal: Single shared implementation
2. Profile and optimize mono pass
3. Plan for full generic support in IR if needed

## Technical Notes

### Generic Method References

Compiler code that needs monomorphization:

```s
// std.option - used everywhere for error handling
func (option[t] self) is_none() bool
func (option[t] self) is_some() bool  
func (option[t] self) unwrap() t

// std.result - error results
func (result[t,e] self) unwrap() t
func (result[t,e] self) unwrap_err() e

// Other generics
box[t], []t, map[k]v
```

Type parameters used in compiler:
- `option[string]` - type names
- `option[type]` - canonical types
- `box[expr]` - AST expressions
- etc.

### IR Monomorphization Format

Current (broken):
```
FUNC_BEGIN|option[t].is_none|_|_
... generic code ...
FUNC_END|option[t].is_none|_|_
```

Needed:
```
FUNC_BEGIN|std.option.is_none.option[string]|_|_
... specialized code ...
FUNC_END|std.option.is_none.option[string]|_|_

FUNC_BEGIN|std.option.is_none.option[type]|_|_
... specialized code ...
FUNC_END|std.option.is_none.option[type]|_|_
```

### Call Site Analysis

Option 1 requires collecting all call sites:
1. Parse IR for CALL instructions
2. Extract target function name and argument types
3. If calling generic, record specialization needed
4. Emit all needed specializations

This is essentially what `compile.internal.mono` does, but earlier and in C.

## Files Modified This Session

- ✅ `doc/BOOTSTRAP.md` - This document
- ✅ `src/cmd/dist/hosted-bootstrap.sh` - Framework and documentation
- ✅ `makefile` - Added `hosted-bootstrap` target
- ✅ Previous sessions: Fixed field reborrow, dead code removal, IR validators

## See Also

- `src/cmd/dist/README.md` - Bootstrap design overview
- `src/cmd/compile/internal/mono/monomorphization.s` - Mono algorithm
- `src/cmd/compile/seed/code/generator.c` - IR generation entry point
- `src/option/option.s` - Generic type example
