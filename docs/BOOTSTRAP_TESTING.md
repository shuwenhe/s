# Bootstrap Modernization - Testing Guide

## ✅ Phase 1: Foundation (COMPLETE)

### What Was Done

1. **Created Entry Point Package**
   - `src/cmd/compile/selfhost/main.s` - Central entry point
   - Contains all necessary imports
   - Includes SELFHOST_MAIN marker for extraction

2. **Created Aggregate Packages**
   - `src/cmd/compile/frontend/selfhost/frontend.s` - Frontend aggregator
   - `src/cmd/compile/middlend/selfhost/middlend.s` - Middlend aggregator
   - `src/cmd/compile/backend/selfhost/backend.s` - Backend aggregator
   - Each imports its respective components

3. **Created New Bootstrap Script**
   - `src/cmd/dist/native-bootstrap-no-manifest.sh` - Import-driven bootstrap
   - Supports 3-stage bootstrap with convergence verification
   - Detailed logging and diagnostics

4. **Updated Makefile**
   - Added `make native-bootstrap-imports` target
   - Added `make validate-imports` target
   - Added `make test-bootstrap-both` target
   - Updated help output

5. **Created Documentation**
   - `docs/BOOTSTRAP_MODERNIZATION.md` - Architecture overview
   - This file - Testing guide

### Current Status

```
Import validation: ✓ PASSED
- All aggregate packages have proper import statements
- Entry point has complete import list

Make targets: ✓ READY
- native-bootstrap-imports: Ready to test
- validate-imports: Passing
- test-bootstrap-both: Ready to run
```

---

## 🔬 Phase 2: Validation (NEXT)

### Pre-Flight Checks

```bash
# 1. Verify import statements
$ make validate-imports
✓ Expected: All imports validated

# 2. Check file structure
$ find src/cmd/compile/selfhost -name "*.s" -type f
✓ Expected: main.s, and all components have proper imports

# 3. Verify seed compiler exists
$ ls -l bin/s_seed
✓ Expected: -rwxr-xr-x seed compiler binary
```

### Test Import-Driven Bootstrap

```bash
# Test new bootstrap approach
$ make native-bootstrap-imports

# Expected output:
# === S Compiler Bootstrap (Import-Driven Model) ===
# Source Root: /path/to/s
# Output Dir:  .bootstrap/native-imports
# Target:      linux/amd64
#
# === Stage 1: Bootstrap with Seed Compiler ===
# Compiling self-hosted compiler entry point...
# ✓ Generated IR: .bootstrap/native-imports/stage1.ir
# ✓ Generated Binary: .bootstrap/native-imports/stage1
#
# === Stage 2: Self-Compilation with Stage 1 ===
# ...
# === Stage 3: Convergence Verification ===
# ✓ SUCCESS: Bootstrap converged (stage2 == stage3)
```

### Verify Output

```bash
# Check that bootstrap produced output
$ ls -lh .bootstrap/native-imports/
-rwxr-xr-x stage1      # Stage 1 compiler
-rwxr-xr-x stage2      # Stage 2 compiler
-rwxr-xr-x stage3      # Stage 3 compiler (for verification)
-rw-r--r-- stage1.ir   # Stage 1 IR
-rw-r--r-- stage2.ir   # Stage 2 IR
-rw-r--r-- stage3.ir   # Stage 3 IR
-rw-r--r-- .complete   # Completion marker
```

---

## 🏁 Phase 3: Comparison

### Compare Both Methods

```bash
# This command tests both bootstrap approaches
$ make test-bootstrap-both

# Expected:
# 1. Original (manifest-based):  [runs existing bootstrap]
# 2. New (import-driven):        [runs new bootstrap]
#
# === Comparison ===
# Manifest-based:  .bootstrap/selfhost/native/stage2
# Import-driven:   .bootstrap/native-imports/stage2
# ✓ Both methods produce identical binaries!
```

### Binary Comparison

```bash
# Manual binary comparison
$ cmp .bootstrap/selfhost/native/stage2 .bootstrap/native-imports/stage2
$ echo $?
0  # Exit code 0 = files are identical

# Or with size check
$ ls -l .bootstrap/selfhost/native/stage2 .bootstrap/native-imports/stage2
-rwxr-xr-x ... 188560 ... stage2 (manifest-based)
-rwxr-xr-x ... 188560 ... stage2 (import-driven)
```

