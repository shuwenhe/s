# S 编译器完全自举 - 实现路线图

状态日期: 2026-07-24

## 当前进展 ✓

- ✅ 理解当前架构：`./bin/s` 仍依赖 C seed 库
- ✅ 识别关键问题：链接时依赖 libc
- ✅ 创建文档：详细实现指南
- ✅ 实现最小化 S runtime：`src/std/runtime_nostdlib.s`
- ✅ 创建链接器脚本：`linker_nostdlib.ld`
- ✅ 扩展 Makefile：添加 `selfhost-nostdlib` 目标

## 三个关键里程碑

### 里程碑 1：编译器链接独立化 (1-2 周)

**目标**：`./bin/s` 不依赖 libc

**任务清单**：
- [ ] 实现编译器 intrinsic syscall 支持
- [ ] 修改 C seed 的链接方式
- [ ] 生成 `-nostdlib` 的编译器二进制
- [ ] 验证：`ldd ./bin/s | grep libc` 无输出
- [ ] 验证：`nm ./bin/s | grep seed_compile` 无输出

**关键代码位置**：
- `src/cmd/compile/seed/code/native_backend.c` - IR 到二进制
- `src/cmd/compile/seed/bootstrap/bootstrap.c` - Bootstrap 过程
- `Makefile` - 链接标志

**实现步骤**：
```bash
# 1. 修改编译命令不链接 libc
gcc -nostdlib -e main -static \
    -T linker_nostdlib.ld \
    -c stage1.ir -o stage1.o

# 2. 链接只包含编译器代码
ld -T linker_nostdlib.ld \
   -o stage1 stage1.o \
   src/std/runtime_nostdlib.s

# 3. 验证
ldd stage1  # 应该无输出
```

### 里程碑 2：纯 S 编译工具链前端 (2-4 周)

**目标**：用 S 实现完整的编译 frontend

**任务清单**：
- [ ] 完成 `lexer.s` 功能完整性
- [ ] 实现 `parser.s` - 语法分析
- [ ] 实现 `semantic.s` - 语义检查
- [ ] 集成到 `compile_pipeline.s`
- [ ] 验证能编译自身

**代码结构**：
```
src/cmd/compile/selfhost/
├── lexer.s            (✅ 已有)
├── parser.s           (待实现)
├── semantic.s         (待实现)
├── compile_pipeline.s (待实现)
└── ir_generator.s     (待实现)
```

**测试**：
```bash
# 编译简单 S 程序
./bin/s test_simple.s /tmp/test.ir

# 用编译器编译自身
./bin/s src/cmd/compile/main.s /tmp/main.ir
```

### 里程碑 3：完整纯 S 编译器 (4-8 周)

**目标**：编译器 100% 用 S 实现，无需 C seed

**任务清单**：
- [ ] 完成所有编译阶段的 S 实现
- [ ] 实现 ELF 链接器（或 IR→ASM→Binary）
- [ ] 完成 bootstrap 过程
- [ ] `make true-selfhost-check` 通过
- [ ] 支持多架构 (x86-64, ARM64, etc.)

**验证条件**：
```
1. true-selfhost-check 通过
2. 编译器大小: < 5MB
3. 编译速度: > 1MB/s
4. 支持文件: ≥ 95% 的 stdlib
```

## 立即行动 (今天)

### 1. 验证基础设施已就位

```bash
cd /home/shuwen/shuwen/s

# 检查新创建的文件
ls -la src/std/runtime_nostdlib.s
ls -la linker_nostdlib.ld
ls -la docs/SELFHOST_IMPLEMENTATION.md

# 检查 Makefile 更新
grep selfhost-nostdlib Makefile

# 运行新目标
make selfhost-nostdlib
```

### 2. 实现编译器 syscall 支持

在 `src/cmd/compile/` 中创建：

```s
// src/cmd/compile/runtime/syscalls.s
package compile.runtime

// Intrinsic syscall wrapper
extern "intrinsic" func syscall(int nr, ...i64) i64

// Exit with code
func syscall_exit(int code) {
    syscall(60, i64(code))  // x86-64 syscall: exit
}

// Write to fd
func syscall_write(int fd, string text) int {
    return int(syscall(1, i64(fd), text_ptr(text), i64(len(text))))
}

// Get command line arguments
func syscall_getargs() []string {
    // Implementation
    return []string{}
}
```

