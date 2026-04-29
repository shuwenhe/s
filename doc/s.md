# S 编译器源码扫描记录

本文基于 `/app/s` 当前源码提取，不依赖外部推测。

主要扫描入口：

- `src/cmd/s/main.s`
- `src/cmd/compile/internal/**`
- `src/s/lexer.s`
- `src/s/parser.s`
- `src/s/ast.s`
- `src/s/tokens.s`

核心编译链（当前实现）在 `src/cmd/compile/internal/backend_elf64.s`：

1. 读源文件
2. 语义检查
3. AST/MIR lowering
4. MIR midend pass
5. SSA pipeline
6. 汇编生成
7. `as` 组装 + `ld` 链接

## 关键字

词法关键字由 `src/s/tokens.s` 的 `is_keyword` 定义，包含：

- package, use, as, pub
- func, const, static, struct, enum, trait, impl
- for, if, else, while, switch, select, case, default
- return, break, continue, sroutine
- true, false, nil
- unsafe, extern, mut, where, in

说明：`src/s/lexer.s` 与 `src/s/tokens.s` 都有关键字判断逻辑，编译入口通过 `compile.internal.syntax` 使用 `s.new_lexer` 和 `s.parse_tokens`。

## 运算符

多字符符号（`src/s/lexer.s`）：

- `->`, `:`, `==`, `!=`, `<=`, `>=`, `&&`, `||`, `++`, `..=`, `..`, `<<`, `>>`, `::`

单字符符号：

- `(` `)` `[` `]` `{` `}` `.` `,` `:` `;`
- `+` `-` `*` `/` `%` `!` `=` `<` `>` `?` `&` `|` `^`

表达式优先级（`src/s/parser.s`）：

1. `||`
2. `&&`
3. `==`, `!=`
4. `<`, `<=`, `>`, `>=`
5. `+`, `-`
6. `*`, `/`, `%`

## 基本类型

从 AST 节点和解析逻辑看，内置字面量层面的基础值包括：

- int literal（`int_expr`）
- string literal（`string_expr`）
- bool literal（`bool_expr`）
- nil（解析为 `name_expr("nil")`）

类型文本在解析期按字符串保留（`parse_type_text`），再由语义阶段处理。

## 复合类型

源码中已出现并被 parser/AST 承载的复合结构：

- 数组字面量 `expr::array`
- map 字面量 `expr::map`
- 结构体声明 `struct_decl`
- 枚举声明 `enum_decl`
- trait 声明 `trait_decl`
- impl 声明 `impl_decl`
- 泛型参数和 where 子句（函数/类型/impl）

## 变量

语句节点（`src/s/ast.s`）包含：

- `var_stmt`
- `assign_stmt`
- `increment_stmt`

parser 中显式支持：

- typed declaration（通过 `parse_typed_var_stmt`）
- 赋值 `name = expr`
- 自增 `name++`

parser 中明确返回错误：

- `parse_var_stmt`: `let/var declarations are not supported`
- `parse_short_var_stmt`: `:= is not supported`

## 常量

顶层常量支持两种形式（`src/s/parser.s`）：

- `const Name = expr`
- `const (...)` 分组

分组常量支持省略值，并记录 `iota_index` 到 `const_decl`。

## 函数

函数签名结构在 `function_sig`：

- 名称
- 泛型参数
- 参数列表
- 可选返回类型

函数体可选：

- 普通函数需要 block
- trait 方法可仅签名（`require_body = false`）

## 控制流

表达式级控制流：

- `if` / `else if` / `else`
- `while`
- `for in`
- `switch`
- `select`

语句级控制流：

- `return`
- C 风格 `for(init; cond; step)`

`select` 在 parser 中会重写为调用表达式：

- `select_recv`
- `select_recv_timeout`
- `select_recv_default`
- `select_send`
- `select_send_timeout`
- `select_send_default`

同时校验：

- recv/send case 不能混用
- timeout 只能一个
- default 只能一个
- timeout 与 default 不能同时出现

## 方法

支持 receiver 风格方法声明：

- `func (T recv) Method(...) ...`

在 `parse_item` 中会把 receiver 函数包装为 `impl_decl` 的 method。

此外支持显式 `impl` 块：

- `impl Target { ... }`
- `impl Trait for Target { ... }`

## 接口

接口对应 trait：

- `trait_decl` 持有方法签名列表
- 方法无函数体，以 `;` 结束
- 支持泛型 trait

## 错误处理

编译前端错误类型：

- `lex_error`（message/line/column）
- `parse_error`（message/line/column）
- `syntax_error`（对外包装）

整体风格：大量使用 `result[T, E]`。

## 模块系统

文件级结构：

