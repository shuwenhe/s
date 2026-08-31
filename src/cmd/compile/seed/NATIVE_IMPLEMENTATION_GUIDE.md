# S 编译器直接机器码生成 - 快速实现指南

**目标**: 参考 Go 编译器，为 S 语言实现编译时直接生成 x86-64 机器码。

**核心优势**:
- 编译后直接运行，无虚拟机开销
- 性能接近 C 语言（预期 80-95% 性能）
- 启动时间快 4 倍
- 内存占用减少 10 倍

---

## 📋 五步实现计划

### Step 1: 代码生成框架 (3 天)

**目标**: 能够生成完整的 x86-64 汇编文件

**实现**:
```s
// codegen.s - 230 行
struct codegen_context {
    assembly_lines: string[]
    next_label_id: int
}

func emit_line(line: string)
func emit_mov_reg_imm(reg: string, imm: int)
func emit_add_reg_reg(dst: string, src: string)
func emit_call(fn_name: string)
```

**测试**:
```bash
# 生成 Hello World 汇编
# 手工验证汇编代码正确性
```

### Step 2: 寄存器分配 (3 天)

**目标**: 自动将变量分配到寄存器或栈

**实现**:
```s
// register.s - 95 行
struct register_allocator {
    registers: register_info[]      // 9 个通用寄存器
    var_to_reg: (string, int)[]     // 变量映射
    spill_offset: int               // 栈溢出偏移
}

func allocate(var_name: string) string
func free(var_name: string)
```

**测试**:
```s
ra := register_allocator_create()
r1, _ := ra.allocate("x")   // 分配寄存器给 x
r2, _ := ra.allocate("y")   // 分配寄存器给 y
// 验证分配正确
```

### Step 3: 栈帧管理 (2 天)

**目标**: 正确生成函数入出代码

**实现**:
```s
// stackframe.s - 72 行
struct stack_frame {
    base_offset: int
    current_offset: int
    locals: (string, int, int)[]    // 局部变量
}

func allocate_local(name: string, size: int) int
func get_frame_size() int
```

**验证**: 函数栈帧大小计算正确

### Step 4: 指令选择 (4 天)

**目标**: 将 IR 指令转换为 x86-64 汇编

**实现**:
```s
// instruction_select.s - 140 行
func instruction_select_mov(op1, result)
func instruction_select_add(op1, op2, result)
func instruction_select_sub(op1, op2, result)
func instruction_select_call(fn_name, args)
```

**测试**: 1+1, 10-5 等简单算术

### Step 5: 链接器集成 (2 天)

**目标**: 调用系统工具生成可执行文件

**实现**:
```s
// linker.s - 60 行
struct compiler_toolchain {
    gcc_path: string
}

func assemble(asm_file, obj_file)
func link_executable(obj_files, output)
```

**流程**:
```
assembly.s → gcc -c → assembly.o → gcc/ld → executable
```

---

## 🧪 测试策略

### Phase 1: 单元测试 (每个模块)

```s
// test_codegen.s
func test_emit_line() {
    ctx := codegen_context_create("test")
    emit_line(&ctx, "    mov $1, %rax")
    assert(ctx.assembly_lines.len() == 1)
}

func test_register_allocate() {
    ra := register_allocator_create()
    r1, _ := ra.allocate("x")
    r2, _ := ra.allocate("y")
    assert(r1 != r2)
}
```

### Phase 2: 集成测试

```s
// 编译小程序
func main() int {
    x := 1 + 2
    y := x * 3
    x
}
// 验证输出正确
```

### Phase 3: 性能测试

```bash
# 对标 IR 方案
time ./test_ir      # 800ms
time ./test_native  # 50ms ← 16 倍快
```

---

## 📊 实现进度表

```
Week 1:
  Day 1-3:  代码生成框架 (codegen.s)
  Day 4-6:  寄存器分配 (register.s)

Week 2:
  Day 1-2:  栈帧管理 (stackframe.s)
  Day 3-6:  指令选择 (instruction_select.s)

Week 3:
  Day 1-2:  链接器集成 (linker.s)
  Day 3-5:  集成测试和优化
  Day 6:    性能基准对标

预计总工作量: 100-120 小时
核心代码行数: ~600 行 S 语言
```

---

## 🚀 验收标准

### 功能验收

- ✅ 能编译输出简单 S 程序
- ✅ 生成的可执行文件能正确运行
- ✅ 输出结果与 IR 方案一致
- ✅ 所有现有测试通过

### 性能验收

