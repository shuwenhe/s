// ref_liveness_integration_roadmap.s
//
// Reference Local Liveness - Integration Roadmap
// Phase 1A → 1B → Real MIR
//

/*

## Phase 1A: Semantic Validation (CURRENT - COMPLETE)
✅ Test semantics locked (6 cases)
✅ Hardcoded results verified
✅ CFG models built (simplified)
✅ Backward liveness algorithm designed
✅ Commit: 00a8077c2

Current State:
- Tests: 6/6 GREEN (hardcoded)
- Analyzer: ref_liveness_analyzer.s ready (not integrated)
- MIR Integration: NOT STARTED

Tests:
1. straight_last_use     → ALLOW
2. same_place_still_live → CONFLICT  
3. branch_all_paths_dead → ALLOW
4. branch_live_after_join → CONFLICT
5. loop_backedge         → CONFLICT
6. disjoint_place        → ALLOW

## Phase 1B: Real Analyzer Integration (NEXT)

### 1B.1: CFG from Simplified Model
Replace hardcoded bash results with S program calling ref_liveness_analyzer.s

Tasks:
- ✅ ref_liveness_analyzer.s: CFG builders for all 6 tests
- ✅ ref_liveness_analyzer.s: compute_liveness() backward dataflow
- ✅ ref_liveness_analyzer.s: validate_test*() result checking
- [ ] ref_liveness_test_driver.s: S program driver
- [ ] check-mir-ref-liveness.sh: call S driver instead of bash hardcode
- [ ] Integration: test via make mir-ref-liveness-check

Verification Gate:
```
make mir-ref-liveness-check
  ↓ (runs S driver)
  ↓ (calls real analyzer)
  ↓ (no more hardcoded ALLOW/CONFLICT)
  ↓
6/6 GREEN (by computation, not hardcode)
```

### 1B.2: Point-Level Liveness (within single block)

Current implementation: Block-level liveness only
Problem: Cannot distinguish last-use within a block

Example (test 1):
```
block0:
  r := &mut x      // def r
  use(r)           // use r  (LAST USE)
  r2 := &mut x     // def r2
  
With block-level: r is live throughout block (cannot reborrow at r2)
With statement-level: r is dead at r2 (can reborrow)
```

Solution:
1. Extend cfg_block to include statement-level use/def lists
2. Implement intra-block backward liveness after block-level analysis
3. Compute live_before/live_after for each statement
4. Result: point_liveness[block_id][stmt_idx]

### 1B.3: Real MIR Input

Tasks:
- Extract reference locals from MIR types
- Identify borrow/use points in MIR instructions
- Build real CFG from MIR basic blocks
- Run liveness analysis on real CFG
- Integrate with existing place borrow checking

MIR Pipeline:
```
S source code
    ↓
compile to MIR
    ↓
extract ref-local use/def
    ↓
build CFG
    ↓
backward liveness
    ↓
point-level live_in/live_out
    ↓
map to place overlap checking
    ↓
loan active?
    ↓
ALLOW/CONFLICT
```

## Current Code Structure

src/cmd/compile/internal/ownership/
├─ reference_local_liveness.s         (Phase 1A: data structures)
├─ ref_liveness_prototype.s           (Phase 1A: simplified models)
├─ ref_liveness_analyzer.s            (Phase 1B: real analyzer logic)
├─ ref_liveness_validation.s          (Phase 1B: validation helpers)
├─ ref_liveness_test_driver.s         (Phase 1B: S program driver)
└─ (future: mir_ref_liveness_pass.s)  (Phase 1B.3: MIR integration)

test/mir_ref_liveness/
├─ README.md                          (semantic documentation)
├─ test_cases.s                       (6 S test functions)
├─ expected.s                         (expected results)
└─ (temp outputs)

misc/scripts/
└─ check-mir-ref-liveness.sh          (test driver script)

makefile
└─ mir-ref-liveness-check target

## Acceptance Criteria

✅ Phase 1A Complete:
- Semantics locked
- Test framework red→green
- Documentation clear

⏳ Phase 1B In Progress:
- [ ] Analyzer integrated (S program → no hardcode)
- [ ] 6/6 tests GREEN by computation
- [ ] Point-level liveness for same-block cases
- [ ] Documentation updated

Phase 1 Complete When:
```
make mir-ref-liveness-check PASS
  AND
make ownership-check PASS (no regressions)
  AND
All hardcoded results removed
  AND
Real liveness analysis producing results
```

Then: Phase 2 (Loan Liveness / NLL)
*/
