# S 语言 Linux x86_64 平台真正独立自举 - 快速指南

## 当前状况

**✗ 现状**: `bin/s` 虽然用 S 代码生成，但仍需要 C seed 编译器的**代码生成后端**

```
bin/s 依赖链：
bin/s → libc.so.6 → 系统库
   ↓（运行时）
包含 seed_compile_file 和 seed_compile_source_text 符号
   ↓（来自 C seed 的代码生成模块）
native_backend.c（C 实现的 IR → x86-64）
```

## 解决方案一句话

**用 S 实现 IR → x86-64 代码生成器**，替换 C seed 的后端。

## 三层架构

```
Layer 1: 前端（S 语言实现）✓ 已有
  S 源代码 → IR 中间代码
  (词法分析、语法分析、语义检查)

Layer 2: 代码生成（需要用 S 实现） ← 这是关键！
  IR 中间代码 → x86-64 汇编
  (寄存器分配、指令选择、模式匹配)

Layer 3: 链接（用现有工具）✓ 已有
  x86-64 汇编 → ELF 二进制
  (使用 gcc/as)
```

## 已创建的文件

| 文件 | 用途 | 状态 |
|------|------|------|
| `SELFHOST_IMPLEMENTATION_GUIDE.md` | 详细技术指南 | ✅ 完成 |
| `PURE_S_SELFHOST_PLAN.md` | 项目计划 | ✅ 完成 |
| `src/cmd/compile/selfhost/ir_parser.s` | IR 解析 | ✅ 完成 |
| `src/cmd/compile/selfhost/ir_codegen.s` | IR 处理框架 | ⏳ 框架 |
| `src/cmd/compile/selfhost/x86_64_codegen.s` | x86-64 生成 | ⏳ 框架 |
| `src/cmd/compile/selfhost/elf_gen.s` | ELF 生成 | ⏳ 框架 |
| `src/cmd/compile/selfhost/ir_to_binary.s` | 集成工具 | ⏳ 框架 |
| `test_bootstrap_feasibility.sh` | 可行性验证 | ✅ 验证通过 |

## 快速启动

### 步骤 1: 理解当前状况
```bash
cd /home/shuwen/shuwen/s

# 检查 bin/s 的 C 依赖
nm ./bin/s | grep seed_compile
# 输出应该有 seed_compile_file 和 seed_compile_source_text
```

### 步骤 2: 运行可行性验证
```bash
bash test_bootstrap_feasibility.sh
```

输出应该显示：
- ✓ IR 格式简单（14 种指令）
- ✓ 编译器 IR 只有 147 行
- ✓ 自我编译产生相同结果

### 步骤 3: 查看 IR 格式
```bash
# 生成一个小程序的 IR
./bin/s_seed src/cmd/compile/main.s /tmp/sample.ir

# 查看格式
head -50 /tmp/sample.ir
```

会看到类似的格式：
```
SSEED-TARGET-V1
FUNC_BEGIN|main|_|_
CALL|t0|host_args|0
MOV|args|t0|_
CMP_NE|t3|buildcfg_err|""
JUMP_IF_FALSE|L0|t3|_
...
FUNC_END|main|_|_
```

## 为什么这个平台完全可行

1. **IR 格式简单**: 只有 14 种指令，都是标准的编译器操作
2. **代码量少**: 147 行 IR 就能表示整个编译器
3. **x86-64 已知**: 该指令集文档齐全，生成相对直接
4. **引导已验证**: 种子编译器能稳定生成 IR

## 核心工作量估计

| 组件 | LOC | 难度 | 时间 |
|------|-----|------|------|
| IR 解析器 | 500 | ⭐ | 1 天 |
| x86-64 生成 | 800 | ⭐⭐ | 2 天 |
| 寄存器分配 | 300 | ⭐⭐ | 1 天 |
| 集成 + 测试 | 200 | ⭐ | 1 天 |
| **总计** | **1800** | | **5 天** |

（如果用简化策略，可以 3 天）

## 最小化可行产品 (MVP)

要快速演示概念，只需实现：

1. **IR 解析器** - 读取和理解 IR 格式 ✓ (已有框架)
2. **简单的 x86-64 生成** - 生成正确的汇编代码
   - 不需要优化
   - 可以用栈存放所有变量
   - 基本的寄存器使用即可
