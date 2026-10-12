# Native Bootstrap `duplicate main` - P0 问题调查

**调查日期**: 2026-10-12  
**调查阶段**: 第一阶段 - 问题定位  
**调查范围**: 只读分析，不涉及代码修改

---

## 问题陈述

**症状**:
Seed 编译器在编译 S 编译器自身时报告"函数重复定义"，具体为两个 `main` 函数被视为重复。

**上下文**:
```
src/cmd/compile/main.s
  package compile.internal.main
  func main(string[] args) int { ... }

src/cmd/compile/internal/compiler/compiler.s
  package compile.internal.compiler
  func main(string[] args) int { ... }
```

两个 `main` 函数在**不同的包**中，但在 import-driven 编译单元中被合并。

---

## 第一阶段：问题解剖

### 关键发现 1: 两个 main 确实在不同的包中

| 文件 | 包名 | 函数 | 行为 |
|------|------|------|------|
| `src/cmd/compile/main.s` | `compile.internal.main` | `func main(args)` | 入口点，调用 `compile.internal.compiler.main()` |
| `src/cmd/compile/internal/compiler/compiler.s` | `compile.internal.compiler` | `func main(args)` | 实际的编译器主逻辑 |

**证据**:
```s
// main.s (package compile.internal.main)
package compile.internal.main
import ("compile.internal.compiler")

func main(string[] args) int {
    return compile.internal.compiler.main(args)
}

// compiler.s (package compile.internal.compiler)
package compile.internal.compiler
import ("std")

func main(string[] args) int {
    buildcfg_err := buildcfg_check()
    // ... 实际的编译器逻辑
}
```

### 关键发现 2: Import-Driven Source Closure 机制

S 编译器使用"导入驱动的源代码闭包"（类似 Go）：

```
bootstrap flow:
─────────────

native-bootstrap.sh
  ↓
compile_native_stage()
  ↓
$compiler --emit-asm <source_file> <output.S>
         │
         └─ 默认: $source_file = "$work/compiler.s"
         
但生产编译时:
$compiler --emit-asm src/cmd/compile/main.s output.S
         ↓
Seed 编译器看到 main.s
         ↓
解析 use compile.internal.compiler
         ↓
自动加载对应的源文件
         ↓
? 如何处理重复的函数名?
```

### 关键发现 3: 编译单元的构建

从 `src/cmd/compile/internal/noder/` 的代码：

```s
// noder.s: compile_unit() 是处理单个源文件的函数
func compile_unit(string source_path, ...) {
    unit := read_unit(source_path)          // 读取单个文件
    ast_result := s.parse_source(unit.text) // 解析为 AST
    ast := ast_result.unwrap()
    ir := lower_to_ir(ast)                  // 转换为 IR
    exports := collect_exports(ast)
    // ... 返回单个单元的结果
}

// unified.s: run_unified() 处理单个源文件的解析
func run_unified(string path, string[] quirks) {
    unit := read_unit(path)
    tokens := lex_source(unit)
    imports := parse_imports(unit)           // 提取 use 语句
    ast_result := s.parse_source(unit.text)  // 调用 s.parse_source()
    // ...
}
```

**关键观察**:
- `run_unified()` 处理**单个源文件**
- 它提取 imports 但**似乎没有递归加载依赖**
- 真正的导入驱动闭包可能发生在 **Seed 编译器中**（C 代码）

---

## 第二阶段：五个关键问题

### Q1: Seed 在编译单元中如何建立函数身份？

**观察**:
- S 编译器的 noder 代码处理单个文件
- 导入加载可能在 Seed 编译器中
- 函数名 + 包名应该形成唯一标识

**假设**:
- 函数身份 = 包名 + 函数名
- 不同包的 `main` 应该被区分
- 如果 Seed 不包含包名，就会产生冲突

**测试点**:
- Seed 在处理多源文件编译单元时，是否包含包名信息
- Seed 的符号表是否使用 `package.function` 格式

**状态**: ⚠️ **HYPOTHESIS** - 未测试

---

### Q2: 函数身份是否包含 package？

**观察**:
- 两个 `main` 在不同包中 (`compile.internal.main` vs `compile.internal.compiler`)
- 按标准，应该分别被标识为：
  - `compile.internal.main.main`
  - `compile.internal.compiler.main`

**假设**:
- 如果 Seed 忽略包名，只看函数名 `main`，就会报告重复
- 这是最可能的根本原因

**测试点**:
- 创建最小复现：两个文件，两个包，各一个同名函数
- 查看 Seed 是否报告重复

**状态**: ⚠️ **HYPOTHESIS** - 需要最小复现验证

---

### Q3: 两个不同 package 的 main 是否被错误地视为同一符号？

**观察**:
```
如果 Seed 的符号表实现为:
  symbols["main"] → [function_info]
  
而不是:
  symbols["compile.internal.main.main"] → [function_info]
  symbols["compile.internal.compiler.main"] → [function_info]

那么第二个 main 会覆盖或被检测为重复。
```

**假设**:
- Seed 的符号表可能在某个阶段丢失了包名信息
- 或者在合并多个源文件的符号时，没有正确前缀包名

**测试点**:
- 检查 Seed 编译器（bin/s_seed）是否有调试输出
- 追踪错误消息的具体内容
- 查看重复检测发生的阶段（Parser? Semantic? IR?)

**状态**: ⚠️ **HYPOTHESIS** - 需要 Seed 编译器的详细输出

---

### Q4: 是 Parser、Semantic 符号表还是 IR 合并阶段首次报告重复？

