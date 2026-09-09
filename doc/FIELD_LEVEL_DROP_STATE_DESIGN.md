# Field-level Drop State Generalization - Complete Design Specification

## Executive Summary

升级 S 编译器的 drop flag 系统，从**变量级别**发展为**字段级别**的通用状态管理。这是从 P0-GATE 审计衍生的、为期 6-8 周的全面 P0 验证计划中的一个关键阶段。

**目标**: 实现完整的、层次化的、有元数据的所有权状态追踪，支持结构体字段、数组元素、嵌套访问的独立状态管理，为条件分支合并（CFG merge）和复杂控制流分析做准备。

**规模**: 4 个核心模块 (~1430 行代码)，11 个全面的测试用例，2-3 周集成周期。

---

## 1. 问题陈述

### 当前系统的限制

S 语言编译器的现有 drop flag 系统（v1）在以下方面存在缺陷：

```s
// 旧系统: 变量级别，状态简单
drop_flag {
  int state;  // unknown | present | absent | partial
}
```

**限制 1: 无法追踪结构体字段的独立状态**
```s
struct Point { int x; int y; }
var p: Point

// 移出 x，但 y 仍然活跃
move(p.x, dest)

// 旧系统: p 被标记为 "absent"（不准确）
// 新系统: p.x → moved, p.y → live（准确）
```

**限制 2: 无法追踪数组元素的独立状态**
```s
var arr: int[10]

move(arr[0], dest)

// 旧系统: 无法独立追踪 arr[0] vs arr[1]
// 新系统: arr[0] → moved, arr[1] → live
```

**限制 3: 条件分支合并无法正确处理**
```s
if condition {
    move(x, dest)  // x 被移出
} else {
    // x 未被移出，仍然活跃
}

// 分支后，x 的状态是什么？
// 旧系统: 不知道如何合并
// 新系统: x → maybe (状态不确定，保守处理)
```

**限制 4: 无调试信息和错误上下文**
```s
// 旧系统错误: "error: use after move"（没有位置）
// 新系统错误: "error: use after move at line 42
//               - moved at line 10 in function foo
//               - moved from 'x' to 'y'"
```

### P0-GATE 审计结论

从 P0-GATE 的 6 个关键差距中，**Gap 1（Move 在控制流中）** 和 **Gap 2（Drop 验证）** 直接指向这个需求：

- Gap 1: Early return, conditional move, loop moves → 需要路径级别的精细追踪
- Gap 2: Drop 生成的正确性 → 需要更强的语义模型

这个阶段就是解决这两个差距的基础工作。

---

## 2. 设计目标

### 主要目标

1. **精细化**: 从变量级 → 字段级，支持嵌套和混合场景
2. **语义完整**: 定义完整的状态机和转移规则
3. **可验证性**: 包含足够的元数据用于调试和验证
4. **可扩展性**: 为 CFG merge, exception handling, loop unrolling 做准备
5. **向后兼容**: 现有代码继续工作，无需修改

### 成功标准

- ✅ 支持最少 4 层嵌套 (x.f[0].g.h)
- ✅ struct 字段独立状态
- ✅ 数组元素独立状态
- ✅ if-else 条件合并
- ✅ LIFO drop 顺序
- ✅ 11/11 测试通过
- ✅ 无性能回归 (< 1.2x)
- ✅ 完整的错误诊断

---

## 3. 核心数据结构

### 3.1 路径表示（Path Representation）

路径表示变量的层次化访问。核心思想：分解访问为一系列单步操作。

#### 设计选项分析

我们考虑了 7 种不同的路径表示方式：

| # | 方式 | 优点 | 缺点 | 选择 |
|---|------|------|------|------|
| 1 | 字符串 "x.f[0].g" | 简单，易读 | 频繁解析，难以 merge | ❌ |
| 2 | 结构体数组 (✓) | O(n) 比较，merge 效率高 | 内存略多 | ✅ |
| 3 | 链表 | 灵活 | 指针操作，缓存差 | ❌ |
| 4 | 树结构 | 前缀共享 | 复杂实现，递归 | ⏰ |
| 5 | Rope（绳结构） | 插入删除快 | 复杂，不利于比较 | ❌ |
| 6 | Hash 值 | 快速相等判断 | 碰撞问题，不能存储 | ❌ |
| 7 | 混合（数组+Hash） | 效率最优 | 最复杂 | ⏰ |

