# Stage1 Delegation Authority Check - Diagnostic Guide

**Date**: 2026-09-15  
**Blocker**: `no-delegation=FAIL` → prevents `canonical-source-compilation=PROVEN`  
**Goal**: Determine if s_modular-stage1's "bootstrap-subset" reference is only marker or real semantic delegation

---

## Problem Statement

```
s_modular-stage1 binary contains "bootstrap-subset" string

Current gate treats this as FAILURE:
  no-delegation=FAIL → canonical-source-compilation=NOT_PROVEN

But unclear: is this string JUST a marker (embed during build)
            or RUNTIME/SEMANTIC delegation (Stage1 really calls bootstrap_subset)?

Current gate condition is too strong (any occurrence = fail)
Need diagnostic to distinguish A vs B
```

---

## Decision Tree

```
Does Stage1 binary contain "bootstrap-subset"?
  │
  ├─ YES → Is it only embedded marker?
  │         │
  │         ├─ YES (marker only)
  │         │   ├─ embedded-marker=YES
  │         │   ├─ runtime-delegation=NO
  │         │   ├─ semantic-delegation=NO
  │         │   └─ GATE: modify condition (not compiler) ✅
  │         │
  │         └─ NO (real delegation)
  │             ├─ Trace Stage1 entry → driver → dispatch
  │             ├─ Find where bootstrap_subset is called
  │             ├─ Determine if it's in canonical path
  │             └─ GATE: cut delegation edge 🔴
  │
  └─ NO (no reference at all)
      └─ Unexpected (check if Stage1 built correctly)
```

---

## Diagnostic Steps

### Step 0: Verify Stage1 Exists and Runs

```bash
# Current state check
cd /Users/feifei/shuwen/s

# Does s_modular-stage1 exist?
[ -f bin/s_modular-stage1 ] && echo "✓ Stage1 binary exists" || echo "✗ Missing"

# Can it run?
bin/s_modular-stage1 --help 2>&1 | head -5
# Should output Go-like help or error, NOT crash

# Can it compile canonical?
bin/s_modular-stage1 src/cmd/compile/internal/syntax/parser.s -c 2>&1 | head -10
# Should compile something (or error gracefully)
```

### Step 1: Check for "bootstrap-subset" Strings

```bash
# A. String search in binary
strings bin/s_modular-stage1 | grep -i bootstrap

# Output interpretation:
# - "bootstrap_subset"  ← probably code constant/embedded
# - "unknown function: bootstrap_subset" ← error message
# - "/path/to/bootstrap_subset.c" ← debug info or constant

# B. Where are these strings from?
nm bin/s_modular-stage1 | grep -i bootstrap

# Output interpretation:
# - External reference (U) → linked from somewhere
# - Defined locally (T) → built into binary
# - In data section (D) → embedded constant

# C. Count occurrences
strings bin/s_modular-stage1 | grep -i bootstrap | wc -l
# If just 1-2 occurrences → probably marker
# If 5+ occurrences → probably real code references
```

### Step 2: Check Source Code References

```bash
# Is bootstrap-subset mentioned in canonical compiler source?
grep -r "bootstrap.subset\|bootstrap_subset" src/cmd/compile/ \
  | grep -v "\.go~" \
  | grep -v ".git" \
  | wc -l

# Expected:
# If 0: good (no reference at all)
# If 1-2: acceptable (maybe in comments or version)
# If 5+: problem (real dependencies)

# What are these references?
grep -r "bootstrap.subset\|bootstrap_subset" src/cmd/compile/ \
  | head -20
```

### Step 3: Trace Runtime Behavior

```bash
# Does Stage1 call bootstrap_subset functions?
# Check via strace/debug

# A. Static analysis: executable symbols
nm -D bin/s_modular-stage1 | grep bootstrap_subset
# If empty → no dynamic reference ✓
# If found → might be runtime call 🔴

# B. Debug info inspection
objdump -t bin/s_modular-stage1 | grep -i bootstrap
# Same interpretation as nm

# C. Dependencies check
ldd bin/s_modular-stage1 | grep -i s_seed
# If no match → good (not linked to seed)
# If match → s_seed is dependency 🔴
```

