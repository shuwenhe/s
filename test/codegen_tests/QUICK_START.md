# 🎯 Quick Start Checklist - Native Codegen Testing

**Status**: Ready to begin testing phase  
**Time**: ~2-3 hours for complete test suite  
**Difficulty**: Low (automated tests)

---

## ✅ Pre-Flight Check (Do This First)

- [ ] s_seed compiler available in PATH
  ```bash
  which s_seed
  ```

- [ ] s_ir_runner available in PATH
  ```bash
  which s_ir_runner
  ```

- [ ] Test directory accessible
  ```bash
  ls /home/shuwen/shuwen/s/test/codegen_tests/
  ```

- [ ] Test programs exist
  ```bash
  ls /home/shuwen/shuwen/s/test/codegen_tests/test_programs/
  ```

- [ ] gcc and ld available (for native compilation)
  ```bash
  which gcc
  which ld
  ```

**If any check fails**: Review TEST_GUIDE.md section "Debugging"

---

## 🚀 Execute Test Suite (Main Task)

### Command
```bash
cd /home/shuwen/shuwen/s/test/codegen_tests
chmod +x run_tests.sh
./run_tests.sh
```

### Time: ~30-45 minutes

### Expected Output
```
========================================
PHASE 1: Environment Check
========================================
✅ PASS: s_seed compiler found
✅ PASS: s_ir_runner found
✅ PASS: Codegen directory exists
...

========================================
PHASE 2: Unit Tests
========================================
ℹ️ INFO: Compiling test_native.s...
✅ PASS: Compilation successful
ℹ️ INFO: Running unit tests...
✅ PASS: Unit tests passed
  Passed: 9
...

========================================
PHASE 3: IR Method Tests (Baseline)
========================================
ℹ️ INFO: Testing arithmetic.s with IR method...
✅ PASS: arithmetic returned 3 (expected: 3)
...

========================================
PHASE 4: Native Method Tests (New)
========================================
ℹ️ INFO: Testing arithmetic.s with native method...
✅ PASS: arithmetic returned 3 (expected: 3)
...

========================================
PHASE 5: Correctness Validation
========================================
ℹ️ INFO: Comparing IR and native results...
✅ PASS: arithmetic: Both methods agree (result: 3)
...

========================================
PHASE 6: Performance Benchmark
========================================
ℹ️ INFO: Creating benchmark program...
ℹ️ INFO: Benchmarking IR method (1M iterations)...
✅ PASS: IR benchmark: 850ms
ℹ️ INFO: Benchmarking native method (1M iterations)...
✅ PASS: Native benchmark: 50ms
ℹ️ INFO: Speedup: 17.0x
✅ PASS: Performance target achieved (≥10x)

========================================
TEST SUMMARY
========================================
Passed:  45
Failed:  0
Skipped: 0
Total:   45

✅ ALL TESTS PASSED!
```

---

## 📊 Success Metrics

### All tests should show:
- [x] Green checkmarks (✅)
- [x] No red X marks (❌)
- [x] Passed count = ~45
- [x] Failed count = 0
- [x] Speedup = 10x or higher

### Specific Target Results:
- Unit tests: **9/9 PASS**
- arithmetic.s: **3** (both methods)
- function_call.s: **8** (both methods)
- nested_calls.s: **60** (both methods)
- loop.s: **45** (both methods)
- Performance: **≥10x faster** (native vs IR)

---

## ❌ If Tests Fail

### Common Issues & Quick Fixes

#### Issue: "s_seed compiler not found"
```bash
# Solution 1: Add to PATH
export PATH="/home/shuwen/shuwen/s/bin:$PATH"

# Solution 2: Use full path
/home/shuwen/shuwen/s/src/cmd/compile/seed/s_seed test.s
```

#### Issue: "s_ir_runner not found"
```bash
# Same solution as above
which s_ir_runner
```

#### Issue: "Test program compilation failed"
```bash
# Check syntax
s_seed arithmetic.s --check-syntax

# Manual compile
s_seed arithmetic.s -o arithmetic.ir
```

#### Issue: "Speedup is only 2x (not 10x+)"
- Expect higher speedup on slower machines
- Benchmark uses 1M iterations (not 10M)
- May improve with optimization passes

#### Issue: "Native method returns wrong result"
1. Check generated assembly
   ```bash
   s_seed arithmetic.s --native -o test --verbose
   ```
2. Compare with IR result
   ```bash
   s_seed arithmetic.s -o test.ir
   s_ir_runner test.ir
   ```
3. Review TEST_GUIDE.md debugging section

#### Issue: "gcc not found"
```bash
# Install build tools
sudo apt-get install build-essential

# Or verify installation
which gcc
gcc --version
```

**For other issues**: See TEST_GUIDE.md "Debugging" section in detail

---

## ✅ Post-Test Actions

### Immediate (After Tests Pass)
- [ ] Note any warnings in output
- [ ] Save test results:
  ```bash
  ./run_tests.sh > test_results_20260831.log 2>&1
  ```
- [ ] Review performance metrics

### Week 1 Summary
- [ ] All unit tests passing
- [ ] All functional tests matching
- [ ] Performance ≥10x achieved
- [ ] Ready for integration phase

### Next Phase: Integration (Week 2)
Proceed to INTEGRATION_GUIDE.md when ready:
1. Modify main.s with --native flag
2. Create router.s module
3. Integration testing
4. Verify backward compatibility

---

## 📚 Reference Documents

During testing, refer to:
- **TEST_GUIDE.md** - Detailed testing procedures
- **EXECUTION_STATUS_REPORT.md** - Overall progress tracking
- **ARCHITECTURE_COMPARISON.md** - Design rationale
- **INTEGRATION_GUIDE.md** - Next steps after testing

---

## ⏱️ Time Estimates

| Phase | Time | Status |
|-------|------|--------|
| Environment check | 5 min | ✅ |
| Unit tests | 5 min | ⏳ |
| IR baseline tests | 10 min | ⏳ |
| Native method tests | 10 min | ⏳ |
| Correctness validation | 10 min | ⏳ |
| Performance benchmark | 10 min | ⏳ |
| **Total** | **~50 min** | ⏳ |

---

## 🎯 Definition of Done

Testing phase is complete when:

```
[ ] ✅ 9/9 unit tests pass
[ ] ✅ 4/4 functional tests match IR results
[ ] ✅ Native method ≥10x faster than IR
[ ] ✅ No compilation errors
[ ] ✅ Proper cleanup of temp files
[ ] ✅ Test results logged
```

---

## 🚀 Start Now

```bash
# 1. Navigate to test directory
cd /home/shuwen/shuwen/s/test/codegen_tests

# 2. Run tests
chmod +x run_tests.sh
./run_tests.sh

# 3. Wait for results (~50 minutes)
# 4. Review output
# 5. Proceed to integration if all pass
```

**Expected**: Complete in 1-2 hours  
**Confidence**: HIGH (95% expected to pass)  
**Next**: Integration phase begins Week 2

---

**Quick Links**:
- Test Guide: [TEST_GUIDE.md](./TEST_GUIDE.md)
- Integration Guide: [INTEGRATION_GUIDE.md](../INTEGRATION_GUIDE.md)
- Full Report: [EXECUTION_STATUS_REPORT.md](../EXECUTION_STATUS_REPORT.md)
- Architecture: [ARCHITECTURE_COMPARISON.md](../ARCHITECTURE_COMPARISON.md)

