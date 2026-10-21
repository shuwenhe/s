# S Compiler Self-Hosting Progress Report

**Date**: 2026-10-21 | **Status**: Critical blocker identified and documented

## Major Achievement ✅

String comparison support has been successfully added to the S compiler, eliminating the primary type-checking blocker that was preventing self-compilation.

**Commit**: `b4f4cc6cb` - "feat: Add string comparison support to compiler (==, !=)"

### What Was Fixed

The compiler couldn't compile any code using string comparisons (`==`, `!=`) because the type checker only accepted integers (value_kind=1) for binary operators. This blocked self-hosting since the compiler's own source code uses string comparisons extensively.

**Solution Implemented**:
- Modified `src/cmd/compile/internal/compiler/frontend.s` (lines 1610-1650)
- Added support for value_kind 2 (string variables) and value_kind 17 (string literals)
- Generates proper `strcmp()` C code for string comparisons

## Current Blocker 🚧

Array parameters in function declarations are not supported by the no-GC subset compiler, blocking compilation of `compiler_main(string[] args)`.

**Location**: `src/cmd/compile/internal/compiler/main.s:13`

### Evidence

```s
// WORKS with seed compiler ✅
func compiler_main(string[] args) int { ... }

// FAILS with self-compiled compiler ❌
compiler: expected ')', found 'string'
```

### Root Cause

The self-compiling no-GC subset only supports:
- Extern declarations with array parameters ✅
- Regular functions with array parameters ❌

This is a parser/type-checker limitation in lines 1400-2100 of `frontend.s`.

## Solution Path

**Recommended**: Option 1 - Wrapper function approach (30 min)
- Keep seed compiler's `compiler_main(string[] args)` unchanged
- Create internal dispatcher that doesn't use array parameters
- Self-compiled version can call dispatcher directly

**Alternative**: Option 2 - Add array parameter support (1-2 hours)
- Extend no-GC parser to handle array parameters in regular functions
- Update type checker and codegen as needed
- Higher risk but eliminates limitation

## Timeline to Full Self-Hosting

```
String comparison fix     ✅ COMPLETE (2 hours ago)
Array parameter handling 🔲 30 min - 2 hours
Full compilation         🔲 30 min
Determinism verification 🔲 15 min
─────────────────────────────────────
Total remaining:         ~2-3 hours
```

## Progress Checkpoints

| Gate | Status | Evidence |
|------|--------|----------|
| P0: Canonical Closure | ✅ DONE | `.freeze.manifest` |
| P1: AST Producer | ✅ DONE | `valid/invalid` tests |
| String Comparison | ✅ DONE | `b4f4cc6cb` |
| Extern Functions | 🟡 PARTIAL | `1146f994b` |
| Array Parameters | 🔴 BLOCKED | Parser limitation |
| Self-Compilation | 🔲 PENDING | Blocked on arrays |
| Determinism | 🔲 PENDING | Blocked on arrays |

## Technical Details

### String Comparison Fix Details

The fix handles three cases:

1. **Direct literals**: `"hello" == "world"` 
   - Both value_kind 17 → generates `(!strcmp(left, right))`

2. **Variables**: `s1 == s2` where s1, s2 are strings
   - Both value_kind 2 → generates `(!strcmp(left, right))`

3. **Mixed**: `str == "literal"` 
   - Handles mixed kinds appropriately

The codegen tracks `left_kind` to determine when `strcmp()` wrapping is needed.

### Array Parameter Limitation

The no-GC parser attempts array support in lines 2495-2510 but only for extern declarations. Regular function parameters at lines 1400+ don't handle arrays.

Error sequence:
1. Parser sees `string` token for first parameter  
2. Next token is `[` (array bracket)
3. Parser doesn't consume `[` in normal function context
4. Parser tries to expect `)` but finds `[`
5. Fails with "expected ')', found 'string'"

## Files Modified

- `src/cmd/compile/internal/compiler/frontend.s`: +5 extern declarations, +modified lines 1617-1645 for comparison support
- `src/cmd/compile/internal/compiler/main.s`: +4 extern declarations

## Commits

1. `b4f4cc6cb` - String comparison support
2. `1146f994b` - Extern declarations for host functions (WIP, blocked by array params)

## Next Immediate Actions

1. Implement wrapper function approach for `compiler_main`
2. Test that wrapped version compiles with self-compiler
3. Execute full compiler self-compilation with wrapper
4. Verify determinism of generated binary
5. Declare full self-hosting achieved

## Architecture Notes

The S compiler follows a no-GC subset philosophy for the self-compiling portion. This subset is intentionally limited to ensure the compiler can compile itself with minimal dependencies. As self-hosting completes, future optimizations can leverage the full S language features that aren't yet supported in the no-GC subset.

---

**Session**: `/home/shuwen/shuwen/s`  
**User**: `shuwen`  
**Repository**: `shuwenhe/s`  
**Branch**: `main`
