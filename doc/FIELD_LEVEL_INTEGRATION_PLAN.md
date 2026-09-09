# Field-level Drop State - Integration Plan with Compiler

## 概述

将新的字段级别 drop state 系统集成到 S 编译器中，替换旧的变量级别实现，支持更复杂的所有权分析和 CFG 合并。

## 集成架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Compiler Frontend                        │
│  (Parser, Lexer, AST Construction)                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Semantic Analysis Phase 1                       │
│  - Type Checking                                            │
│  - Symbol Resolution                                        │
│  - Borrow Checking (lexical scopes)                        │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│         ★ Semantic Analysis Phase 2 (NEW)                  │
│         Field-Level Drop State Analysis                    │
│  - Initialize FieldLevelDropFlag                           │
│  - Track declarations, moves, uses                         │
│  - Handle scope entry/exit                                 │
│  - Merge conditional branches (CFG)                        │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Code Generation (IR/MIR)                       │
│  - Generate drop calls (based on analysis results)          │
│  - Create IR with ownership metadata                        │
│  - Optimize drop calls (dead code elimination)              │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              Backend (C Code Generation)                    │
│  - Generate C code with proper cleanup                      │
│  - Insert RAII patterns                                     │
│  - Handle exception safety                                  │
└─────────────────────────────────────────────────────────────┘
```

## 集成点详解

### 1. 编译器初始化

**文件**: `compiler.s`

**变更**:
```s
// 旧方式:
import drop_flag
var global_drop_flags = drop_flag_new()

