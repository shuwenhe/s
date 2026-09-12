# S语言 Ownership → Borrow → Drop 完整闭环实现

## 概述

本文档描述了S语言no-GC编译器中**完整的资源生命周期管理系统**的实现。这是一个**三阶段的闭环**系统：

1. **OWNERSHIP阶段** - 识别资源所有者和状态转换
2. **BORROW阶段** - 强制借用规则和生命周期约束
3. **DROP阶段** - 插入drop调用并验证exactly-once语义

---

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│         源代码AST                                            │
│     (包含所有权声明和操作)                                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  PHASE 1: OWNERSHIP │
        │   Ownership Analysis │
        └──────────┬──────────┘
                   │
          ✓ 识别所有资源所有者
          ✓ 追踪状态转换 (OWNED→MOVED→DROPPED)
          ✓ 检测use-after-move
          ✓ 检测double-move
          │
        ┌─────────▼──────────┐
        │  PHASE 2: BORROW   │
        │  Borrow Checker    │
        └──────────┬─────────┘
                   │
          ✓ 验证borrowed规则
          ✓ 强制exclusive mutable borrow
          ✓ 允许multiple shared borrow
          ✓ 检测move-while-borrowed
          ✓ 检测dangling borrow
          │
        ┌─────────▼──────────┐
        │  PHASE 3: DROP     │
        │  Drop Elaboration  │
        └──────────┬─────────┘
                   │
          ✓ 插入drop调用
          ✓ 保证exactly-once drop
          ✓ LIFO顺序 (reverse declaration)
          ✓ 验证no use-after-drop
          │
        ┌─────────▼──────────┐
        │  最终验证          │
        │ Closed Loop Check  │
        └──────────┬─────────┘
                   │
          ✓ 每个资源有所有者
          ✓ 所有借用有效
          ✓ 所有资源被清理
          │
        ┌─────────▼──────────────────┐
        │   带drop调用的最终AST      │
        │   (ready for codegen)      │
        └────────────────────────────┘
```

---

## PHASE 1: 所有权分析

### 概念

所有权系统跟踪每个变量的**所有权状态**：

| 状态 | 含义 | 转换规则 |
|------|------|--------|
| UNDEFINED | 未初始化 | 声明后→OWNED |
| OWNED | 拥有资源 | →MOVED(移动) 或 →BORROWED(借用) |
| BORROWED_SHARED | 被共享借用 | ←OWNED; →OWNED(借用结束) |
| BORROWED_MUT | 被可变借用 | ←OWNED; →OWNED(借用结束) |
| MOVED | 已移动 | 终止态 - 不能再使用 |
| DROPPED | 已销毁 | 终止态 - 不能再使用 |

### 实现

```s
type OwnershipRecord struct {
    name string                  // 变量名
    type_name string            // 类型名
    state int                   // 当前状态 (OWNED, MOVED, DROPPED等)
    declaration_order int       // 声明顺序(用于LIFO drop)
    scope_depth int            // 作用域深度
    is_param bool              // 是否为参数
}
```

### 算法

```
1. Pass 1: 收集所有变量声明
   - 为每个声明创建OwnershipRecord
   - 初始状态为OWNED
   - 记录声明顺序和作用域深度

2. Pass 2: 追踪所有权转换
   - 遍历每个语句
   - 移动操作: OWNED→MOVED
   - 借用操作: OWNED→BORROWED_*
   - 使用操作: 验证状态有效

3. 错误检测:
   - use-after-move: 使用MOVED变量 ✗
   - double-move: 两次移动同一变量 ✗
   - move-while-borrowed: 借用后移动 ✗
```

### 例子

```s
// 有效程序
var x: File = open("data.txt")  // x = OWNED
var y = x                        // x = MOVED, y = OWNED
// 不能再使用 x
// <- x.read() 会报错

// 无效程序
var x: File = open("data.txt")  // x = OWNED
var y = x                        // x = MOVED
var z = x  // ✗ ERROR: use-after-move
```

---

## PHASE 2: 借用检查

### 概念

借用系统强制**排他性可变借用**和**共享借用兼容**规则：

| 借用类型 | 数量 | 能否与其他借用共存 | 能否修改 |
|---------|-----|------------------|---------|
| 共享借用 (&T) | 多个 | ✓ 仅其他共享借用 | ✗ 只读 |
| 可变借用 (&mut T) | 最多1个 | ✗ 必须排他 | ✓ 可修改 |

### 规则

```
1. 共享借用规则 (&x):
   ✓ 可以创建多个共享借用
   ✓ 可以与其他共享借用共存
   ✗ 不能与可变借用共存
   ✗ 可变借用活跃时不能创建

2. 可变借用规则 (&mut x):
   ✓ 必须排他 - 不能有其他任何借用
   ✗ 不能与共享借用共存
   ✗ 不能重叠

3. 移动规则:
   ✗ 不能在有活跃借用时移动
   ✓ 借用结束后才能移动

4. 悬垂借用:
   ✗ 不能创建指向已销毁资源的借用
