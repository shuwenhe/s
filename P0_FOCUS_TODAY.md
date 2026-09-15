# P0 Focus: Stage1 Delegation Authority - Action Plan

**Date**: 2026-09-15  
**Commit**: 6f727898  
**Single Focus**: Answer whether `no-delegation=FAIL` is justified or gate condition is wrong

---

## Current State

```
✅ stage0-identity=PASS
✅ stage0-authority=PASS
✅ closure-authority=PASS
✅ stage1-provenance=PASS
✅ canonical-syntax-probe=PASS
✅ canonical-syntax-probe-exit=7

🔴 no-delegation=FAIL         ← why?
🔴 canonical-source-compilation=NOT_PROVEN
```

**Why is this blocker?**
```
Because current gate assumes ANY occurrence of "bootstrap-subset" in binary = failure

But this might be wrong:
  - If it's only embedded marker (version string, build info) → gate condition too strong
  - If it's real delegation → gate is correct, compiler has bug
  
Until we know which, we can't proceed.
```

---

## The One Question To Answer

```
┌─────────────────────────────────────────────────────────────┐
│ Does Stage1 runtime/semantic DELEGATE to bootstrap_subset? │
└─────────────────────────────────────────────────────────────┘

Answer options:
  A. NO, it's only an embedded marker (version string, etc)
     → Modify gate, NOT compiler
     → Result: canonical-source-compilation=PROVEN ✅
  
  B. YES, Stage1 really calls bootstrap_subset functions
     → Fix delegation in compiler (cut the call edge)
     → Retry test
     → Result: canonical-source-compilation=PROVEN ✅
  
  C. Unclear (both marker AND real calls)
     → Determine which calls are necessary vs removable
     → Fix necessary ones
     → Remove unnecessary ones
     → Result: canonical-source-compilation=PROVEN ✅
```

---

## Today's Work

### Do These (and ONLY these)

```bash
# 1. Quick string search (2 minutes)
cd /Users/feifei/shuwen/s
strings bin/s_modular-stage1 | grep -c "bootstrap"
echo "Count: __?"

# 2. Check makefile (2 minutes)
grep -A 10 "s_modular-stage1:" Makefile
echo "Bootstrap linked? YES/NO"

# 3. Test delegation (5 minutes)
cat > /tmp/test.s << 'EOF'
package main
func main() int { return 42 }
EOF

bin/s_modular-stage1 /tmp/test.s 2>&1 | head -20
echo "Mentions bootstrap-subset? YES/NO"

# 4. Determine outcome (1 minute)
# Combine results above → A, B, or C?
```

### Do NOT Do These (save for later)

```
❌ Modify bootstrap_subset.c
❌ Add new features to bootstrap_subset
❌ Work on generics/mono/ownership/SSA
❌ Refactor canonical compiler structure
❌ Add new gates or measurements
```

**Reason**: Each of these is a separate project. Until we know WHY the gate fails, fixing the compiler is guessing.

---

## Expected Outcomes and Next Step

### If Outcome A (Embedded Marker Only) ✅

```bash
# Result interpretation:
# - strings shows 1-2 "bootstrap" occurrences
# - makefile doesn't link bootstrap objects
# - /tmp/test.s compiles without bootstrap error

Action:
  [ ] 1. Identify what the embedded marker is
        (e.g., version string "bootstrapped from s_seed")
  
  [ ] 2. Modify gate condition
        Change: no-delegation = "bootstrap-subset" not in binary
        To:     no-delegation = bootstrap functions not called at runtime
  
  [ ] 3. Re-run gate
        make canonical-source-compilation-check
  
  [ ] 4. Expected result
        canonical-source-compilation=PROVEN ✅
  
  [ ] 5. Declare P0 COMPLETE
        Freeze bootstrap_subset
        Tag: canonical_authority_v1.0
```

### If Outcome B (Real Delegation) 🔴

