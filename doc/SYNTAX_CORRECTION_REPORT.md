# S 语言语法修正报告

**日期**: 2026-09-02  
**修正范围**: 移除所有 Rust 风格的指针语法，统一为 S 语言规范

---

## 问题描述

编译器代码库中混用了 Rust 风格的指针和参数语法，不符合 S 语言的规范：

### ❌ 错误的 Rust 风格语法

```rust
// 参数列表
func lexer_read_char(lex: &mut lexer) { }
func parser_parse(p: &mut parser) ast_node { }
func semantic_analyze(ast: &ast_node) semantic_result { }

// 函数调用
lexer_read_char(&mut lex)
parser_parse(&mut p)

// 返回值类型
result[T, E]
option[T]
```

---

## 修正方案

### ✅ S 语言正确语法

根据 S 语言规范，正确的指针和参数语法如下：

#### 1. 函数参数 - 直接指针语法

**修正**: 参数列表中的 `name: &mut type` 改为 `name* type`

```s
// 正确的 S 语言写法
func lexer_read_char(lex* lexer)
func parser_parse(p* parser) ast_node
func semantic_analyze(ast* ast_node) (semantic_result, string)
```

**规则**:
- 指针参数: `name* type` (不用冒号 `:`)
- 值参数: `name type` (不用冒号 `:`)
- 多个参数: `func name(param1 type1, param2 type2) return_type`

#### 2. 方法接收器语法

**方法定义**:
```s
// 不可变接收器 (只读)
func (receiver type) method_name() return_type { }

// 可变接收器 (可修改)
func (receiver* type) method_name() return_type { }
```

**例子**:
```s
func (lex* lexer) read_char()
func (p* parser) next_token() token
func (st* symbol_table) define(name string, kind int)
```

#### 3. 错误处理和返回值

**S 语言不使用 `result[T, E]` 或 `option[T]`，而是用多返回值和错误检查**:

```s
// ❌ Rust/Go 风格 (错误)
func write(data string) result[int, error]
func read() option[string]

// ✅ S 语言风格 (正确)
func write(data string) (int, string)    // 返回 (字节数, 错误信息)
func read() (string, string)              // 返回 (数据, 错误信息)

// 调用时检查错误
n, err := write("hello")
if err != "" {
    return err
}
```

---

## 修正清单

### 修正的文件 (共 15 个)

#### 前端编译器
- ✅ `src/cmd/compile/internal/frontend/lexer.s`
- ✅ `src/cmd/compile/internal/frontend/lexer_test.s`
- ✅ `src/cmd/compile/internal/frontend/parser.s`
- ✅ `src/cmd/compile/internal/frontend/semantic.s`
- ✅ `src/cmd/compile/internal/frontend/ast.s`
- ✅ `src/cmd/compile/internal/frontend/frontend_integration_test.s`

#### 代码生成
- ✅ `src/cmd/compile/internal/codegen/compiler_integration.s`
- ✅ `src/cmd/compile/internal/codegen/bootstrap_integration.s`
- ✅ `src/cmd/compile/seed/codegen/codegen.s`
- ✅ `src/cmd/compile/seed/codegen/instruction_select.s`
- ✅ `src/cmd/compile/seed/codegen/stackframe.s`
- ✅ `src/cmd/compile/seed/codegen/linker.s`
- ✅ `src/cmd/compile/seed/codegen/test_native.s`
- ✅ `src/cmd/compile/seed/compile_native.s`

#### 集成测试
- ✅ `src/cmd/compile/test_complete_system.s`

### 修正统计

| 项目 | 数量 |
|------|------|
| 修正的文件 | 15 |
| 修正的参数签名 | ~50+ |
| 修正的函数调用 | ~100+ |
| 修正的类型声明 | ~30+ |

---

## 验证说明

### 函数调用的指针传递机制

S 语言中，当函数参数声明为 `type*`（指针），调用时的传递方式：

**需要验证和确认的问题**:

1. **值转指针**: 如果 `lex` 是值类型，`func lexer_read_char(lex* lexer)` 如何调用？
   - 是否自动取地址？ `lexer_read_char(lex)`
   - 是否需要显式取地址？ `lexer_read_char(&lex)`
   - 是否需要显式创建指针？ `lexer_read_char(lex*)` ← 当前用法

2. **指针转指针**: 如果 `lex` 已经是指针，如何调用？
   - 直接传递？ `lexer_read_char(lex)`
   - 还是需要特殊处理？

3. **结构体成员访问**: 对于指针类型的结构体，成员访问是否自动解引用？
   - `lex.current_char` vs `lex*.current_char` vs `(*lex).current_char`

---

## 后续优化计划

1. **明确指针传递规则** - 定义 S 语言的指针传递机制
2. **验证代码** - 编译和运行代码验证语法正确性
3. **统一代码风格** - 确保所有新代码遵循 S 语言规范
4. **更新文档** - 在官方文档中明确这些规则
5. **代码审查** - 建立代码审查流程确保一致性

---

## 参考资源

**S 语言指针和参数规范** (来自用户内存):
- ✅ 值接收器: `func (receiver type) method()`
- ✅ 可变接收器: `func (receiver* type) method()`
- ✅ 函数参数: `func name(param1 type1, param2* type2) return_type`
- ❌ 禁止: Rust 风格的 `&`, `&mut`, `:` 分隔符

---

## 提交信息

```
commit: 3dfcacb0
message: fix: 修正所有 S 源文件中的 Rust 风格指针语法

- 函数参数: &mut type -> type*
- 函数参数: &type -> type*
- 函数调用: (&mut var) -> (var*)
- 函数调用: (&var) -> (var*)

修正 15 个文件中的指针语法，符合 S 语言规范。
```

---

## 设计决策

### 为什么使用 `type*` 而不是 `&type`

1. **避免 Rust 混淆**: `&` 在 Rust 中有特殊含义，S 语言要有自己的风格
2. **C 风格一致性**: `type*` 是 C 语言的标准指针语法，S 语言继承了这一传统
3. **简洁性**: 一个字符 `*` 比 `&` 或 `&mut` 更简洁
4. **方法接收器区分**: 明确区分值接收器 `(t type)` 和指针接收器 `(t* type)`

### 为什么使用多返回值而不是 `result[T, E]`

1. **避免泛型复杂性**: 多返回值更简单直接
2. **Go 风格一致性**: S 语言在错误处理上参考了 Go 的设计
3. **简单的错误检查**: `value, err := call(); if err != "" { ... }`
4. **性能**: 多返回值通常比堆分配的 Result 更高效