// 新方式:
import field_level_drop_flag
var global_field_flags = fldf_new()
```

### 2. 语义分析 - 变量声明

**文件**: `semantic_analysis.s` (或 `type_checker.s`)

**现有代码**:
```s
func check_variable_declaration(ast_node decl) {
    var_name := decl.name
    type_name := check_type(decl.type_expr)
    
    // 旧: 添加到变量表
    symbol_table.add(var_name, type_name)
    
    // 旧: 注册到 drop flag
    drop_flags = drop_flag_declare(drop_flags, var_name, type_name)
}
```

**新方式**:
```s
func check_variable_declaration(ast_node decl) {
    var_name := decl.name
    type_name := check_type(decl.type_expr)
    
    // 添加到符号表（不变）
    symbol_table.add(var_name, type_name)
    
    // 新: 注册到字段级 drop flag
    p := path_new(var_name)
    field_flags = fldf_declare(field_flags, p, type_name)
}
```

### 3. 语义分析 - 变量使用

**文件**: `semantic_analysis.s`

**现有代码**:
```s
func check_use_expr(ast_node expr) {
    var_name := expr.variable_name
    
    // 检查是否已声明
    if !symbol_table.contains(var_name) {
        error("undefined variable: " + var_name)
    }
    
    // 旧: 检查 move 状态
    drop_flags = drop_flag_use(drop_flags, var_name)
}
```

**新方式**:
```s
func check_use_expr(ast_node expr) {
    var_name := expr.variable_name
    type_name := symbol_table.get(var_name)
    
    // 构建访问路径
    p := path_from_expr(expr)  // 例: "x", "x.f", "v[0]" 等
    
    // 新: 检查字段级状态
    field_flags = fldf_use(field_flags, p)
    
    // 处理错误
    if fldf_has_errors(field_flags) {
        error(fldf_get_errors(field_flags)[0])
    }
}
```

### 4. 语义分析 - 移出操作

**文件**: `semantic_analysis.s`

**现有代码**:
```s
func check_assignment(ast_node assign) {
    left := assign.left
    right := assign.right
    
    // 类型检查
    left_type := check_expr(left)
    right_type := check_expr(right)
    
    if left_type != right_type {
        error("type mismatch")
    }
    
    // 旧: 如果是移出
    if is_move_assignment(assign) {
        from := right.variable_name
        to := left.variable_name
        drop_flags = drop_flag_move(drop_flags, from, to)
    }
}
```

**新方式**:
```s
func check_assignment(ast_node assign) {
    left_expr := assign.left
    right_expr := assign.right
    
    // 类型检查
    left_type := check_expr(left_expr)
    right_type := check_expr(right_expr)
    
    if left_type != right_type {
        error("type mismatch")
    }
    
    // 新: 字段级 move
    if is_move_assignment(assign) {
        from_path := path_from_expr(right_expr)    // "x", "x.f", 等
        to_path := path_from_expr(left_expr)       // "y", "arr[0]", 等
        
        line := assign.line
        col := assign.column
        
        field_flags = fldf_move(field_flags, from_path, to_path, line, col)
        
        // 处理错误
        if fldf_has_errors(field_flags) {
            errors := fldf_get_errors(field_flags)
            error(errors[0])  // 输出第一个错误
        }
    }
}
```

### 5. 控制流 - 作用域进出

**文件**: `control_flow.s` 或 `block_analysis.s`

**新增功能**:
```s
func analyze_block(ast_node block) {
    // 进入新的作用域
    field_flags = fldf_enter_scope(field_flags)
    
    // 分析块中的语句
    for stmt in block.statements {
        analyze_stmt(stmt)
    }
    
    // 作用域退出，自动生成 drop
    field_flags, drop_paths := fldf_scope_exit(field_flags)
    
    // 记录哪些变量需要 drop
    for path in drop_paths {
        // 生成 drop 调用的 MIR
        emit_drop_call_mir(path)
    }
}
```

### 6. 控制流 - 条件分支（if-else）

**文件**: `control_flow.s`

**新增功能**:
```s
func analyze_if_statement(ast_node if_stmt) {
    // 分析条件表达式
    analyze_expr(if_stmt.condition)
    
    // 保存分支前的状态
    state_before_branch := field_flags
    
    // 分析 if 分支
    field_flags = fldf_enter_scope(field_flags)
    analyze_block(if_stmt.then_block)
    field_flags, then_drops := fldf_scope_exit(field_flags)
    field_flags_after_then := field_flags
    
    // 恢复到分支前状态
    field_flags = state_before_branch
    
    // 分析 else 分支（如果有）
    if if_stmt.else_block != nil {
        field_flags = fldf_enter_scope(field_flags)
        analyze_block(if_stmt.else_block)
        field_flags, else_drops := fldf_scope_exit(field_flags)
        field_flags_after_else := field_flags
        
        // 合并两个分支的状态
        field_flags = fldf_merge_branches(field_flags_after_then, field_flags_after_else)
    } else {
        // 没有 else，则状态在分支前后可能改变
        // 取 then 分支后的状态
        field_flags = field_flags_after_then
    }
}
```

### 7. 控制流 - 循环

**文件**: `control_flow.s`

**新增功能**:
```s
func analyze_loop(ast_node loop) {
    // 进入循环
    field_flags = fldf_enter_scope(field_flags)
    
    // 分析循环体
    analyze_block(loop.body)
    
    // 循环体结束，变量可能在下一个迭代重新初始化
    // 需要合并循环变量的状态
    
    // 简化版本：假设循环变量每次迭代重新初始化
    // 复杂版本：需要做不动点分析
    
    field_flags, loop_drops := fldf_scope_exit(field_flags)
}
```

### 8. 代码生成 - MIR 生成

**文件**: `codegen.s` 或 `mir_gen.s`

**新增功能**:
```s
// 在代码生成时，使用 drop paths 信息
func generate_mir_for_statement(ast_node stmt) {
    // ... 生成语句的 MIR ...
    
    // 如果是 return 语句
    if stmt.kind == RETURN {
        // 在 return 前，生成所有活跃变量的 drop
        drop_paths := fldf_get_paths_needing_drop(field_flags)
        
        for path in drop_paths {
            mir_emit_drop(path)
        }
        
        // 然后生成 return 本身
        mir_emit_return(stmt.value)
    }
}
```

### 9. 数据结构集成

**原有数据结构**:
```s
struct symbol_entry {
    string name
    string type_name
    int scope_depth
}
```

**扩展（可选）**:
```s
struct symbol_entry_extended {
    string name
    string type_name
    int scope_depth
    
    // 新增：所有权信息
    path ownership_path
    drop_state ownership_state
}
```

## 实现步骤

### 步骤 1: 集成 path.s (~1 天)

```bash
# 1. 验证 path.s 编译
$ ./bin/s_compiler src/cmd/compile/internal/path.s -check

# 2. 在 compiler.s 中导入
$ edit src/cmd/compile/compiler.s
  + use compile.internal.path

# 3. 运行路径操作的单元测试
$ make path-test
```

### 步骤 2: 集成 drop_state_v2.s (~1 天)

```bash
# 1. 验证编译
$ ./bin/s_compiler src/cmd/compile/internal/drop_state_v2.s -check

# 2. 在 compiler.s 中导入
$ edit src/cmd/compile/compiler.s
  + use compile.internal.drop_state_v2

# 3. 运行状态转移的单元测试
$ make drop_state_v2_test
```

### 步骤 3: 集成 field_level_drop_flag.s (~2 天)

```bash
# 1. 验证编译
$ ./bin/s_compiler src/cmd/compile/internal/field_level_drop_flag.s -check

