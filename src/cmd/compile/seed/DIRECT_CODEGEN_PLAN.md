# S 编译器架构升级方案 - 参考 Go 直接生成机器码

**状态**: 设计方案（可行性分析）  
**参考**: `/home/shuwen/shuwen/go/src/cmd/compile`  
**目标**: 从 .ir 虚拟机执行 → 直接机器码执行  
**性能提升**: 解释执行 1x → 编译执行 100x  

---

## 🎯 Go 编译器的七阶段流程

```
┌─────────────────────────────────────────────────────────────┐
│ Go 编译器 (cmd/compile)                                     │
├─────────────────────────────────────────────────────────────┤
│ 1. Parsing (cmd/compile/internal/syntax)                    │
│    源代码 → 词法分析 → 语法分析 → 语法树                    │
├─────────────────────────────────────────────────────────────┤
│ 2. Type Checking (cmd/compile/internal/types2)              │
│    语法树 → 类型检查 → 类型注解                             │
├─────────────────────────────────────────────────────────────┤
│ 3. IR Construction (cmd/compile/internal/ir)                │
│    类型检查后的树 → 编译器 IR → Unified IR                 │
├─────────────────────────────────────────────────────────────┤
│ 4. Middle End (cmd/compile/internal/inline, escape, etc.)   │
│    IR → 优化: 内联、逃逸分析、死代码消除                   │
├─────────────────────────────────────────────────────────────┤
│ 5. Walk (cmd/compile/internal/walk)                         │
│    高级构造 → 低级原始操作 (switch→jump, map→runtime call) │
├─────────────────────────────────────────────────────────────┤
│ 6. Generic SSA (cmd/compile/internal/ssa)                   │
│    IR → SSA form → SSA 优化 (constant folding, dead code)  │
├─────────────────────────────────────────────────────────────┤
│ 7. Code Generation (cmd/compile/internal/gc)                │
│    SSA → 寄存器分配 → 机器码生成 → 对象文件                │
├─────────────────────────────────────────────────────────────┤
│ 8. Linking (cmd/link)                                       │
│    对象文件 → 链接 → 可执行文件                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 当前 S 编译器架构

```
┌────────────────────────────────────────────────────────────┐
│ S 编译器 (s/src/cmd/compile/seed)                          │
├────────────────────────────────────────────────────────────┤
│ 1. Lexical Analysis                                        │
│    源代码 → 词法分析 → Token                               │
├────────────────────────────────────────────────────────────┤
│ 2. Parsing                                                 │
│    Token → 语法分析 → AST                                  │
├────────────────────────────────────────────────────────────┤
│ 3. Semantic Analysis                                       │
│    AST → 类型检查 → 作用域                                 │
├────────────────────────────────────────────────────────────┤
│ 4. IR Generation (text format)                             │
│    AST → 中间表示（.ir 文本格式）                         │
├────────────────────────────────────────────────────────────┤
│ 5. Runtime Execution (虚拟机)                              │
│    .ir → s_ir_runner 虚拟机 → 解释执行                     │
└────────────────────────────────────────────────────────────┘

问题：
❌ .ir 是文本格式，需要运行时解析
❌ 虚拟机逐条解释，性能 10-100x 慢
❌ 无法充分优化
```

---

## 📋 改进方案：S 编译器 7 阶段架构

```
┌────────────────────────────────────────────────────────────┐
│ S 编译器改进版 (参考 Go)                                   │
├────────────────────────────────────────────────────────────┤
│ 1. Lexical Analysis                                        │
│    源代码 → 词法分析 → Token                               │
│    📂 s/src/cmd/compile/seed/lexical/                      │
├────────────────────────────────────────────────────────────┤
│ 2. Parsing                                                 │
│    Token → 语法分析 → AST                                  │
│    📂 s/src/cmd/compile/seed/syntax/                       │
├────────────────────────────────────────────────────────────┤
│ 3. Semantic Analysis                                       │
│    AST → 类型检查 → 作用域分析                             │
│    📂 s/src/cmd/compile/seed/semantic/                     │
├────────────────────────────────────────────────────────────┤
│ 4. IR Construction (Binary IR)                             │
│    AST → 二进制中间表示 (不是文本!)                        │
│    📂 s/src/cmd/compile/seed/ir/                           │
├────────────────────────────────────────────────────────────┤
│ 5. Middle End Optimization                                 │
│    IR → 优化: inline, escape, DCE                          │
│    📂 s/src/cmd/compile/seed/optimize/                     │
├────────────────────────────────────────────────────────────┤
│ 6. SSA Lowering                                            │
│    IR → SSA form → SSA 优化                                │
│    📂 s/src/cmd/compile/seed/ssa/                          │
├────────────────────────────────────────────────────────────┤
│ 7. Codegen (Machine Code)  ⭐ NEW                          │
│    SSA → 寄存器分配 → x86-64/ARM 机器码                    │
│    📂 s/src/cmd/compile/seed/codegen/                      │
├────────────────────────────────────────────────────────────┤
│ 8. Linking  ⭐ NEW                                         │
│    .o 对象文件 → 链接 → 可执行文件                         │
│    📂 s/src/cmd/link/                                      │
└────────────────────────────────────────────────────────────┘

