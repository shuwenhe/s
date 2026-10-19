# S Compiler Current Status — 2026-10-19

**Authority**: Actual development progress, not historical audits  
**Last Updated**: 2026-10-19 11:00 UTC  
**Status**: 🟡 **PARSER REFINEMENT IN PROGRESS**

---

## Executive Summary

| Item | Status | Details |
|------|--------|---------|
| **Source Closure** | ✅ FUNCTIONAL | 320 files, 40-42 seconds, acceptable |
| **Seed Compiler** | ✅ FROZEN | bin/s_seed (C implementation) |
| **Current Phase** | 🚧 M2 (Parser) | M2.4 completed, M2.6 in progress |
| **Current FIRST RED** | 🔴 ACTIVE | `compiler_integration.s:31`, struct literal |
| **Stage1 Generation** | ⏳ PENDING | Blocked until FIRST RED fixed |

---

## M2 Parser Progress (Real Data)

### Completed
- ✅ **M2.4**: Consecutive `as` declaration parsing fixed
- ✅ **M2.5**: (Unknown content, likely follow-up fixes)

### Current Work
- 🚧 **M2.6**: Struct literal pointer field recognition
  - **Error Location**: `compiler_integration.s:31`
  - **Pattern**: `elf_gen* elf_gen` (pointer field in struct literal)
  - **Root Cause**: `looks_like_struct_literal()` incorrectly rejects valid pointer fields
  - **Action**: Refactor literal recognition logic to allow pointer fields
  - **Blocking**: Stage1 IR/ELF generation

---

## Immediate Priority (P0)

### Task: Fix M2.6 - Struct Literal Pointer Fields

**Location**: `src/cmd/compile/internal/compiler/` (parser implementation)

**Input**:
```s
elf_gen* elf_gen  // pointer field in struct literal
```

**Expected Output**:
- ✅ Parsed as valid struct literal field
- ✅ No "expected TOKEN_X" error
- ✅ Passes regression test
- ✅ Unblocks Stage1 IR generation

**Time Estimate**: 2-4 hours  
**Risk Level**: LOW (isolated Parser bug)  
**Impact**: CRITICAL (gates Stage1)

---

## Secondary Priorities

### P1: Parser Diagnostics Improvement

**Tasks**:
- Add Token cursor/position tracking
- Include source line:column in error messages
- Provide Parser call stack context
- Reduce future FIRST RED diagnosis time

**Time Estimate**: 2-4 hours  
**Dependency**: After P0 (use improved Parser)

### P2: Source Closure Performance Optimization (Optional)

**Prerequisites**:
- ✅ Establish baseline: current 40-42s closure (hash/content frozen)
- ✅ P0 + P1 complete (Stage1 generated)

**Approach**:
1. Apply optimization proposals (xargs batch, awk dedup, caching)
2. Verify consistency (files, order, hashes match)
3. Measure runtime improvement
4. Accept only if <10s and verified identical

**Not Urgent**: Current 40-42s is acceptable  
**Time Estimate**: 4-6 hours (if attempted)

### P3: Stage1→Stage2→Stage3 Convergence

**Prerequisites**:
- ✅ P0 complete (Stage1 IR/ELF generation)
- ✅ P1 optional (but helpful)

**Tasks**:
- Verify Stage1 IR generation
- Test Stage1 ELF executability
- Compile Stage1 → Stage2
- Verify behavioral equivalence
- Check reproducibility

**Time Estimate**: 8-12 hours  
**Milestone**: True bootstrap convergence

---

## Correct Order (Non-negotiable)

```
P0: M2.6 Parser fix
  ├─ Fix struct literal
  ├─ Regression test
  └─ Stage1 IR/ELF generation
        ↓
P1: Parser diagnostics (optional, can run in parallel with P2)
        ↓
P2: M0 performance optimization (only if time permits, low priority)
        ↓
P3: Stage1→Stage2→Stage3 convergence
```

**Critical**: Do NOT start P2 before P0 completes.

---

## What Changed Since M0 Audit Report

| Assumption in Audit | Actual Reality | Gap |
|-------------------|-----------------|-----|
| **Performance bottleneck**: 137x speedup needed | 40-42s closure acceptable (<60s budget) | Audit was over-optimistic |
| **Current FIRST RED**: `bc*` name conflict | `compiler_integration.s:31`, struct literal | Audit guessed wrong |
| **Current phase**: M0 Performance | M2.4/M2.5/M2.6 Parser refinement | 5+ days ahead |
| **Optimization approach**: 4 shell fixes | Already working Parser, need refinement | Different problem |

**Key Lesson**: Actual error discovery beats theoretical performance optimization.

---

## Do Not

❌ Start M0 large-scale refactoring  
❌ Run M0 benchmark suite before P0  
❌ Plan P2 performance work now  
❌ Abandon Parser work for performance chasing  
❌ Consider M0 audit as authoritative status  

---

## Do

✅ Continue M2.6 Parser fix  
✅ Create comprehensive regression test  
✅ Document FIRST RED diagnosis method  
✅ Prepare P1 diagnostics enhancements  
✅ Track actual Stage1 generation time  
✅ Use M0 audit only as reference material  

---

## Next Checkpoint

**Criterion**: Stage1 IR and ELF successfully generated from 320-file closure

**Blockers**:
- M2.6: `looks_like_struct_literal()` fix
- Regression: Test coverage for pointer fields
- Integration: Seed backend consumes IR correctly

**Timeline**: After P0 completion (estimated 2-4 hours away)

---

## References

- **Current FIRST RED**: compiler_integration.s:31, struct literal
- **Audit (Historical)**: `doc/audit/M0_AUDIT_REPORT.md` (reference only)
- **Status Correction**: `doc/audit/M0-STATUS-CORRECTION.md`
- **Parser Implementation**: `src/cmd/compile/internal/compiler/`
- **Test Suite**: `test/` (for regression validation)

---

**Authority**: Real development progress  
**Confidence**: HIGH (based on actual commits + known FIRST RED)  
**Actionability**: IMMEDIATE (P0 task clear and scoped)  
**Validity Period**: Until Stage1 generation succeeds

---

**Final Word**: The M0 audit was a theoretical exercise. Reality has moved forward. Focus on P0. 🎯