**选择: 结构体数组（方案 2）**

```s
struct path {
    string base_var                // 基变量 "x"
    path_segment[] segments        // 访问路径
}

struct path_segment {
    int kind                       // FIELD | INDEX | INDEX_VAR | DEREF
    string field_name              // 字段名（用于 FIELD）
    int index_value                // 下标值（用于 INDEX）
    string index_var               // 下标变量（用于 INDEX_VAR）
}
```

#### 路径示例

```
x               → {base: "x", segs: []}
x.f             → {base: "x", segs: [FIELD("f")]}
x.f[0]          → {base: "x", segs: [FIELD("f"), INDEX(0)]}
x.f[i].g        → {base: "x", segs: [FIELD("f"), INDEX_VAR("i"), FIELD("g")]}
vec[10].data    → {base: "vec", segs: [INDEX(10), FIELD("data")]}
(*ptr).f        → {base: "ptr", segs: [DEREF(), FIELD("f")]}
```

#### 路径操作

```s
// 构造
path_new(base: string) → path
path_field(path, field_name: string) → path
path_index(path, index: int) → path
path_index_var(path, var: string) → path
path_deref(path) → path

// 比较和查询
path_equal(p1: path, p2: path) → bool
path_is_prefix(prefix: path, full: path) → bool
path_common_prefix(p1: path, p2: path) → path
path_len(path) → int

// 字符串转换
path_to_string(path) → string
path_parse(str: string) → path

// 集合
path_map { path → value }      // 哈希表
path_set { path }               // 集合
```

#### 路径比较示例

```
path_equal(path("x.f"), path("x.f")) → true
path_equal(path("x.f"), path("x.g")) → false

path_is_prefix(path("x"), path("x.f")) → true
path_is_prefix(path("x.f"), path("x")) → false

path_common_prefix(path("x.f.a"), path("x.f.b")) → path("x.f")
```

### 3.2 Drop State 结构

从简单的 int 升级为有元数据的 struct。

#### 五种状态

```s
enum DropStateKind {
    LIVE    = 0,      // 可以使用，可以 drop
    MOVED   = 1,      // 所有权已移出，不能使用
    MAYBE   = 2,      // 不确定（来自条件分支），保守处理
    PARTIAL = 3,      // 结构体的某些字段 moved，某些 live
    DROPPED = 4       // 已被 drop，不能再用
}

struct drop_state {
    int kind                                    // 状态种类
    string reason                              // 原因："move at line X", "after if-merge", etc.
    int line_number                            // 调试信息
    int column_number
    
    struct {                                   // 用于 PARTIAL 状态
        string field_name
        drop_state field_state
    }[] field_states
    
    int[] source_branch_ids                    // 用于 MAYBE 状态
}
```

#### 状态转移规则

```
Declaration:
    → live

Use (accessing/reading):
    live → live (验证但状态不变)
    moved → ERROR "use of moved value"
    maybe → ERROR "use of possibly moved value" (保守)
    dropped → ERROR "use of dropped value"

Move (转移所有权):
    live → moved (全部移出)
    partial (x: struct) → partial (移出一个字段)
    moved → ERROR "cannot move twice"
    dropped → ERROR "cannot move dropped"

Reassign (重新赋值):
    moved → live (恢复)
    dropped → live (重新初始化)
    maybe → live (恢复确定性)

Drop (销毁资源):
    live → dropped
    moved → OK (no-op，已经没有资源)
    maybe → dropped (保守，可能需要 drop)
    partial → dropped (只 drop live 的字段)

Drop at Scope Exit:
    auto drop all live/partial/maybe
    order: LIFO (后声明先 drop)
```

### 3.3 DropState 转移示例

