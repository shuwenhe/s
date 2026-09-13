# C.3.1b.2-pre A1+A2 Canonicalization Checkpoint

## Current Status: Foundation Ready

```
C.3.1b.2-pre.1    Place audit                              ✅
C.3.1b.2-pre.A1   Projection kind enum                     ✅ COMPLETE
C.3.1b.2-pre.A2   Place base identity audit                ✅ COMPLETE
C.3.1b.2-pre.A3   Structural equality                      ← NEXT
```

---

## A1 Summary: Projection Kind Canonicalization ✅

**What Changed**:
```s
// BEFORE: String dispatch
if projection.kind == "field" { ... }

// AFTER: Type-safe enum dispatch
switch projection.kind {
    mir_projection_kind.field: { ... }
    mir_projection_kind.deref: { ... }
    mir_projection_kind.index: { ... }
}
```

**Impact**:
- 🟢 18/18 A1 gate PASS
- 🟢 All existing gates still pass (C.3.1a, C.3.1b.1)
- 🟢 No breaking changes

---

## A2 Summary: Base Identity Audit ✅

**Discovered**:

```
Current mir_place.root
  Type: string (identifier name)
  Source: mir_place_from_expr() from AST
  Examples: "_1", "x", "obj"

Supported Categories:
  ✓ Local variables
  ? Arguments (string or separate index?)
  ? Return place (separate marker?)
  ? Temporaries (numbering scheme?)
  ✗ Static/Global (not yet)
```

**Key Finding**:
- mir_place.root is currently "local identifier string"
- No separate root type for args/return/temporaries
- Type system integration happens at/after MIR construction

**Design Options (Deferred)**:
1. **Option A**: Keep root as string, improve equality (A3 proceeds)
2. **Option B**: Introduce mir_place_base enum (future optimization)

**Recommendation**: 
- A3 proceeds with string root (low-risk)
- mir_place_base can be introduced in A2.1 if needed

---

## A3 Preview: Structural Equality (NEXT)

**Goal**: Add `mir_place_equal(a, b) → bool` function

**What It Does**:
```s
func mir_place_equal(a mir_place, b mir_place) bool {
    // Pure structural comparison
    // NO string serialization, NO mir_place_key()
    
    if a.root != b.root { return false }
    if len(a.projections) != len(b.projections) { return false }
    
    i := 0
    for i < len(a.projections) {
        if a.projections[i].kind != b.projections[i].kind { return false }
        if a.projections[i].value != b.projections[i].value { return false }
        i = i + 1
    }
    return true
}
```

**Why Canonical**:
- ✓ No string key generation
- ✓ No parsing or reconstruction
- ✓ Direct structural comparison
- ✓ Deterministic, type-safe

**Next Gate**: `mir-place-structural-equality-check.sh`
- Verify mir_place_equal() exists and is pure structural
- No reference to mir_place_key()
- All existing gates still pass

---

## A4 Preview: Structural Prefix (After A3)

**Goal**: Add `mir_place_is_prefix(a, b) → bool` function

**Examples**:
```
Local(1)                    prefix Local(1).Field(0)        true
Local(1).Field(0)           prefix Local(1).Field(0).Field(1) true

Local(1).Field(0)           prefix Local(1).Field(1)        false
Local(1)                    prefix Local(2).Field(0)        false
```

**Next Gate**: `mir-place-structural-prefix-check.sh`

---

## B Series Preview: System Migration (After A1-A4)

Once canonical Place core is solid (A1-A4):
- B1: Borrow system → mir_place migration
- B2: Move system → mir_place migration
- B3: MovePath system → mir_place migration
- B4: Eliminate string paths from ownership/

---

## Commit History

```
ebe37d13c  C.3.1b.2-pre.A1: Canonicalize mir_place_projection.kind to enum
fa57572b5  C.3.1a-b1: add ownership decision model and loan liveness query
```

---

## Ready for A3?

✅ **YES**. Proceed with `mir_place_equal()` implementation.

- Projection kind is canonical (enum)
- Base identity audit complete (can defer mir_place_base decision)
- All existing gates passing
- Low-risk next step

**Action**: User confirms A3 direction?
