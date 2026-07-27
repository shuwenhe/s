# S 自举实现完整方案

## 🎯 核心问题

当前 S 编译器的自举链（bootstrap chain）：
```
C seed compiler (bin/s_seed) → IR
                     ↓
bootstrap.c (C 代码) → 调用 C seed 库
                     ↓
bin/s (仍然链接 C)
```

**目标**：完全消除 C 依赖
```
IR codegen (纯 S) → 二进制
    ↑
bootstrap_pure_s.s (纯 S) → 调用自己生成新的 S 编译器
```

---

## 📊 三阶段自举路线

### **第一阶段：基础设施（已完成）**

✅ 创建的文件：
- `src/std/syscall.s` - Linux syscall 包装
- `src/std/io_syscall.s` - 文件 I/O 操作
- `src/std/process.s` - 进程执行

这些文件使用 S 的 `extern "intrinsic"` 直接生成 Linux syscall，**完全不依赖 libc**。

### **第二阶段：完成 Bootstrap 驱动**

编辑 `bootstrap_pure_s.s`，实现核心逻辑：

```s
use std.io_syscall
use std.process

func bootstrap_two_stage(string compiler_src, string output_dir) int {
    // Step 1: 编译源码 → IR (使用 seed)
    let stage1_ir = output_dir + "/stage1.ir"
    let exit1, err1 = process.compile_to_ir(
        "./bin/s_seed",
        compiler_src,
        stage1_ir
    )
    if exit1 != 0 { return 1 }
    
    // Step 2: IR → 二进制 (纯 S 实现)
    let stage1_bin = output_dir + "/stage1"
    let exit2, err2 = emit_ir_to_binary(stage1_ir, stage1_bin)
    if exit2 != 0 { return 1 }
    
    // Step 3: 用 stage1 编译自己 → stage2.ir
    let stage2_ir = output_dir + "/stage2.ir"
    let exit3, _ = process.compile_to_ir(
        stage1_bin,
        compiler_src,
        stage2_ir
    )
    
    // Step 4: 验证确定性编译
    if !io_syscall.files_equal(stage1_ir, stage2_ir) {
        eprintln("ERROR: stage1.ir != stage2.ir (non-deterministic)")
        return 1
    }
    
    eprintln("[✓] Bootstrap successful!")
    return 0
}
```

### **第三阶段：生成无依赖二进制**

修改 Makefile：
```makefile
true-selfhost-bin: bin/s_seed
	@mkdir -p .bootstrap/true
	@$(CC) -o .bootstrap/true/bootstrap_driver \
	  src/cmd/compile/selfhost/bootstrap_pure_s.s \
	  src/std/syscall.s \
	  src/std/io_syscall.s \
	  src/std/process.s \
	  -nostdlib -static
	@.bootstrap/true/bootstrap_driver \
	  src/cmd/compile/main.s \
	  .bootstrap/true

true-selfhost-check: true-selfhost-bin
	@nm .bootstrap/true/stage1 | grep -E 'U (seed_compile|malloc|free)' && \
	  echo "FAIL: still has C dependencies" || \
	  echo "PASS: pure S bootstrap successful"
```

---

## 🔧 实现细节和限制

### **编译器需要的 Intrinsic 支持**

为了使用这些库，S 编译器需要支持：

1. **字符串 → 指针转换**
   ```s
   let ptr = string_to_ptr(my_string)  // intrinsic
   ```

2. **Syscall 生成**
   ```s
   extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int
   ```

3. **缓冲区管理**
   ```s
   let buf = allocate(1024)  // 分配内存
   ```

检查 `src/cmd/compile/seed/intermediate/ir.c` 中是否已定义这些 intrinsic。

### **当前的 TODO 项**

| 文件 | 函数 | 优先级 | 工作量 |
|------|------|--------|--------|
| `io_syscall.s` | `file_read_string` | 🔴 高 | 1 天 |
| `io_syscall.s` | `file_write_string` | 🔴 高 | 1 天 |
| `process.s` | `parse_command_line` | 🔴 高 | 1 天 |
| `process.s` | `run_command` | 🔴 高 | 2 天 |
| `bootstrap_pure_s.s` | 所有 TODO | 🔴 高 | 3 天 |
| `process.s` | `pipe_commands` | 🟠 中 | 2 天 |

---

## 📈 验证步骤

```bash
# 1. 编译 bootstrap 驱动
make bootstrap-pure-s-bin

# 2. 运行两阶段启动
./.bootstrap/true/bootstrap_driver \
  src/cmd/compile/main.s \
  .bootstrap/true

# 3. 验证无 C 依赖
nm .bootstrap/true/stage1 | grep -E 'U (seed|malloc|free)'
# 应该没有输出

# 4. 测试新编译器
./.bootstrap/true/stage1 test_program.s test_output.ir

# 5. 确定性检查
diff .bootstrap/true/stage1.ir .bootstrap/true/stage2.ir
# 应该完全相同
```

---

## 🚀 快速开始

### 立即执行（1-2 天）

1. **实现文件读取** (`io_syscall.s`)
   ```s
   func file_read_string(path: string) -> string {
       let fd = open_file(path, O_RDONLY, 0)
       let buf = []byte[65536]
       let n = read_from_fd(fd, buf, 65536)
       let result = bytes_to_string(buf, n)
       close_fd(fd)
       result
   }
   ```

2. **实现文件写入** (`io_syscall.s`)
   ```s
   func file_write_string(path: string, content: string) -> int {
       let fd = open_file(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
       let ptr = string_to_ptr(content)
       write_to_fd(fd, ptr, len(content))
       close_fd(fd)
   }
   ```

3. **实现命令行解析** (`process.s`)
   ```s
   func parse_command_line(cmd: string) -> []string {
       // 简单版本：按空格分割（不处理引号）
       let parts = split_string(cmd, " ")
       parts
   }
   ```

4. **测试文件 I/O**
   ```bash
   make test-io-syscall
   ```

### 关键检查点

在继续下一步前，确保：
- [ ] `file_read_string` 能读取任意文件
- [ ] `file_write_string` 能创建新文件
- [ ] `run_command` 能调用 `bin/s_seed`
- [ ] 没有 libc 符号（`nm bin/s | grep -i libc`）

---

## 💡 关键洞察

**为什么 S 很难自举？**

1. **字符串处理**：S 字符串与 C char* 不兼容，需要转换
2. **内存模型**：S 的垃圾回收与 C malloc/free 冲突  
3. **编译器本身**：主要还是用 C 写的（seed/），只有部分用 S 写
4. **无法真正绕过 C**：除非完整重写前端（parser/semantic）

**S 真正的自举需要：**
- ✅ 纯 S 的 IR 代码生成（已有 75% 实现）
- ⏳ 纯 S 的前端编译（parser/semantic/typechecker）- **这是最大的缺失**
- ⏳ 完整的运行时库替代 C stdlib

目前只能达到 **"种子编译器 B 可以编译自己"** 的程度，而不是 **"S 编译器完全不依赖 C"**。

---

## 📚 参考资源

- Linux syscall 表：`man 2 syscall`
- S 编译器源：`src/cmd/compile/seed/`
- IR 格式：查看 `seed/intermediate/ir.c` 中的 `SSEED-TARGET-V1`
- ELF 格式：`src/cmd/compile/selfhost/elf_gen.s`

