# Go vs S 编译器核心功能对标分析

**分析日期**: 2026-09-02  
**目标**: 系统性列出 Go 有而 S 需要补完的核心功能

---

## 总体规模对比

| 指标 | Go | S 当前 | S 目标 | 差距 |
|------|-----|--------|--------|------|
| **代码行数** | 714K | 42K | 280K | 6.5× |
| **模块数** | 45+ | ~50 | 200+ | 对齐中 |
| **SSA 模块** | 14.5K | 7K | 15K | 2× |
| **后端模块** | 10K | 3.3K | 10K | 3× |
| **Walk/优化** | 10K | 2K | 10K | 5× |

---

## 关键功能对标

### 1️⃣ 前端 (Lexer/Parser/TypeCheck)

#### Go 的实现
```
syntax/          → 3K LOC
├─ lexer
├─ parser
├─ source
└─ operators

types/           → 2K LOC
├─ type.go
├─ type_hash.go
└─ ...

types2/          → 5K LOC (类型检查器 - 完整)
typecheck/       → 6K LOC (约束传播)
```

#### S 的实现
```
syntax/          → ~2K LOC ✅
├─ lexer.s       (完整)
└─ parser.s      (完整)

types/           → ~1K LOC ⚠️
├─ type.s        (基础)
└─ (缺少详细实现)

semantic.s       → ~3K LOC ⚠️ (需完善)
```

#### **S 缺失的功能**
- ❌ **完整的类型推导系统** (type inference)
- ❌ **泛型类型参数处理** (generic type params)
- ❌ **接口隐式满足验证** (interface satisfaction)
- ❌ **方法集计算** (method set computation)
- ❌ **约束解决器** (constraint solver) - 用于泛型/接口
- ⚠️ **类型别名处理** (type alias)
- ⚠️ **嵌入类型的方法继承** (embedded type method inheritance)
- ⚠️ **循环依赖检测** (circular dependency detection)

**优先级**: 🔴 HIGH
**Gate**: A (Bootstrap Language Closure)

---

### 2️⃣ IR 和 Semantic 分析

#### Go 的实现
```
ir/              → 2K LOC (IR 节点定义)
├─ node.go       (所有 Op 类型)
├─ method.go     (方法处理)
└─ ...

noder/           → 4K LOC (AST → IR 转换)
typecheck/       → 6K LOC (类型检查)
```

#### S 的实现
```
ir/              → ~2K LOC ✅
└─ ir.s          (基本节点定义)

semantic.s       → ~3K LOC ⚠️
└─ (框架完整，实现不完整)

noder/           → ~1K LOC ⚠️
└─ (部分实现)
```

#### **S 缺失的功能**
- ❌ **完整的 IR 节点类型** - Go 有 50+ 种 Op，S 不完整
- ❌ **符号表完整管理** (symbol table w/ scope management)
- ❌ **生存性分析** (liveness analysis in semantic)
- ❌ **未初始化变量检测** (uninitialized variable detection)
- ❌ **死代码检测** (dead code detection - semantic phase)
- ❌ **类型宽度和对齐计算** (type width/alignment calculation)
- ⚠️ **方法绑定** (method binding to types)
- ⚠️ **函数签名规范化** (function signature normalization)

**优先级**: 🔴 HIGH
**Gate**: C (Typed IR Closure)

---

### 3️⃣ ABI 和调用约定

#### Go 的实现
```
abi/             → 专门的 ABI 定义模块
├─ amd64.go      (x86-64 ABI)
├─ arm64.go      (ARM64 ABI)
├─ types.go      (ABI 类型映射)
└─ ...

ssagen/          → 17K LOC
├─ call.go       (调用规约生成)
├─ param.go      (参数处理)
└─ ...
```

#### S 的实现
```
abi/             → 存在但基础
├─ x86_64.s      (骨架)
└─ (不完整)

backend/         → 3.3K LOC
└─ (ABI 处理分散在各处)
```

#### **S 缺失的功能**

这是 **最关键的 Gate D** 问题：