```
// 场景: 结构体的字段级 move

struct Point { int x; int y; }
var p: Point

// 初始: p → live

move(p.x, dest)
// 结果: p.x → moved, p.y → live
//      p 本身 → partial

use(p.x)
// ERROR: "use of moved value 'p.x' at line 10"

use(p.y)
// OK: p.y 仍然 live

move(p.y, dest2)
// 结果: p.x → moved, p.y → moved
//      p 本身 → moved（所有字段都被移出了）

scope_exit
// p 本身不需要 drop（已经完全被移出）
// 但如果部分字段仍然 live，就需要 drop
```

### 3.4 CFG Merge 规则

当程序流从 if-else 汇聚时，两个分支的状态需要合并。

#### 合并表

```
Branch A + Branch B → Result

live + live           → live      （都活跃）
moved + moved         → moved     （都被移出）
live + moved          → maybe     （不确定）
moved + live          → maybe     （不确定）

live + maybe          → maybe     （已经不确定了）
moved + maybe         → maybe

maybe + maybe         → maybe

partial + *           → maybe     （partial 很特殊，保守）
dropped + *           → maybe     （dropped 也很特殊）
```

#### 合并示例

```
if condition {
    move(x, dest)    // x: live → moved
} else {
    // x 不动                         // x: live
}

after merge:
// x: maybe (因为一个分支 moved，一个 live)

use(x)              // ERROR 或 WARNING，x 可能 moved
drop(x)             // OK，保守处理（可能需要 drop）
```

---

## 4. 主系统架构

### 4.1 FieldLevelDropFlag 数据结构

```s
struct field_level_entry {
    path path                  // 访问路径
    drop_state state          // 当前状态
    string type_name          // 类型信息（用于调试）
    int scope_depth           // 在第几层作用域
}

struct field_level_drop_flag {
    field_level_entry[] entries        // 所有追踪的路径
    int scope_depth                    // 当前作用域深度
    int next_branch_id                 // 用于 maybe 追踪
    
    string[] errors                    // 累积的错误
    
    // 优化: 加快查询
    path_map entry_map                 // path → entry
}
```

### 4.2 核心操作

```s
// 初始化
fldf_new() → field_level_drop_flag

// 作用域管理
fldf_enter_scope(f: field_level_drop_flag) → field_level_drop_flag
fldf_exit_scope(f) → field_level_drop_flag

// 变量/字段操作
fldf_declare(f, path, type_name) → field_level_drop_flag
fldf_use(f, path) → field_level_drop_flag
fldf_move(f, from_path, to_path, line, col) → field_level_drop_flag
fldf_reassign(f, path, type_name) → field_level_drop_flag

// 作用域退出时的自动 drop
fldf_scope_exit(f) → (field_level_drop_flag, path[])
                    // 返回需要 drop 的路径列表（LIFO 顺序）

// 条件分支处理
fldf_save_checkpoint(f) → checkpoint
fldf_merge_branches(f_if, f_else) → field_level_drop_flag

// 查询
fldf_find(f, path) → field_level_entry
fldf_find_related(f, path) → field_level_entry[]  // 所有以 path 开头的
fldf_get_paths_needing_drop(f) → path[]
fldf_get_moved_paths(f) → path[]

// 错误处理
fldf_has_errors(f) → bool
fldf_get_errors(f) → string[]
```

### 4.3 调用流程示例

```s
// 编译一个函数
func compile_function(func_ast) {
    f := fldf_new()
    
    // 声明参数
    for param in func_ast.parameters {
        p := path_new(param.name)
        f = fldf_declare(f, p, param.type)
    }
    
    // 分析函数体
    f = analyze_block(f, func_ast.body)
    
    // 函数退出，drop 所有本地变量
    f, drop_paths := fldf_scope_exit(f)
    
    for path in drop_paths {
        emit_drop_call(path)  // 生成 drop 调用
    }
}

// 分析块
func analyze_block(f, block_ast) {
    f = fldf_enter_scope(f)
    
    for stmt in block_ast {
        match stmt.kind {
            DECL → {
                p := path_new(stmt.name)
                f = fldf_declare(f, p, stmt.type)
            }
            ASSIGN → {
                if is_move(stmt) {
                    from := path_from_expr(stmt.right)
                    to := path_from_expr(stmt.left)
                    f = fldf_move(f, from, to, stmt.line, stmt.col)
                }
            }
            USE → {
                p := path_from_expr(stmt.expr)
                f = fldf_use(f, p)
            }
            IF → {
                state_before := checkpoint(f)
                
                // if 分支
                f_if = analyze_block(f, stmt.then)
                
                // else 分支
                f = restore(f, state_before)
                f_else = analyze_block(f, stmt.else)
                
                // 合并
                f = merge_branches(f_if, f_else)
            }
        }
    }
    
    f, drops := fldf_scope_exit(f)
    return f
}
```

