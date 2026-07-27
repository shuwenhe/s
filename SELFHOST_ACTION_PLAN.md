# S 自举实现行动计划 (2026-07-27)

## 🎯 立即优先事项（下周）

### 第 1 天：实现文件读取

**目标文件**：`src/std/io_syscall.s` 中的 `file_read_string` 函数

```s
// 伪代码实现步骤
func file_read_string(string path) (string, int) {
    // 1. 调用 open syscall
    let fd = open_file(path, O_RDONLY, 0)
    if fd < 0 { return "", fd }
    
    // 2. 分配读缓冲区 (64KB)
    let buffer = allocate_buffer(65536)
    
    // 3. 循环读取直到 EOF
    let total = 0
    loop {
        let n = read_from_fd(fd, buffer + total, 65536 - total)
        if n <= 0 { break }
        total += n
    }
    
    // 4. 转换字节为字符串
    let result = bytes_to_string(buffer, total)
    
    // 5. 关闭文件
    close_fd(fd)
    
    return result, 0
}
```

**关键决策**：
- [ ] 选择缓冲区大小（建议 64KB）
- [ ] 错误处理策略（返回 error code）
- [ ] 字节 → 字符串转换方法

**验证方法**：
```bash
# 创建测试程序
cat > test_file_read.s <<'EOF'
use std.io_syscall

func main() int {
    let content, err = io_syscall.file_read_string("test.txt")
    if err != 0 { return err }
    eprint(content)
    return 0
}
EOF

# 编译并测试
./bin/s_seed test_file_read.s test_read.ir
./bin/s --emit-bin test_read.ir -o test_read
echo "hello world" > test.txt
./test_read
```

---

### 第 2 天：实现文件写入

**目标文件**：`src/std/io_syscall.s` 中的 `file_write_string` 函数

```s
func file_write_string(string path, string content) int {
    // 1. 打开文件 (创建或截断)
    let flags = O_WRONLY | O_CREAT | O_TRUNC
    let fd = open_file(path, flags, 0o644)
    if fd < 0 { return fd }
    
    // 2. 获取字符串指针和长度
    let ptr = string_to_ptr(content)  // intrinsic
    let len = len(content)
    
    // 3. 写入数据
    let written = write_to_fd(fd, ptr, len)
    if written != len {
        close_fd(fd)
        return -1  // Write failed
    }
    
    // 4. 关闭文件
    return close_fd(fd)
}
```

**关键问题**：
- 如何获取字符串的指针？（需要编译器 intrinsic）
- 写入失败时如何处理？

**测试**：
```bash
cat > test_file_write.s <<'EOF'
use std.io_syscall

func main() int {
    return io_syscall.file_write_string("output.txt", "Hello from S!")
}
EOF

./bin/s_seed test_file_write.s test_write.ir
./bin/s --emit-bin test_write.ir -o test_write
./test_write
cat output.txt  # 应该输出: Hello from S!
```

---

### 第 3 天：命令行解析

**目标文件**：`src/std/process.s` 中的 `parse_command_line` 函数

简单版本（不支持引号）：
```s
func parse_command_line(string cmd_line) []string {
    // 1. 按空格分割
    let parts = split_string(cmd_line, " ")
    
    // 2. 过滤空字符串
    let result: []string = {}
    for part in parts {
        if len(part) > 0 {
            result = append(result, part)
        }
    }
    
    return result
}
```

完整版本（支持引号和转义）：
```s
func parse_command_line(string cmd) []string {
    var result: []string = {}
    var current_arg = ""
    var in_quotes = false
    var i = 0
    
    for i < len(cmd) {
        let ch = char_at(cmd, i)
        
        if ch == '"' {
            in_quotes = !in_quotes
        } else if ch == ' ' && !in_quotes {
            if len(current_arg) > 0 {
                result = append(result, current_arg)
                current_arg = ""
            }
        } else {
            current_arg = current_arg + ch
        }
        
        i += 1
    }
    
    if len(current_arg) > 0 {
        result = append(result, current_arg)
    }
    
    return result
}
```

**测试**：
```bash
# 简单测试
echo 'gcc -c -o test.o test.s' | parse_command_line
# 应该得到: ["gcc", "-c", "-o", "test.o", "test.s"]
```

---

### 第 4-5 天：进程执行

**目标文件**：`src/std/process.s` 中的 `run_command` 函数

关键难点：需要 `fork()` + `execve()` + `waitpid()`

```s
func run_command(string cmd_line) (int, string) {
    // 1. 解析命令行
    let argv = parse_command_line(cmd_line)
    if len(argv) == 0 { return -1, "empty command" }
    
    // 2. Fork 子进程
    let pid = fork()
    if pid < 0 { return -1, "fork failed" }
    
    if pid == 0 {
        // 子进程：执行命令
        // execve(argv[0], argv, environ)
        syscall.__syscall3(SYS_EXECVE, ptr_to_argv[0], ptr_to_argv, 0)
        // 如果到这里，exec 失败了
        exit(127)
    }
    
    // 3. 父进程：等待子进程
    let status = 0
    let ret = waitpid(pid, &status, 0)
    if ret < 0 { return -1, "waitpid failed" }
    
    // 4. 提取退出代码
    let exit_code = (status >> 8) & 0xFF
    
    return exit_code, ""
}
```