- ❌ **完整的参数传递规范** 
  ```
  当前: 基本 int/string 支持
  缺失: 
  • struct 参数 ABI
  • array 参数传递
  • >6 words 栈参数完整支持
  • 参数对齐规则 (16-byte stack alignment)
  ```

- ❌ **多返回值 ABI**
  ```
  当前: (int, int) → RAX/RDX
  缺失:
  • struct 返回
  • >2 words 返回值
  • return value 内存布局
  ```

- ❌ **Intrinsic 调用约定**
  ```
  缺失:
  • syscall ABI
  • malloc/free 的参数/返回约定
  • panic/recover frame layout
  • defer 的栈处理
  ```

- ❌ **寄存器约定**
  ```
  缺失:
  • Caller-save vs Callee-save
  • 固定寄存器 (SP, BP)
  • 浮点寄存器 (XMM) ABI
  • 红区 (red zone) 管理
  ```

- ❌ **栈对齐和帧布局**
  ```
  缺失:
  • 进入函数时 RSP 对齐检查
  • 返回地址位置
  • 局部变量排列
  • 参数传递区 (home location)
  ```

- ❌ **两字值 (two-word) 的精确处理**
  ```
  当前: string = (data, len) 基本支持
  缺失:
  • interface = (type, value)
  • slice = (data, len, cap)
  • 在调用中的 ABI
  • 在栈上的布局
  ```

**优先级**: 🔴 CRITICAL
**Gate**: D (ABI Closure)  
**这是 stage2 SIGSEGV 最可能的根源**

---

### 4️⃣ SSA 优化规则

#### Go 的实现
```
ssa/_gen/AMD64.rules     → 126K (126,863 bytes)
ssa/_gen/ARM64.rules     → 112K (112,836 bytes)
ssa/_gen/generic.rules   → (通用规则)

生成的代码:
ssa/rewrite.go          → 41K LOC

总共: 13,711 条规则分布在:
• 通用规则: 1,044 条
• AMD64: 2,500+ 条
• ARM64: 2,200+ 条
• 其他: 7,000+ 条
```

#### S 的实现
```
ssa/                    → 7K LOC
└─ (规则不完整，大多数是框架)

backend/rules_generic.s → <100 条规则
```

#### **S 缺失的功能**

- ❌ **规则定义 DSL**
  ```
  Go: 使用 .rules 文件 + code generator
  S:  需要类似的系统性定义和生成机制
  ```

- ❌ **常数折叠规则** (~100 条)
  ```
  缺失:
  • (Add (Const a) (Const b)) → (Const (a+b))
  • (Mul x (Const 0)) → (Const 0)
  • (And x x) → x
  • 所有基本算术/逻辑常数求值
  ```

- ❌ **代数化简规则** (~200 条)
  ```
  缺失:
  • (Mul x (Const 2^n)) → (Shl x n)
  • (Div x (Const 2^n)) → (Shr x n)
  • (Add x (Const 0)) → x
  • 指数和位操作优化
  ```

- ❌ **条件分支优化** (~100 条)
  ```
  缺失:
  • if (Const true) → 删除分支
  • if (Const false) → 只执行 else
  • 分支合并
  ```

- ❌ **全局值编号 (GVN)** (~300 条)
  ```
  缺失:
  • 重复表达式消除
  • 值哈希表
  • 等价性分析
  ```

- ❌ **循环不变式提升 (LICM)** (~200 条)
  ```
  缺失:
  • 环不变式识别
  • 安全提升判断
  • 支配关系分析
  ```

- ❌ **死代码消除 (DCE)** (~300 条)
  ```
  缺失:
  • 活跃性分析
  • 无用指令删除
  • 写后覆盖检测
  ```

- ❌ **架构特定规则** (6000+ 条)
  ```
  缺失 x86-64:
  • 寻址模式优化 (500条)
  • 指令选择 (1000条)
  • 操作数大小选择 (500条)
  • 位操作特化 (300条)
  • 浮点特化 (200条)
  
  缺失 ARM64:
  • NEON 向量指令 (200条)
  • ARM64 特定寻址 (400条)
  • 条件执行 (200条)
  ```

