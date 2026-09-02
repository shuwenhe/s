# S 语言编译器优化基础设施完整实现

## 📋 概览

本实现为 S 语言编译器提供了完整的代码优化和分析基础设施。所有组件采用 S 语言编写，支持类型安全和模块化设计。

---

## 🎯 核心功能

### 1. SSA (Static Single Assignment) 形式 [ssa_complete.s]

**特性：**
- 完整 SSA 构造与转换
- 支持所有基本操作 (算术、逻辑、访存、控制流)
- Phi 函数自动插入

**关键类型：**
```s
enum value_op {
    op_const, op_param, op_phi, op_add, op_sub, op_mul, op_div,
    op_load, op_store, op_call, op_return, op_branch, ...
}

struct ssa_value {
    i32 id
    string name
    value_op op
    i32[] args
    i32 block
    string type_str
}

struct ssa_phi {
    i32 id
    i32 var_id
    i32[] block_preds
    i32[] value_preds
    string type_str
}

struct ssa_function {
    ssa_block*[] blocks
    ssa_value*[] values
    map[string]i32 name_to_value
}
```

**核心函数：**
- `new_ssa_function(name)` - 创建 SSA 函数
- `(f ssa_function*) build_ssa()` - 构建 SSA 形式
- `(f ssa_function*) eliminate_dead_code()` - 消除死代码

---

### 2. 支配树和支配前沿 [dominance.s]

**特性：**
- 计算立即支配树 (IDom)
- 支配前沿 (DF) 计算
- 严格支配关系判定
- 支配孩子集合维护

**关键结构：**
```s
struct dominator_tree {
    i32[] immediate_dominator
    i32[][] dom_children
    i32[][] dom_frontier
    i32[][] strict_dom_frontier
    bool[] computed
}
```

**核心函数：**
- `compute_dominators(preds, entry)` - 迭代数据流分析计算支配者
- `compute_dominance_frontier(succs, preds)` - 计算支配前沿用于 phi 插入
- `strictly_dominates(a, b)` - 检查严格支配关系
- `get_dominance_frontier(block)` - 获取块的支配前沿

**算法细节：**
采用迭代数据流分析，直到不动点收敛。支配前沿用于确定 phi 函数放置点。

---

### 3. 活跃性分析 [liveness_complete.s]

**特性：**
- Gen/Kill 集合计算
- Live-in/Live-out 计算
- 活跃范围追踪
- 寄存器分配辅助

**关键结构：**
```s
struct liveness_analyzer {
    liveness_info[] infos
    i32[][] gen_set      // 块生成的值
    i32[][] kill_set     // 块定义的值
}

struct liveness_info {
    i32 value_id
    bool[][] live_in
    bool[][] live_out
    live_range[] ranges
}
```

**核心函数：**
- `compute_liveness(succs)` - 计算活跃性（反向数据流）
- `is_live_at_point(value_id, block, instr)` - 查询点活跃性
- `get_live_in/out(block)` - 获取块的 live-in/live-out 集合

**应用：**
- 寄存器分配约束
- 死代码消除验证
- 指令调度优化

---

### 4. 别名分析 [alias.s]

**特性：**
- May-alias 关系追踪
- Must-alias 关系追踪
- 流敏感分析
- 指针相等性传递闭包

**关键结构：**
```s
struct alias_analysis {
    alias_relation[] relations
    i32[][] may_alias_matrix
    i32[][] must_alias_matrix
    string[] value_names
}

enum alias_kind {
    alias_none, alias_may, alias_must
}
```

**核心函数：**
- `add_may_alias(v1, v2)` - 标记可能别名
- `add_must_alias(v1, v2)` - 标记必定别名
- `may_alias(v1, v2)` - 查询别名关系
- `compute_transitive_closure()` - 计算传递闭包

**分析类型：**
- 指针相等性分析
- 指针解引用分析
- 存储操作分析
- 函数参数逃逸分析

---

### 5. 写屏障插入 [writebarrier_complete.s]

**特性：**
- 指针写屏障追踪
- 切片/数组写屏障
- 接口类型写屏障
- GC 指针追踪

**关键结构：**
```s
struct wb_inserter {
    wb_info[] barriers
    bool[] is_heap_allocated
    bool[] is_pointer_type
}

enum wb_kind {
    wb_none, wb_ptr_write, wb_slice_write, 
    wb_array_write, wb_interface_write
}
```

**核心函数：**
- `mark_heap_allocated(value)` - 标记堆分配值
- `mark_pointer_type(value)` - 标记指针类型
- `needs_write_barrier(target, value)` - 判断屏障需要
- `insert_ptr_write_barrier()` - 插入指针屏障
- `generate_barrier_call()` - 生成屏障调用代码

**运行时集成：**
调用 `runtime.write_barrier()` 用于垃圾回收跟踪。

---

### 6. 调试位置传播 [debug_loc_complete.s]

