# S Language Ownership System - Complete Semantic Audit

## 审计目的
验证 Ownership → Move → Borrow → Drop → MIR → Backend 形成完整、可测试、无缺陷的语义闭环

## 关键发现

### 【发现 1】所有权追踪的实现位置
- ✓ src/cmd/compile/internal/ownership.s - 事件驱动检查
- ✓ src/cmd/compile/internal/borrow.s - 借用分析（部分）
- ✓ src/cmd/compile/internal/drop_system.s - Drop 系统（刚实现）
- ✓ src/cmd/compile/internal/drop_flag.s - Drop flag（刚实现）
- ✓ src/cmd/compile/internal/lifetime_check.s - 生命周期（刚实现）

**问题:**
- ⚠️ 这些模块是否真的被集成到编译流程中？
- ⚠️ 它们之间是否协调一致？
- ⚠️ AST → Parser → Semantic Analysis → IR/MIR → Codegen 的流程中，这些检查何时运行？何时失败？
- ⚠️ 是否存在多处不一致的实现？

### 【发现 2】Move 语义的完整性问题

问题:
- ✓ Simple move 似乎可以工作
- ⚠️ 但以下情况未测试：
  - move 在 if/else 中的处理
  - move 在 loop 中的处理
  - move 在 early return 时的处理
  - move 在 function call 时的完整检查
  - partial move (struct field move)
  - conditional move (两个分支中都 move)

### 【发现 3】Drop 的集成不完全

drop_system.s 已实现了：
- ✓ Drop trait 定义
- ✓ Drop flag 追踪
- ✓ 代码生成框架

但缺失：
- ✗ 与当前编译器流程的集成点
- ✗ 针对不同控制流的测试（break, continue, return, if/else）
- ✗ 与 GC 的交互验证
- ✗ 后端验证（生成的 C 代码是否正确？）

### 【发现 4】MIR/IR 表示的不清晰

现存代码缺少：
- ✗ 明确的所有权信息在 MIR 中的表示
- ✗ Move 操作的显式 IR 指令
- ✗ Borrow 在 MIR 中的清晰表示
- ✗ 生命周期约束在 IR 中的编码

### 【发现 5】测试覆盖的缺口

现存测试文件：
- test/compiler/ownership.s (基础事例)
- src/cmd/compile/internal/ownership_test.s (单元)
- src/cmd/compile/internal/borrow_test.s (单元)
- src/cmd/compile/internal/no_gc_test.s (新，部分)

缺失：
- ✗ 完整的 move 语义测试（控制流）
- ✗ 完整的 drop 语义测试（控制流）
- ✗ 完整的 borrow 语义测试（NLL）
- ✗ 综合集成测试
- ✗ 回归测试套件

### 【发现 6】GC 与 Box 的边界不清晰

问题：
- box[T] 应该保持唯一所有权
- GC-managed 对象与 box 对象的分界是什么？
- GC 的写屏障是否可能破坏 deterministic drop？
- 是否存在 GC 对象的意外引用计数？

## 当前能力矩阵

| Feature | Implemented | Tested | Correct | Status |
|---------|-------------|--------|---------|--------|
| Unique ownership | ✓ 部分 | ⚠️ 基础 | ❓ 未验证 | 需要审查 |
| Move semantics (simple) | ✓ 部分 | ⚠️ 基础 | ❓ 未验证 | 控制流缺陷 |
| Move semantics (complex) | ⚠️ 部分 | ❌ 无 | ❌ 无 | 缺失 |
| Borrow checking | ✓ 部分 | ⚠️ 基础 | ❓ 未验证 | NLL 缺失 |
| Drop scope exit | ✓ 部分 | ⚠️ 基础 | ❓ 待验证 | 需集成测试 |
| Drop early return | ✓ 部分 | ❌ 无 | ❌ 无 | 缺失 |
| Drop break/continue | ✓ 部分 | ❌ 无 | ❌ 无 | 缺失 |
| MIR ownership representation | ⚠️ 部分 | ❌ 无 | ❌ 无 | MIR 表示缺失 |
| Codegen memory safety | ⚠️ 部分 | ❌ 无 | ❌ 无 | 需验证 |

## 第一个真实缺口诊断

### Critical Gap 1: Move 语义在控制流中的完整性

现状:
- 简单的 `b := a` move 有基础实现
- 但在以下情况缺失：

1. Early return 中的 move
   ```
   func test() Box {
       x := box(5)
       if some_condition {
           return x  // ← x 的所有权转移到返回值
       }
       use(x)        // ← x 此时是否仍然有效？
       return x
   }
   ```

2. Conditional move
   ```
   func test() {
       x := box(5)
       y := Box
       if condition {
           y = x   // ← move x to y
       } else {
           // ← x 此时仍然在 y's shadow 中？
       }
       // ← scope exit 时，x 和 y 谁应该被 drop？
   }
   ```

3. Loop 中的 move
   ```
   func test() {
       v := []Box
       for item in v {
           x := item     // move
           use(x)
           // ← loop 尾部 x 的 drop 时序？
       }
   }
   ```

### Critical Gap 2: Drop 的运行时验证

现状:
- 生成 C 代码，包含 __s_drop_* 函数
- 但未验证：
  - 生成的 C 代码是否真的调用了 drop？
  - 是否存在 double-free？
  - 是否存在 use-after-drop？

### Critical Gap 3: MIR 中的所有权表示

现状:
- Drop system, drop flag, lifetime_check 都是高级抽象
- 但都没有映射到 MIR/IR

需要:
- 定义 MIR ownership 表示
- Move 操作的显式 IR 指令
- 让优化 pass 能看到这些信息

## 建议的修复顺序

### 【阶段 1】建立完整的测试框架（1 周）

目标: 有明确的失败测试能暴露当前缺口

任务:
1. 创建 test/no_gc/ 目录
2. 编写完整的 move 语义测试套件
3. 编写完整的 drop 语义测试套件
4. 编写完整的 borrow 语义测试套件
5. 验证当前实现在这些测试上的表现

### 【阶段 2】修复 Move 在控制流中的处理（2 周）

目标: move 在所有控制流中都正确

任务:
1. 在 semantic analyzer 中添加完整的 CFG 分析
2. 对每个 basic block 追踪所有权状态
3. 在 early return, break, continue 时生成 drop
4. 测试所有之前失败的用例

### 【阶段 3】验证 Drop 的正确性（1 周）

目标: drop 生成的 C 代码在所有情况下都正确

任务:
1. 检查生成的 C 代码
2. 添加 allocation tracking
3. 用 valgrind/ASAN 验证
4. 确认无 double-free、无 use-after-free、无 leak

### 【阶段 4】定义 MIR 表示（1-2 周）

目标: 所有权在 MIR 中有清晰表示

任务:
1. 扩展 MIR 定义
2. 添加 move, borrow, drop 指令
3. 更新 codegen 以保留这些信息
4. 更新优化 pass 以不违反这些语义

### 【阶段 5】完整集成验证（1 周）

目标: 整个流程无缺陷

任务:
1. 运行完整的测试套件
2. 验证自举编译器
3. 确认无回归
4. 发布 P0 gate 通过报告

## 成功标准

P0 Gate 通过的标准：

- ✅ 所有 no_gc 测试通过
- ✅ ASAN/Valgrind 无错误
- ✅ 0 memory leak
- ✅ 0 use-after-free
- ✅ 0 double-free
- ✅ 所有回归测试通过
- ✅ MIR 有清晰的 ownership 表示
- ✅ 文档化所有权语义