**优先级**: 🟡 MEDIUM
**Gate**: 优化优先级，自举后处理

---

### 5️⃣ 中端优化

#### Go 的实现
```
walk/            → 10K LOC
├─ walk.go       (树遍历变换)
└─ ...

inline/          → 1.4K LOC
├─ inl.go        (内联分析)
└─ inlheur/      (内联启发式)

escape/          → 3.6K LOC
└─ escape.go     (逃逸分析)

devirtualize/    → 专门模块
liveness/        → 2K LOC
```

#### S 的实现
```
walk/            → ~0.1K LOC ⚠️ (几乎没有)
inline/          → ~0.3K LOC ⚠️ (基础)
escape/          → ~0.3K LOC ⚠️ (基础)
middleend/       → ~2K LOC ⚠️ (框架)
```

#### **S 缺失的功能**

- ❌ **树遍历和转换系统** (Walk)
  ```
  缺失:
  • 完整的 AST 树遍历
  • 类型转换和下沉
  • 表达式简化 (Simplify)
  • 块内语句重排
  ```

- ❌ **内联系统** (~1.4K LOC)
  ```
  缺失:
  • 大小估计 (function size estimation)
  • 代价分析 (cost analysis)
  • 内联启发式 (inlining heuristics)
  • 链式内联 (iterative inlining)
  • 内联限制管理
  ```

- ❌ **逃逸分析** (~3.6K LOC)
  ```
  缺失:
  • 指针追踪
  • 栈 vs 堆分配决策
  • 不逃逸优化
  • 指针活性分析
  ```

- ❌ **死局部变量消除** (deadlocals)
  ```
  缺失:
  • 局部变量活跃性
  • 无用变量删除
  ```

- ❌ **虚拟方法去虚化** (devirtualize)
  ```
  缺失:
  • 接口类型缩减
  • 直接调用替换
  ```

- ❌ **范围函数支持** (rangefunc)
  ```
  S 语言可能不支持这个特性
  ```

**优先级**: 🟡 MEDIUM
**Gate**: 优化优先级

---

### 6️⃣ 寄存器分配

#### Go 的实现
```
ssa/regalloc.go      → Go 源码 (复杂)
包含:
• 生存范围构造 (live range)
• 干涉图构造 (interference graph)
• 图着色分配 (graph coloring)
• 溅出处理 (spill handling)
• 寄存器分配策略
```

#### S 的实现
```
backend/register_allocator.s → 基础实现
ssa/allocators.s              → 分配器框架
(代码不完整)
```

#### **S 缺失的功能**

- ❌ **生存范围构造** (Live Range)
  ```
  缺失:
  • 生存范围追踪
  • 跨基本块生存性
  • 范围表示
  ```

- ❌ **干涉图** (Interference Graph)
  ```
  缺失:
  • 图构造算法
  • 冲突检测
  • 图着色前准备
  ```

- ❌ **图着色分配** (Graph Coloring)
  ```
  当前: 线性扫描 (linear scan)
  缺失:
  • 图着色算法 (graph coloring algorithm)
  • 贪心着色 (greedy coloring)
  • 着色启发式
  • 寄存器数量约束
  ```

- ❌ **溅出处理** (Spill)
  ```
  缺失:
  • 溅出位置选择
  • 代价分析
  • Spill code 生成
  • 重新加载优化
  ```

- ❌ **两字值处理**
  ```
  缺失:
  • string, slice, interface 的寄存器对处理
  • 成对寄存器约束
  ```

- ❌ **固定寄存器处理**
  ```
  缺失:
  • 系统调用寄存器
  • 参数寄存器约束
  • 返回值寄存器约束
  ```

**优先级**: 🔴 HIGH
**Gate**: F (Stage2 Executable)

---

### 7️⃣ 栈帧管理和 Liveness

#### Go 的实现
```
ssa/stackalloc.go    → 栈分配
ssa/liveness.go      → Liveness 分析

包含:
• Liveness 数据流分析
• 栈位置分配
• 同时活跃变量识别
• 栈复用优化
• 指针活性 (GC root)
```