### 3. 修改链接过程

编辑 `Makefile` 中的 `selfhost-nostdlib`：

```makefile
# 使用 nostdlib 标志
selfhost-nostdlib: seed-compiler-bin
	@mkdir -p $(SELFHOST_DIR) ./bin
	@S_SOURCE_ROOT=$(CURDIR) ./bin/s_seed --bootstrap src/cmd/compile/main.s $(SELFHOST_DIR)
	@gcc -nostdlib -e __start \
		-T linker_nostdlib.ld \
		-static \
		-o ./bin/s_nostdlib \
		$(SELFHOST_DIR)/stage2.o
	@echo "Installed: ./bin/s_nostdlib (no libc)"
```

### 4. 验证

```bash
# 构建
make selfhost-nostdlib

# 验证无 libc 依赖
ldd ./bin/s_nostdlib
# 应该输出: not a dynamic executable (静态链接)
# 或: 无任何共享库

# 验证可用性
./bin/s_nostdlib --help
./bin/s_nostdlib test/simple.s /tmp/test.ir
```

## 关键文件位置

| 文件 | 用途 | 状态 |
|------|------|------|
| `src/std/runtime_nostdlib.s` | 最小化运行时 | ✅ 已创建 |
| `linker_nostdlib.ld` | 链接脚本 | ✅ 已创建 |
| `docs/SELFHOST_IMPLEMENTATION.md` | 实现指南 | ✅ 已创建 |
| `src/cmd/compile/selfhost/bootstrap_pure_s.s` | 纯S Bootstrap | ✅ 已创建 |
| `src/cmd/compile/runtime/syscalls.s` | 系统调用 | 待创建 |
| `Makefile` (selfhost-nostdlib) | 构建规则 | ✅ 已更新 |

## 技术挑战与解决方案

### 挑战 1: 缺少 printf/fprintf

**解决方案**：使用 syscall 直接写入 stdout

```s
func eprintln(string msg) {
    syscall_write(STDERR_FILENO, msg + "\n")
}
```

### 挑战 2: 内存管理

**解决方案**：使用 brk() syscall 实现简单的 bump allocator

```s
func malloc(int size) &byte {
    let new_break = current_break + size
    brk(new_break)  // Extend heap
    return &byte(current_break)
}
```

### 挑战 3: 文件 I/O

**解决方案**：使用 open/read/write/close syscalls

```s
func read_file(string path) string {
    let fd = syscall_open(path, O_RDONLY)
    // ... read loop using syscall_read
    syscall_close(fd)
}
```

## 预期收益

- ✅ 编译器完全独立
- ✅ 无需 C 库依赖
- ✅ 可在任何系统上运行
- ✅ 真正实现自举
- ✅ 可作为标准示例

## 后续优化

1. **性能**：实现 `-O2` 优化
2. **代码大小**：减少二进制大小
3. **兼容性**：支持更多平台
4. **工具链**：完整的开发工具集

## 参考链接

- [Linux Syscall Reference](https://filippo.io/linux-syscall-table/)
- [System V AMD64 ABI](https://gitlab.com/x86-psABI/x86-64-ABI)
- [ELF Format](https://refspecs.linuxbase.org/elf/elf.pdf)
- [Self-hosting Compilers](https://en.wikipedia.org/wiki/Bootstrapping_(compilers))

## 提交和追踪

完成任务后提交：

```bash
git add -A
git commit -m "feat: S compiler bootstrapping infrastructure

- Add nostdlib runtime library (src/std/runtime_nostdlib.s)
- Add linker script for independent execution (linker_nostdlib.ld)
- Add documentation (docs/SELFHOST_IMPLEMENTATION.md)
- Update Makefile with selfhost-nostdlib target
- Infrastructure ready for true self-hosting

Next: Implement syscall wrappers in compiler"

git push origin main
```
