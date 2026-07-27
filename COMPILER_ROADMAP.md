# S Compiler Stabilization Roadmap

**Goal:** Make S Seed Compiler production-ready for NeurX Tensor Runtime and Post-Training Pipeline.

**Status:** 🚀 Active - Starting 2026-07-27

**Timeline:** 3-5 days (parallel work on backend & intrinsics)

---

## Executive Summary

The S Seed Compiler (C-based) can parse and generate IR, but three critical gaps block downstream tooling:

| Phase | Issue | Blocker | Impact | Effort |
|-------|-------|---------|--------|--------|
| **1** | Backend IR support | `[]` instruction | All tensor code | 2-4h |
| **2** | Stdlib Intrinsics | `stdout_write` link | All I/O | 4-6h |
| **3** | Dynamic Arrays | Array runtime | Tensor/Dataset | 6-8h |

---

## Phase 1: Standalone Backend Support (Priority 1)

### Issue: Empty Array IR Instruction

**Symptom:**
```
$ s tensor_runtime_test.s -o test.ir
$ s --emit-standalone-amd64 test.ir -o test
error[5] at 0:0: unknown standalone value [] in new_test_suite_s()
```

**Root Cause:**
- IR contains: `MOV|t2.results|[]|_`
- Backend (`standalone_amd64_backend.c`) has no handler for `[]`

**Reproduction:**
```s
// test/compiler/dynamic_array.s
package test
struct my_array {
    []int items
}
func init_array() my_array {
    my_array { items: []int{} }
}
func main() int { 0 }
```

**Fix Location:** `src/cmd/compile/seed/code/standalone_amd64_backend.c`

**Steps:**
1. Locate handler for `MOV` instructions
2. Add case for empty array value `[]`
3. Generate appropriate x86_64 code (likely: `xor r8, r8; mov rax, r8` for null/empty)
4. Recompile seed compiler: `cd s && gcc ... -o bin/s_seed`
5. Test with regression suite