# 2. 在 semantic_analysis.s 中使用
$ edit src/cmd/compile/internal/semantic_analysis.s
  # 替换 drop_flag 调用为 fldf_* 调用

# 3. 运行集成测试
$ ./bin/s_compiler test/compiler/ownership.s -emit-mir
  # 检查生成的 drop 调用是否正确
```

### 步骤 4: 修改 semantic_analysis.s (~2 天)

```bash
# 涉及的修改点:
# - check_variable_declaration() → 使用 fldf_declare()
# - check_use_expr() → 使用 fldf_use()
# - check_assignment() → 使用 fldf_move()
# - 其他变量操作

# 回归测试:
$ make compiler-check
  # 所有现有测试应该仍然通过
```

### 步骤 5: 修改 control_flow.s (~2 天)

```bash
# 涉及的修改点:
# - analyze_block() → 作用域进出
# - analyze_if_statement() → 分支合并
# - analyze_loop() → 循环处理

# 新测试:
$ ./bin/s_compiler test/no_gc/test_conditional_move.s -emit-mir
  # 检查条件分支的状态合并
```

### 步骤 6: 运行完整回归测试 (~1 天)

```bash
$ make compiler-check
  # 所有 compiler 测试
$ make no_gc_test
  # 所有 no_gc 测试
$ make self_host
  # 自举编译器
```

## 向后兼容性

新系统设计了完整的兼容层：

```s
// 旧的 API（仍然可用）
drop_flag_declare()
drop_flag_move()
drop_flag_use()

// 映射到新的 API
fldf_declare_var()        // 调用 fldf_declare(f, path_new(var), type)
fldf_move_var()           // 调用 fldf_move(f, path_new(from), path_new(to), ...)
fldf_use_var()            // 调用 fldf_use(f, path_new(var))
```

这允许逐步迁移代码。

## 验证清单

### 编译验证
- [ ] path.s 编译无误
- [ ] drop_state_v2.s 编译无误
- [ ] field_level_drop_flag.s 编译无误
- [ ] field_level_drop_test.s 编译无误
- [ ] 修改后的 compiler.s 编译无误

### 功能验证
- [ ] 所有字段级别测试通过
- [ ] 条件分支合并正确
- [ ] drop 顺序正确（LIFO）
- [ ] use-after-move 检测正确
- [ ] double-drop 检测正确

### 回归验证
- [ ] make compiler-check 全部通过
- [ ] make no_gc_test 全部通过
- [ ] make self_host 成功
- [ ] 生成的二进制大小无明显增加

### 性能验证
- [ ] 编译时间 < 1.2x（新系统开销不超过 20%）
- [ ] 内存占用 < 1.5x
- [ ] 生成的 C 代码质量不下降

## 时间表

| 周 | 任务 | 工作量 | 人天 |
|----|------|--------|------|
| 1 | 集成 path.s, drop_state_v2.s | 简单 | 2 |
| 1 | 集成 field_level_drop_flag.s | 中等 | 2 |
| 2 | 修改 semantic_analysis.s | 复杂 | 2 |
| 2 | 修改 control_flow.s | 复杂 | 2 |
| 3 | 回归测试、优化、修复 | 中等 | 3 |
| **总计** | | | **11 人天** |

## 风险和缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 性能下降 | 中 | 编译变慢 | 性能测试、优化索引 |
| 回归问题 | 高 | 功能破坏 | 完整回归测试、增量集成 |
| 路径查询复杂 | 中 | 难以维护 | 加入路径缓存、测试工具 |
| CFG 合并复杂 | 高 | 状态不准确 | 先支持 if-else，后支持 switch/loop |

## 后续优化

集成完成后的优化项：

1. **性能优化** (1 周)
   - 路径查询的哈希表缓存
   - 状态转移的快速路径
   - 条件合并的不动点分析缓存

2. **高级特性** (2 周)
   - 完整 CFG (switch, loop, exception)
   - 生命周期推理（从 maybe 恢复到 live）
   - 智能 drop 消除（DCE）

3. **工具支持** (1 周)
   - 所有权可视化
   - 调试器集成
   - 编译器诊断改进

## 检查清单提交

集成完成时需要提交：
- [ ] 所有 4 个模块的生产代码
- [ ] 完整的测试套件（通过）
- [ ] 集成到 compiler.s, semantic_analysis.s, control_flow.s
- [ ] 所有回归测试通过
- [ ] 文档和 API 指南
- [ ] 性能测试报告
