#!/bin/bash
set -e

echo "🧹 清理工作区根目录的测试文件..."
cd /Users/feifei/shuwen

# 删除所有 test_*.s 文件
rm -f test_array_syntax.s test_complex_arrays.s test_empty_array.s test_func_array.s \
      test_one_element.s test_simple_array.s test_trailing.s test_typed_decl.s \
      test_untyped.s test_untyped_array.s test_var_array.s test_var_decl.s \
      test_var_multi.s test_let_var.s test_let_error.s test_var_reassign.s \
      test_let_var_comprehensive.s

echo "✓ 删除了所有 test_*.s 文件"

# 删除脚本文件
rm -f test_arrays.sh test_neurx_arrays.sh test_pre_commit_hook.sh \
      demo_precommit_hook.sh final_verification.sh verify_let_var.sh \
      migrate_tests_to_project.sh cleanup_workspace.sh cleanup.py

echo "✓ 删除了所有脚本文件"

# 删除文档文件
rm -f ARRAY_SYNTAX_MIGRATION_COMPLETE.md LET_VAR_IMPLEMENTATION.md

echo "✓ 删除了所有文档文件"

echo ""
echo "✅ 清理完成！"
echo "📂 所有测试文件现在都在项目中："
echo "   - s/test/arrays/          - 数组测试"
echo "   - s/test/syntax/          - let/var 测试"
echo "   - s/test/                 - 测试脚本"