3. **工具集成** - 把 1 和 2 连接起来

## 验证方法

完成后验证自举成功：

```bash
# 1. 检查没有 C 依赖
nm ./bin/s | grep seed_compile  # 应该为空！

# 2. 能自我编译
./bin/s src/cmd/compile/main.s /tmp/test.ir

# 3. 结果一致
diff /tmp/test.ir $(previous_ir)  # 应该相同

# 4. 最后一步：编译自己
./bin/s src/cmd/compile/main.s /tmp/final.ir
diff /tmp/final.ir /tmp/test.ir  # 应该相同
```

## 关键决策

在开始实现前需要决定：

### 1. 寄存器分配策略
- **简单** (推荐 MVP): 所有变量用栈，只在需要时用寄存器
- **复杂**: 线性扫描或图着色算法

### 2. 代码生成方式
- **AT&T 语法**: 用 gcc 进行最后的链接 (推荐，最快)
- **Intel 语法**: 也可以，语法略有不同
- **直接机器码**: 最快但实现最复杂

### 3. 优化程度
- **无优化** (推荐 MVP): 快速实现，正确性第一
- **基本优化**: 死代码消除、常量折叠
- **高级优化**: 指令调度、循环优化

## 技术参考

### x86-64 系统调用约定 (Linux System V AMD64 ABI)
```
参数传递: %rdi, %rsi, %rdx, %rcx, %r8, %r9
返回值:   %rax (64位) / %rdx:%rax (128位)
保存寄存器: %rbx, %rsp, %rbp, %r12-%r15
临时寄存器: %rax, %rcx, %rdx, %rsi, %rdi, %r8-%r11

栈帧:
    +--------+
    | RIP    | ← return address
    +--------+
    | RBP    | ← saved caller's RBP
    +--------+
    | locals | ← local variables
    +--------+ ← RSP
```

### 基本的函数序言/尾声
```asm
func:
    push %rbp              # 保存调用者的 RBP
    mov %rsp, %rbp        # 建立新的栈帧
    sub $<stack>, %rsp    # 分配栈空间
    ...
    add $<stack>, %rsp    # 释放栈空间
    pop %rbp              # 恢复调用者的 RBP
    ret                   # 返回
```

## 推荐实现顺序

1. **完成 IR 解析器** (`ir_parser.s`)
   - 能读取和解析 IR 文件
   - 提取函数和指令
   - 验证结构完整性

2. **实现基本的 x86-64 生成**
   - 支持函数序言/尾声
   - 支持基本的 MOV、ADD 等操作
   - 支持函数调用（CALL）

3. **支持控制流**
   - 标签 (LABEL)
   - 条件跳转 (JUMP_IF_FALSE, CMP_*）
   - 无条件跳转 (JUMP)

4. **完整的指令支持**
   - 所有 14 种 IR 指令
   - 完整的参数传递
   - 完整的寄存器分配

5. **优化和错误处理**
   - 代码优化
   - 更好的错误消息
   - 性能改进

## 成功标志

✅ **完全成功的标志**:
- `bin/s` 中 **没有** `seed_compile*` 符号
- `bin/s` 能**独立编译**自己
- 编译结果**确定性**（多次编译相同）
- **无需 C seed 编译器**即可使用

## 推荐阅读

1. 本目录的 `SELFHOST_IMPLEMENTATION_GUIDE.md` - 详细技术文档
2. 本文件的 `PURE_S_SELFHOST_PLAN.md` - 项目管理计划
3. x86-64 汇编参考 - https://www.felixcloutier.com/x86/
4. System V AMD64 ABI - 调用约定规范

## 立即行动

```bash
# 1. 切换到项目目录
cd /home/shuwen/shuwen/s

# 2. 运行可行性验证
bash test_bootstrap_feasibility.sh

# 3. 查看已创建的文件
ls -la src/cmd/compile/selfhost/

# 4. 查看实现指南
cat SELFHOST_IMPLEMENTATION_GUIDE.md | less

# 5. 开始实现!
# 从完成 ir_parser.s 开始
```

---

**作者**: Copilot  
**日期**: 2026-07-24  
**状态**: 计划完成，待实现  
**难度**: 中等 ⭐⭐  
**预计时间**: 3-5 天 (MVP 3 天，完整版 5-7 天)