**Success Metric:** `tensor_runtime_test.s` → binary (doesn't need to run yet)

---

## Phase 2: Standard Library Intrinsics (Priority 2)

### Issue 1: Undefined Reference to `stdout_write`

**Symptom:**
```
ld: /tmp/test.o: undefined reference to `s_fn_stdout_write'
```

**Root Cause:**
- Function declared in `src/std/syscall.s`
- But linker can't find implementation
- Should be compiler-generated intrinsic

**Root File:** `src/std/syscall.s`

**Current Code:**
```s
extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int
// ... other syscall wrappers

func stdout_write(string text) int {
    write_to_fd(STDOUT_FD, 0, len(text))  // ← Wrong: passing 0 as pointer
}
```

**Problem:** `write_to_fd` expects a buffer pointer, but passes `0`.

**Fix Approach:**
1. Mark `stdout_write` as compiler builtin (not user-defined)
2. Compiler should inline syscall directly
3. Handle string-to-pointer conversion in code generator

**Alternative (Simpler):** Implement as bridge function:
```s
func stdout_write(string text) int {
    __syscall3(SYS_WRITE, STDOUT_FD, ptr(text), len(text))
}
// Add ptr() builtin if missing
```

**Test Cases:**
```s
// test/compiler/stdout_write.s
use std.syscall.{stdout_write}
func main() int {
    stdout_write("Hello\n")
    0
}

// test/compiler/string_io.s
func main() int {
    stdout_write("Test: ")
    stdout_write("42\n")
    0
}
```

### Issue 2: File I/O Not Implemented

**Symptom:**
```
undefined reference to `s_fn_file_read_string'
```

**Root Cause:**
`src/std/io_syscall.s` has function stubs:
```s
func file_read_string(string path) (string, int) {
    "", 0  // ← Stub! No actual implementation
}
```

**Files to Complete:**
- `src/std/io_syscall.s` (2.4 KB, ~70% complete)
- Functions needed:
  - `file_open_read()` → `FileHandle`
  - `file_open_write()` → `FileHandle`
  - `file_read_string()` → `(string, error)`
  - `file_write_string()` → `error`
  - `file_close()` → `error`

**Implementation Strategy:**
1. Use syscalls: `SYS_OPEN`, `SYS_READ`, `SYS_WRITE`, `SYS_CLOSE`
2. Allocate buffers via `malloc()` for reads
3. Handle errors gracefully
4. Test with safetensors model loading

**Test Case:**
```s
// test/compiler/file_io.s
use std.io_syscall.{file_write_string, file_read_string}
func main() int {
    file_write_string("/tmp/test.txt", "Hello")
    let (content, err) = file_read_string("/tmp/test.txt")
    if err != 0 { return 1 }
    0
}
```

---

## Phase 3: Dynamic Array Runtime (Priority 3)

### Issue: Array Initialization and Operations

**Symptom:**
```
error: unsupported operation on []T
```

**Missing Operations:**
- `[]T{}` → empty array initialization
- `append([]T, item)` → add element
- `[]T{val1, val2, ...}` → literal initialization
- Array slicing: `arr[i:j]`
- Array indexing with bounds checking

**Files to Modify:**
- `src/runtime/memory.h` - Add array allocation helpers
- `src/std/builtins.s` - Add append, make, len, cap

**Implementation Plan:**
```c
// In src/runtime/memory.h
struct array_header {
    int len;
    int cap;
    int element_size;
    void *data;
};

void *alloc_array(int element_size, int capacity) {
    struct array_header *h = malloc(...);
    h->len = 0;
    h->cap = capacity;
    h->element_size = element_size;
    h->data = malloc(capacity * element_size);
    return h->data;  // Return pointer to data, not header
}
```

**Test Cases:**
```s
// test/compiler/arrays_basic.s
func main() int {
    []int arr = []int{}
    arr = append(arr, 42)
    if arr[0] != 42 { return 1 }
    0
}

// test/compiler/arrays_tensors.s
struct tensor {
    []float data
}
func main() int {
    []float data = []float{}
    // Should compile and run
    0
}
```

---

## Regression Test Suite

Create at: `src/test/compiler_fixes/`

```
Makefile                    # Run all tests
├── regression/
│   ├── hello_world.s       # Basic "works at all"
│   ├── empty_array.s       # Phase 1: [] support
│   ├── stdout_write.s      # Phase 2: Intrinsic linking
│   ├── file_io.s           # Phase 2: File operations
│   └── dynamic_array.s     # Phase 3: Array ops
└── tensor_runtime_subset.s # Final integration test
```

**Build and run:**
```sh
make test-compiler-fixes  # Compile all, run checks
```

---

## Verification Milestones

### ✅ Milestone 1: Backend Support
- [ ] `empty_array.s` compiles to IR
- [ ] `empty_array.s` → binary via `--emit-standalone-amd64`
- [ ] Binary executes (exit code 0)
- Effort: 2-4h

### ✅ Milestone 2: Intrinsics
- [ ] `stdout_write.s` compiles and links
- [ ] Output "Hello\n" to stdout
- [ ] `file_io.s` reads/writes files
- Effort: 4-6h

### ✅ Milestone 3: Dynamic Arrays
- [ ] `dynamic_array.s` compiles
- [ ] Can initialize, append, index
- [ ] `tensor_runtime_test.s` compiles to binary
- Effort: 6-8h

### 🎉 Final Success
- [ ] `tensor_runtime_test.s` runs all 80+ tests
- [ ] All tests PASS
- [ ] Regression suite established

---

## Build & Test Workflow

```bash
# Start from s/ project directory
cd /home/shuwen/shuwen/s

# Phase 1: Backend fix
# Edit: src/cmd/compile/seed/code/standalone_amd64_backend.c
gcc -std=c11 -O2 ... -o bin/s_seed  # Recompile
/bin/s_seed test/compiler_fixes/empty_array.s -o /tmp/test.ir
bin/s_seed --emit-standalone-amd64 /tmp/test.ir -o /tmp/test
/tmp/test  # Should run

# Phase 2: Intrinsics
# Edit: src/std/syscall.s + io_syscall.s
# (Recompile seed if needed)
bin/s_seed test/compiler_fixes/stdout_write.s -o /tmp/test.ir
bin/s_seed --emit-standalone-amd64 /tmp/test.ir -o /tmp/test
/tmp/test  # Should print "Hello"

# Phase 3: Arrays + Final Test
# Edit: src/runtime/memory.h + src/std/builtins.s
bin/s_seed test/compiler_fixes/dynamic_array.s -o /tmp/test.ir
bin/s_seed test/compiler_fixes/tensor_runtime_subset.s -o /tmp/tensor.ir
bin/s_seed --emit-standalone-amd64 /tmp/tensor.ir -o /tmp/tensor
/tmp/tensor  # Should run tests
```

---

## Key Insights

1. **Priority is Phase 1 (Backend):** It blocks everything else. Once IR-to-binary works, we can iterate on Intrinsics and Arrays.

2. **Don't touch NeurX yet:** Let it freeze. Once compiler is stable, all NeurX code compiles cleanly.

3. **One small test per fix:** Each phase should have a minimal reproduction case that can be built in 30 seconds.

4. **Regression testing:** Once fixed, maintain test suite to prevent regressions.

---

## Timeline Estimate

| Phase | Est. Time | Start | Complete By |
|-------|-----------|-------|------------|
| 1 (Backend) | 2-4h | 2026-07-27 | 2026-07-27 evening |
| 2 (Intrinsics) | 4-6h | 2026-07-28 | 2026-07-28 evening |
| 3 (Arrays) | 6-8h | 2026-07-29 | 2026-07-30 |
| Regression Suite | 2-3h | Ongoing | 2026-07-30 |
| **Total** | **14-21h** | | **By 2026-07-30** |

---

## Notes

- Work in `src/cmd/compile/seed/` when modifying C code
- Work in `src/std/` when fixing stdlib
- Always recompile seed compiler after C changes: `make seed-compiler-bin`
- Keep NeurX frozen until all three phases complete
- Document each fix in this roadmap
