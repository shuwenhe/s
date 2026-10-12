# Go vs S 编译器 - 入口文件对比

**对比日期**: 2026-10-12  
**范围**: 编译器入口点和主控制流

---

## 快速对比

| 特性 | Go 编译器 | S 编译器 |
|------|---------|---------|
| **顶层入口** | src/cmd/compile/main.go (59行) | src/cmd/compile/main.s (9行) |
| **实际主逻辑** | src/cmd/compile/internal/gc/main.go (446行) | src/cmd/compile/internal/compiler/compiler.s (28行) |
| **总代码量** | 505 行 | 37 行 (已知) |
| **层级数** | 2 层 | 3+ 层 (推测) |

---

## 1. Go 编译器入口

### main.go (59 行)
```go
package main

import (
    "cmd/compile/internal/amd64"
    "cmd/compile/internal/arm"
    // ... 其他架构导入
    "cmd/compile/internal/gc"
)

var archInits = map[string]func(*ssagen.ArchInfo){
    "386":      x86.Init,
    "amd64":    amd64.Init,
    "arm":      arm.Init,
    // ... 所有架构列表
}

func main() {
    log.SetFlags(0)
    log.SetPrefix("compile: ")
    
    buildcfg.Check()
    archInit, ok := archInits[buildcfg.GOARCH]
    if !ok {
        fmt.Fprintf(os.Stderr, "compile: unknown architecture %q\n", buildcfg.GOARCH)
        os.Exit(2)
    }
    
    gc.Main(archInit)  // ← 关键委托
    base.Exit(0)
}
```

**特点**:
- ✅ 代码简洁（59行）
- ✅ 架构初始化明确
- ✅ 直接委托给 gc.Main()

### gc.Main() (446 行)
- 实际编译逻辑
- 初始化各子系统
- 解析命令行
- 处理源文件
- 调用编译流程

---

## 2. S 编译器入口

### main.s (9 行)
```s
package compile.internal.main

import (
    "compile.internal.compiler"
)

func main(string[] args) int {
    return compile.internal.compiler.main(args)
}
```

**特点**:
- ✅ 极简（9行）
- ✅ 纯粹的委托
- ✅ 甚至不处理错误

### compiler.s (28 行)
```s
package compile.internal.compiler
import (
    "std"
)

func main(string[] args) int {
    buildcfg_err := buildcfg_check()
    if buildcfg_err != "" {
        return 2
    }
    arch_err := arch_dispatch_init(buildcfg_goarch())
    if arch_err != "" {
        return 2
    }
    return build_main(args)  // ← 神秘函数！
}
```

**特点**:
- ✅ 架构初始化处理
- ✅ 基本的错误检查
- ❌ build_main 位置不明

---

## 3. build_main 之谜

**问题**: build_main 在 S 代码中被调用但**找不到定义**！

### 被调用的地方：
1. **compiler/compiler.s**
   ```s
   return build_main(args)
   ```

2. **gc/compile.s**
   ```s
   status := build_main(args)
   ```

### 可能的位置：
1. ❓ **core/backend_elf64.s** (最可能)
   - 后端是编译的核心
   - 包含许多 build_* 函数

2. ❓ **Seed 编译器提供**
   - 作为 std 库的一部分
   - C 编译的 bin/s_seed 中

3. ❓ **链接时链接**
   - bootstrap 过程中动态链接

### 推测流程：
```
compiler.main()
  ├─ buildcfg_check()
  ├─ arch_dispatch_init()
  └─ build_main(args)  ← ???
     ├─ pipeline_compile()  ?
     │  └─ backend_elf64.build()
     └─ 或直接
        └─ backend_elf64.build()
```

---

## 4. 架构初始化对比

### Go: 架构映射表 + 函数指针
```go
var archInits = map[string]func(*ssagen.ArchInfo){
    "amd64": amd64.Init,
    // ...
}

archInit, ok := archInits[buildcfg.GOARCH]
gc.Main(archInit)
```

**优势**:
- ✅ 显式注册
- ✅ 易于添加新架构
- ✅ 编译时检查

### S: 调用函数
```s
arch_err := arch_dispatch_init(buildcfg_goarch())
```

**优势**:
- ✅ 集中处理
- ✅ 返回错误

**问题**:
- ❓ arch_dispatch_init 在哪里？
  推测在 dispatch/ 模块

---

## 5. 代码复杂度对比

```
        Go          S
───────────────────────
入口    59行        9行     (S 多简洁 6.5x)
主逻辑  446行       ?       (未知)
已知总计 505行      37行    (当前 Go 多 13.6x)
```

**分析**:
- S 的入口极其精简
- 但 build_main 隐藏了实际复杂度
- 可能 build_main 包含了 Go 在 gc.Main 中的所有代码

---

## 6. 权威链对比

### Go: 清晰的权威链
```
main.go
  ├─ 权威: 架构初始化选择
  └─ 委托给: gc.Main()
     ├─ 权威: 编译流程管理
     └─ 委托给: 各个子系统
        ├─ syntax (词法/语法)
        ├─ typecheck (类型检查)
        ├─ ssa (SSA 生成)
        └─ ssagen (代码生成)
```

### S: 待确认的权威链
```
main.s
  ├─ 权威: 包路由
  └─ 委托给: compiler.main()
     ├─ 权威: 架构初始化检查
     └─ 委托给: build_main()
        ├─ 权威: ???
        └─ 委托给: ???
```

---

## 7. 立即行动

### 第一步: 找出 build_main
```bash
# 方法 1: 全局搜索
grep -r "func build_main" /home/shuwen/shuwen/s/src/

# 方法 2: 检查 core 模块
grep "func build" /home/shuwen/shuwen/s/src/cmd/compile/internal/core/backend_elf64.s | head -20

# 方法 3: 查看链接过程
nm bin/s_seed | grep build_main

# 方法 4: 运行编译器看错误信息
src/cmd/compile/main.s 2>&1 | head
```

### 第二步: 追踪调用链
```bash
grep -A 20 "func build_main" src/cmd/compile/internal/*/backend*.s
```

### 第三步: 理解 Pipeline
```bash
head -100 src/cmd/compile/internal/pipeline/pipeline.s
```

---

## 结论

| 方面 | Go | S |
|------|-----|-----|
| **入口清晰度** | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **代码简洁性** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **权威链明确** | ⭐⭐⭐⭐ | ⭐⭐ |
| **架构初始化** | ⭐⭐⭐⭐ | ⭐⭐⭐ |

**关键发现**:
- Go: 明确 + 集中 + 经证实
- S: 精简 + 分散 + 有谜团

**下一步**: 解开 build_main 之谜！