---

## 5. 架构设计

### 5.1 模块分解

```
┌──────────────────────────────────────────────────────────────┐
│                   Compiler Integration Layer                 │
│  (semantic_analysis.s, control_flow.s, codegen.s)           │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│         field_level_drop_flag.s (380 lines)                 │
│              Main system, all operations                     │
│         declare, use, move, reassign, scope_exit, merge      │
└──────────┬───────────────────────────┬──────────────────────┘
           │                           │
           ▼                           ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│   path.s (400 lines) │    │ drop_state_v2.s (350 lines) │
│ Path operations and  │    │  State definitions and      │
│  representation      │    │   transition rules          │
└──────────────────────┘    └──────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│         field_level_drop_test.s (300 lines)                 │
│              Comprehensive test suite (11 tests)            │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 模块职责

| 模块 | 行数 | 职责 |
|------|------|------|
| path.s | ~400 | 路径构造、比较、序列化 |
| drop_state_v2.s | ~350 | 状态定义、转移、合并 |
| field_level_drop_flag.s | ~380 | 主系统、操作协调 |
| field_level_drop_test.s | ~300 | 11 个测试用例 |
| **Total** | **~1430** | |

### 5.3 依赖关系

```
field_level_drop_flag.s
    ↓ imports
    path.s
    drop_state_v2.s

field_level_drop_test.s
    ↓ imports
    field_level_drop_flag.s
    path.s
    drop_state_v2.s
```

---

## 6. 测试策略

### 6.1 测试用例 (11 个)

#### 基础操作 (3 个)

1. **test_basic_declare_and_use**
   - 声明变量，成功使用
   - 验证 declare + use 的基本流程
   
2. **test_use_after_move**
   - 移出变量，尝试使用
   - 验证错误检测
   
3. **test_struct_field_move**
   - 移出结构体字段，验证其他字段仍活跃
   - 验证字段级状态独立性

#### 高级操作 (3 个)

4. **test_array_element_move**
   - 移出数组元素，验证其他元素独立
   - 验证数组索引的独立状态
   
5. **test_nested_field_access**
   - 嵌套字段访问 x.in.value
   - 验证多层路径正确
   
6. **test_partial_move_two_fields**
   - 移出结构体的两个字段
   - 验证部分状态追踪

#### 条件合并 (2 个)

7. **test_conditional_merge_same_state**
   - if-else 两分支都 live（或都 moved）
   - 验证合并后状态正确
   
8. **test_conditional_merge_different_state**
   - if 分支 moved, else 分支 live
   - 验证合并后状态变为 maybe

#### 作用域管理 (2 个)

9. **test_struct_field_drop_order**
   - 作用域退出时的 drop 顺序
   - 验证 LIFO 顺序
   
10. **test_reassignment_after_move**
    - 移出后重新赋值
    - 验证状态恢复

#### 综合测试 (1 个)

11. **test_scope_lifo_drop_order**
    - 复杂场景：多个变量、嵌套作用域
    - 验证完整的 drop 顺序和状态

### 6.2 测试执行

```
$ ./bin/s_compiler src/cmd/compile/internal/field_level_drop_test.s -o test.o
$ ./test.o

