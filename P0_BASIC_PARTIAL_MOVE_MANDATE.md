# P0 Basic Partial Move Compiler Integration - Agent Execution Mandate

**Date**: 2026-09-09  
**Status**: Ready for Implementation  
**Target**: Real `compiler.s` integration (not prototype)  
**Success Metric**: 16 tests + generated C + diagnostics validation  

---

## 🎯 Mission

Transform partial field move from prototype (`__field_p_b` virtual encoding) to real compiler integration:

**Real S source**:
```s
p := Triple {
    a: Resource(1),
    b: Resource(2),
    c: Resource(3),
}
x := p.b
```

**NOT converted to**: `__field_p_a`, `__field_p_b`, `__field_p_c`

**MUST become**: Aggregate `p` with field-level ownership state

**Generated C**:
```c
S_Triple *p = compiler_box_Triple(...);
S_Resource *x = p->b;  // ← Pointer to field
p->b = NULL;           // ← Mark moved
// ... use x ...
compiler_drop_owned_Triple(p);  // ← Single destructor
```

---

## 🔧 Four Critical Technical Corrections

### Correction 1: Field Assignment Overwrite Logic

**WRONG**:
```s
x := p.b                      // p.b MOVED
p.b = Resource(99)            // Always drop old value
```

**CORRECT**:
```s
// Case A: p.b is MOVED
x := p.b                      // p.b MOVED, x LIVE
p.b = Resource(99)            
  ↓
  Check p.b state: MOVED
  ↓
  Evaluate RHS
  ↓
  Install to p.b (no drop needed)
  ↓
  p.b = LIVE

Generated C:
  S_Resource *x = p->b;
  p->b = NULL;
  // ... later ...
  p->b = Resource(99);        // ← No drop; field was NULL

// Case B: p.b is LIVE
y := p.c                      // p.c LIVE
p.c = Resource(55)
  ↓
  Check p.c state: LIVE
  ↓
  Evaluate RHS
  ↓
  Drop old p->c
  ↓
  Install new to p.c
  ↓
  p.c = LIVE

Generated C:
  compiler_drop_owned_Resource(p->c);
  p->c = Resource(55);        // ← Drop needed; field had owner
```

**Implementation Rule**:
```
When assigning to field f of aggregate p:
  if f == MOVED → evaluate RHS, install, f = LIVE
  if f == LIVE  → evaluate RHS, drop old, install, f = LIVE
  if f == DEAD  → error: cannot assign to dead field
```

---

### Correction 2: Aggregate State Derivation (Not Dual Truth)

**WRONG**: Maintain separate `p = PARTIAL` alongside `p.b = MOVED, p.a = LIVE, p.c = LIVE`

**CORRECT**: `p` state is **derived from field states**:

```
Derivation Rule:
  all owned fields == LIVE        → p = LIVE
  some MOVED, rest LIVE           → p = PARTIAL
  all appropriate fields == DEAD  → p = DEAD
  CFG conflict (P2 later)         → p = MAYBE
```

**Implementation**:
```s
func derive_aggregate_state(owned_field[] fields) ownership_state {
    live_count := 0
    moved_count := 0
    dead_count := 0

    for f in fields {
        match f.state {
            case LIVE:  live_count++
            case MOVED: moved_count++
            case DEAD:  dead_count++
        }
    }

    if moved_count == 0 && dead_count == 0 {
        return LIVE
    }
    if moved_count > 0 && dead_count == 0 {
        return PARTIAL
    }
    if moved_count + dead_count == len(fields) {
        return DEAD
    }
    
    MAYBE  // CFG conflict (future)
}
```

**Never call `drop_aggregate(p)` if `p` PARTIAL** — only owned field destructors fire.

**State Recovery Example**:
```s
p := Triple { a, b, c }        // p = LIVE

x := p.b                        // p.b MOVED → p = PARTIAL
y := p.c                        // p.c MOVED → p = PARTIAL

p.c = Resource(99)              // p.c LIVE → re-derive aggregate
                                // p.a LIVE, p.b MOVED, p.c LIVE
                                // → p still PARTIAL

p.b = Resource(88)              // p.b LIVE → re-derive aggregate  
                                // All owned fields LIVE
                                // → p = LIVE (restored!)
```

