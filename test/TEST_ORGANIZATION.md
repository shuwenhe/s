# S Language Test Suite Organization

## Test Structure

All test files have been organized into the S language compiler project at `/Users/feifei/shuwen/s/test/`

### Directory Organization

```
s/test/
├── arrays/              # Array syntax tests
│   ├── test_array_syntax.s
│   ├── test_complex_arrays.s
│   ├── test_empty_array.s
│   ├── test_func_array.s
│   ├── test_one_element.s
│   ├── test_simple_array.s
│   ├── test_trailing.s
│   ├── test_typed_decl.s
│   ├── test_untyped.s
│   ├── test_untyped_array.s
│   ├── test_var_array.s
│   ├── test_var_decl.s
│   └── test_var_multi.s
│
├── syntax/              # Syntax features (let/var, etc.)
│   ├── let_var_basic.s
│   ├── let_immutable.s
│   ├── var_mutable.s
│   ├── let_var_comprehensive.s
│   ├── README_LET_VAR.md
│   ├── run_let_var_tests.sh
│   └── (other syntax tests...)
│
└── TEST_ORGANIZATION.md # This file

s/bin/scripts/          # Test verification scripts
├── test_arrays.sh      # Array syntax verification script
├── test_neurx_arrays.sh # Neurx codebase validation
└── test_pre_commit_hook.sh  # Pre-commit hook testing

```

## Test Categories

### 1. Array Syntax Tests (`s/test/arrays/`)
Tests the S language array type syntax and literals:
- **Prefix syntax**: `[]int`, `[N]string`
- Empty arrays: `[]int{}`
- Single elements: `[]int{1}`
- Multi-element arrays: `[]int{1, 2, 3}`
- Trailing commas: `[]int{1, 2,}`
- Fixed-size arrays: `[5]int{1, 2, 3, 4, 5}`

### 2. Let/Var Tests (`s/test/syntax/`)
Tests immutability and mutability features:
- **`let`**: Immutable variable declarations
- **`var`**: Mutable variable declarations
- Type annotations: `let x int =bin/scripts/`)
- `test_arrays.sh` - Tests basic array syntax
- `test_neurx_arrays.sh` - Validates conversions in neurx codebase
- `test_pre_commit_hook.sh` - Verifies git pre-commit hook

## Running Tests

```bash
# Test array syntax
bash /Users/feifei/shuwen/s/bin/scripts/test_arrays.sh

# Test let/var features
bash /Users/feifei/shuwen/s/test/syntax/run_let_var_tests.sh

# Validate neurx conversions
bash /Users/feifei/shuwen/s/bin/scripts/test_neurx_arrays.sh

# Test pre-commit hook
bash /Users/feifei/shuwen/s/bin/scripts/test_neurx_arrays.sh

# Test pre-commit hook
bash test_pre_commit_hook.sh
```

## Compiler Information

- **Binary**: `/Users/feifei/shuwen/s/bin/s`
- **Source**: `/Users/feifei/shuwen/s/src/cmd/compile/seed/`
- **Build**: `bash /Users/feifei/shuwen/s/bin/build_s_arm64.sh`

## Note on Workspace Cleanup

The original test files in `/Users/feifei/shuwen/` (workspace root) have been migrated to the project structure. Those files should be removed from the workspace root to maintain clean organization.
