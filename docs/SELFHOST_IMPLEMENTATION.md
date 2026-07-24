# S 编译器完全自举实现指南

## 概述

实现 S 编译器的完全自举（不依赖任何 C 库）需要多个阶段的工作。本文档描述了分阶段的实现策略。

## 当前状态

```
✅ S 可以编译 S 代码到 IR
✅ S 可以将 IR 转换为二进制（使用 GCC 链接）
❌ 最终二进制仍然链接到 libc（来自 C seed 编译的二进制）
❌ 无法消除 C 库依赖
```

## 完全自举的三个阶段

### 阶段 1：消除编译器本身的 C 依赖（当前重点）

**目标**：生成一个纯 S 的编译器，不链接任何 C 库

**关键步骤**：
1. 实现最小化 S 运行时库（替代 libc）
2. 创建纯 S 链接器或使用 `-nostdlib` 标志
3. 修改编译过程不调用 C seed 的链接器

**实现路线**：

```
Stage 1: Implement S runtime stubs
├── malloc/free implementations
├── printf/file I/O stubs
└── syscall wrappers

Stage 2: Create pure S linker
├── Parse ELF format
├── Link object files
└── Generate executable without libc

Stage 3: Bootstrap compilation
├── Compile main.s → IR (using current seed)
├── Emit IR → ASM (using S code generator)
├── Assemble with AS
├── Link with pure S linker
```

### 阶段 2：实现完整的 S 编译工具链

**组件**：
- `lexer.s` - 词法分析 ✅ (已有)
- `parser.s` - 语法分析 (待实现)
- `semantic.s` - 语义分析 (待实现)
- `ir_generator.s` - IR 生成 (待实现)
- `x86_64_codegen.s` - x86-64 代码生成 ✅ (已有)
- `elf_linker.s` - ELF 链接器 (待实现)

### 阶段 3：完全自主引导

**流程**：
```
S source → S Parser → S IR Gen → S Codegen → S Linker → Executable
       (纯 S 实现，不依赖任何外部工具)
```

## 立即可实现的改进

### 1. 使用 `-nostdlib` 编译

修改构建过程，在最终链接时不使用 libc：

```bash
# 当前方式
gcc -o stage2 stage2.s

# 改进方式  
gcc -nostdlib -e main -static stage2.s
```

这需要：
- 实现 `_start` 符号
- 实现 `exit` 系统调用
- 实现 `write` 系统调用用于输出

### 2. 实现最小 S Runtime

创建 `src/std/runtime_nostdlib.s`：

```s
package std.runtime

// System call wrapper for x86-64 Linux
extern "intrinsic" func syscall(int nr, ...i64) i64

// Exit process
func exit(int code) {
    syscall(60, i64(code))  // exit syscall #60
}

// Write to file descriptor
func write(int fd, []byte buf) int {
    return int(syscall(1, i64(fd), ptr(buf), i64(len(buf))))  // write syscall #1
}

// Minimal memory allocator
var heap_ptr: i64 = 0x10000000  // Start of heap
const HEAP_SIZE = 1 * 1024 * 1024  // 1MB

func malloc(int size) &byte {
    let ptr = heap_ptr
    heap_ptr += i64(size)
    if heap_ptr > 0x10000000 + HEAP_SIZE {
        return nil
    }
    return &byte(ptr)
}

func free(&byte ptr) {
    // No-op in simple allocator
}
```

### 3. 修改 Bootstrap 过程

创建 `Makefile.selfhost-nostdlib`：

```makefile
# Build stage1 without C library
stage1-nostdlib: seed-compiler-bin
	./bin/s_seed src/cmd/compile/main.s .bootstrap/nostdlib/main.ir
	gcc -nostdlib \
		-Wl,--entry=main \
		-Wl,-m,elf_x86_64 \
		-T linker.ld \
		-o .bootstrap/nostdlib/stage1 \
		.bootstrap/nostdlib/main.ir

# Build stage2 using stage1
stage2-nostdlib: stage1-nostdlib
	.bootstrap/nostdlib/stage1 src/cmd/compile/main.s .bootstrap/nostdlib/stage2.ir
	# ... rest of compilation
```

### 4. 创建 Linker Script

创建 `linker.ld`：

```ld
ENTRY(main)

SECTIONS
{
    . = 0x400000;
    
    .text : {
        *(.text)
        *(.rodata)
    }
    
    .data : {
        *(.data)
        *(.bss)
    }
    
    /DISCARD/ : {
        *(.note.GNU-stack)
        *(.gnu_version)
    }
}
```

## 验证步骤

### 检查清单

- [ ] 编译器不链接 libc
  ```bash
  nm ./bin/s | grep -i "__libc"  # 应该无输出
  ldd ./bin/s | grep libc         # 应该无输出
  ```

- [ ] 编译器可以自编译
  ```bash
  ./bin/s src/cmd/compile/main.s /tmp/verify.ir
  ```

- [ ] 生成的二进制独立运行
  ```bash
  ./bin/s --version  # 应该成功
  echo "func main() int { return 0 }" > test.s
  ./bin/s test.s /tmp/test.ir
  ```

## 后续工作

### Phase 2: 完整编译器实现

需要在 S 中实现：
- 完整的语法分析器
- 类型系统和语义检查
- 中间代码优化
- 完整的代码生成

### Phase 3: 目标平台扩展

- ARM64 支持
- WebAssembly 支持
- RISC-V 支持

## 参考资源

- [ELF Format](https://refspecs.linuxbase.org/elf/elf.pdf)
- [System V AMD64 ABI](https://gitlab.com/x86-psABI/x86-64-ABI)
- [x86-64 Syscall Reference](https://filippo.io/linux-syscall-table/)

## 相关文件

- 词法分析: `src/cmd/compile/selfhost/lexer.s`
- x86-64 代码生成: `src/cmd/compile/selfhost/x86_64_codegen.s`
- ELF 生成: `src/cmd/compile/selfhost/elf_gen.s`
- Bootstrap 驱动: `src/cmd/compile/selfhost/bootstrap_pure_s.s`