```

### 实现

```s
type BorrowRecord struct {
    borrow_var string      // 借用变量名
    source_var string      // 源变量名
    is_mutable bool        // 是否可变
    lifetime_start int     // 生命周期开始位置
    lifetime_end int       // 生命周期结束位置
    scope_depth int        // 作用域深度
}
```

### 冲突检测

```
checkBorrowCreation:
  1. 检查源变量有效 (非MOVED, 非DROPPED)
  2. 若是可变借用: 检查无其他借用
  3. 若是共享借用: 检查无可变借用
  4. 记录借用生命周期
```

### 例子

```s
// 有效: 多个共享借用
var data: Vec[int] = [1, 2, 3]
var r1 = &data     // 共享借用
var r2 = &data     // 共享借用 ✓
read(r1)
read(r2)

// 无效: 共享与可变冲突
var data: Vec[int] = [1, 2, 3]
var r = &data      // 共享借用
var w = &mut data  // ✗ ERROR: 无法创建可变借用
write(w, 42)

// 无效: 移动时还有借用
var x: File = open("file.txt")
var r = &x         // 借用中
var y = x          // ✗ ERROR: 移动时有活跃借用
```

---

## PHASE 3: Drop插入与验证

### 概念

Drop系统**自动插入清理代码**并保证**exactly-once语义**：

```
每个资源在其生命周期结束时恰好被清理一次
```

### 规则

```
1. Drop时机:
   - 块级作用域结束时
   - 函数返回前
   - 错误处理路径中

2. Drop顺序:
   - LIFO (Last In First Out)
   - 反向声明顺序
   - 确保无依赖问题

3. Drop保证:
   ✓ 每个资源恰好drop一次
   ✓ 不能use-after-drop
   ✓ 不能double-drop
   ✓ 移动后不drop原始所有者
```

### 实现

```s
type DropRecord struct {
    variable string            // 变量名
    type_name string          // 类型名
    has_drop_impl bool        // 是否有Drop trait
    drop_fn string            // Drop函数名
    fields []string           // 字段列表(用于部分移动)
    field_drop_order []string // 字段drop顺序
}
```

### 算法

```
1. 构建Drop注册表:
   - 为每个变量创建DropRecord
   - 跳过已MOVED的变量 (所有权已转移)
   - 获取Drop函数名 (__s_drop_TypeName)

2. 排序:
   - 按反向声明顺序排序 (LIFO)
   - 确保依赖关系正确

3. 插入Drop调用:
   - 块结束时插入
   - 返回前插入
   - 错误路径插入

4. 验证:
   - 无use-after-drop
   - 无double-drop
   - 所有资源都被drop
```

### 例子

```s
func process() {
    var f: File = open("data.txt")      // 声明1
    var lines: Vec[string] = []         // 声明2
    
    // 使用资源...
    
    // 块结束: 自动插入drops
    // 因为声明顺序: f先, lines后
    // Drop顺序: LIFO = lines, 然后 f
    
    // 生成的drop代码:
    //   __s_drop_Vec(&lines)
    //   __s_drop_File(&f)
}
```

---

## 闭环验证

### 完整性检查

```s
func verify_closed_loop() bool:
    Check 1: 每个变量都有所有者
        ✓ 没有UNDEFINED变量
        ✓ 没有orphan资源
    
    Check 2: 没有use-after-move
        ✓ MOVED和OWNED互斥
        ✓ MOVED变量没有后续操作
    
    Check 3: 没有悬垂借用
        ✓ 所有借用都有lifetime_end
        ✓ 没有指向DROPPED资源的借用
    
    Check 4: 所有资源都被drop
        ✓ 所有OWNED变量都在drop_registry
        ✓ 没有泄漏的资源
    
    所有检查通过 → 资源安全 ✓
```

### 三阶段管道

```s
analyze_complete(stmts):
    1. phase_ownership_analyze(stmts)
       └─> 失败? 返回错误
    
    2. phase_borrow_check(stmts)
       └─> 失败? 返回错误
    
    3. phase_drop_elaboration(stmts)
       └─> 生成带drop调用的AST
    
    4. verify_closed_loop()
       └─> 失败? 返回错误
    
    所有通过 → 返回elaborated AST + drop_order
```

---

## 测试覆盖

### 核心测试

| 测试名称 | 覆盖范围 | 预期结果 |
|---------|---------|--------|
| test_basic_ownership | 单一所有者 | ✓ PASS |
| test_use_after_move_error | 使用后移动检测 | ✓ 正确拒绝 |
| test_shared_borrow | 多个共享借用 | ✓ PASS |
| test_mutable_borrow_conflict | 可变冲突检测 | ✓ 正确拒绝 |
| test_basic_drop_insertion | drop插入 | ✓ drop被插入 |
| test_drop_lifo_order | drop顺序 | ✓ LIFO顺序正确 |
| test_complete_pipeline_valid | 完整有效程序 | ✓ PASS |
| test_complete_pipeline_invalid | 完整无效程序 | ✓ 正确拒绝 |
| test_borrow_ends_before_move | 借用→drop→move | ✓ PASS |
| test_move_while_borrowed_error | 借用时移动 | ✓ 正确拒绝 |

---

## 集成与代码生成

### 编译器集成点

```
Frontend (解析):
  ↓