// 预期输出:
// ════════════════════════════════════════════
// Field-Level Drop Flag Tests
// ════════════════════════════════════════════
// ✓ test_basic_declare_and_use
// ✓ test_use_after_move
// ✓ test_struct_field_move
// ✓ test_array_element_move
// ✓ test_nested_field_access
// ✓ test_partial_move_two_fields
// ✓ test_conditional_merge_same_state
// ✓ test_conditional_merge_different_state
// ✓ test_struct_field_drop_order
// ✓ test_reassignment_after_move
// ✓ test_scope_lifo_drop_order
// ════════════════════════════════════════════
// Passed: 11 / 11
// ════════════════════════════════════════════
```

---

## 7. 关键设计决策及其理由

### 决策 1: 路径表示选择（Structured Array）

**决策**: 使用 `{base_var, path_segment[]}`

**理由**:
- O(n) 路径比较，n 通常很小 (≤ 4)
- 支持高效的前缀匹配（CFG merge 时需要）
- 易于序列化和调试
- 易于添加元数据（路径来源、类型等）

**替代方案评估**:
- 字符串: 频繁解析，不利于 merge
- 链表: 缓存差，指针操作复杂
- 树: 实现复杂，收益不大

### 决策 2: Drop State 升级为 Struct（含元数据）

**决策**: 使用 `struct drop_state { kind, reason, line, col, field_states[], ... }`

**理由**:
- 支持详细的错误诊断
- 支持 maybe 状态的源追踪
- 便于调试复杂的分支合并
- 支持未来的优化（如 maybe 恢复）

**替代方案**:
- int: 简单但无诊断信息，难以调试
- String: 灵活但低效

### 决策 3: 保守的 Maybe 处理

**决策**: maybe 状态下，在作用域退出时保守 drop（可能造成 double-drop，但安全）

**理由**:
- 安全第一，避免内存泄漏或 use-after-free
- 可以后续优化（比如检测 double-drop）
- 符合 Rust 的设计哲学

**权衡**:
- 精度: 低（可能不必要的 drop）
- 安全性: 高（不会 miss drop）
- 复杂性: 低

### 决策 4: Flat Storage（非树结构）

**决策**: 所有路径条目存储在单个数组中，使用 path_map 索引

**理由**:
- 实现简单，易于迭代
- 足够快（通常 < 100 个路径）
- 易于遍历和调试
- 易于生成 drop 顺序

**缺点**:
- 可能在非常大的函数中变慢
- 不支持路径压缩

**后续优化**:
- 如果性能成为问题，升级为树结构或图

### 决策 5: CFG Merge 策略（先支持 if-else）

**决策**: Phase 2 只支持 if-else，loop 和 switch 延迟到 Phase 3

**理由**:
- 减少 Phase 2 复杂性
- if-else 是最常见的分支
- 为 Phase 3 建立基础
- 可以逐步扩展

**Phase 3 计划**:
- switch: 多分支合并
- loop: 循环变量状态追踪
- exception: throw/catch 的 drop 保证

---

## 8. 集成策略

### 8.1 编译器中的集成点

集成涉及修改 3 个主要文件：

1. **compiler.s** - 初始化和协调
2. **semantic_analysis.s** - 跟踪声明、使用、移动
3. **control_flow.s** - 处理作用域、条件、循环
4. **codegen.s** - 生成 drop 调用

详见 FIELD_LEVEL_INTEGRATION_PLAN.md

### 8.2 向后兼容性

提供简化的变量级 API 作为兼容层：

```s
// 旧 API（仍然可用）
fldf_declare_var(f, var_name, type)  // → fldf_declare(f, path_new(var_name), type)
fldf_move_var(f, from, to, ...)      // → fldf_move(f, path_new(from), path_new(to), ...)
fldf_use_var(f, var)                 // → fldf_use(f, path_new(var))
```

### 8.3 分阶段集成

```
Week 1: 
  - Day 1: 集成 path.s, drop_state_v2.s
  - Day 2: 集成 field_level_drop_flag.s
  
Week 2:
  - Day 1-2: 修改 semantic_analysis.s
  - Day 3-4: 修改 control_flow.s
  
Week 3:
  - Day 1-2: CFG merge 高级特性
  - Day 3: 优化和性能调优
  - Day 4: 回归测试