### Step 4: Examine Build Process

```bash
# What's in the makefile that builds Stage1?
grep -A 20 "s_modular-stage1:" Makefile

# Key questions:
# - Is bootstrap_subset_object.o linked in?
# - Any flags referencing seed/bootstrap?
# - What's the actual compiler command?

# Result interpretation:
# If bootstrap objects NOT linked → marker only ✓
# If bootstrap objects linked → real dependency 🔴
```

### Step 5: Behavioral Test (Most Definitive)

```bash
# Can Stage1 compile something that explicitly tests delegation?

# Create a minimal test
cat > /tmp/test_stage1_delegation.s << 'EOF'
package main

func main() {
    // This tests if Stage1 can handle basic compilation
    // without delegating to bootstrap_subset
    x := 42
    return x
}
EOF

# Test 1: Try to compile
bin/s_modular-stage1 /tmp/test_stage1_delegation.s -c \
  2>&1 | tee /tmp/stage1_output.txt

# Test 2: Check if error mentions bootstrap_subset
grep -i "bootstrap" /tmp/stage1_output.txt
# If no match → Stage1 didn't delegate ✓
# If match → Stage1 tried to call bootstrap 🔴

# Test 3: Check exit code
echo $?
# Exit 0 = compiled successfully (no delegation needed)
# Exit 1-127 = error (check if bootstrap_subset mentioned)
```

### Step 6: Source Code Walkthrough

If Steps 1-5 suggest real delegation, trace it:

```bash
# Find main entry of Stage1
grep -r "func main" src/cmd/compile/ | head -3

# Trace the call chain
# Look for: main → driver → dispatch → ???

# Key files to check:
# - src/cmd/compile/main.s (entry point)
# - src/cmd/compile/driver.s (main compilation driver)
# - src/cmd/compile/internal//*parser*.s (parsing)

# Grep for bootstrap references in these
grep -n "bootstrap\|s_seed" src/cmd/compile/main.s
grep -n "bootstrap\|s_seed" src/cmd/compile/driver.s
grep -n "bootstrap\|s_seed" src/cmd/compile/internal/*/parser.s

# Result: find first call site
# Then determine if it's in CANONICAL path or fallback path
```

---

## Expected Outcomes

### Outcome A: Embedded Marker Only ✅

```
Diagnostics show:
  ├─ strings bin/s_modular-stage1 | grep bootstrap: 1-2 matches (version strings)
  ├─ nm bin/s_modular-stage1 | grep bootstrap_subset: (empty)
  ├─ grep src/cmd/compile/**/*.s: 0 real code references
  ├─ ldd bin/s_modular-stage1 | grep s_seed: (empty)
  ├─ /tmp/test_stage1_delegation.s compiles without bootstrap mention
  └─ Conclusion: MARKER ONLY

Action:
  [✅] Do NOT modify compiler
  [✅] Modify gate condition instead
  [✅] Change "no-delegation=FAIL" to accept embedded markers
  [✅] Result: canonical-source-compilation=PROVEN
```

### Outcome B: Real Runtime Delegation 🔴

```
Diagnostics show:
  ├─ strings bin/s_modular-stage1: 5+ bootstrap_subset occurrences
  ├─ nm bin/s_modular-stage1: bootstrap_subset_* symbols present
  ├─ grep src/cmd/compile/**/*.s: multiple real code references
  ├─ ldd bin/s_modular-stage1: links to s_seed
  ├─ /tmp/test_stage1_delegation.s fails with "bootstrap_subset: unsupported"
  └─ Trace shows main → driver → parser → bootstrap_subset call

Action:
  [🔴] Real delegation exists
  [🔴] Must trace exact call site
  [🔴] Check if parser delegates to bootstrap OR if canonical parser is incomplete
  [🔴] Modify compiler to use canonical parser
  [🔴] Result: retry canonical-source-compilation
```

