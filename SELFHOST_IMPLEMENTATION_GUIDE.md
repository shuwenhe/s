# S 语言真正独立自举实现指南 (Linux x86_64)

## 当前状态分析

**平台**: Linux x86_64 (Ubuntu 24.04)  
**现状**: `bin/s` 虽然用 S 源代码生成，但仍链接 C seed 编译器的代码生成后端

```
seed 编译器的内部流程：
源代码 (.s) 
  ↓ [种子前端：词法+语法分析 - 已用 S 实现部分]
  IR (中间代码)
  ↓ [代码生成后端 - 仍是 C 实现！❌]
  x86-64 机器码
  ↓ [链接]
  可执行文件
```

问题：第2步仍需 C seed 的代码生成器 (`native_backend.c`)

## 解决方案：实现纯 S 的代码生成链

```
├─ Stage 0: seed 编译器生成 IR（现有，C 实现）
├─ Stage 1: IR → x86-64 汇编（新，S 实现）
├─ Stage 2: 汇编 → ELF 二进制（用 gcc/as，暂不用 S）
└─ Stage 3: 循环 - 用 Stage 2 的二进制重新编译自己
```

## 实现步骤

### 第一步：验证 IR 格式理解

IR 输出格式分析（从 `stage2.ir`）：

```
SSEED-TARGET-V1          # 标头
FUNC_BEGIN|main|_|_      # 函数开始
CALL|t0|host_args|0      # 调用函数，结果→t0
MOV|args|t0|_            # 移动 t0 → args
CMP_NE|t3|buildcfg_err|""  # 比较
JUMP_IF_FALSE|L0|t3|_    # 条件跳转
...
FUNC_END|main|_|_        # 函数结束
```

**格式规则**：
- `OPCODE|DEST|SRC1|SRC2|SRC3`
- 临时变量：`t0`, `t1` 等
- 局部变量和参数：按名称
- 标签：`L0`, `L1` 等

### 第二步：实现 IR 解析器（已创建）

**文件**: `src/cmd/compile/selfhost/ir_codegen.s`

核心功能：
- 解析 IR 格式
- 识别函数、指令、标签
- 构建 AST（抽象语法树）

### 第三步：实现 x86-64 代码生成（已创建）

**文件**: `src/cmd/compile/selfhost/x86_64_codegen.s`

核心功能：
- 将每个 IR 指令翻译为 x86-64 汇编
- 管理寄存器分配
- 处理调用约定（System V AMD64 ABI）

**关键指令翻译**：

| IR 指令 | x86-64 翻译 | 说明 |
|--------|-----------|------|
| `MOV\|dest\|src\|_` | `movq src, dest` | 数据移动 |
| `ADD\|dest\|a\|b` | `mov a,%rax; add b,%rax; mov %rax,dest` | 加法 |
| `CALL\|result\|func\|_` | `call func; mov %rax,result` | 函数调用 |
| `JUMP\|label\|_\|_` | `jmp label` | 无条件跳转 |
| `JUMP_IF_FALSE\|label\|cond\|_` | `test cond,cond; jz label` | 条件跳转 |
| `RET\|value\|_\|_` | `mov value,%rax; pop %rbp; ret` | 返回 |

### 第四步：集成工具（已创建）

**文件**: `src/cmd/compile/selfhost/ir_to_binary.s`

这个工具：
1. 读取 IR 文件
2. 调用 IR 解析器
3. 调用 x86-64 生成器
4. 生成汇编文件
5. 用 `gcc` 进行最终的汇编和链接

### 第五步：修改 Makefile 支持纯 S 自举

添加新的 build 目标：