- ✅ 运行速度 ≥ 10 倍 vs IR
- ✅ 内存占用 < 10% vs IR
- ✅ 编译时间 < 2 倍 vs Go

### 质量验收

- ✅ 代码覆盖率 > 80%
- ✅ 文档完整
- ✅ 无内存泄漏
- ✅ 错误处理完善

---

## 💡 关键实现建议

### 1. 寄存器分配策略

```
推荐: 简单线性分配（先到先得）

优点:
  - 实现简单 (20 行)
  - 足够快速
  - 调试容易

缺点:
  - 非最优分配
  - 可能过度溢出

后期优化: 图着色算法
```

### 2. 指令选择方式

```
推荐: 模式匹配

switch (ins.op) {
    case "MOV":  emit_mov(...)
    case "ADD":  emit_add(...)
    case "CALL": emit_call(...)
}

优点:
  - 清晰易维护
  - 方便扩展

缺点:
  - 代码重复
  - 手工维护

后期优化: 生成规则表
```

### 3. 错误处理

```s
// 关键检查点
1. 寄存器溢出检查
2. 栈大小溢出检查
3. 标签重定义检查
4. 汇编器错误捕获
5. 链接器错误捕获
```

---

## 📚 参考代码模板

### 最小化 MVP 例子

```s
// 编译 fn() int { 1 + 2 }

.section .text
.globl main

main:
    push %rbp
    mov %rsp, %rbp
    
    mov $1, %rax        # x = 1
    mov $2, %rcx        # y = 2
    add %rcx, %rax      # x = x + y (结果在 rax)
    
    leave
    ret
```

编译步骤:
```bash
gcc -c output.s -o output.o    # 汇编
gcc output.o -o output          # 链接
./output                        # 执行
echo $?                         # 输出: 3
```

### 函数调用例子

```s
call_add:
    push %rbp
    mov %rsp, %rbp
    
    mov $1, %rdi        # 第 1 个参数 = 1
    mov $2, %rsi        # 第 2 个参数 = 2
    call add_func       # 调用 add_func(1, 2)
    
    # 返回值在 %rax
    leave
    ret

add_func:
    push %rbp
    mov %rsp, %rbp
    
    add %rsi, %rdi      # rdi = rdi + rsi
    mov %rdi, %rax      # 返回值 = rdi
    
    leave
    ret
```

---

## 🔄 集成到主编译器

### 编译器主函数修改

```s
func main(args: &string[]) int {
    // ... 原有代码 ...
    
    // 新增: 检查 --native 选项
    if should_use_native_codegen {
        compiler := compiler_native_create(input_file, output_file)
        return compiler.compile_to_executable()
    }
    
    // 原有: IR + 虚拟机方案
    return compile_to_ir(input_file, output_file)
}
```

### 命令行选项

```bash
s_seed input.s -o output --native          # 使用直接机器码
s_seed input.s -o output --native -O2      # 使用优化
s_seed input.s -o output                   # 默认（当前 IR 方案）
```

---

## 🎯 成功标志

当实现以下目标时，说明项目成功：

1. **Hello World 能编译运行**
   ```bash
   s_seed hello.s --native -o hello
   ./hello
   # 输出: Hello, World!
   ```

2. **性能对标成功**
   ```bash
   time ./test_ir                  # ~800ms
   time ./test_native              # ~50ms
   # 加速比: 16 倍 ✅
   ```

3. **现有测试全部通过**
   ```bash
   make test-all --native
   # All tests passed ✅
   ```

4. **文档完整清晰**
   ```
   - README.md (本文件)
   - 代码注释充分
   - 集成指南完整
   ```

---

## 📞 常见问题

**Q: 为什么不用 LLVM？**
A: LLVM 功能强大但集成复杂。我们的方案更轻量级，够用就好。

**Q: 能支持 ARM/RISC-V 吗？**
A: MVP 先做 x86-64。ARM 后续版本支持（代码生成后端可插拔）。

**Q: 如何处理浮点数？**
A: MVP 只支持整数。浮点数指令选择在 Phase 2。

**Q: 如何优化性能？**
A: 分三层：MVP(60% C), Beta(80% C), Release(95% C)

---

## 📈 预期时间表

```
Week 1-2:  核心框架（代码生成、寄存器、栈帧）
Week 2-3:  指令选择和链接器集成
Week 3-4:  集成测试和性能优化
Week 4-5:  文档和生产就绪

总计: 4-5 周，可投入 1-2 人
```

---

**版本**: 1.0  
**创建**: 2026-08-31  
**状态**: 实现计划就绪