### Outcome C: Unexpected (No Reference At All)

```
Diagnostics show:
  ├─ strings bin/s_modular-stage1 | grep bootstrap: (empty)
  ├─ no reference anywhere
  └─ Stage1 doesn't mention bootstrap_subset at all

Possible causes:
  - Stage1 wasn't built with bootstrap_subset code
  - Bootstrap code was dead-code eliminated
  - Stage1 is using something else entirely

Action:
  [❓] Investigate gate logic
  [❓] Why did gate report "no-delegation=FAIL" if there's nothing to delegate to?
  [❓] Check if gate is checking the right binary
```

---

## Diagnostic Checklist

```
[ ] Step 0: Verify Stage1 exists and runs
    bin/s_modular-stage1 --help: __________

[ ] Step 1: Search for "bootstrap-subset" in binary
    strings count: ______ (1-2=marker, 5+=delegation)
    nm references: __________
    
[ ] Step 2: Check source code references
    grep count: ______ (0=good, 5+=problem)
    Actual references: __________
    
[ ] Step 3: Trace runtime behavior
    nm -D result: __________
    ldd result: __________
    
[ ] Step 4: Examine makefile linking
    s_modular-stage1 rule: __________
    Bootstrap objects linked? YES / NO
    
[ ] Step 5: Behavioral test
    /tmp/test_stage1_delegation.s compiles? YES / NO
    Error mentions bootstrap? YES / NO
    Exit code: ____
    
[ ] Step 6: Source code walkthrough (if delegation found)
    First bootstrap call site: __________
    In canonical path? __________

DIAGNOSIS RESULT:
  ☐ A. Embedded marker only → modify gate ✅
  ☐ B. Real delegation → trace and fix 🔴
  ☐ C. Unexpected → investigate gate 🤔
```

---

## How to Use This Diagnostic

### Quick Version (5 minutes)

```bash
# Just run these three commands:
strings bin/s_modular-stage1 | grep -i bootstrap | wc -l
nm bin/s_modular-stage1 | grep -i bootstrap
grep -r "bootstrap" src/cmd/compile/ | grep -v ".git" | wc -l

# If all three show <3 matches → Outcome A (marker only)
# If any show >5 matches → Outcome B (real delegation)
```

### Full Version (30 minutes)

Run all 6 steps in sequence, record results, determine outcome.

### With Tracing (1-2 hours)

If Outcome B, add strace/gdb to trace actual function calls during compilation.

---

## Important: Do NOT Skip This

This is the critical blocker between:
- **Current**: `canonical-source-compilation=NOT_PROVEN` (multi-compiler system)
- **Next**: `canonical-source-compilation=PROVEN` (single canonical authority)

Until this is proven, S is still operating as:
```
bootstrap_subset + s_seed + canonical compiler = three semantic implementations
(risk of divergence, no authority)
```

Once proven:
```
canonical compiler = one authority
bootstrap_subset = discarded (frozen)
s_seed = frozen (only bootstrap)
(single source of truth)
```

This diagnostic determines which you're actually in.

---

## After This Diagnostic

Once diagnosis is complete (A, B, or C):

```
If A (Marker): 
  modify gate condition
  → canonical-source-compilation=PROVEN
  → P0 COMPLETE ✅
  → Move to P1 (Stage1 → Stage2)

If B (Real delegation):
  trace call site
  → cut delegation edge
  → retry canonical-source-compilation
  → then P0 COMPLETE ✅
  → Move to P1 (Stage1 → Stage2)

If C (Unexpected):
  investigate gate
  → verify testing infrastructure
  → understand what gate is actually testing
  → then repeat A or B
```

**Key principle**: Do not modify bootstrap_subset.c. Answer the diagnostic first. Gate conditions might need fixing instead.

---

**Next Step**: Run Steps 0-2 (quick version), report results, determine outcome path.