---

## 🧪 Phase 4: Integration Testing

### Run Full Test Suite

```bash
# Test with import-driven compiler
$ ./bin/s_seed --compile-unit /tmp/test.ir test_file.s
$ ./bin/s_seed --emit-bin /tmp/test.ir /tmp/test_binary

# Run existing tests
$ make pipeline
$ make native-bootstrap-diagnostic-check
```

### Regression Testing

Check that:
- [ ] All existing tests pass
- [ ] Pipeline checks still pass
- [ ] No performance regression
- [ ] Error messages are meaningful

### Cross-Platform Testing

If possible, test on:
- [ ] Linux x86_64
- [ ] Linux ARM64
- [ ] macOS (if available)

---

## 📋 Troubleshooting

### Issue: Bootstrap script fails on import resolution

```bash
# Check seed compiler options
$ bin/s_seed --help

# Should show options like:
#   --compile-unit   Compile source to IR
#   --emit-bin       Generate binary from IR
#   --source-root    Set source root directory
```

**Solution**: If seed compiler doesn't support necessary options, may need to:
1. Update seed compiler build
2. Add import resolution support to seed compiler
3. Fall back to manifest-based approach during transition

### Issue: Different binaries from both methods

```bash
# Compare IR files instead of binaries
$ cmp .bootstrap/selfhost/native/stage1.ir \
      .bootstrap/native-imports/stage1.ir

# Check logs for differences
$ diff .bootstrap/selfhost/native/stage1-compile.log \
       .bootstrap/native-imports/stage1-compile.log
```

**Possible causes**:
- Different import ordering
- Missing or extra imports
- Seed compiler behaves differently
- Source files have changed

---

## 🎯 Success Criteria

### Phase 2 (Validation)
- [ ] `make validate-imports` passes
- [ ] `make native-bootstrap-imports` completes successfully
- [ ] Output binaries are generated
- [ ] Convergence is verified (stage2 == stage3)

### Phase 3 (Comparison)
- [ ] Both bootstrap methods produce identical binaries
- [ ] `make test-bootstrap-both` completes successfully
- [ ] No performance regression

### Phase 4 (Integration)
- [ ] All existing tests pass
- [ ] Pipeline checks pass
- [ ] Diagnostic checks pass
- [ ] Cross-platform tests pass (if applicable)

### Phase 5 (Migration) - Future
- [ ] Mark old manifest approach as deprecated
- [ ] Update documentation
- [ ] Plan for cleanup

---

## 📊 Performance Metrics

Track these metrics before/after:

```bash
# Build time
$ time make native-bootstrap
$ time make native-bootstrap-imports

# Binary size
$ ls -lh .bootstrap/selfhost/native/stage2
$ ls -lh .bootstrap/native-imports/stage2

# Source file count
$ find src/cmd/compile -name "*.s" | wc -l
```

---

## 🚀 Next Steps

1. **Immediately**
   - Run `make validate-imports` - ✓ PASSED
   - Review created files

2. **This Week**
   - Run `make native-bootstrap-imports`
   - Compare outputs with `make test-bootstrap-both`

3. **After Validation**
   - Run full test suite with new bootstrap
   - Verify no regressions
   - Document findings

4. **After Confirmation**
   - Plan migration timeline
   - Update documentation
   - Deprecate manifest approach
   - Schedule cleanup

---

## 📞 Questions & Debugging

If something doesn't work:

1. Check logs in `.bootstrap/native-imports/`:
   - `stage1-compile.log` - Compilation errors
   - `stage1-emit.log` - Binary generation errors
   - `stage2-compile.log` - Stage 2 compilation
   - `stage3-compile.log` - Convergence check

2. Run validation:
   ```bash
   $ make validate-imports
   $ grep "import" src/cmd/compile/selfhost/main.s
   ```

3. Compare with working approach:
   ```bash
   $ make native-bootstrap
   $ make native-bootstrap-imports
   $ ls -lh .bootstrap/*/native/stage*
   ```

4. Check seed compiler capabilities:
   ```bash
   $ bin/s_seed --help
   ```

Good luck! 🎉