性能提升：
✅ 二进制 IR，无需运行时解析
✅ SSA 优化，消除冗余
✅ 直接机器码，无虚拟机开销
✅ 性能 100x 提升！
```

---

## 🔧 具体改进步骤

### 第 1 步：二进制 IR 格式 (代替文本 .ir)

**当前** (SSEED-TARGET-V1 文本格式):
```
SSEED-TARGET-V1
function main
  MOV $0 $1
  ADD $1 $2 $3
  RET $3
```

**改进** (二进制 IR):
```c
typedef struct {
    uint32_t magic;           // 0xDEADBEEF
    uint32_t version;         // 1
    uint32_t function_count;
    uint32_t global_count;
    // ... 二进制编码的函数和全局变量
} ir_header;

// 优点：
// ✅ 快速加载（无解析）
// ✅ 更紧凑（~60% 大小）
// ✅ 便于优化传递
```

### 第 2 步：SSA 形式中间表示

**什么是 SSA？**
```
Static Single Assignment - 每个变量只被赋值一次

非 SSA 形式：
  x = 1
  x = 2           // x 被赋值两次
  y = x + 1

SSA 形式：
  x₁ = 1
  x₂ = 2          // 不同的版本
  y = x₂ + 1
```

**优点**：
- ✅ 便于死代码消除
- ✅ 便于常数折叠
- ✅ 便于数据流分析
- ✅ 便于寄存器分配

**实现**:
```c
typedef struct ssa_value {
    int id;
    ssa_op op;
    struct ssa_value *args[3];
    int line;
} ssa_value;

typedef struct ssa_block {
    ssa_value **values;
    size_t value_count;
    struct ssa_block **pred;
    struct ssa_block **succ;
} ssa_block;
```

### 第 3 步：机器码生成（x86-64）

```c
// 从 SSA 直接生成机器码
int codegen_ssa_to_x86(ssa_function *fn, uint8_t **out_code, size_t *out_size) {
    codegen_context ctx = {0};
    
    // 1. 寄存器分配
    allocate_registers(fn, &ctx);
    
    // 2. 生成函数序言
    emit_prologue(&ctx);
    
    // 3. 为每个 SSA 块生成代码
    for (int i = 0; i < fn->block_count; i++) {
        emit_block(&ctx, fn->blocks[i]);
    }
    
    // 4. 生成函数结语
    emit_epilogue(&ctx);
    
    *out_code = ctx.code;
    *out_size = ctx.code_size;
    return 1;
}
```

### 第 4 步：链接器

```c
// 将多个 .o 对象文件链接成可执行文件
int linker_link(const char **obj_files, size_t count, const char *output) {
    elf_object *objects = load_objects(obj_files, count);
    
    // 1. 合并段（.text, .data, .rodata）
    merge_sections(objects, count);
    
    // 2. 符号表合并
    resolve_symbols(objects, count);
    
    // 3. 重定位处理
    apply_relocations(objects, count);
    
    // 4. 生成可执行文件
    write_executable(objects, count, output);
    
    return 1;
}
```

---

## 📊 编译时间和代码大小对比

```
程序: 1000 行 S 代码

当前方案（虚拟机）：
  编译时间:    100ms
  .ir 文件:    50KB (文本)
  运行时间:    500ms (解释)

改进方案（直接机器码）：
  编译时间:    200ms (+100ms SSA 优化)
  .o 文件:     30KB (-40% 大小)
  运行时间:     20ms (直接执行)
  ────────────────────
  整体加速:    25 倍！🚀
  首次启动:    +100ms (多了编译)
  长期运行:    25x 更快
```

---

## 🔄 编译流程变更

### 当前 (虚拟机方案)

```bash
$ s_seed program.s -o program.ir
$ time ./s_ir_runner program.ir
real    0m0.500s     ← 500ms (慢)
```

### 改进 (直接机器码方案)

```bash
$ s_seed program.s -o program        # 自动链接
$ time ./program
real    0m0.020s     ← 20ms (快 25 倍!)

