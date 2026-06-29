#!/bin/bash

# Migrate test files from workspace root to s/test project structure

set -e

WORKSPACE="/Users/feifei/shuwen"
PROJECT_ARRAYS="$WORKSPACE/s/test/arrays"

echo "📦 Migrating test files to S project structure..."

# Array test files
array_files=(
    "test_array_syntax.s"
    "test_complex_arrays.s"
    "test_empty_array.s"
    "test_func_array.s"
    "test_one_element.s"
    "test_simple_array.s"
    "test_trailing.s"
    "test_typed_decl.s"
    "test_untyped.s"
    "test_untyped_array.s"
    "test_var_array.s"
    "test_var_decl.s"
    "test_var_multi.s"
)

# Move array tests to arrays directory
for file in "${array_files[@]}"; do
    if [ -f "$WORKSPACE/$file" ]; then
        mv "$WORKSPACE/$file" "$PROJECT_ARRAYS/"
        echo "  ✓ $file → s/test/arrays/"
    fi
done

# Move test scripts to project root
PROJECT_TEST_SCRIPTS="$WORKSPACE/s/test"
if [ -f "$WORKSPACE/test_arrays.sh" ]; then
    mv "$WORKSPACE/test_arrays.sh" "$PROJECT_TEST_SCRIPTS/"
    echo "  ✓ test_arrays.sh → s/test/"
fi

if [ -f "$WORKSPACE/test_neurx_arrays.sh" ]; then
    mv "$WORKSPACE/test_neurx_arrays.sh" "$PROJECT_TEST_SCRIPTS/"
    echo "  ✓ test_neurx_arrays.sh → s/test/"
fi

if [ -f "$WORKSPACE/test_pre_commit_hook.sh" ]; then
    mv "$WORKSPACE/test_pre_commit_hook.sh" "$PROJECT_TEST_SCRIPTS/"
    echo "  ✓ test_pre_commit_hook.sh → s/test/"
fi

# Remove workspace root test documentation and verification scripts
rm -f "$WORKSPACE/demo_precommit_hook.sh"
rm -f "$WORKSPACE/final_verification.sh"
rm -f "$WORKSPACE/verify_let_var.sh"
echo "  ✓ Removed workspace root verification scripts"

echo ""
echo "✅ Migration complete! All tests now in s/test/"
echo "   - Array tests: s/test/arrays/"
echo "   - Let/Var tests: s/test/syntax/"
echo "   - Test scripts: s/test/"

# Verify no .s test files remain in root
remaining=$(find "$WORKSPACE" -maxdepth 1 -name "*.s" -type f 2>/dev/null | grep -v "^$WORKSPACE/s/" | wc -l)
if [ "$remaining" -eq 0 ]; then
    echo "   ✓ No test files remaining in workspace root"
else
    echo "   ⚠️  Warning: $remaining .s files still in workspace root"
fi