1. `package ...`
2. 多个 `use ...`
3. 顶层 item

import 语法支持：

- 点路径 `a.b.c`
- `as` 别名
- 花括号成员导入 `a.b.{x, y as z}`

工具链中的模块命令（`src/cmd/compile/internal/build/exec/exec.s`）：

- `s mod init <module>`: 生成 `s.mod`
- `s mod tidy`: 当前实现为存在性检查并返回 `ok`

## 数组slice

当前 parser 明确支持：

- 数组字面量：`[type]{...}`
- map 字面量：`map[key]value{...}`
- 索引表达式：`a[i]`

切片是类型文本的一部分（如 `[]T`），由 `parse_type_text` 透传。

## 内建函数

编译链中可见的内建/约定调用包括：

- select 重写目标（见上）
- 后端工具链调用：`as`, `ld`
- wasm 路径下的对象链与导出检查

另外，构建命令支持 `--ssa-dominant-margin`，用于调节 SSA 管线行为。

## 并发

语法层：

- `sroutine expr` 语句
- `select { case ... }` 表达式

测试层（pipeline regression）已覆盖：

- `sroutine` 站点计数
- `select recv/send/timeout/default` 相关路径统计

## 命令行工具链

`src/cmd/s/main.s` 作为统一入口，转发到 `compile.internal.dispatch.main`。

当前 `s` 命令（`src/cmd/compile/internal/build/parse/parse.s`）：

- `s check <path>`
- `s tokens <path>`
- `s ast <path>`
- `s build <path> -o <output> [--ssa-dominant-margin ...]`
- `s run <path> [--ssa-dominant-margin ...]`
- `s test [fixtures_root]`
- `s mod init <module>`
- `s mod tidy`

`s test` 执行顺序：semantic -> golden -> backend_abi -> mir -> ssa -> pipeline_regression -> typesys。

## AST -> SSA -> Machine Code

主流程函数（`src/cmd/compile/internal/backend_elf64.s`）：

1. `load_source_graph`
2. `check_text`
3. `lower_main_to_mir`
4. `run_midend_pipeline`
5. `build_ssa_pipeline_with_graph_hints_and_margin`
6. `dump_ssa_pipeline` / `dump_ssa_debug_map`
7. `emit_asm`
8. `as -o out.o out.s`
9. `ld -o <output> out.o`

构建产物除可执行文件外，还会写出多个调试/分析附件，如：

- `.dbg`
- `.stackmap`
- `.abi`
- `.abi.emit`
- `.abi.matrix`
- `.dwarf`
- `.cfi`

以上即当前源码可验证的编译器实现概况。

## 最小可运行示例区块

以下命令假设你当前在仓库根目录 `/app/s`。

### 1) 词法与语法检查（最小输入）

使用仓库内置样例：

```bash
s check /app/s/misc/examples/s/hello.s
```

预期：

- 返回码 `0`
- 输出包含 `ok:` 或无错误提示

### 2) 查看 tokens（最小调试路径）

```bash
s tokens /app/s/misc/examples/s/hello.s
```

预期：

- 输出逐行 token（含行列、kind、value）

### 3) 查看 AST（前端结果）

```bash
s ast /app/s/misc/examples/s/hello.s
```

预期：

- 输出解析后的 source/AST 文本

### 4) 编译为可执行文件（AST -> MIR -> SSA -> machine code）

```bash
s build /app/s/misc/examples/s/hello.s -o /tmp/s_hello
```

预期：

- 生成 `/tmp/s_hello`
- 同目录生成调试附件（如 `.dbg`、`.stackmap`、`.abi`）

可选：指定 SSA 参数

```bash
s build /app/s/misc/examples/s/hello.s -o /tmp/s_hello --ssa-dominant-margin=5
```

### 5) 直接运行（build + run）

```bash
s run /app/s/misc/examples/s/sum.s
```

预期：

- 执行成功并返回 `0`

### 6) 运行编译器回归测试

```bash
s test
```

或指定 fixtures：

```bash
s test /app/s/src/cmd/compile/internal/tests/fixtures
```

预期：

- 输出 `test: ok`

### 7) 模块最小闭环

初始化模块：

```bash
s mod init demo.app
```

预期：

- 当前目录生成 `s.mod`

整理（当前实现为 manifest 存在性检查）：

```bash
s mod tidy
```

预期：

- 输出 `mod tidy: ok`

### 8) 一键验证最小链路

```bash
s check /app/s/misc/examples/s/hello.s \
&& s build /app/s/misc/examples/s/hello.s -o /tmp/s_hello \
&& /tmp/s_hello
```

如果以上三步都通过，说明最小工具链链路（前端 + 中端 + 后端 + 运行）已打通。



