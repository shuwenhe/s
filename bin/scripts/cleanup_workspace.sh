#!/bin/bash
# Clean up test files from workspace root - they're now in s/test

echo "🧹 Cleaning up test files from workspace root..."
echo "   (Test files are now organized in s/test project structure)"
echo ""

WORKSPACE="/Users/feifei/shuwen"

# Remove array test files
files_removed=0
for file in test_array_syntax.s test_complex_arrays.s test_empty_array.s test_func_array.s \
            test_one_element.s test_simple_array.s test_trailing.s test_typed_decl.s \
            test_untyped.s test_untyped_array.s test_var_array.s test_var_decl.s test_var_multi.s; do
    if [ -f "$WORKSPACE/$file" ]; then
        rm -f "$WORKSPACE/$file"
        ((files_removed++))
    fi
done

echo "✓ Removed $files_removed array test files"

# Remove old test files from workspace root
for file in test_let_var.s test_let_error.s test_var_reassign.s test_let_var_comprehensive.s; do
    if [ -f "$WORKSPACE/$file" ]; then
        rm -f "$WORKSPACE/$file"
    fi
done

echo "✓ Removed legacy let/var test files from root"

# Remove old documentation and verification scripts
for file in ARRAY_SYNTAX_MIGRATION_COMPLETE.md LET_VAR_IMPLEMENTATION.md \
            demo_precommit_hook.sh final_verification.sh verify_let_var.sh \
            test_arrays.sh test_neurx_arrays.sh test_pre_commit_hook.sh; do
    if [ -f "$WORKSPACE/$file" ]; then
        rm -f "$WORKSPACE/$file"
    fi
done

echo "✓ Removed workspace root documentation and scripts"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📂 Test files are now organized in:"
echo "   - s/test/arrays/          - Array syntax tests"
echo "   - s/test/syntax/          - Let/var and other syntax tests"
echo "   - s/test/                 - Test scripts"
echo ""
echo "📖 See: s/test/TEST_ORGANIZATION.md"
