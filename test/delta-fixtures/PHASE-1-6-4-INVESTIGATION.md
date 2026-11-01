# Phase 1.6.4 Investigation Report - Corrected Analysis
## function-call-expression-in-local-binding-RHS

## Test Results Summary

```
Test Case                              Status   Exit Code    Error
─────────────────────────────────────────────────────────────────────────
delta-019: return value()               ✅ PASS   17           —
delta-015: x := value(); return x       ❌ FAIL   —        undefined local
delta-020: x := value29(); return x     ❌ FAIL   —        undefined local
delta-016: x := std; return 0           ❌ FAIL   —        undefined local
delta-017: x := std.env; return 0       ❌ FAIL   —        undefined local  
delta-018: x := std.env.args(); ...     ❌ FAIL   —        undefined local
```

## PROVEN Finding (With Evidence)

### Direct Call WORKS
```c
func main() int {
    return value()    // ← bootstrap_subset ALREADY supports this
}
```
✅ Exit 17 (function call works in return expression via bs_expression)

### Call in Binding FAILS  
```c
func main() int {
    x := value()      // ← bootstrap_subset DOES NOT support this
    return x
}
```
❌ "undefined local" error at byte 82

## CRITICAL ARCHITECTURE DISCOVERY

When token is `BS_NAME`, two code paths treat it differently:

```
return value()
    ↓
bs_expression()
    ↓
sees '(' after name
    ↓
recognizes function call ✅

x := value()
    ↓
bs_local_binding()
    ↓
sees BS_NAME "value"
    ↓
immediately searches locals
    ↓
"undefined local" error ❌
```

**Root Cause**: Expression semantics are split across two code paths:
- `return expr` → `bs_expression()` (full capabilities)
- `:= expr` → `bs_local_binding()` own parser (limited to int/name)

**The Real Problem**: Not "function calls not supported" but **"same expression
has two different implementations depending on context"**.

### Why This Matters
This violates the principle of unified language semantics. When source code 
contains an expression like `value()`, its meaning should NOT depend on whether
it appears after `return` or `:=`.

## Current vs Needed RHS Handling

```
CURRENT (Two code paths):
  return expr {
    bs_expression(u, f, 0);     // Full power
    return u->value;
  }
  
  x := expr {
    // bs_local_binding's own limited parser
    if (token == BS_INT) { ... }
    else if (token == BS_NAME) { ... search locals ... }
    else error("expected literal or local");
  }

NEEDED (Unified):
  return expr {
    bs_expression(u, f, 0);
    return u->value;
  }
  
  x := expr {
    bs_expression(u, f, 0);     // SAME authority
    bs_local_bind(f, x_name, u->value);
  }
```

## Why NOT Implement Lookahead Hack?

Tempting but wrong:
```c
} else if (token == BS_NAME) {
    if (next_token == '(') {  // ← Lookahead hack
        bs_expression(u, f, 0);
    } else {
        // local reference
    }
}
```

This would **perpetuate the split**. Better to simply delegate:
```c
} else {
    // Use unified expression evaluator for ALL cases
    bs_expression(u, f, 0);
    local_value = u->value;
}
```

This fixes not just function calls, but the architectural inconsistency.

## UNPROVABLE Inferences (REJECTED)

- ✗ "All FAIL cases are unified blocker"
  Cannot prove qualified names fail for same reason; they could be separate
  
- ✗ "Implement arbitrary expression evaluation"
  Violates bootstrap minimalism; untested scope creep
  
- ✗ "This will unlock qualified names too"
  Unproven; requires separate investigation after 1.6.4

## Phase 1.6.4 Scope (PRECISE)

**First-Blocking-Capability**: 
```
function-call-expression-in-local-binding-RHS
```

**NOT**: "arbitrary expression evaluation in binding"
**NOT**: "all expression types in binding"
**ONLY**: Unifying the two code paths so that function calls 
         (already working in return) work in binding too

## Minimum PASS/FAIL Pair

**FAIL (current)**:
```s
func value() int { return 17 }
func main() int { x := value(); return x }
```
Error: "undefined local" at byte 82

**PASS (after 1.6.4)**:
```s
func value() int { return 17 }
func main() int { x := value(); return x }
```
Result: exit 17

**Source-Dependent Proof**:
```s
func value29() int { return 29 }
func main() int { x := value29(); return x }
```
Result: exit 29 (not 17; proves value propagates)

## Implementation Strategy

1. Modify `bs_local_binding()` to:
   - Parse `identifier :=`
   - Call `bs_expression()` for RHS evaluation
   - Store result via `bs_local_bind()`

2. Keep `bs_expression()` unchanged
   - It already handles function calls
   - No new expression types added

3. Test:
   - delta-015: x := value(); return x → exit 17
   - delta-020: x := value29(); return x → exit 29
   - All Phase 1.6.1-1.6.3 baseline tests remain GREEN

4. Immediately rerun canonical:
   - Will error at same location (byte 537) or beyond
   - CANNOT assume it will pass; `std` is still undefined

## Why STOP After 1.6.4?

Because we've solved the PROVEN problem (function calls in binding RHS).

Qualified names (std.env) are still UNKNOWN:
- Different from function calls (they have NO call operator)
- Could require qualified-name-expression support
- Could require module/package handling
- CANNOT assume unified solution fixes them

Only after rerunning canonical can we write new fixtures
to isolate the qualified-name blocker.

## Code Locations

- PASS/FAIL fixtures:
  - `test/delta-fixtures/delta-015-simple-call.s`
  - `test/delta-fixtures/delta-020-call-binding-29.s`
- Implementation target:
  - `src/cmd/compile/stage0/bootstrap_subset.c`
  - Function: `bs_local_binding()` (lines 159-187)
  - Strategy: delegate RHS to `bs_expression()`
- Frozen: All Phase 1.6.1-1.6.3 code (no changes)
