# P0 Execution - Critical Constraints

**Date**: 2026-09-09  
**Scope**: Real implementation (not test-driven shortcuts)  
**Audience**: Coding Agent  

---

## 🔴 Critical Constraint: No Workarounds for Test Count

**DO NOT** introduce new abstractions just to satisfy 16 test slots.

**Current Technical Debt**:
```s
// WRONG - hardcoded left/right
field_left_live: bool
field_right_live: bool
```

**Must be eliminated FIRST**:
- Remove hardcoded `left/right` field tracking
- Wire field state to existing `Path → FieldState` infrastructure
- Support arbitrary field count from day 1

**Red flag**: If you see code patterns like:
```s
if num_fields == 2 { ... special case ... }
```
Stop and refactor. This is the exact blocker.

---

## 📋 Strict Execution Order (Do NOT skip steps)

### Step 1: Audit Real Field Access/Move Lowering
**What**: Read the actual compiler code:
- How does `p.b` parse?
- How does `x := p.b` lower to AST/IR?
- Where is field move currently handled?
- Where is `field_left_live/field_right_live` used?

**Output**: List of files to modify, functions involved

### Step 2: Wire Field State from left/right to Path→FieldState
**What**: Extend existing `Path` infrastructure:
- Does `Path` already support 3+ fields?
- Wire `p.a`, `p.b`, `p.c` all to `FieldState`
- Remove hardcoded left/right checks

**Output**: Code diff showing removal of `field_left/right`, addition to Path

### Step 3: Verify Third Field Actually Works
**What**: Simplest test - just compile without semantic checking:
```s
p := Quad { a, b, c, d }
x := p.c
```

**Must produce**: AST where `p.c` is recognized as `Path{base: p, field: c}`

**Output**: Compilation succeeds, no crash

### Step 4: Record Field State at Move
**What**: Semantic analyzer marks ownership:
- After `x := p.c`: `p.c = MOVED` (compiler state)
- Aggregate state derived: `p = PARTIAL`
- Bind `x` to ownership of `p.c`

**Output**: Compiler tracks state internally (can be verified by generated C)

### Step 5: Emit Correct Generated C
**What**: Code gen emits:
```c
S_Resource *x = p->c;   // ← Pointer to field
p->c = NULL;            // ← Mark moved
```

**NOT**:
```c
S_Resource *x = __field_p_c;  // ✗ Virtual field (WRONG)
```

**Output**: `.s` file compiles to `.c` with above pattern

### Step 6: Verify Single Destruction Authority
**What**: Aggregate destructor (`compiler_drop_owned_Quad`) handles all fields:
```c
void compiler_drop_owned_Quad(S_Quad *q) {
    compiler_drop_user_Quad(q);  // ← dispatch to user drop
    free(q);
}

void compiler_drop_user_Quad(S_Quad *q) {
    // Iterate fields, skip NULL
    if (q->d != NULL) compiler_drop_owned_Resource(q->d);
    if (q->c != NULL) skip;  // ← moved field is NULL
    if (q->b != NULL) compiler_drop_owned_Resource(q->b);
    if (q->a != NULL) compiler_drop_owned_Resource(q->a);
}
```

**Output**: Generated C shows correct guard + skip pattern

### Step 7: Verify Negative Cases
**What**: These MUST compile to ERROR:
```s
y := p.c        // ✗ double move
use(p.c)        // ✗ use of moved
```

**Output**: Diagnostic messages at compile time

### Step 8: Field Reassignment (MOVED → LIVE)
**What**: After move, reassigning restores field:
```s
x := p.c        // p.c MOVED
p.c = Resource(99)
y := p.c        // ✓ p.c LIVE (allowed)
```

**Generated C**:
```c
S_Resource *x = p->c;
p->c = NULL;
// ... later ...
p->c = Resource(99);  // ← No drop, field was NULL
```

**Output**: Compiler allows second use after reassign

### Step 9: Aggregate State Recovery
**What**: After all moved fields reassigned, aggregate returns to LIVE:
```s
x := p.b; y := p.c; z := p.d;  // p = PARTIAL

p.b = Resource(1);  // p.b LIVE
p.c = Resource(2);  // p.c LIVE  
p.d = Resource(3);  // p.d LIVE
                    // p = LIVE (derived)

foo(p)              // ✓ Allowed (p = LIVE)
```

**Output**: Compiler allows aggregate consumption after recovery

### Step 10: Write 16 Tests (NOT before steps 1-9)
**What**: Only AFTER verification above, write tests:
- 9 positive cases (all should compile)
- 7 negative cases (all should reject)

