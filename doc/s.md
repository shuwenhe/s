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

## EBNF 语法草案（按当前实现）

本节按当前 `src/s/parser.s`、`src/s/lexer.s`、`src/s/ast.s` 的实际实现整理。

说明：

1. 这是“实现语法”，不是理想化设计语法。
2. 某些关键字在词法层存在，但 parser 未完整支持。
3. 类型文本当前大量按原样字符串保留，语义阶段再处理。

### 1. 词法层

```ebnf
letter            = "a" ... "z" | "A" ... "Z" | "_" ;
digit             = "0" ... "9" ;

ident_start       = letter ;
ident_continue    = letter | digit ;
identifier        = ident_start , { ident_continue } ;

int_literal       = digit , { digit | "_" } ;
string_literal    = '"' , { char | escape } , '"' ;
bool_literal      = "true" | "false" ;

whitespace        = " " | "\t" | "\r" | "\n" ;
line_comment      = "//" , { char - "\n" } ;
block_comment     = "/*" , { block_comment | char } , "*/" ;

keyword           = "package" | "use" | "as" | "pub" | "func" | "const"
				  | "static" | "struct" | "enum" | "trait" | "impl"
				  | "for" | "if" | "else" | "while" | "switch" | "select"
				  | "case" | "default" | "return" | "break" | "continue"
				  | "sroutine" | "true" | "false" | "nil" | "unsafe"
				  | "extern" | "mut" | "where" | "in" ;

multi_symbol      = "->" | ":" | "==" | "!=" | "<=" | ">=" | "&&" | "||"
				  | "++" | "..=" | ".." | "<<" | ">>" | "::" ;

single_symbol     = "(" | ")" | "[" | "]" | "{" | "}" | "." | "," | ":"
				  | ";" | "+" | "-" | "*" | "/" | "%" | "!" | "=" | "<"
				  | ">" | "?" | "&" | "|" | "^" ;
```

### 2. 文件级结构

```ebnf
source_file       = package_decl , { use_decl } , { top_level_item } ;

package_decl      = "package" , path ;
use_decl          = "use" , use_path , [ "as" , identifier ] ;
```

### 3. 导入与路径

```ebnf
path              = identifier , { "." , identifier | "::" , identifier } , [ bracket_group ] ;

use_path          = identifier , { "." , identifier }
				  | identifier , { "." , identifier } , "." , "{" , use_member , { "," , use_member } , "}" ;

use_member        = identifier , [ "as" , identifier ] ;

bracket_group     = "[" , { token } , "]" ;
```

### 4. 顶层声明

```ebnf
top_level_item    = function_decl
				  | const_decl
				  | const_group
				  | struct_decl
				  | enum_decl
				  | trait_decl
				  | impl_decl ;
```

#### 4.1 常量

```ebnf
const_decl        = "const" , identifier , "=" , expr , [ ";" ] ;

const_group       = "const" , "(" , { const_entry , [ "," | ";" ] } , ")" ;
const_entry       = identifier , [ "=" , expr ] ;
```

#### 4.2 函数

```ebnf
function_decl     = "func" , [ receiver ] , identifier , [ generic_params ] ,
					"(" , [ param_list ] , ")" , [ return_type ] ,
					[ where_clause ] , block_expr ;

trait_method_decl = "func" , [ receiver ] , identifier , [ generic_params ] ,
					"(" , [ param_list ] , ")" , [ return_type ] ,
					[ where_clause ] , ";" ;

receiver          = "(" , named_type , ")" ;
param_list        = named_type , { "," , named_type } ;
return_type       = type_text ;
```

#### 4.3 结构体 / 枚举 / trait / impl

```ebnf
struct_decl       = "struct" , identifier , [ generic_params ] ,
					"{" , { named_type , [ "," ] } , "}" ;

enum_decl         = "enum" , identifier , [ generic_params ] ,
					"{" , { enum_variant , [ "," ] } , "}" ;
enum_variant      = identifier , [ "(" , type_text , ")" ] ;

trait_decl        = "trait" , identifier , [ generic_params ] ,
					"{" , { trait_method_decl } , "}" ;

impl_decl         = "impl" , [ generic_params ] , path , [ "for" , path ] ,
					[ where_clause ] ,
					"{" , { function_decl } , "}" ;
```

### 5. 泛型与类型文本

```ebnf
generic_params    = "[" , generic_param , { "," , generic_param } , "]" ;
generic_param     = identifier | identifier , ":" , path , { "+" , path } ;

where_clause      = "where" , type_text , { "," , type_text } ;

named_type        = identifier , ":" , type_text
				  | type_text , identifier ;

type_text         = { token - stop_symbol } ;
```

说明：

1. `type_text` 在当前实现中不是完整独立 parser，而是按停止符号切片后规范化。
2. 因此 `[]int`、`map[string]int`、`result[int, string]` 一类文本通常在语法层都能通过。