---

### Correction 3: Boundary Between P0 and P2

**P0 allows** (Basic Partial Move before branching):
```s
x := p.b                       // Partial move happens first
                               // p.b definitely MOVED at this point

if condition {
    return x                   // One branch: x LIVE, p PARTIAL
}

y := p.a                       // Other branch: p.a accessible
                               // Both use common p state
```
✅ No CFG merge of field states needed.

**P2 requires** (Conditional partial move — NOT in P0):
```s
if cond {
    x := p.b                   // Path A: p.b MOVED
} else {
    y := 42                    // Path B: p.b still LIVE
}

use(p.b)                       // ← After merge: p.b is MAYBE_MOVED
```
❌ Requires CFG merge → MAYBE state → NOT P0.

**Test boundary**:
- `partial_move_early_return`: ✅ P0 (move before branch)
- Conditional move itself: ❌ P2 (branch inside move)

---

### Correction 4: Use Real S Custom Drop Syntax

**NOT Rust style**:
```s
impl Drop for Triple {          // ❌ NOT valid S
    func drop(self) { ... }
}
```

**Real S style**:
```s
func (Triple* t) drop() {       // ✅ Real S custom drop
    printf("dropping triple")
    // cleanup logic
}
```

**Negative test**:
```s
struct Triple {
    a: Resource
    b: Resource
    c: Resource
}

func (Triple* t) drop() {
    // Custom destructor
    printf("custom drop")
}

func main() {
    p := Triple { ... }
    x := p.b                    // ← Compile ERROR
}
```

**Expected diagnostic**:
```
error: cannot partially move field 'b' from aggregate 'p'
  reason: type 'Triple' defines custom drop
  location: line X, column Y
```

---

## 📋 Five Immutable Invariants

These MUST hold at end of P0. If any fail → GATE FAIL.

### Invariant 1: Ownership Transfer
```
Before: p has exclusive owner of b
        b is part of p's destruction

After x := p.b:
        x has exclusive owner of b
        b is NOT part of p's destruction anymore
        Violation: use(p.b) after move → compile error
```

### Invariant 2: Static Ownership Tracking
```
Compiler's ownership_state[b]:
  Before: LIVE
  After:  MOVED

Not just runtime NULL check.
Editor should show: p.b [MOVED] if hover.
Diagnostic "use of moved field 'b'" must be compile-time.
```

### Invariant 3: Runtime NULL Marking
```
Generated C:
  x = p->b;    // Move pointer
  p->b = NULL; // Mark moved

If aggregate destructor accesses p->b:
  if (p->b != NULL) drop(p->b);  // ← guarded
  else skip                        // ← NULL safe
```

### Invariant 4: Single Destruction Authority
```
Only ONE function destroys aggregate:
  compiler_drop_owned_Triple(p)
    ↓
    compiler_drop_user_Triple(p)  [iterate owned fields]
      ↓
      for each field f:
        if (f != NULL) compiler_drop_owned_<FieldType>(f)
        else skip

Field-state system NEVER independently calls destructor.
No double-drop possible.
```

### Invariant 5: State Restoration
```
When moved field gets new owner:

p.b = Resource(99)  // re-assign
  ↓
p.b = LIVE          // field state updated
  ↓
Re-derive p: all owned fields LIVE
  ↓
p = LIVE            // aggregate state restored

If aggreg needs to be moved/consumed later:
  func foo(Triple t) { }
  foo(p)              // ← Now valid (was PARTIAL, now LIVE)
```

---

## ✅ Test Checklist (16 tests)

### Positive Tests (9 must PASS)

- [ ] **partial_move_one_field**
  - Source: `x := p.b`
  - Verify: `p.b MOVED, p PARTIAL, x LIVE`
  - Generated C: `x = p->b; p->b = NULL;`

- [ ] **partial_move_two_fields**
  - Source: `x := p.b; y := p.c`
  - Verify: `p.b MOVED, p.c MOVED, p.a LIVE`
  - Generated C: Both fields NULL