类型检查:
  ↓
[所有权→借用→Drop分析] ← 本系统
  ├─ phase_ownership_analyze()
  ├─ phase_borrow_check()
  ├─ phase_drop_elaboration()
  └─ verify_closed_loop()
  ↓
MIR生成 (Drop调用已插入):
  ↓
后端代码生成:
  ↓
链接 + 运行
```

### AST转换

```
输入 AST:
  func process() {
    var x: File = ...
    use(x)
  }

↓ 经过三阶段分析

输出 AST (带drop调用):
  func process() {
    var x: File = ...
    use(x)
    __s_drop_File(&x)
  }
```

---

## 性能特性

### 时间复杂度

| 操作 | 复杂度 | 备注 |
|------|-------|------|
| 所有权分析 | O(n) | n = 语句数 |
| 借用检查 | O(n*b) | b = 最大借用数 |
| Drop插入 | O(n*d) | d = 最大变量数 |
| 闭环验证 | O(v+b) | v = 变量数, b = 借用数 |
| **总计** | **O(n*max(b,d))** | 实际很快 |

### 空间复杂度

| 数据结构 | 复杂度 | 用途 |
|---------|-------|------|
| variableOwners | O(v) | 变量记录 |
| borrowed_set | O(v*b) | 借用追踪 |
| drop_registry | O(v) | Drop信息 |
| **总计** | **O(v*(1+b))** | 实际很小 |

---

## 典型资源生命周期

### 案例1: 简单文件处理

```s
func read_file(path: string) string {
    var file: File = open(path)         // 状态: OWNED
    var content = file.read_all()       // 借用file
    println(content)
    
    // 块结束 → 自动drop
    // 最后一步: __s_drop_File(&file)
}
```

**状态追踪:**
```
文件对象:
  打开 → OWNED (file) 
  读取 → BORROWED_SHARED (read_all中)
  借用结束 → OWNED
  块结束 → DROP
```

### 案例2: 所有权转移

```s
func process_data() {
    var source: Vec[int] = parse_input()   // OWNED
    var dest = source                       // MOVED
    
    // 不能再使用 source
    transform(dest)
    
    // 块结束: 只drop dest (source已MOVED)
    // __s_drop_Vec(&dest)
}
```

**状态追踪:**
```
source:
  解析 → OWNED
  赋值 → MOVED
  (不drop source, 因为已转移)

dest:
  赋值 → OWNED
  块结束 → DROP
  __s_drop_Vec(&dest)
```

### 案例3: 多变量LIFO顺序

```s
func multi_resources() {
    var a: File = open("a.txt")         // 声明1
    var b: Socket = connect("localhost") // 声明2
    var c: Stream = make_stream()        // 声明3
    
    // 块结束: LIFO drop
    // 1. __s_drop_Stream(&c)     (最后声明)
    // 2. __s_drop_Socket(&b)     (中间声明)
    // 3. __s_drop_File(&a)       (最先声明)
}
```

---

## 关键优势

### 1. **内存安全**
- ✓ 无悬垂指针
- ✓ 无use-after-free
- ✓ 无double-free
- ✓ 无数据竞争

### 2. **确定性**
- ✓ 无GC暂停
- ✓ 确定的资源释放时机
- ✓ 可预测的内存使用

### 3. **性能**
- ✓ 零运行时开销 (drop在编译时计算)
- ✓ LIFO顺序最小化依赖问题
- ✓ 快速的闭环验证

### 4. **调试友好**
- ✓ 清晰的错误信息
- ✓ 精确的位置信息 (PC location)
- ✓ 完整的生命周期追踪

---

## 文件结构

```
src/cmd/compile/internal/ownership/
├── ownership_drop_closure.s           ← 核心三阶段管道
├── ownership_drop_closure_test.s      ← 完整测试套件
├── ownership_analysis.s               ← 原始分析器
├── borrow_checker.s                   ← 原始借用检查
├── move_checker.s                     ← 原始移动检查
└── drop_elaboration.s                 ← 原始drop插入
```

---

## 使用示例

### 集成到编译器

```s
// 在编译器中使用
func compile_function(func_ast *FunctionDef) bool {
    // 创建上下文
    ctx := new_ownership_drop_context()
    
    // 运行完整分析管道
    result := ctx.analyze_complete(func_ast.body)
    
    if !result.success {
        // 报错
        for _, err := range result.errors {
            report_error(err)
        }
        return false
    }
    
    // 使用带drop调用的AST继续编译
    return codegen(result.elaborated_stmts)
}
```

---

## 总结

S语言的**Ownership → Borrow → Drop完整闭环**实现了：

1. **三阶段分析**: 所有权 → 借用 → Drop
2. **完整验证**: 闭环检查确保资源安全
3. **自动化**: 编译器自动插入cleanup代码
4. **确定性**: 无GC暂停, 确定的资源生命周期
5. **性能**: 零运行时开销, O(n)时间复杂度

这是S语言no-GC编译器的**核心优势**，提供了**Rust级别的内存安全**和**C级别的性能**。