### 6. 语句

```ebnf
stmt              = typed_var_stmt
				  | assign_stmt
				  | increment_stmt
				  | c_for_stmt
				  | return_stmt
				  | defer_stmt
				  | sroutine_stmt
				  | expr_stmt ;

typed_var_stmt    = named_type , "=" , expr , [ ";" ] ;
assign_stmt       = identifier , "=" , expr , [ ";" ] ;
increment_stmt    = identifier , "++" , [ ";" ] ;

return_stmt       = "return" , [ expr ] , [ ";" ] ;
defer_stmt        = "defer" , expr , [ ";" ] ;
sroutine_stmt     = "sroutine" , expr , [ ";" ] ;

expr_stmt         = expr , [ ";" ] ;
```

#### 6.1 C 风格 for

```ebnf
c_for_stmt        = "for" , "(" , for_clause_stmt , ";" , expr , ";" , for_clause_stmt , ")" , block_expr ;

for_clause_stmt   = typed_var_stmt_no_semi
				  | assign_stmt_no_semi
				  | increment_stmt_no_semi ;
```

说明：

1. 当前实现不支持 `let` / `var` 风格声明。
2. 当前实现不支持 `:=` 短声明。

### 7. 表达式

```ebnf
expr              = select_expr
				  | switch_expr
				  | if_expr
				  | while_expr
				  | for_in_expr
				  | binary_expr ;
```

#### 7.1 控制流表达式

```ebnf
if_expr           = "if" , expr , block_expr , [ "else" , ( if_expr | block_expr ) ] ;

while_expr        = "while" , expr , block_expr ;

for_in_expr       = "for" , identifier , "in" , expr , block_expr ;

switch_expr       = "switch" , expr , "{" , { switch_arm , [ "," ] } , "}" ;
switch_arm        = pattern , ":" , expr ;
```

#### 7.2 select 表达式

```ebnf
select_expr       = "select" , "{" , { select_case } , "}" ;
select_case       = "case" , "default" , ":" , [ ";" ]
				  | "case" , expr , ":" , [ ";" ] ;
```

说明：

1. parser 约束 `case expr` 实际必须是 `recv(...)`、`send(...)`、`timeout(...)` 或 `after(...)` 调用。
2. `select` 最终会被重写为内部调用表达式，而不是保留独立 AST 节点。

#### 7.3 模式

```ebnf
pattern           = "_"
				  | int_literal
				  | string_literal
				  | "true"
				  | "false"
				  | path , [ "(" , [ pattern , { "," , pattern } ] , ")" ]
				  | identifier ;
```

#### 7.4 二元表达式

```ebnf
binary_expr       = unary_expr , { binary_op , unary_expr } ;

binary_op         = "||" | "&&" | "==" | "!="
				  | "<" | "<=" | ">" | ">="
				  | "+" | "-" | "*" | "/" | "%" ;
```

优先级从低到高：

1. `||`
2. `&&`
3. `==` `!=`
4. `<` `<=` `>` `>=`
5. `+` `-`
6. `*` `/` `%`

#### 7.5 一元 / 调用 / 成员 / 索引

```ebnf
unary_expr        = "&" , [ "mut" ] , unary_expr
				  | call_expr ;

call_expr         = primary_expr , { call_suffix | member_suffix | index_suffix } ;

call_suffix       = "(" , [ expr , { "," , expr } ] , ")" ;
member_suffix     = "." , identifier | "::" , identifier ;
index_suffix      = "[" , expr , "]" ;
```

#### 7.6 primary

```ebnf
primary_expr      = int_literal
				  | string_literal
				  | bool_literal
				  | "nil"
				  | identifier
				  | block_expr
				  | "(" , expr , ")"
				  | array_literal
				  | map_literal ;

array_literal     = bracket_group , [ type_text ] , "{" , [ expr , { "," , expr } ] , "}" ;

map_literal       = "map" , bracket_group , [ type_text ] ,
					"{" , [ map_entry , { "," , map_entry } ] , "}" ;
map_entry         = expr , ":" , expr ;
```

### 8. block 表达式

```ebnf
block_expr        = "{" , { block_item } , [ final_expr ] , "}" ;
block_item        = stmt | expr_stmt ;
final_expr        = expr ;
```

说明：

1. 如果块尾表达式后没有分号，并且后面紧跟 `}`，则记为 `final_expr`。
2. 否则按 `expr_stmt` 处理。

### 9. 当前实现中的保留与不完整区域

以下内容在词法或 AST 层出现，但当前 parser/语义闭环并不完整，规范上应视为未正式纳入 MVP：

- `break`
- `continue`
- `pub`
- `unsafe`
- `extern`
- `let`
- `var`
- `:=`
```