#### S 的实现
```
backend/liveness_analysis.s → 基础实现
backend/stack_frame.s        → 基础实现
(不完整)
```

#### **S 缺失的功能**

- ❌ **Liveness 分析**
  ```
  缺失:
  • 定义集合 (Def)
  • 使用集合 (Use)
  • 活跃入口 (LiveIn)
  • 活跃出口 (LiveOut)
  • 数据流方程求解
  ```

- ❌ **栈位置复用**
  ```
  缺失:
  • 同时活跃集合识别
  • 栈位置冲突图
  • 位置分配 (bin-packing)
  • 栈帧减少 20-30%
  ```

- ❌ **栈帧布局** (stack frame layout)
  ```
  缺失:
  • 参数区 (argument home)
  • 返回地址
  • 被调用者保存寄存器
  • 局部变量区
  • 对齐计算
  ```

- ❌ **指针活性** (pointer liveness)
  ```
  缺失:
  • 哪些栈位置是指针
  • GC root 扫描
  • 位图生成
  ```

**优先级**: 🔴 HIGH
**Gate**: D (ABI Closure) / F (Stage2)

---

### 8️⃣ 代码生成和后端

#### Go 的实现
```
amd64/           → 7.7K LOC (x86-64)
├─ asm.go        (指令生成)
├─ reg.go        (寄存器定义)
└─ ...

arm64/           → 3.7K LOC (ARM64)
...

objw/            → 目标文件生成
dwarfgen/        → DWARF 调试信息
```

#### S 的实现
```
backend/         → 3.3K LOC
├─ codegen_x86_64.s (x86-64 生成)
├─ elf64_gen.s      (ELF 生成)
└─ ...
```

#### **S 缺失的功能**

- ❌ **指令选择** (Instruction Selection)
  ```
  缺失:
  • SSA → machine code 映射
  • 复杂指令选择
  • 操作数大小选择
  • 寻址模式利用
  ```

- ❌ **寻址模式优化**
  ```
  缺失:
  • x86-64 SIB (scale-index-base)
  • 复杂寻址模式识别
  • 内存操作优化
  ```

- ❌ **调用序列生成**
  ```
  缺失:
  • 函数序言 (prologue) 完整性
  • 函数尾声 (epilogue) 完整性
  • 寄存器保存/恢复
  • 栈指针调整
  ```

- ❌ **浮点支持**
  ```
  缺失:
  • 浮点指令 (ADDSD, SUBSD 等)
  • 浮点 ABI
  • 浮点寄存器分配
  ```

- ❌ **SIMD 支持**
  ```
  缺失:
  • SSE/AVX 指令
  • 向量类型 ABI
  • 向量优化规则
  ```

- ❌ **符号解析和重定位**
  ```
  缺失:
  • 外部符号引用
  • PC 相对重定位
  • GOT (Global Offset Table)
  • PLT (Procedure Linkage Table)
  ```

- ❌ **PIC/PIE 支持** (Position Independent)
  ```
  缺失:
  • 地址无关代码生成
  • 重定位信息
  • ASLR 支持
  ```

- ❌ **DWARF 调试信息** (~3K LOC)
  ```
  缺失:
  • 源行号映射
  • 变量位置信息
  • 类型描述
  • 调试符号表
  ```

**优先级**: 🔴 HIGH
**Gate**: G (Stage2 → Stage3)

---

### 9️⃣ 链接和程序集成

#### Go 的实现
```
cmd/link/        → 链接器 (Go)
包含:
• 符号解析
• 重定位
• 动态链接
• 调试信息合并
```

#### S 的实现
```
backend/linker.s → 基础框架
(依赖外部 ld/gcc)
```

#### **S 缺失的功能**

- ❌ **自托管链接器**
  ```
  当前: 依赖 gcc/ld
  缺失: 纯 S 链接器
  ```

- ❌ **符号表管理**
  ```
  缺失:
  • 全局符号表
  • 符号导出/导入
  • 符号版本管理
  ```

