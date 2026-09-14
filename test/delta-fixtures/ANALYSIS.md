# Phase 1.6.3 Blocker Analysis

## 证据链

### Canonical Source
- File: `src/cmd/compile/modular_build_main.s`
- Error: `bootstrap-subset: byte 530: expected bootstrap keyword`
- Position: First line of `main()` function body: `args := std.env.args()`

### Delta Fixture Testing

#### ✅ PASS Cases
```s
package cmd
import ()
func main() int {
    return 0
}
```
(delta-003)

```s
package cmd
func main() int {
    return 42
}
```
(delta-009)

#### ❌ FAIL Cases
```s
package cmd
func main() int {
    x := 17           ← FAIL at byte 36: "expected bootstrap keyword"
    return x
}
```
(delta-004)

```s
package cmd
func main() int {
    args := std.env.args()    ← FAIL
    return 0
}
```
(delta-005)

## Root Cause

In `src/cmd/compile/stage0/bootstrap_subset.c`, function `bs_unit()` line ~179:
```c
bs_expect(u, '{');
bs_word(u, "return");      // Expects keyword "return" immediately
bs_expression(u, f, 0);
bs_expect(u, '}');
```

Current grammar enforces:
```
func-declaration = "func" identifier "(" ")" "int" "{" "return" expression "}"
```

Bootstrap_subset requires **exactly one `return` statement** in function body.
**Any other statement causes failure.**

## First Real Blocker: Phase 1.6.3

**Name**: `local-variable-binding`

**Definition**: Support for local variable declarations and statements before the mandatory `return` in function body.

**Minimal FAIL case**:
```s
package cmd
func main() int {
    x := 17
    return x
}
```

**Minimal PASS case** (already passes):
```s
package cmd
func main() int {
    return 0
}
```

**Canonical blocker point**: byte 530 in `modular_build_main.s`
- Requires parsing statement-level constructs
- Requires `:=` operator recognition
- Requires binding identifier to local scope

**Bootstrap subset impact**:
- Must parse statements before `return`
- Must recognize `:=` operator
- Must NOT do semantic binding (names can be collected but not resolved)
- Must still validate that `return` is final statement in body