**特性：**
- 源代码位置关联
- 作用域栈维护
- DWARF 调试信息生成
- 行号映射表构建

**关键结构：**
```s
struct debug_loc_propagator {
    debug_loc_info[] loc_infos
    source_location[] file_locations
    string[] scope_stack
}

struct debug_loc_info {
    i32 instr_id
    source_location loc
    string var_name
    string scope
}

struct source_location {
    string filename
    i32 line, column
    i32 end_line, end_column
}
```

**核心函数：**
- `enter_scope(scope_name)` - 进入作用域
- `exit_scope()` - 退出作用域
- `set_location_with_range()` - 设置指令源位置
- `propagate_locations()` - 传播位置信息
- `emit_dwarf_debug_info()` - 生成 DWARF 章节
- `get_current_scope()` - 获取当前完整作用域路径

**调试支持：**
- 单步调试
- 变量检查
- 堆栈追踪精确化

---

### 7. 优化管道整合 [optimization_pipeline.s]

**特性：**
- 函数级别分析坐标
- 全流水线执行
- 分析结果缓存
- 优化通道编排

**关键类型：**
```s
struct compiler_pipeline {
    ssa_function*[] functions
    dominator_tree*[] dominators
    liveness_analyzer*[] liveness_analyses
    alias_analysis*[] alias_analyses
    wb_inserter*[] write_barriers
    debug_loc_propagator*[] debug_propagators
}
```

**核心函数：**
- `add_function(name)` - 注册函数进行优化
- `analyze_function(func_idx)` - 执行所有分析
- `run_optimization_pipeline()` - 运行完整优化流水线
- `get_*_info(func_idx)` - 查询分析结果

**执行流程：**
1. SSA 构造
2. 支配树计算
3. 活跃性分析
4. 别名分析
5. 写屏障插入
6. 调试信息传播
7. 死代码消除

---

## 📊 架构关系

```
CompilerPipeline
    ├── SSA Function Construction
    ├── Dominator Tree Analysis
    ├── Liveness Analysis
    │   └── Gen/Kill Set Computation
    ├── Alias Analysis
    │   └── May/Must Alias Matrices
    ├── Write Barrier Insertion
    │   └── Heap Tracking
    ├── Debug Location Propagation
    │   └── Scope Stack Management
    └── Optimization Passes
        ├── Dead Code Elimination
        └── Register Allocation Prep
```

---

## 🔧 使用示例

```s
// 1. 创建优化管道
pipeline := new_compiler_pipeline()

// 2. 添加函数
func := pipeline.add_function("my_function")

// 3. 构建 SSA 基本块
entry := func.new_block("entry")
block1 := func.new_block("block1")
func.add_edge(entry.id, block1.id)

// 4. 创建值
x := func.new_value(op_param, "x", "i32")
y := func.new_const_value("5", "i32")

// 5. 运行分析
pipeline.analyze_function(0)

// 6. 查询结果
liveness := pipeline.get_liveness_info(0)
dom_tree := pipeline.get_dominator_tree(0)
aliases := pipeline.get_alias_info(0)
```

---

## ✨ 关键优势

| 特性 | 优势 |
|------|------|
| **完整 SSA** | 精确数据流分析基础 |
| **支配树** | 最优 phi 函数放置 |
| **活跃性分析** | 寄存器分配约束 |
| **别名分析** | 内存操作优化 |
| **写屏障** | GC 安全性保证 |
| **调试信息** | 生产级调试支持 |
| **类型安全** | S 语言全类型检查 |

---

## 📈 性能特征

- **时间复杂度：**
  - SSA 构造: O(n)
  - 支配树: O(n²) 渐进
  - 活跃性: O(n·m) 迭代
  - 别名: O(n³) 传递闭包

- **空间复杂度：** O(n²) 用于矩阵结构

- **可优化方向：**
  - 迭代次数限制
  - 增量分析更新
  - 并行块处理

---

## 📦 文件列表

```
src/cmd/compile/internal/ir/
├── ssa_complete.s              # SSA 构造与转换
├── dominance.s                 # 支配树计算
├── liveness_complete.s         # 活跃性分析
├── alias.s                     # 别名分析
├── writebarrier_complete.s     # 写屏障插入
├── debug_loc_complete.s        # 调试位置传播
└── optimization_pipeline.s     # 优化管道整合
```

---

## 🔗 集成说明

这些模块可直接集成到 S 语言编译器：

```s
import (
    "compile.internal.ir.ssa_complete"
    "compile.internal.ir.dominance"
    "compile.internal.ir.liveness_complete"
    "compile.internal.ir.alias"
    "compile.internal.ir.writebarrier_complete"
    "compile.internal.ir.debug_loc_complete"
    "compile.internal.ir.optimization_pipeline"
)
```

---

**完成时间**: 2026-09-02  
**实现语言**: S Language  
**类型系统**: 完全类型安全  
**版本**: 1.0.0 (Production Ready)
