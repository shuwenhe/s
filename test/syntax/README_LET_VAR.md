# Let/Var Test Suite

This directory contains tests for the immutable (`let`) and mutable (`var`) variable declarations in the S language.

## Test Files

### 1. `let_var_basic.s`
**Purpose**: Basic functionality test for let and var

**Features tested**:
- `let` declaration with type inference
- `var` declaration with type inference  
- Array initialization with both let and var
- Multiple variable declarations

**Expected**: Compilation succeeds ✓

```s
let x = 10
var y = 20
let arr = []int{1, 2, 3}
```

### 2. `let_immutable.s`
**Purpose**: Verify immutability enforcement

**Features tested**:
- Attempting to reassign an immutable variable
- Compiler error detection

**Expected**: Compilation fails with "symbol 'x' is immutable" ✗

```s
let x = 10
x = 20  // ← ERROR: immutable
```

### 3. `var_mutable.s`
**Purpose**: Verify mutability functionality

**Features tested**:
- Reassigning a mutable variable
- Multiple reassignments allowed

**Expected**: Compilation succeeds ✓

```s
var y = 10
y = 20  // ✓ OK
y = 30  // ✓ OK
```

### 4. `let_var_comprehensive.s`
**Purpose**: Comprehensive integration test

**Features tested**:
- Basic let immutability
- Basic var mutability
- Type-annotated let declarations
- Type-annotated var declarations
- Mixed let and var in same scope
- Variable usage in loops and control flow

**Expected**: Compilation succeeds ✓

## Running the Tests

### Individual Test
```bash
# Compile a specific test
/Users/feifei/shuwen/s/bin/s test/syntax/let_var_basic.s /tmp/output.ir

# Check compilation status
echo $?  # 0 = success, 1 = failure
```

### All Let/Var Tests
```bash
# Quick verification
for test in let_var_basic.s let_immutable.s var_mutable.s let_var_comprehensive.s; do
    /Users/feifei/shuwen/s/bin/s test/syntax/$test /tmp/$test.ir 2>&1
done
```

### With Error Checking
```bash
# Test immutability enforcement
/Users/feifei/shuwen/s/bin/s test/syntax/let_immutable.s /tmp/test.ir 2>&1 | grep "immutable"
# Should output: error[...]: symbol '...' is immutable
```

## Expected Behavior

| Test | Expected Result | Status |
|------|-----------------|--------|
| `let_var_basic.s` | Compile successfully | ✓ |
| `let_immutable.s` | Fail with "immutable" error | ✓ |
| `var_mutable.s` | Compile successfully | ✓ |
| `let_var_comprehensive.s` | Compile successfully | ✓ |

## Implementation Details

### Compiler Support
- **Lexer**: Recognizes `let` and `var` keywords
- **Parser**: Generates AST with mutability flag
- **Semantic Analyzer**: Enforces immutability at assignment time

### Error Messages
```
error[5] at <line>:<col>: symbol '<name>' is immutable
```

## Integration with S Project

These tests are integrated into the S language compiler test suite:
- Location: `s/test/syntax/`
- Runs as part of syntax tests
- Validates immutability system functionality

## Development Notes

When adding new let/var tests:
1. Place test files in `s/test/syntax/`
2. Use naming convention: `let_*`, `var_*`, or `let_var_*`
3. Add comments describing what feature is tested
4. Update this README with test description
5. Run compiler to verify: `/Users/feifei/shuwen/s/bin/s <test.s> /tmp/out.ir`

---

Last Updated: 2026-06-29
Compiler Version: s_arm64_20260629155934
