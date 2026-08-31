# S 语言编译器本机后端 - 参考 Go 编译器设计

**目标**: 实现与 Go 编译器类似的本机代码生成能力

## 架构概览

```
输入 (S 源代码)
    ↓
[解析器] → AST
    ↓
[语义分析] → 类型检查
    ↓
[SSA 生成] → 中间表示
    ↓
[本机后端] ← 新增模块
    ├─ instruction_selector.s    (IR → x86-64 指令选择)
    ├─ register_allocator.s       (寄存器分配与溅出)
    ├─ stack_frame.s              (栈帧管理)
    ├─ codegen_x86_64.s           (代码生成)
    ├─ assembly_generator.s       (汇编输出)
    ├─ linker.s                   (链接器集成)
    └─ native_compiler.s          (编译驱动)
    ↓
[汇编] (gcc -c)
    ↓
[链接] (gcc/ld)
    ↓
输出 (可执行文件)
```

## 模块详解

### 1. codegen_x86_64.s
- **功能**: x86-64 汇编指令生成
- **核心结构**: `machine_code_builder`
- **关键方法**:
  - `emit_mov_immediate_to_register()`: MOV 立即数到寄存器
  - `emit_mov_register_to_register()`: MOV 寄存器到寄存器
  - `emit_add_registers()`: ADD 寄存器操作
  - `emit_call()`: 函数调用
  - `emit_return_value()`: 返回值处理
- **参考**: Go `src/cmd/compile/internal/amd64/`

### 2. register_allocator.s
- **功能**: x86-64 寄存器分配
- **可用寄存器**: rax, rcx, rdx, rsi, rdi, r8-r11 (9 个通用寄存器)
- **策略**:
  - 优先分配物理寄存器
  - 超出时溅到栈上
  - 自动管理栈偏移
- **核心方法**:
  - `allocate_for_variable()`: 为变量分配寄存器
  - `get_variable_location()`: 查询变量位置
  - `get_stack_size()`: 计算所需栈空间
- **参考**: Go `src/cmd/compile/internal/ssa/allocate.go`

### 3. stack_frame.s
- **功能**: System V ABI 栈帧管理
- **标准布局**:
  ```
  [rbp + 8]  ← 返回地址
  [rbp]      ← 保存的 rbp
  [rbp - 8]  ← 局部变量 1
  [rbp - 16] ← 局部变量 2
  ...
  [rsp]      ← 栈顶
  ```
- **对齐**: 16 字节对齐（System V ABI 要求）
- **参考**: Go `src/cmd/compile/internal/amd64/abi.go`

### 4. instruction_selector.s
- **功能**: IR 指令到 x86-64 指令的映射
- **支持的 IR 指令**:
  - ADD (加法)
  - SUB (减法)
  - MOV (移动)
  - CALL (函数调用)
  - RET (返回)
- **参考**: Go `src/cmd/compile/internal/ssagen/ssa.go`

### 5. assembly_generator.s
- **功能**: 生成最终的 x86-64 汇编代码
- **输出格式**: AT&T 汇编语法（gcc 兼容）
- **节管理**:
  - `.text` - 代码节
  - `.data` - 初始化数据
  - `.rodata` - 只读数据
  - `.bss` - 未初始化数据

### 6. linker.s
- **功能**: 系统工具链集成
- **支持工具**:
  - gcc 汇编 (as)
  - ld 链接器
  - gcc 驱动程序
- **流程**:
  - 汇编 (`.s` → `.o`)
  - 链接 (`.o` → 可执行文件)

### 7. native_compiler.s
- **功能**: 编译驱动程序
- **工作流程**:
  1. 代码生成 → 汇编
  2. 汇编 → 目标文件
  3. 链接 → 可执行文件
- **错误处理**: 逐步检查每个阶段

### 8. backend_native.s
- **功能**: 后端上下文管理
- **职责**:
  - 启用/禁用本机编译
  - 管理目标架构和 OS
  - 协调所有后端模块

## 性能目标

| 指标 | IR+VM | 本机编译 | 改进 |
|------|-------|---------|------|
| 10M 循环执行时间 | 900ms | 50ms | **18x** |
| 每指令周期数 | 221 | 3 | **73x** |
| 内存使用 | 50MB | 8MB | **6x** |

## 使用方法

### 1. 启用本机编译

```bash
s_seed build program.s -o program --native
```

### 2. 编译流程

```
program.s
  ↓ [parse & check]
IR representation
  ↓ [instruction_selector]
x86-64 instructions
  ↓ [codegen_x86_64]
assembly code
  ↓ [assembly_generator]
program.s (汇编)
  ↓ [gcc -c]
program.o
  ↓ [gcc/ld]
program (可执行文件)
```

### 3. 调试输出

可选查看生成的汇编代码：
```bash
objdump -d program
```

## 参考资源

- **Go 编译器**:
  - `src/cmd/compile/internal/amd64/` - x86-64 后端
  - `src/cmd/compile/internal/ssa/` - SSA 和代码生成
  - `src/cmd/compile/internal/ssagen/` - SSA 生成

- **x86-64 ABI**:
  - System V AMD64 ABI (Linux 标准)
  - 调用约定: rdi, rsi, rdx, rcx, r8, r9 (参数)
  - 返回值: rax, rdx (整数)

- **汇编参考**:
  - AT&T 汇编语法 (gcc/as 格式)
  - Intel 语法可选 (使用 `.intel_syntax` 指令)

## 实现状态

- ✅ 架构设计
- ✅ 模块分解
- ⏳ 完整的 IR 支持
- ⏳ 优化 (常数折叠, 死码消除等)
- ⏳ 调试信息生成
- ⏳ 异常处理

## 下一步

1. **集成 IR 前端**
   - 连接 SSA 生成到指令选择器
   - 实现完整的 IR 指令支持

2. **优化**
   - 寄存器分配优化
   - 指令选择优化
   - 常数折叠

3. **测试**
   - 单元测试 (每个模块)
   - 集成测试 (端到端编译)
   - 性能基准 (对比 IR+VM)

4. **功能扩展**
   - 其他架构支持 (ARM64, RISC-V)
   - 内联汇编支持
   - 优化级别 (-O0, -O1, -O2, -O3)