```bash
# Result interpretation:
# - strings shows 5+ "bootstrap_subset" occurrences
# - makefile links bootstrap objects
# - /tmp/test.s fails with bootstrap_subset error

Action:
  [ ] 1. Find first delegation edge
        Trace main → driver → dispatch → bootstrap_subset
        Use: grep -n "bootstrap" src/cmd/compile/**/*.s
  
  [ ] 2. Determine reason
        Is it:
        a) Parser incomplete → bootstrap delegates as fallback?
        b) Semantic incomplete → bootstrap delegates?
        c) MIR incomplete → bootstrap delegates?
        Which one?
  
  [ ] 3. Fix canonical compiler
        Implement missing part so delegation is not needed
        (NOT by delegating, but by completing canonical)
  
  [ ] 4. Rebuild Stage1
        make modular-bootstrap
  
  [ ] 5. Re-test
        /tmp/test.s compiles without bootstrap mention
  
  [ ] 6. Re-run gate
        make canonical-source-compilation-check
  
  [ ] 7. Expected result
        canonical-source-compilation=PROVEN ✅
```

### If Outcome C (Mixed)

```bash
# Result interpretation:
# - Some references are markers (version strings)
# - Some references are real (delegation edges)

Action:
  [ ] 1. Separate them
        Which ones are markers? Which are real calls?
  
  [ ] 2. Accept markers in gate
        Modify gate to ignore version strings
  
  [ ] 3. Fix real delegations
        Follow steps in Outcome B for each real edge
  
  [ ] 4. Result: P0 COMPLETE ✅
```

---

## Hypothesis Before Testing

**Most Likely**: Outcome A (Embedded Marker)

**Reasoning**:
- Gate runs canonical-syntax-probe successfully (exit 7)
- This suggests canonical parser CAN parse canonical source
- If real delegation existed, probe would fail earlier
- Bootstrap reference probably just version string or build marker

**If Outcome A confirmed**: Today's work = 15 minutes (diagnostic + gate fix)

**If Outcome B**: More work needed, but scope is clear (trace & fix delegation)

---

## Success Criteria for P0

```
Checklist at end of day:

[ ] Question answered: Does Stage1 delegate to bootstrap_subset?
[ ] Outcome determined: A, B, or C?
[ ] Next action clear: (modify gate) OR (trace & fix compiler)?
[ ] No compiler modifications without knowing reason
[ ] No gate modifications without knowing what they fix

Final result:
[ ] canonical-source-compilation=PROVEN ✅
[ ] (or clear task list if not proven today)
```

---

## Do NOT Cross This Line

```
❌ Do NOT start work on:
  - Generic monomorphization
  - Ownership system
  - MIR optimization
  - SDK toolchain
  - AI-native features

✅ DO stay focused on:
  - Diagnosing stage1-delegation-authority
  - Fixing whatever stage1-delegation-authority reveals
  - Proving canonical-source-compilation

This is THE gate. Everything else depends on it.
Once P0 proven, P1 becomes much clearer.
```

---

## Communication After Testing

Once diagnostic complete:

**To Report**:
```
Stage1 Delegation Authority Diagnostic Result:

Outcome: A / B / C
  Details: ________
  
Action Required:
  [ ] Modify gate condition
  [ ] OR: Fix compiler delegation
  [ ] OR: Both (mixed case)
  
Expected Timeline:
  _______ hours to implement
  
P0 Status:
  ✅ PROVEN (canonical-source-compilation ready)
  OR
  🔄 IN PROGRESS (next steps defined)
  OR
  🔴 BLOCKED (unforeseen issue, needs review)
```

---

**Bottom Line**: Run diagnostic today. Answer the one question. Then either fix gate or fix compiler. Everything else waits.

This is not "do this instead of generics". This is "do this BEFORE generics". It's the prerequisite.

Once P0=PROVEN, P1 and beyond become possible without architectural confusion.