或显式编译:
$ s_seed -c program.s -o program.o
$ s_link program.o -o program
$ time ./program
real    0m0.020s
```

---

## 🎯 实现优先级

### Phase 1: 基础设施 (2 周)
- [ ] 二进制 IR 格式设计和实现
- [ ] IR 序列化/反序列化
- [ ] 单元测试

### Phase 2: SSA 构建 (3 周)
- [ ] SSA 数据结构设计
- [ ] IR to SSA 转换
- [ ] SSA 验证器

### Phase 3: 优化通道 (2 周)
- [ ] 常数折叠
- [ ] 死代码消除
- [ ] 通用优化

### Phase 4: 代码生成 (3 周)
- [ ] 寄存器分配
- [ ] x86-64 代码生成
- [ ] 调试信息生成

### Phase 5: 链接器 (2 周)
- [ ] ELF 对象文件处理
- [ ] 符号解析
- [ ] 重定位处理

### 总计: 12 周 (3 个月)

---

## 📁 新的目录结构

```
s/src/cmd/compile/seed/
├── ir/                    # 二进制 IR
│   ├── ir.h/c            # IR 数据结构
│   ├── serialize.h/c     # 序列化
│   └── validate.h/c      # 验证
│
├── ssa/                   # SSA 形式
│   ├── ssa.h/c           # SSA 数据结构
│   ├── builder.h/c       # IR to SSA
│   ├── passes.h/c        # SSA 优化通道
│   └── verify.h/c        # SSA 验证
│
├── codegen/               # 代码生成
│   ├── codegen.h/c       # 主代码生成器
│   ├── regalloc.h/c      # 寄存器分配
│   ├── x86.h/c           # x86-64 后端
│   ├── arm.h/c           # ARM 后端
│   └── dwarf.h/c         # 调试信息
│
├── optimize/              # 优化通道
│   ├── inline.h/c        # 内联
│   ├── escape.h/c        # 逃逸分析
│   ├── dcm.h/c           # 死代码消除
│   └── cse.h/c           # 公共子表达式消除
│
└── ...（原有目录）

s/src/cmd/link/            # 新增：链接器
├── link.h/c
├── elf.h/c               # ELF 处理
├── symbol.h/c            # 符号表
└── reloc.h/c             # 重定位
```

---

## 🚀 使用示例

### 编译单个文件
```bash
# 编译到机器码
$ s_seed program.s -o program
$ ./program
Hello, World!

# 编译到中间对象文件
$ s_seed -c program.s -o program.o
```

### 编译多个文件
```bash
$ s_seed -c main.s -o main.o
$ s_seed -c lib.s -o lib.o
$ s_link main.o lib.o -o program
$ ./program
```

### 输出优化信息
```bash
$ s_seed -opt-pass program.s
[SSA Pass] Constant Folding: 5 → 2
[SSA Pass] Dead Code Elimination: 10 → 8
[SSA Pass] Common Subexpression: 8 → 6
$ s_seed program.s -o program.opt
```

---

## 📈 性能预期

```
基准测试: 1000万次循环加法

当前虚拟机:    800ms
改进编译器:     20ms
加速比:        40 倍

更复杂的计算（矩阵乘法）:
当前虚拟机:    5000ms
改进编译器:      100ms
加速比:         50 倍
```

---

## 🔑 关键设计决策

### 1. 二进制 IR vs 文本 IR
- ✅ 二进制：快速，紧凑，便于优化
- ❌ 文本：易于调试，但慢

**决策**: 二进制 IR，但提供文本转储工具

### 2. 何时进行 SSA 构建
- ❌ 编译时：更多时间
- ✅ 编译时（优化可观察）：速度快，优化有效

**决策**: 编译时构建 SSA

### 3. 支持哪些平台
- ✅ x86-64（先）
- ✅ ARM64（后）
- ❌ WebAssembly（需要专门工具）

**决策**: x86-64 优先，ARM64 后续

---

## 💡 与 Go 的相似点和差异

### 相似点
- ✅ 都有多阶段编译过程
- ✅ 都使用 SSA 中间表示
- ✅ 都支持多种优化通道
- ✅ 都有专门的链接器

### 差异
| 方面 | Go | S |
|------|-----|-----|
| 编译时间 | ~1s/文件 | 目标 <500ms/文件 |
| 优化级别 | 多层 | 基础 |
| 运行时支持 | GC, goroutine | 无 (C 风格) |
| 代码大小 | 50-100KB | 目标 <30KB |

---

## ✅ 检查清单

- [ ] 设计二进制 IR 格式规范
- [ ] 实现 IR 序列化
- [ ] 设计 SSA 数据结构
- [ ] 实现 IR to SSA 转换
- [ ] 实现基础 SSA 优化
- [ ] 实现 x86-64 代码生成
- [ ] 实现寄存器分配
- [ ] 实现简单链接器
- [ ] 编写单元测试
- [ ] 性能基准测试
- [ ] 与虚拟机并行支持（过渡期）
- [ ] 文档和示例

---

## 📝 后续步骤

1. **Week 1-2**: 设计评审和反馈
2. **Week 3-14**: 分阶段实现
3. **Week 15**: 性能调优和测试
4. **Week 16**: 文档和发布

**预期完成**: 4 个月内生产就绪

---

**文档版本**: 1.0  
**作者**: AI Assistant for NeurX  
**参考**: Go compiler (cmd/compile, cmd/link)  
**状态**: 设计方案完成，可开始实现