- [ ] **partial_move_nested**
  - Source: `p.nested = Pair{...}; x := p.nested.inner`
  - Verify: `p.nested.inner MOVED`
  - Generated C: Nested field NULL

- [ ] **partial_move_unmoved_sibling_accessible**
  - Source: `x := p.b; val := p.a`
  - Verify: `p.a LIVE` (no error)
  - Generated C: Direct p->a access

- [ ] **partial_move_plain_field**
  - Source: `struct Pair { a: int, b: Resource }; res := p.b`
  - Verify: `p.a LIVE` (Copy type, unaffected)
  - Generated C: No cleanup of p.a

- [ ] **partial_move_overwrite_case_a**
  - Source: `x := p.b; p.b = Resource(99)`
  - Verify: `p.b MOVED → p.b LIVE`
  - Generated C: NO drop, just install
  - Generated C detail: `p->b = Resource(99)` without drop

- [ ] **partial_move_overwrite_case_b**
  - Source: `p.a = Resource(1); p.a = Resource(2)`
  - Verify: `p.a LIVE → LIVE` (always LIVE)
  - Generated C: drop old, install new

- [ ] **partial_move_early_return**
  - Source: `x := p.b; if cond { return x }`
  - Verify: `x LIVE, p PARTIAL` on return path
  - Generated C: x returned, p cleanup skipped

- [ ] **partial_move_reverse_cleanup**
  - Source: `x := p.b; y := p.c; (scope exit)`
  - Verify: Cleanup order LIFO
  - Generated C: `drop(y); drop(x); drop(p);`
  - Cleanup detail: `drop(y)` first (last declared), then `drop(x)`, then `drop(p)`

### Negative Tests (7 must REJECT)

- [ ] **double_partial_move_rejected**
  - Source: `x := p.b; y := p.b`
  - Error: "field 'b' has already been moved"

- [ ] **moved_field_use_rejected**
  - Source: `x := p.b; val := p.b`
  - Error: "use of moved field 'b'"

- [ ] **whole_move_after_partial_rejected**
  - Source: `x := p.b; y := p` (aggregate with moved field)
  - Error: "cannot move aggregate with moved field"

- [ ] **whole_consume_after_partial_rejected**
  - Source: `x := p.b; foo(p)` where foo consumes
  - Error: "cannot pass aggregate with moved field"

- [ ] **custom_drop_partial_move_rejected**
  - Source: aggregate with `func (T* t) drop()`, then `x := p.b`
  - Error: "partial move of aggregate with custom drop is unsafe"

- [ ] **conditional_partial_move_rejected**
  - Source: `if cond { x := p.b }; use(p.b)`
  - Error: "field 'b' may be moved on some paths"
  - Note: This bridges toward P2 but is a clear REJECT in P0

- [ ] **loop_partial_move_rejected**
  - Source: `for _ { x := p.b }`
  - Error: "cannot guarantee single move in loop"

---

## 🎬 Generated C Quality Checklist

Every positive test must produce C matching these requirements:

- [ ] No virtual field encoding (`__field_p_b` NEVER appears)
- [ ] Aggregate struct preserved (e.g., `S_Triple *p`)
- [ ] Field access via `->` pointer syntax
- [ ] Moved fields marked with `NULL`
- [ ] Single `compiler_drop_owned_Triple` function call
- [ ] Internal `compiler_drop_user_Triple` iterates fields
- [ ] Cleanup in LIFO reverse order (last declared first)
- [ ] No possible double-drop (NULL guards protect)
- [ ] Copy-type fields skip drop
- [ ] Nested owned fields use `compiler_move_<NestedType>` pattern

---

## 🚀 Implementation Priority (Do in this order)

### Phase 1: Ownership State Representation
- [ ] Extend `ownership_state` enum: `LIVE, MOVED, DEAD, MAYBE`
- [ ] Add field-level state tracking: `owned_field { name, state, owner_var }`
- [ ] Add aggregate state derivation function
- [ ] Do NOT implement CFG merge yet (P2)

