# Reference Liveness Test Suite

Test cases for CFG-aware backward reference-local liveness analysis.

## Test Cases

### 1. straight_last_use
```
borrow r := &x.left
use(r)              // last use
reborrow r2 := &x.left
```
**Expected**: ALLOW (loan dead after use(r))

### 2. same_place_still_live
```
borrow r := &x.left
reborrow r2 := &x.left   // conflict
use(r)
```
**Expected**: CONFLICT (r still live)

### 3. branch_dead_after_join
```
borrow r := &x.left
if cond {
    use(r)
}
join
reborrow r2 := &x.left
```
**Expected**: ALLOW (union on join = one path doesn't use r, but may-liveness = ⋃, so loan IS live)

Actually, this needs reconsideration. Standard may-liveness: loan is live because one path DOES use r.
Let's reframe: **branch_live_after_join is the critical test**.

### 3b. branch_all_paths_dead
```
borrow r := &x.left
if cond {
    use(r)
} else {
    // no use of r
}
join
reborrow r2 := &x.left
```
**Expected**: CONFLICT (union on join = at least one path uses r, so loan active at join)

### 4. branch_live_after_join
```
borrow r := &x.left
if cond {
    use(r)
}
join
use(r)              // second use AFTER join
reborrow
```
**Expected**: CONFLICT (join point loan still active because of use after)

### 5. loop_backedge
```
borrow r := &x.left
loop {
    use(r)
    cond?
}
exit
reborrow
```
**Expected**: CONFLICT (backedge propagates live to loop header and exit)

### 6. disjoint_place
```
r := &mut x.left
...
reborrow r2 := &mut x.right
```
**Expected**: ALLOW (different places, no overlap)

## Execution
```
make mir-ref-liveness-check
```

Each test: generates MIR → runs reference liveness → checks conflicts
