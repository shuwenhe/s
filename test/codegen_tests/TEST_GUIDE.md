# Native Code Generation Test Suite

## 📋 Test Overview

This directory contains validation tests for the direct machine code generation system in the S compiler.

### Test Structure

```
test_native.s              - Unit tests for codegen modules
test_programs/
  ├── arithmetic.s         - Simple 1+2 calculation
  ├── function_call.s      - Basic function calls
  ├── nested_calls.s       - Multiple function calls
  ├── loop.s               - For loop with accumulation
  └── recursive.s          - Recursive Fibonacci
```

---

## 🚀 Running Tests

### Phase 1: Unit Tests (Module Level)

```bash
# Compile unit tests
cd /home/shuwen/shuwen/s/src/cmd/compile/seed/codegen
s_seed test_native.s -o test_native.ir
s_ir_runner test_native.ir

# Expected output:
# [TEST SUMMARY] PASS
#   Passed: 9
#   Failed: 0
#   Total:  9
```

**Test Cases**:
1. ✅ `test_codegen_emit_line` - Verify assembly line emission
2. ✅ `test_register_allocate` - Register allocation correctness
3. ✅ `test_register_spillover` - Spillover to stack
4. ✅ `test_stackframe_allocate` - Stack frame management
5. ✅ `test_stackframe_size` - Frame size calculation
6. ✅ `test_instruction_select_mov` - MOV instruction generation
7. ✅ `test_instruction_select_add` - ADD instruction generation
8. ✅ `test_codegen_context_init` - Context initialization
9. ✅ `test_multiple_functions` - Multiple function handling

---

### Phase 2: Functional Tests (Compilation Level)

#### Test 2a: IR Method (Current - Baseline)

```bash
cd /home/shuwen/shuwen/s/test/codegen_tests/test_programs

# Compile with IR (default, baseline)
s_seed arithmetic.s -o arithmetic.ir
result_ir=$(s_ir_runner arithmetic.ir)

s_seed function_call.s -o function_call.ir
result_ir_func=$(s_ir_runner function_call.ir)

s_seed loop.s -o loop.ir
result_ir_loop=$(s_ir_runner loop.ir)

echo "IR Results:"
echo "  arithmetic.s: $result_ir (expected: 3)"
echo "  function_call.s: $result_ir_func (expected: 8)"
echo "  loop.s: $result_ir_loop (expected: 45)"
```

#### Test 2b: Native Method (New - Comparison)

```bash
cd /home/shuwen/shuwen/s/test/codegen_tests/test_programs

# Compile with --native (new system)
s_seed arithmetic.s -o arithmetic_native --native
./arithmetic_native
result_native=$?

s_seed function_call.s -o function_call_native --native
./function_call_native
result_native_func=$?

s_seed loop.s -o loop_native --native
./loop_native
result_native_loop=$?

echo "Native Results:"
echo "  arithmetic_native: $result_native (expected: 3)"
echo "  function_call_native: $result_native_func (expected: 8)"
echo "  loop_native: $result_native_loop (expected: 45)"
```

---

### Phase 3: Correctness Validation

**Validation Script** (validate.sh):

```bash
#!/bin/bash
set -e

cd /home/shuwen/shuwen/s/test/codegen_tests/test_programs

PASS=0
FAIL=0

test_program() {
    local prog=$1
    local expected=$2
    
    echo "Testing $prog..."
    
    # Compile with IR
    s_seed "$prog.s" -o "$prog.ir"
    ir_result=$(s_ir_runner "$prog.ir")
    
    # Compile with native
    s_seed "$prog.s" -o "$prog" --native
    native_result=$(./"$prog")
    
    if [ "$ir_result" == "$native_result" ] && [ "$ir_result" == "$expected" ]; then
        echo "  ✅ PASS: Both methods returned $ir_result"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: IR=$ir_result, Native=$native_result, Expected=$expected"
        FAIL=$((FAIL + 1))
    fi
    
    # Cleanup
    rm -f "$prog.ir" "$prog"
}

# Run tests
test_program "arithmetic" "3"
test_program "function_call" "8"
test_program "nested_calls" "60"
test_program "loop" "45"
# Note: recursive.s (fib) may take longer, test separately

echo ""
echo "[SUMMARY] Passed: $PASS, Failed: $FAIL"
exit $FAIL
```

**Run validation**:
```bash
chmod +x validate.sh
./validate.sh
```