**Do NOT** create tests until steps 1-9 work. Tests are validation, not discovery.

**Output**: 16 `.s` files in `test/partial_move_gate/`

---

## 🚫 What NOT to Do

### DO NOT modify `compiler_drop_owned_T` signature
**Current** (keep as-is):
```s
func compiler_drop_owned_Triple(Triple* t)
```

**WRONG** (don't do this):
```s
func compiler_drop_owned_Triple(Triple* t, uint64 flags)
```

**Why**: 
- NULL guards are sufficient for straight-line P0
- Runtime bitmap for `MAYBE_MOVED` is P2+ (CFG merge)
- Don't solve future problem now

### DO NOT create workaround abstractions
**Red flags**:
- New field tracking structure that's not `Path`
- Separate "partial move state machine"
- Field count dispatch logic

**Right approach**:
- Extend existing Path infrastructure
- Derive aggregate state from field states
- No special cases for `field_count > 2`

### DO NOT skip negative tests
- `double_move` must compile FAIL
- `moved_use` must compile FAIL
- Don't guess; test and show error output

### DO NOT run 16 tests before steps 1-9 work
- Test count is NOT a metric
- One correctly-implemented field move > 16 half-baked tests

---

## ✅ Success Proof (Required Artifacts)

When complete, provide ONLY these:

### Artifact 1: git diff
```bash
git diff HEAD~1
```
Shows exactly what changed in `.s` files. Should show:
- Removed `field_left_live/field_right_live`
- Added Path support for 3+ fields
- Modified field state tracking
- Modified code gen for aggregate fields

### Artifact 2: Real S Fixtures
Actual `.s` source files:
- `partial_move_three_field.s` - Simplest case
- `partial_move_reassign.s` - Aggregate recovery
- `moved_field_rejected.s` - Negative case

### Artifact 3: Generated C Output
Real `.c` files from compilation:
- Shows `p->c = NULL` pattern
- Shows NULL-guarded destructor
- Shows LIFO cleanup order
- Shows no double-drop

### Artifact 4: Test/Diagnostic Output
```bash
$ make build
$ s_compiler test/partial_move_three_field.s
(compilation succeeds, C output shows NULL pattern)

$ s_compiler test/moved_field_rejected.s
error: use of moved field 'c' at line X
```

---

## 🎬 The Critical Milestone

Proof that this Gate has value:

**Before P0**:
```
p.b is special (only two fields in typesys)
```

**After P0**:
```
p := Quad { a: Resource, b: Resource, c: Resource, d: Resource }
x := p.c
y := p.d
```
Works correctly. Compiler knows:
- `p.c = MOVED`
- `p.d = MOVED`
- `p.a = LIVE`
- `p.b = LIVE`
- `p = PARTIAL`

Generated C safely drops unused fields, skips moved fields, no crashes.

This proves S can handle **arbitrary-field ownership** now, not just pairs.

---

## ⏱️ Implementation Timeline (Estimate)

- Audit + Path extension: 1-2 days
- Code gen for 3+ fields: 1 day
- Negative case validation: 1 day
- Aggregate recovery: 1 day
- 16 tests: 1-2 days
- **Total**: ~1 week (solo dev) or 3-4 days (2 people)

---

## 📞 Reporting Points

After each step, report:

**After Step 3**: "Third field AST parsing works. Compilation succeeds."

**After Step 5**: "Generated C for 3-field case: [snippet]"

**After Step 7**: "Negative test output: [diagnostic]"

**After Step 10**: "16 tests pass. Artifact list ready for review."

---

## 🏁 Final Gate Decision Criteria

At end of implementation, I will check:

✅ **Invariant 1** (Ownership Transfer): Does compiler know `p.c` ownership passed to `x`?

✅ **Invariant 2** (Static State): Can we verify `p.c = MOVED` at compile time (not just runtime)?

✅ **Invariant 3** (Runtime NULL): Does generated C have `p->c = NULL`?

✅ **Invariant 4** (Single Authority): Does only `compiler_drop_owned_Quad` handle cleanup?

✅ **Invariant 5** (State Restoration): Can aggregate recover from PARTIAL to LIVE?

If all 5 hold + 16 tests correct + git diff clean:

```
P0 PASS ✓
```

If any issue found → **Report first blocker, request guidance**

---

## 🎯 Focus

Not: "How do I make tests pass?"

Right: "Does the compiler actually understand field-level ownership?"

Evidence: Generated C, diagnostics, git changes.

No stories, no estimates, no percentages. Just code.

