# P0 Gate - Ownership System Verification Plan

## 现在的任务

立即行动（不要做常量传播、Trait、泛型）：

**【必做】完整验证 S 的所有权系统语义闭环**

原因：
- ✓ 刚刚实现了大量内存管理代码（drop_system.s 等）
- ✓ 但这些实现**可能未充分集成或测试**
- ✓ 如果现在做常量传播等优化，后续改 MIR 时都要重写
- ✓ 必须先验证基础语义是否正确，才能做安全的优化

预期工作量: 6-8 周
ROI: 100% - 这是根本，没有这个，后面都不安全

## 第 1 步：建立完整的测试框架（1 周）

已创建的测试文件：
- ✓ test/no_gc/test_early_return_move.s - Early return 下的 move
- ✓ test/no_gc/test_conditional_move.s - 条件分支下的 move
- ✓ test/no_gc/test_use_after_move.s - Move 后再使用（应失败）

待创建的测试文件（需立即编写）：
1. test/no_gc/test_loop_move.s - Loop 中的 move
2. test/no_gc/test_break_continue.s - break/continue 时的 drop
3. test/no_gc/test_function_move.s - 函数参数和返回值的 move
4. test/no_gc/test_struct_field_move.s - Struct 字段的 move
5. test/no_gc/test_drop_order.s - Drop 的 LIFO 顺序
6. test/no_gc/test_borrow_after_move.s - Move 和 borrow 的交互
7. test/no_gc/test_partial_init.s - 部分初始化
8. test/no_gc/test_memory_leak.s - Memory leak 检查

## 第 2 步：运行审计（2-3 天）

执行命令：

```bash
$ cd /Users/feifei/shuwen/s
$ make compiler

# 针对每个测试运行：
$ for test in test/no_gc/test_*.s; do
    echo "Testing: $test"
    ./bin/s_compiler "$test" -o /tmp/test.ir
    if [ $? -eq 0 ]; then
      echo "  ✓ Compiled"
      cat /tmp/test.ir | head -20
    else
      echo "  ✗ Compilation failed"
    fi
  done
```

## 第 3 步：内存安全验证（1 周）

对每个通过编译的测试：

```bash
$ gcc -fsanitize=address -fsanitize=undefined \
      /tmp/test.ir -o /tmp/test_bin
$ ./tmp/test_bin

# 或用 Valgrind:
$ gcc -g /tmp/test.ir -o /tmp/test_bin
$ valgrind --leak-check=full --show-leak-kinds=all ./tmp/test_bin
```

检查列表：
- □ 是否有 use-after-free？
- □ 是否有 double-free？
- □ 是否有 memory leak？
- □ 是否有 buffer overflow？

## 第 4 步：代码审查（1-2 周）

基于第 2、3 步的结果，审查代码实现：

□ 审查 src/cmd/compile/internal/ownership.s
  - 是否真的被调用？何时调用？
  - 是否支持控制流？（当前是事件驱动）
  - 是否能正确处理嵌套作用域？

□ 审查 src/cmd/compile/internal/drop_flag.s
  - 是否被集成到编译器中？
  - 数据流分析是否正确？
  - 是否支持所有控制流？

□ 审查 src/cmd/compile/internal/drop_system.s
  - 是否真的生成 __s_drop 调用？
  - 顺序是否 LIFO？
  - 是否处理 early return/break/continue？

## 第 5 步：修复缺口（2-3 周）

基于审查结果，按优先级修复：

【优先级 1】Critical: 影响内存安全的缺口
- 例如: early return 时不 drop → memory leak
- 例如: conditional move 的 drop flag 错误 → double-free

【优先级 2】Important: 影响 move 语义的缺口
- 例如: function call 时的 move 处理不完全
- 例如: loop 中的 move 顺序错误

## 第 6 步：MIR 表示定义（1-2 周）

定义清晰的 MIR 所有权表示，为未来的优化做准备：

【新增 MIR 操作】
- MIRMove: src_var → dst_var
- MIRBorrow: borrowed_var → borrow_var
- MIRDrop: var_name (with reason)

【新增 MIR 信息】
- OwnershipInfo per variable
- ownership_in/ownership_out per block

好处：
- ✓ 优化 pass 可以安全地看到这些信息
- ✓ 可以验证优化不违反所有权语义
- ✓ 为未来的 NLL 等高级特性做准备

## 第 7 步：回归测试（1 周）

确保修复过程中没有引入新的问题：

```bash
$ make compiler-check       # 所有现有 compiler 测试
$ make benchmark            # 性能回归检查
```

## 关键时间表

- Week 1: 建立完整测试框架 (test/no_gc/*.s)
- Week 2: 运行审计和内存检查 (诊断当前缺口)
- Week 3: 代码审查 (理解现有实现)
- Week 4-5: 修复 Critical 缺口 (内存安全第一)
- Week 6: 修复 Important 缺口 (move 语义完整)
- Week 7: 定义 MIR 表示 (为优化做准备)
- Week 8: 回归测试和验证 (确保无问题)

Total: 8 周 = P0 Gate 通过

## 成功标准

P0 Gate 通过的标准：

✅ 所有 no_gc 测试通过

✅ ASAN/Valgrind 无错误：
- 0 memory leak
- 0 use-after-free
- 0 double-free
- 0 buffer overflow

✅ MIR 有清晰的所有权表示

✅ 所有现有编译器测试仍然通过（无回归）

✅ 能用 MIR 所有权信息验证：
- 每个 move 都有对应的 state 变化
- 每个 drop 都有对应的 scope exit
- 每个 borrow 都有明确的生命周期

完成后声明：
"S 编译器的所有权系统通过了完整的语义验证，保证：无 GC、内存安全、确定性资源清理。"