```makefile
# 纯 S 编译流程（第一次需要 seed）
pure-selfhost: seed-compiler-bin
	@echo "Stage 1: Building IR-to-Binary tool (S implementation)..."
	@mkdir -p $(SELFHOST_DIR)
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed \
	  src/cmd/compile/selfhost/ir_to_binary.s \
	  $(SELFHOST_DIR)/ir_to_binary.ir
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --emit-bin \
	  $(SELFHOST_DIR)/ir_to_binary.ir \
	  $(SELFHOST_DIR)/ir_to_binary_tool
	
	@echo "Stage 2: Using S-based code generator..."
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --bootstrap \
	  src/cmd/compile/main.s \
	  $(SELFHOST_DIR)
	
	@echo "Stage 3: Converting IR to binary with pure S tool..."
	@$(SELFHOST_DIR)/ir_to_binary_tool \
	  $(SELFHOST_DIR)/stage2.ir \
	  $(SELFHOST_DIR)/stage2_pure
	
	@echo "Stage 4: Verifying true self-hosting..."
	@$(SELFHOST_DIR)/stage2_pure src/cmd/compile/main.s \
	  $(SELFHOST_DIR)/final.ir
	@cmp $(SELFHOST_DIR)/stage2.ir $(SELFHOST_DIR)/final.ir
	@echo "✓ True self-hosting achieved!"
	@$(INSTALL_PROGRAM) -m 0755 $(SELFHOST_DIR)/stage2_pure ./bin/s
```

## 开发路线表

| 阶段 | 任务 | 文件 | 优先级 | 工作量 |
|------|------|------|--------|--------|
| 1 | IR 解析器 | `ir_codegen.s` | P0 | 500-800 LOC |
| 2 | x86-64 代码生成 | `x86_64_codegen.s` | P0 | 800-1200 LOC |
| 3 | 寄存器分配器 | `x86_64_codegen.s` | P0 | 300-500 LOC |
| 4 | 集成工具 | `ir_to_binary.s` | P0 | 200-300 LOC |
| 5 | 修改 Makefile | `Makefile` | P0 | 50-100 行 |
| 6 | 测试框架 | `test/` | P1 | 300-500 LOC |
| 7 | ELF 直接生成 | `elf_gen.s` | P2 | 1000-1500 LOC |

## 快速启动

### 编译模块
```bash
cd /home/shuwen/shuwen/s

# 编译代码生成器
./bin/s_seed src/cmd/compile/selfhost/ir_codegen.s /tmp/ir_codegen.ir
./bin/s_seed --emit-bin /tmp/ir_codegen.ir /tmp/ir_codegen_tool

# 编译 x86-64 生成器
./bin/s_seed src/cmd/compile/selfhost/x86_64_codegen.s /tmp/x86_64_gen.ir
./bin/s_seed --emit-bin /tmp/x86_64_gen.ir /tmp/x86_64_gen_tool
```

### 测试 IR 转换
```bash
# 生成测试 IR
./bin/s_seed src/cmd/compile/main.s /tmp/test.ir

# 用新工具转换
/tmp/ir_to_binary_tool /tmp/test.ir /tmp/test_binary
```

## 技术细节

### 调用约定 (System V AMD64 ABI)
- 参数传递：`%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9` + 栈
- 返回值：`%rax`, `%rdx` (64 位返回)
- 保存的寄存器：`%rbx`, `%rsp`, `%rbp`, `%r12-r15`
- 临时寄存器：`%rax`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%r8-r11`

### Stack Frame 布局
```
+------+
| RIP  |  <- return address (pushed by CALL)
+------+
| RBP  |  <- saved RBP (we push it)
+------+
| ...  |  locals and temporaries
+------+
```

### 寄存器分配策略
1. 为每个临时变量分配物理寄存器
2. 寄存器用完时，使用栈（栈溢出）
3. 跨函数调用要保存/恢复被调用者保存的寄存器

## 调试技巧

```bash
# 生成汇编检查
./bin/s_seed src/cmd/compile/main.s /tmp/debug.ir
cat /tmp/debug.ir | head -100

# 验证生成的二进制
file /tmp/stage2_pure
ldd /tmp/stage2_pure
nm /tmp/stage2_pure | grep seed

# 最关键的检查
nm ./bin/s | grep seed_compile  # 现在应该有
nm /tmp/stage2_pure | grep seed_compile  # 应该没有！
```

## 预期成果

完成后：
- ✅ `bin/s` 不链接任何 C seed 代码
- ✅ `bin/s` 能自我编译
- ✅ 三次编译产生相同的二进制（确定性）
- ✅ 真正的 S 语言独立自举

## 相关资源

- [x86-64 汇编参考](https://www.felixcloutier.com/x86/)
- [ELF 二进制格式](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
- [System V AMD64 ABI](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf)
- [GCC 汇编语法](https://sourceware.org/binutils/docs/as/)