- ❌ **重定位处理** (Relocation)
  ```
  缺失:
  • PC 相对重定位
  • 绝对地址重定位
  • GOT 重定位
  • PLT 生成
  ```

- ❌ **动态链接** (shared object)
  ```
  缺失:
  • .so/.dylib 生成
  • C ABI 兼容性
  • 符号可见性
  ```

- ❌ **打包和构建** (multi-file)
  ```
  缺失:
  • 多文件编译链接
  • 静态库生成
  • 链接顺序管理
  ```

**优先级**: 🟡 MEDIUM
**Gate**: H (Stage3 → Stage4)

---

## 优先级排序 (按 Bootstrap Gate)

### Gate A-E (Bootstrap Closure, Week 1-10)

| 功能 | 重要性 | 当前状态 | 目标完成 |
|------|--------|---------|---------|
| 语言子集编译 | 🔴 | 50% | Week 2 |
| ABI 完整性 | 🔴 | 30% | Week 6 |
| Runtime (malloc/string/syscall) | 🔴 | 50% | Week 10 |
| 参数/返回 ABI | 🔴 | 40% | Week 6 |
| 栈帧布局 | 🔴 | 30% | Week 8 |

### Gate F-H (Self-Host Closure, Week 11-16)

| 功能 | 重要性 | 当前状态 | 目标完成 |
|------|--------|---------|---------|
| 指令生成 | 🔴 | 40% | Week 12 |
| 寄存器分配 | 🔴 | 20% | Week 14 |
| Liveness 分析 | 🔴 | 20% | Week 13 |
| 目标文件生成 | 🟡 | 50% | Week 14 |

### 优化 (Week 17+)

| 功能 | 重要性 | 当前状态 | 目标完成 |
|------|--------|---------|---------|
| SSA 规则 (500) | 🟡 | 10% | Week 18 |
| SSA 规则 (1500) | 🟡 | 10% | Week 20 |
| 内联/逃逸 | 🟡 | 5% | Week 22 |
| DWARF 信息 | 🟢 | 5% | Week 24 |

---

## 立即应该修复的 Top 5

| 优先级 | 功能 | 缺失程度 | 工作量 | 影响 |
|--------|------|---------|--------|------|
| 🔴 1 | ABI 完整性测试 | 70% | 2 周 | Gate D |
| 🔴 2 | Intrinsic 调用约定 | 80% | 1 周 | Stage2 稳定 |
| 🔴 3 | 栈帧布局精确 | 70% | 2 周 | Gate F |
| 🔴 4 | 寄存器分配图着色 | 80% | 3 周 | 性能 |
| 🔴 5 | Liveness 分析 | 80% | 2 周 | 栈优化 |

---

## 关键观察

### 最容易被忽视的缺陷

1. **ABI 不完整** (Gate D)
   - 这是 stage2 段错误的最可能根源
   - S 当前的 ABI 实现只有 30-40% 完整
   - 需要系统的 ABI test matrix

2. **Liveness 分析缺失** 
   - 影响栈帧优化
   - 影响寄存器分配
   - 影响 GC 根追踪

3. **指令选择基础**
   - S 的代码生成很原始
   - 没有系统的指令选择机制
   - 每个操作几乎都是硬编码

### 最耗时的补完工作

1. **SSA 规则库** (8000+ 条)
   - 需要规则 DSL + 代码生成
   - 但这是优化问题，不是自举必需

2. **多架构支持** (ARM64 等)
   - 规模大但可逐步进行
   - 应该在 Gate H 后处理

3. **DWARF 调试信息**
   - 重要但不阻塞自举
   - 可以最后处理

---

## 建议行动顺序

```
Week 1-2:  诊断 + ABI 建立
Week 3-6:  ABI test suite + Intrinsic 修复
Week 7-10: 运行时完整 + 栈帧精确
Week 11-14: 指令生成 + 寄存器分配
Week 15-16: Liveness + 栈优化
Week 17-18: 基础 SSA 规则
Week 19-22: 中端优化 (可选)
Week 23-24: 完善和验证
```

这个顺序以**闭合为首要目标**，而不是性能优化。

