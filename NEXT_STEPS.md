# Next Steps for Completing S Compiler Self-Hosting

## Current Status

**✅ Stage 1**: Complete (seed → stage1 in ~30 minutes)
**⏳ Stage 2**: Blocked by performance (semantic analysis O(n*m) complexity)
**❌ Stage 3**: Not reached

## Immediate Next Steps (Pick One)

### Option A: Performance Optimization (RECOMMENDED - 2-4 hours work)

This is the fastest path to completion for this session.

**Goal**: Reduce Stage 2 from 12+ hours to 1-2 hours by optimizing type lookup

**Changes Required**:

1. **File**: `src/cmd/compile/internal/semantic/semantic.s` (line 3667)
   
   Current function (slow - linear search):
   ```s
   func lookup_name_type(type_binding[] env, string name) string {
       i := std.prelude.len(env)
       for i > 0 {
           i = i - 1
           if env[i].name == name {
               return env[i].type_name
           }
       }
       "unknown"
   }
   ```

   **Solution Options**:
   
   Option A1: Early termination optimization (quick win)
   - Build reverse index during scope entry
   - Cache last N lookups
   - Estimated speedup: 2-3x
   - Estimated effort: 1 hour
   
   Option A2: Hash map replacement (best solution)
   - Replace linear array search with hash map
   - May require type_binding struct changes
   - Estimated speedup: 10-50x
   - Estimated effort: 2-4 hours
   
   Option A3: Lazy index building
   - Build lookup index on first use of scope
   - Cache indices across lookups
   - Estimated speedup: 5-10x
   - Estimated effort: 1-2 hours

2. **Testing**: Run with extended timeout and S_CANONICAL_TRACE=1
   ```bash
   cd /app/shuwen/s
   rm -rf .bootstrap/native-imports
   timeout 7200 make native-bootstrap-imports  # 2 hour timeout for testing
   ```

3. **Verification**: Once Stage 2 completes:
   ```bash
   ls -lh .bootstrap/native-imports/stage2.sasm  # Should exist and be large (>100KB)
   ```

**Timeline**:
- 1-2 hours: Implement optimization
- 1-2 hours: Test and debug
- 1-2 hours: Run to completion
- **Total: 3-6 hours for full completion**

### Option B: Extended Runtime (NOT RECOMMENDED - 12-18 hours)

**Approach**: Let current bootstrap run for 12-18 hours without changes

**Pros**: No code changes needed
**Cons**: 
- Very expensive in time
- Not suitable for CI/CD
- Machine/process management overhead
- Risk of timeout or interruption

**Only use if optimization is not feasible**

### Option C: Modular Compilation (MEDIUM-TERM - 8-16 hours work)

This is the best long-term solution but requires more work.

**Goal**: Compile each package separately instead of mega-file

**Changes Required**:
1. Modify `src/cmd/compile/internal/compiler/main.s` handle_compile_unit function
2. Create per-package compilation wrapper
3. Implement linking step in bootstrap script
4. Update `src/cmd/dist/native-bootstrap-no-manifest.sh`

**Benefits**:
- Enables parallel compilation
- Dramatically reduces memory usage
- Reduces environment depth (smaller scopes per package)
- Scales better for larger codebases
- Better for CI/CD

**Timeline**:
- 2-4 hours: Design and planning
- 4-8 hours: Implementation
- 2-4 hours: Testing and debugging
- **Total: 8-16 hours development, then much faster runtimes**

## What Happens After Stage 2 Completes

Once `stage2.sasm` is generated:

1. **Emit stage2 binary**:
   ```bash
   /app/shuwen/s/.bootstrap/native-imports/stage1 \
     --emit-bin /app/shuwen/s/.bootstrap/native-imports/stage2.sasm \
     /app/shuwen/s/.bootstrap/native-imports/stage2
   ```

2. **Stage 2 verification** (should be fast):
   ```bash
   bash /app/shuwen/s/misc/scripts/verify_true_selfhost.sh \
     /app/shuwen/s/.bootstrap/native-imports/stage2
   ```

3. **Compile stage3** (should be faster than stage2):
   ```bash
   /app/shuwen/s/.bootstrap/native-imports/stage2 --compile-unit \
     /app/shuwen/s/.bootstrap/native-imports/stage3.sasm \
     [all source files]
   ```

4. **Convergence check**:
   ```bash
   cmp -s stage2.sasm stage3.sasm  # Should be identical
   cmp -s stage2 stage3            # Should be identical
   ```

5. **Declare success**: When stage2 == stage3 in both assembly and binary, self-hosting is complete!

## Key Files for Optimization Work

- `src/cmd/compile/internal/semantic/semantic.s` - lookup_name_type() function
- `src/cmd/compile/internal/mono/canonical_annotation.s` - annotation phase
- `src/cmd/compile/internal/compiler/main.s` - handle_compile_unit()
- `src/cmd/dist/native-bootstrap-no-manifest.sh` - bootstrap orchestration

## Monitoring Progress

### Check if stage2 is making progress
```bash
# Watch log file size growth
watch -n 10 'wc -l /app/shuwen/s/.bootstrap/native-imports/stage2-compile.log'
```

### Check with tracing enabled
```bash
S_CANONICAL_TRACE=1 timeout 3600 make native-bootstrap-imports 2>&1 | tee bootstrap.log
# Look for "canonical: annotating ..." lines
```

### Check memory usage
```bash
ps aux | grep stage1 | grep compile-unit
# Look at RSS (resident set size) column
```

## Warning Signs

- **Log file not growing**: stage1 is stuck before output
- **Log file growth stalls**: stuck on a particular file or function
- **Memory growing without bound**: possible memory leak
- **CPU at 0%**: likely deadlocked or waiting for I/O

## Success Criteria

1. ✅ `stage2.sasm` file created (>100KB)
2. ✅ `stage2` binary created (>6MB) 
3. ✅ `stage3.sasm` file created and matches stage2.sasm
4. ✅ `stage3` binary created and matches stage2
5. ✅ Both binaries pass verification checks

## Rollback Plan

If optimization introduces bugs:

```bash
cd /app/shuwen/s
git log --oneline | head -5              # Find last good commit
git reset --hard <commit-hash>
make clean && rm -rf .bootstrap/native-imports
make native-bootstrap-imports            # Retry with original code
```

## Support Files

- `BOOTSTRAP_STATUS.md` - Initial status analysis
- `BOOTSTRAP_FINAL_REPORT.md` - Comprehensive technical analysis
- `NEXT_STEPS.md` - This file

All analysis and findings documented for future reference.

---

**Recommendation**: Start with Option A (Performance Optimization). It's the fastest path to completion with minimal risk and clear implementation path.

Expected timeline with Option A: 3-6 hours total for complete self-hosting.