---

### Phase 4: Performance Benchmarking

#### Benchmark: Simple Loop (10M iterations)

```bash
# Create benchmark program
cat > benchmark_loop.s << 'EOF'
package main

func benchmark() int {
    int sum = 0
    int i = 0
    for i < 10000000 {
        sum = sum + i
        i = i + 1
    }
    sum
}

func main() int {
    benchmark()
}
EOF

# Test 1: IR Method (baseline)
echo "IR Method Benchmark:"
time s_seed benchmark_loop.s -o benchmark_loop.ir
time s_ir_runner benchmark_loop.ir
# Expected: ~900ms

# Test 2: Native Method (optimized)
echo "Native Method Benchmark:"
time s_seed benchmark_loop.s -o benchmark_loop --native
time ./benchmark_loop
# Expected: ~50ms

# Speedup = 900ms / 50ms = 18x
```

---

## 📊 Expected Results

### Unit Tests
```
[TEST SUMMARY] PASS
  Passed: 9/9
  Failed: 0/9
```

### Functional Tests
```
Arithmetic:
  IR: 3
  Native: 3
  Status: ✅ PASS

Function Call:
  IR: 8
  Native: 8
  Status: ✅ PASS

Nested Calls:
  IR: 60
  Native: 60
  Status: ✅ PASS

Loop:
  IR: 45
  Native: 45
  Status: ✅ PASS
```

### Performance
```
Benchmark (10M iterations):
  IR Method:     ~900ms
  Native Method: ~50ms
  Speedup:       18x ✅
  Target:        16x ✅
```

---

## 🔍 Debugging

### If Unit Tests Fail

```bash
# Verbose mode
S_CODEGEN_VERBOSE=1 s_ir_runner test_native.ir

# Check individual module
# Edit test_native.s to test one function at a time
# Then recompile and run
```

### If Compilation Fails

```bash
# Check if codegen modules are correctly compiled
ls -la /home/shuwen/shuwen/s/src/cmd/compile/seed/codegen/

# Verify S syntax
s_seed codegen.s --check-syntax

# Generate verbose assembly
S_VERBOSE_ASM=1 s_seed arithmetic.s --native -o arithmetic_verbose.s
cat arithmetic_verbose.s  # View generated assembly
```

### If Execution Fails

```bash
# Check generated assembly quality
objdump -d arithmetic_native | head -20

# Run with gdb (if available)
gdb ./arithmetic_native
(gdb) run
(gdb) backtrace

# Check system compatibility
uname -m  # Should be x86_64
ldd ./arithmetic_native  # Check dependencies
```

---

## 📈 Progressive Testing Strategy

```
Week 1:
  Day 1: Unit tests pass ✅
  Day 2: arithmetic.s & function_call.s work
  Day 3: Nested calls and loops working

Week 2:
  Day 1: Recursive functions (Fibonacci)
  Day 2: Full program suite passes
  Day 3: Performance targets achieved

Week 3:
  Day 1: Complex real programs
  Day 2: Edge cases and error handling
  Day 3: Production readiness validation
```

---

## ✅ Acceptance Criteria

- [ ] All 9 unit tests pass
- [ ] arithmetic.s returns 3
- [ ] function_call.s returns 8
- [ ] nested_calls.s returns 60
- [ ] loop.s returns 45
- [ ] recursive.s (Fibonacci) matches IR result
- [ ] Performance: Native ≥ 10x faster than IR
- [ ] No memory leaks (valgrind clean)
- [ ] Assembly output validated manually

---

## 🎯 Next Steps After Passing Tests

1. **Integrate into Compiler** → Add --native flag to main.s
2. **Extended Testing** → Run full test suite with --native
3. **Performance Optimization** → Profile and optimize hot paths
4. **Documentation** → Update user guides and compiler manual
5. **Production Release** → Mark --native as stable

---

## 📚 References

- [NATIVE_IMPLEMENTATION_GUIDE.md](./NATIVE_IMPLEMENTATION_GUIDE.md) - Implementation roadmap
- [ARCHITECTURE_COMPARISON.md](./ARCHITECTURE_COMPARISON.md) - Architecture details
- [DIRECT_CODEGEN_PLAN.md](./DIRECT_CODEGEN_PLAN.md) - Detailed design

---

**Status**: Test suite created, ready to execute  
**Target Completion**: Week 1 (3 days)