```

---

## 9. 与 P0-GATE 的关系

### P0-GATE 的 6 个关键差距

| 差距 | 影响 | 本设计的覆盖 |
|------|------|-------------|
| Gap 1: Move 在控制流中 | 无法处理 if/loop/return 中的 move | ✓ CFG merge (if-else) |
| Gap 2: Drop 验证 | Drop 生成的正确性未知 | ✓ 字段级追踪、LIFO drop |
| Gap 3: MIR 所有权 | IR 中无所有权信息 | ⏰ Phase 3 |
| Gap 4: 测试覆盖 | 测试不足 | ✓ 11 个综合测试 |
| Gap 5: GC 边界 | GC 和 manual drop 混用不安全 | ⏰ Phase 3-4 |
| Gap 6: 语义闭环 | 没有正式验证 | ⏰ Phase 4-5 |

本设计直接解决 Gaps 1, 2, 4，为 Gaps 3, 5, 6 奠定基础。

---

## 10. 性能考虑

### 10.1 编译时开销

预期编译时间增加不超过 20%（< 1.2x）：

- 路径操作: O(n), n ≤ 4, 每次 < 100 ns
- 状态转移: O(1), 每次 ~ 10 ns
- 条件合并: O(m * n), m ≤ 100 路径, n ≤ 4 深度, ~ 1 µs

对于典型函数 (100-1000 行代码)，总开销 1-10 ms，可接受。

### 10.2 内存开销

```
per path entry:
  - path: 100 字节 (base + 4 segments * 15 字节)
  - drop_state: 80 字节
  - metadata: 20 字节
  = 200 字节 per entry

typical function: 50 paths
= 10 KB per function

compiler total: 1000 functions
= 10 MB overhead
```

相对于编译器的总内存占用（通常 100+ MB），可接受。

### 10.3 优化机会

- 路径查询缓存 (hash table)
- 状态转移快速路径（对于常见情况）
- 条件合并的增量处理
- 死代码消除（DCE）优化 drop 调用

---

## 11. 已知限制和未来工作

### 11.1 Phase 2 的限制

- 仅支持 if-else，不支持 switch/loop
- 路径不支持通配符 (x.*)
- 不支持符号执行
- maybe 状态不能自动恢复为确定状态

### 11.2 Phase 3 计划

- 完整 CFG (switch, loop, exception)
- 智能 maybe 恢复
- MIR 所有权表示
- Drop 调用优化 (DCE)
- 异常安全性验证

### 11.3 Phase 4+ 计划

- 生命周期推理
- 借用检查器（borrow checker）
- 移动语义优化
- 堆栈分析和寄存器分配集成

---

## 12. 实施清单

### 编码阶段

- [x] path.s - 完全实现
- [x] drop_state_v2.s - 完全实现
- [x] field_level_drop_flag.s - 完全实现
- [x] field_level_drop_test.s - 11 个测试
- [ ] 编译测试
- [ ] 单元测试执行

### 集成阶段

- [ ] 修改 compiler.s
- [ ] 修改 semantic_analysis.s
- [ ] 修改 control_flow.s
- [ ] 修改 codegen.s
- [ ] 回归测试

### 文档阶段

- [x] 设计文档（本文档）
- [x] 集成计划
- [x] 实现总结
- [ ] API 文档
- [ ] 调试指南

---

## 13. 总结

Field-level Drop State Generalization 是从简单的变量级追踪升级到完整的、层次化的、有元数据的所有权系统的关键一步。通过结构化的路径表示、增强的状态定义、和保守的合并语义，我们为 S 编译器建立了一个坚实的所有权分析基础。

**预期成果**:
- ✅ 正确处理结构体字段和数组元素的部分 move
- ✅ 支持条件分支的状态合并
- ✅ 提供详细的诊断和错误消息
- ✅ 为 CFG 分析、异常处理、loop 优化奠定基础
- ✅ 在 P0-GATE 的 6 周内完成

**关键指标**:
- 4 个模块, ~1430 行代码
- 11 个综合测试
- < 1.2x 编译时开销
- 完整的向后兼容

**里程碑**:
- Phase 2: 字段级追踪 (当前)
- Phase 3: 完整 CFG + 编译器集成 (2-3 周)
- Phase 4: 优化和高级特性 (3-4 周)
- Phase 5: 正式验证和语义闭环 (1-2 周)

总计: 6-8 周，完成 P0-GATE 的所有所有权验证。
