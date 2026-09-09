# S编译器平台架构

本文档描述S编译器的平台抽象层设计，便于添加新平台。

## 📁 目录结构

```
src/cmd/compile/
├── compiler.s              # 主编译器（调用各平台后端）
├── target.s                # 目标平台抽象层（定义接口）
│
├── platforms/              # 各平台特定实现
│   ├── macos/              # Apple macOS平台
│   │   ├── macos_driver.s     # 编译驱动
│   │   ├── macho_backend.s    # Mach-O后端
│   │   ├── macos_example.s    # 使用示例
│   │   ├── macos_demo.s       # 演示程序
│   │   └── README.md          # 平台文档
│   │
│   ├── linux/              # Linux平台 (待创建)
│   │   ├── linux_driver.s
│   │   ├── elf_backend.s
│   │   └── README.md
│   │
│   └── windows/            # Windows平台 (待创建)
│       ├── windows_driver.s
│       ├── pe_backend.s
│       └── README.md
│
├── seed/                   # C语言seed编译器
│   └── code/
│       ├── backend_registry.c   # 平台选择器
│       ├── native_backend.c     # C代码生成
│       └── standalone_amd64_backend.c  # x86_64直接生成
│
└── build/
    └── macos.mk            # macOS构建规则
```

## 🎯 平台接口定义

### 核心抽象
每个平台需要实现以下功能：

```s
// 1. 架构检测
func detect_architecture() string
    // 返回: "arm64", "x86_64", "amd64"

// 2. SDK/工具检测
func detect_sdk_path() string
    // 返回: SDK路径或空字符串

// 3. 汇编生成
func generate_assembly(string arch) string
    // 返回: 汇编代码

// 4. 编译
func compile_assembly(string asm_file, string obj_file) int
    // 返回: 编译结果 (0=成功)

// 5. 链接
func link_to_executable(string obj_file, string output) int
    // 返回: 链接结果 (0=成功)
```

## 🔄 编译流程

### 通用流程
```
源代码 (.s)
    ↓
[前端] 词法/语法/语义分析
    ↓
[平台选择] 根据S_TARGET_OS选择后端
    ↓
[后端] 平台特定代码生成
    ├─ Linux: ELF + 汇编 → ASM
    ├─ macOS: Mach-O + 汇编 → ASM
    └─ Windows: PE + 汇编 → ASM
    ↓
[汇编编译] as/clang/ml64 → OBJ
    ↓
[链接] ld/clang/link → 可执行文件
    ↓
目标可执行文件
```

## 🏗️ 平台特定实现

### Linux平台
**文件**: `platforms/linux/`

**特性**:
- ELF二进制格式
- 支持x86_64和ARM64
- 动态链接支持
- PIE (Position Independent Executable)

**工具**:
- 编译器: gcc/clang
- 汇编器: as
- 链接器: ld

### macOS平台
**文件**: `platforms/macos/`

**特性**:
- Mach-O二进制格式
- 支持x86_64和ARM64
- Universal Binary (Fat)
- Code Signing

**工具**:
- 编译器: clang
- 汇编器: as
- 链接器: clang

### Windows平台
**文件**: `platforms/windows/` (待创建)

**特性**:
- PE二进制格式
- 支持x86_64
- DLL动态链接库
- 清单和资源

**工具**:
- 编译器: cl.exe
- 汇编器: ml64.exe
- 链接器: link.exe

## 🔌 如何添加新平台

### 步骤1: 创建平台目录
```bash
mkdir -p src/cmd/compile/platforms/newos
```

### 步骤2: 实现平台驱动
创建 `platforms/newos/newos_driver.s`:

```s
package newos_driver

// 1. 检测函数
func detect_architecture() string {
    // 实现架构检测
    return "arm64"
}

func detect_sdk_path() string {
    // 实现SDK检测
    return "/path/to/sdk"
}

// 2. 汇编生成
func generate_arm64_assembly() string {
    // 生成ARM64汇编
    return "..."
}

func generate_x86_64_assembly() string {
    // 生成x86_64汇编
    return "..."
}

// 3. 编译和链接
func compile_assembly_to_object() int {
    // 调用编译器
    return 0
}

func link_to_executable() int {
    // 调用链接器
    return 0
}

// 4. 主编译入口
func compile() int {
    // 完整编译流程
    return 0
}
```

### 步骤3: 实现后端
创建 `platforms/newos/newos_backend.s`:

```s
package newos_backend

// 定义二进制格式
struct newos_header {
    uint magic
    uint arch
    uint file_type
    // ... 其他字段
}

// 实现二进制生成
func generate_binary() string {
    // 返回二进制数据
    return ""
}
```

### 步骤4: 创建平台文档
创建 `platforms/newos/README.md`:

```markdown
# NewOS平台支持

## 特性
- ...

## 使用
...
```

### 步骤5: 注册平台
修改 `compiler.s` 或平台选择器:

```s
if target_os == "newos" {
    import "platforms/newos/newos_driver"
    ret := newos_driver.compile()
}
```

## 🔗 平台选择流程

### 环境变量
```bash
export S_TARGET_OS=darwin      # darwin, linux, windows
export S_TARGET_ARCH=arm64     # arm64, amd64, x86_64
export S_HOST_OS=darwin        # 编译器运行的OS
export S_HOST_ARCH=arm64       # 编译器运行的架构
```

### 程序流程
```
S编译器启动
    ↓
读取 S_TARGET_OS 和 S_TARGET_ARCH
    ↓
调用 backend_registry.c
    ↓
根据目标平台选择后端
    ├─ linux → standalone_amd64_backend.c
    ├─ darwin → platforms/macos/macos_driver.s
    └─ windows → platforms/windows/windows_driver.s (待实现)
    ↓
执行编译流程
```

## 📊 平台矩阵

```
操作系统         架构          二进制格式    状态
─────────────────────────────────────────────
Linux/x86_64     amd64         ELF         ✅
Linux/ARM        arm64         ELF         ✅
macOS/x86        x86_64        Mach-O      ✅
macOS/ARM        arm64         Mach-O      ✅
Windows/x64      x86_64        PE          🟡
iOS              arm64         Mach-O      🟡
RISC-V           riscv64       ELF         🟡
```

## 🛠️ 构建系统集成

### Makefile规则

每个平台目录应包含 `rules.mk`:

```makefile
# src/cmd/compile/platforms/macos/rules.mk

.PHONY: macos-compile macos-test macos-clean

macos-compile:
	@echo "Compiling for macOS..."
	@$(S_COMPILER) build platforms/macos/macos_demo.s

macos-test:
	@echo "Testing macOS platform..."
	@make -f build/macos.mk test-macos

macos-clean:
	@rm -rf build/macos
```

## 🎓 最佳实践

### 1. 使用通用接口
```s
// ❌ 错误: 平台特定的函数
func macos_compile() int

// ✅ 正确: 通用接口
func compile() int
```

### 2. 错误处理
```s
// ✅ 好: 完整的错误报告
ret := system(cmd)
if ret != 0 {
    println("Error: compilation failed")
    return ret
}
```

### 3. 日志和调试
```s
// ✅ 好: 包含调试信息
if debug_enabled {
    println("Using SDK: " + sdk_path)
}
```

### 4. 文档
```s
// ✅ 好: 清晰的函数文档
// compile_assembly_to_object() 将汇编文件编译为目标文件
// 使用平台特定的编译器 (clang/gcc/cl)
// 返回: 0=成功, 非0=失败
func compile_assembly_to_object() int
```

## 📚 参考资源

### Linux/ELF
- [ELF规范](http://www.skyfree.org/linux/references/ELF_Format.pdf)
- [x86_64 ABI](https://github.com/hjl-tools/x86-psABI/wiki/x86-64-psABI-1.0.pdf)
- [ARM64 ABI](https://github.com/ARM-software/abi-aa)

### macOS/Mach-O
- [Mach-O文件格式](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/MachORuntime/)
- [Apple ARM64 ABI](https://developer.apple.com/documentation/)

### Windows/PE
- [PE规范](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format)
- [x86_64 微软ABI](https://docs.microsoft.com/en-us/cpp/build/x64-software-conventions)

## 🎯 下一步平台

### 优先级1 (1-2周)
- [ ] Linux平台重组 (从seed分离)
- [ ] 创建 platforms/linux/

### 优先级2 (2-4周)
- [ ] Windows平台初步支持
- [ ] PE二进制生成

### 优先级3 (1-2个月)
- [ ] iOS支持 (基于macos)
- [ ] RISC-V支持

## 📞 贡献指南

如果要贡献新平台:

1. Fork项目
2. 创建特性分支: `git checkout -b feature/newos-support`
3. 实现平台支持
4. 添加文档
5. 提交PR

---

**更新**: 2026-09-09  
**S编译器版本**: latest  
**平台数量**: 2 (Linux, macOS)  
**计划平台**: 3 (+ Windows)