**关键挑战**：
- [ ] argv 数组格式转换（S array → C argv）
- [ ] 环境变量传递
- [ ] 状态码解析（宏 WEXITSTATUS）

**验证**：
```bash
# 测试 echo 命令
./test_run_command "echo hello"
# 应该输出: 0 (exit code)

# 测试非零退出
./test_run_command "false"
# 应该输出: 1

# 测试无效命令
./test_run_command "nonexistent_command_xyz"
# 应该输出: 127 (command not found)
```

---

### 第 6-7 天：完善 Bootstrap 驱动

**目标文件**：`src/cmd/compile/selfhost/bootstrap_pure_s.s`

实现三阶段启动逻辑：

```s
func bootstrap_three_stage(...) int {
    eprintln("[1/6] 读编译器源码")
    let source = file_read_string(compiler_src)
    
    eprintln("[2/6] 编译到 IR (stage1)")
    run_command(seed_compiler + " " + compiler_src + " " + stage1_ir)
    
    eprintln("[3/6] IR 转二进制")
    run_command(ir_codegen_bin + " " + stage1_ir + " -o " + stage1_bin)
    
    eprintln("[4/6] Stage1 重新编译自己 (stage2)")
    run_command(stage1_bin + " " + compiler_src + " " + stage2_ir)
    
    eprintln("[5/6] 验证确定性编译")
    if !files_equal(stage1_ir, stage2_ir) {
        eprintln("ERROR: 非确定性编译!")
        return 1
    }
    
    eprintln("[✓] 自举成功!")
    return 0
}
```

---

## 📊 工作量评估

| 任务 | 天数 | 难度 | 阻碍 |
|------|------|------|------|
| file_read_string | 1 | ⭐⭐ | 字符串↔指针转换 |
| file_write_string | 1 | ⭐⭐ | 同上 |
| parse_command_line | 1 | ⭐ | 字符操作 |
| run_command | 2 | ⭐⭐⭐ | fork/exec/wait |
| Bootstrap 完整实现 | 2 | ⭐⭐ | 集成测试 |
| **总计** | **7** | | |

---

## 🔧 需要编译器支持的 Intrinsic

为了实现上述功能，S 编译器需要这些 intrinsic：

```s
// 字符串操作
extern "intrinsic" func string_to_ptr(string s) int
extern "intrinsic" func ptr_to_string(int ptr, int len) string
extern "intrinsic" func char_at(string s, int index) string
extern "intrinsic" func slice_string(string s, int start, int end) string

// 数组操作
extern "intrinsic" func array_to_ptr([]string arr) int
extern "intrinsic" func ptr_to_array(int ptr, int len) []string

// 内存
extern "intrinsic" func allocate(int size) int
extern "intrinsic" func deallocate(int ptr) int

// 字符串工具
extern "intrinsic" func split_string(string s, string sep) []string
extern "intrinsic" func join_strings([]string arr, string sep) string
```

**检查清单**：
- [ ] 在 `src/cmd/compile/seed/` 中搜索这些 intrinsic 是否已定义
- [ ] 如果未定义，需要添加到 IR 代码生成器

---

## 🚀 快速验证

每完成一天的任务，运行：

```bash
# 1. 编译库
make lib-io-syscall
make lib-process

# 2. 运行单元测试
./bin/test_io_syscall
./bin/test_process

# 3. 检查没有 C 依赖
nm ./bin/bootstrap_driver | grep -E 'U (malloc|free|fopen|printf)'
# 应该没有输出

# 4. 检查确定性
./bootstrap_driver ... && \
diff stage1.ir stage2.ir && \
echo "✓ Deterministic!"
```

---

## 💡 关键知识点

### Linux Syscall ABI (x86-64)
```
syscall:
  rax = syscall number
  rdi = arg1
  rsi = arg2
  rdx = arg3
  r10 = arg4
  r8  = arg5
  r9  = arg6
  rcx = destroyed
  r11 = destroyed
  return: rax (result or -errno)
```

### Fork/Exec 模式
```bash
pid = fork()
if pid == 0:
    # 子进程
    execve(program, argv, env)
    # 如果 execve 失败
    exit(127)
else:
    # 父进程
    status = 0
    waitpid(pid, &status, 0)
    exit_code = (status >> 8) & 0xFF
```

### 文件 I/O 模式
```bash
fd = open(path, flags, mode)
if fd >= 0:
    bytes_read = read(fd, buffer, size)
    bytes_written = write(fd, buffer, size)
    close(fd)
```

---

## 📚 参考文档

- Linux syscall 详细文档：`man 2 syscall`
- fork/exec 编程：`man 2 fork`, `man 2 execve`
- 文件 I/O：`man 2 open`, `man 2 read`
- S 编译器代码：`src/cmd/compile/seed/` 查看 IR 生成
- 已有实现参考：`src/cmd/compile/selfhost/lexer.s` (字符串操作)

