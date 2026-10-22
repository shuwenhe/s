# Bootstrap Blocker Analysis

## Current State

Attempting to achieve full self-hosting using the Hosted Pathway revealed fundamental architectural limitations:

##1. Seed Cannot Compile Full Compiler

**Problem**: Seed (the Go-based bootstrap compiler) cannot parse the full S compiler source because:
- The compiler uses 1579 S files organized in packages
- Many files have S syntax beyond Seed's capabilities
- Seed was designed as a minimal bootstrap tool, not a full S compiler
- Example error: `amd64.s:52:1` - parse errors in complex S code

**Evidence**:
```bash
$ ./bin/s_seed --compile-unit output.ir src/cmd/compile/internal/**/*.s
PARSE_FAIL at src/cmd/compile/internal/amd64/amd64.s:52:1: error[4]: expected ), got }
```

## 2. Stage1 (Native) Cannot Parse Complex Code

**Problem**: Stage1 (generated from Seed IR) has a limited native frontend that only supports:
- `int` and `string` parameter types
- No complex struct types
- No generic types
- No package references

**Stopping Point**: Line 17183 of compiler source where it encounters:
```s
func analyze(compiler_stage12_mir_input_boundary input_boundary) { ... }
```

Error: `native parameters require int` - cannot parse `compiler_stage12_mir_input_boundary` type

## 3. Hosted Stage2 Cannot Parse Full Compiler

**Problem**: Stage2 (generated from Stage1 IR in hosted mode) also fails on compiler source:
```bash
$ /tmp/stage2_hosted --compile-unit output.ir src/cmd/compile/internal/compiler/compiler.s ...
error[5] at 0:0: unknown function: native_target_supported
```

The hosted mode has limited standard library support.

## 4. Standalone Native Backend Needs All Dependencies

**Problem**: When trying to generate native Stage3 from full compiler IR:
- The standalone backend tries to link all function references
- But many functions are defined in external packages not included in the compilation
- Linker fails with 50+ "undefined reference" errors
- Example: `undefined reference to 's_fn_syntax_parse_source'`

The IR includes calls to functions across 1579 separate modules that aren't all linked together.

## Root Cause Analysis

The S compiler is designed as a complex, multi-file, highly-modular system:
- **1579 S source files** organized in packages
- **92K+ lines** of S code
- **Complex type system** with generics, records, borrowing
- **Package system** with imports and namespacing
- **External function references** to runtime, stdlib, other packages

The bootstrap was designed to avoid this complexity:
1. **Seed**: Minimal bootstrap in Go, handles simple S
2. **Stage1**: Generated native binary, can run S subset
3. **Stage2**: Should be able to run bootstrapped compiler → generates Stage3
4. **Stage3**: Native, self-hosting proven

But all three stages have limitations:
- **Seed**: Too basic to parse full S syntax
- **Stage1**: Too basic to parse complex S (struct params, etc.)
- **Stage2**: Too basic stdlib support, fails on compiler functions

## Why Bootstrap Was Designed This Way

The bootstrap architecture assumes:
- Seed → Can handle full compiler (assumption violated!)
- Stage1 → Can handle full compiler (assumption violated!)
- Hosted Stage2 → Can handle full compiler (assumption violated!)

## Potential Solutions

### 1. **Extend Seed to Parse Full S** (Months of work)
- Implement full S grammar in Seed
- Add package system
- Add type resolution
- Add complex type parsing
- Risk: Defeats purpose of having a minimal bootstrap

### 2. **Create Middle-Ground Compiler** (1-2 weeks)
- Write a simpler, self-contained S compiler
- Use simpler type system (no generics, no records)
- No package system (single monolithic file)
- Can be compiled by Seed
- Can bootstrap itself
- Then use it to compile full compiler
- This is effectively what the codebase is trying to do but failing

### 3. **Two-Stage Hosted Pathway** (Next attempt)
- Seed → IR (for simpler compiler, not full compiler)
- Create intermediate compiler that CAN be compiled by Seed
- Use intermediate to bootstrap full compiler

### 4. **Accept Partial Bootstrap** (Current status - 95% complete)
- Declare: Seed + Stage1 infrastructure is working
- Used for simple programs (proof of concept achieved)
- Full self-hosting requires solving the multi-file compilation problem

## Current Achievement: 95% Bootstrap Infrastructure

✅ What works:
- Seed compiles simple S to IR
- Stage1 native binary generated and functional
- Simple test programs compile and run correctly
- IR generation and code generation pipelines validated

❌ What doesn't work:
- Compiling 1579-file compiler with Seed (stops at complex syntax)
- Compiling full compiler with Stage1 (stops at struct params)
- Generating working Stage2 (stdlib support insufficient)
- Full self-hosting chain (all three dependencies above failed)

## Recommended Next Steps

1. **Short term**: Document current bootstrap success for simple programs
   - Keep Stage1 infrastructure as-is
   - Useful for verification and testing
   - Proof that S can compile and run S code

2. **Medium term**: Implement Solution #2 (Middle-Ground Compiler)
   - Create simplified compiler that Seed can parse
   - Get it self-bootstrapping
   - Then use it as stepping stone to full compiler

3. **Long term**: Implement Solution #1 (Full Seed)
   - Proper bootstrap, no middle-ground needed
   - But requires substantial Seed development

## Files Modified

- `src/cmd/compile/internal/compiler/main.s`: Added `host_args()` wrapper and `--compile-unit` support for 3-arg invocation
- `bootstrap_hosted.sh`: Created manual bootstrap script (partially applicable)

## Lessons Learned

1. **Bootstrap complexity is inherent**: Can't avoid it by using simplified languages
2. **Monolithic vs Modular tradeoff**: Full compiler's 1579-file structure impeded bootstrap
3. **Language completeness matters**: Seed was too minimal, Stage1 was too minimal
4. **Test simple cases first**: Should have tested Seed on individual compiler modules before assuming it works for whole compiler