### Phase 2: Parser & Semantic Analysis
- [ ] Ensure `p.b` parses as field access (already works?)
- [ ] Semantic analyzer recognizes `p.b` move: mark `p.b = MOVED`
- [ ] Update aggregate state after field move
- [ ] Implement Correction 1 logic: assignment overwrite cases

### Phase 3: Generated C
- [ ] Emit `x = p->b` (pointer to field)
- [ ] Emit `p->b = NULL` after move
- [ ] Ensure aggregate destructor does not drop MOVED/NULL fields
- [ ] Implement LIFO cleanup order

### Phase 4: Testing & Validation
- [ ] Write 16 test cases (9 positive, 7 negative)
- [ ] Capture generated C for each test
- [ ] Capture diagnostic messages for negative tests
- [ ] Run `make no-gc-test`, `make compiler-check`

### Phase 5: Documentation
- [ ] Update compiler.s comments explaining field move logic
- [ ] Add test case comments explaining each scenario

---

## ❌ What NOT to do

- ❌ Do NOT create virtual field encoding (`__field_p_b`)
- ❌ Do NOT implement CFG merge for field ownership (P2)
- ❌ Do NOT support conditional partial move (P2)
- ❌ Do NOT create new optimization documents
- ❌ Do NOT attempt Generic system
- ❌ Do NOT attempt Trait system
- ❌ Do NOT discuss "completeness percentages"
- ❌ Do NOT skip testing negative cases
- ❌ Do NOT proceed to P1 (Nested Partial Move) until this is DONE

---

## 🏁 Success Criteria (Mandatory)

### Compile Correctly
```bash
make build
make no-gc-test      # All existing tests PASS
make compiler-check  # No new warnings
```

### All Tests Pass
```
Positive: 9/9 compile ✓
Negative: 7/7 reject with correct error ✓
Generated C: 10/10 quality checks ✓
```

### Demonstrate Evidence
At completion, provide:

1. **Code changes summary**
   - List of files modified in compiler.s
   - New functions added (if any)
   - Modified functions (which ones, what changed)

2. **Generated C samples**
   - `partial_move_one_field.c` (from test)
   - `partial_move_overwrite_case_a.c` (verify no drop)
   - `partial_move_reverse_cleanup.c` (verify LIFO)
   - One negative test error output

3. **Test results**
   - 16 test case list with PASS/REJECT status
   - Error message for each negative test

4. **Build confirmation**
   ```
   make clean && make build && make no-gc-test
   ```

5. **P0 Gate Declaration**
   ```
   Status: PASS / PARTIAL / FAIL
   Invariant 1 (Ownership Transfer): PASS / FAIL
   Invariant 2 (Static State): PASS / FAIL
   Invariant 3 (Runtime NULL): PASS / FAIL
   Invariant 4 (Single Authority): PASS / FAIL
   Invariant 5 (State Restoration): PASS / FAIL
   First Blocker (if any): [description]
   Ready for P1: YES / NO
   ```

---

## 📞 When to Stop & Sync

**Do NOT**:
- Guess about ownership semantics
- Skip a negative test because it seems hard
- Continue past first blocker without reporting

**DO**:
- Report any case where "test PASS but semantics unclear"
- Ask for clarification on Correction 1/2/3/4 if implementation unclear
- Provide generated C for review if uncertain

---

## 🎯 Final Gate Review

After Agent completes, I will perform **strict Gate Review** checking:

1. Does aggregate truly preserve (not virtualized)?
2. Is ownership transfer real (compiler knows state)?
3. Is runtime NULL marking present?
4. Is single destruction authority preserved?
5. Can state restoration work (PARTIAL → LIVE)?
6. Do negative tests reveal bugs or catch them?
7. Any "looks like PASS but semantically questionable" cases?

If all 5 invariants hold + all 16 tests correct → **P0 PASS**

If any issue found → **P0 PARTIAL/FAIL** with blocker description

---

**This document replaces all optimization roadmaps and architecture discussions.**

**Focus: Real code. Real tests. Real C output. No estimates. No percentages.**

**Start implementation. Report progress and blockers. I will review the Gate.**