**观察**:
编译有多个阶段：
1. **Parser** (syntax.parse_source) - 生成 AST，可能建立符号表
2. **Semantic** (semantic.check_source_file) - 类型检查，维护符号表
3. **Monomorphization** (mono.monomorphize_file) - 泛型单形化
4. **IR Lowering** (ir.lower.lower_main_to_mir) - AST → IR
5. **Backend** - 后续处理

**假设**:
- 最可能在 **Parser** 或 **Semantic** 阶段检测重复
- 这两个阶段建立和维护符号表

**测试点**:
- Seed 的错误消息是否指明阶段
- 查看 Parser、Semantic 的重复检测逻辑

**状态**: ⚠️ **HYPOTHESIS** - 需要错误消息分析

---

### Q5: 最小复现是否能证明这是跨包同名函数的一般问题？

**观察**:
```
最小复现案例:

file1.s:
  package pkg1
  func foo() int { 1 }

file2.s:
  package pkg2
  use pkg1
  func foo() int { 2 }
  
预期:
  ✓ 两个 foo 被正确区分为 pkg1.foo 和 pkg2.foo

实际 (如果有 bug):
  ✗ Seed 报告函数 foo 重复定义
```

**假设**:
- 如果这是一个一般的问题，任何跨包同名都会触发
- 不仅限于 `main` 函数
- 这证明问题不在应用逻辑，而在编译器的符号表管理

**测试点**:
- 创建 3-5 个最小复现案例
- 使用不同的函数名（不仅 main）
- 验证重复错误是否在所有情况下出现

**状态**: ⚠️ **HYPOTHESIS** - 需要实验验证

---

## 当前的架构理解

### Pipeline 的权威链

```
Pipeline (顶层)
  ├─ Input: src/cmd/compile/main.s
  ├─ Authority: pipeline_compile()
  │   ├─ [权威交接点1] Frontend 权威 ← 目前缺失!
  │   ├─ [权威交接点2] Middlend 权威 ← 在 Backend 中
  │   └─ [权威交接点3] Backend 权威 ← backend_elf64.build()
  └─ Output: 编译后的二进制
```

**问题**:
- Pipeline 层级已存在
- 但前端权威交接点不清晰
- 导入驱动的源代码闭包处理散落在各处

### 相关的代码模块

| 模块 | 位置 | 职责 |
|------|------|------|
| noder | `src/cmd/compile/internal/noder/` | 单文件编译单元处理 |
| unified | `src/cmd/compile/internal/noder/unified.s` | 源代码解析和 import 提取 |
| import | `src/cmd/compile/internal/noder/import.s` | import 语句解析 |
| backend | `src/cmd/compile/internal/core/backend_elf64.s` | 跨阶段编排（但这应该属于前端或 Pipeline） |
| Seed | `bin/s_seed` | 导入驱动闭包的实际实现（C 代码） |

---

## 下一步调查计划

### 第二阶段：错误定位 (建议 1-2 天)

**任务 1: 获取详细的 Seed 错误输出**
```bash
# 运行 Seed 编译器并捕获完整的错误消息
S_BOOTSTRAP_SOURCE=src/cmd/compile/main.s \
  ./bin/s_seed --emit-asm src/cmd/compile/main.s /tmp/test.S 2>&1 | tee /tmp/error.log

# 检查错误消息中：
# 1. 函数完整名称（是否包含包名）
# 2. 重复检测发生的阶段
# 3. 涉及的文件和行号
```

**任务 2: 创建最小复现**
```
测试案例 A: 同一包中的重复
  file1.s: package p1, func foo() {}
  file2.s: package p1, func foo() {}
  预期: ✓ 报告重复

测试案例 B: 不同包中的同名
  file1.s: package p1, func foo() {}
  file2.s: package p2, use p1, func foo() {}
  预期: ✓ 不报告重复（如果 Seed 正确）

测试案例 C: main 函数
  file1.s: package compile.internal.main, func main() {}
  file2.s: package compile.internal.compiler, func main() {}
  预期: ✓ 不报告重复（如果 Seed 正确）
```

**任务 3: 分析错误来源**
- 错误是来自 Parser？Semantic？还是其他阶段？
- 错误涉及的符号表是什么格式？

---

### 第三阶段：根本原因确认 (建议后续)

**基于第二阶段的结果**：

- 如果最小复现重现了问题 → 这是 Seed 编译器的通用 bug
- 如果最小复现不重现 → 问题可能特定于 `main` 函数或 import 处理
- 根据错误消息 → 确定精确的修复位置

---

## 停止条件

✅ **调查完成当**:
1. 找到第一个报告重复的确切位置（文件、函数、行号）
2. 创建能够重现问题的最小测试案例
3. 确认问题的范围（是否影响所有跨包同名函数）
4. 给出根本原因假说（需要修复的是 Seed 的哪个部分）

❌ **不做**:
- 不修改编译器代码
- 不拆分 backend_elf64.s
- 不试图绕过 main 冲突
- 不预先宣布权威交接

---

## 审计状态

**Backend Responsibility Audit**: ✅ 冻结
- 结论已提交
- 不再修改
- 拆分建议标记为"估计"

**Native Bootstrap Investigation**: 🔄 开始
- 第一阶段：问题解剖 (当前)
- 第二阶段：错误定位 (待执行)
- 第三阶段：根本原因确认 (待执行)

---

**调查开始时间**: 2026-10-12  
**下一个里程碑**: 获取 Seed 详细错误输出
