
## S 语言变量声明

### A.1 基本声明（可初始化）

```s
int x = 10
char y = 'a'
float z = 3.14f
```

### A.2 先声明后赋值

```s
int n
n = 42
```

### A.3 同类型多变量声明

```s
int a = 1, b = 2, c = 3
```

### A.4 常量声明

```s
const int max_count = 100
```

### A.5 指针变量

```s
int v = 10
int *p = &v
```

### A.6 数组变量

```s
int arr[3] = {1, 2, 3}
char name[6] = "hello"
```

### A.7 结构体变量

```s
struct Point {
    int x
    int y
}

struct Point p = {1, 2}
```

### A.8 静态变量

```s
static int counter = 0
```

# S 语言语法规则（按编译器源码提取）

本文基于以下实现提取：
- `src/s/parser.s`
- `src/s/lexer.s`
- `src/s/tokens.s`

以下规则描述的是当前解析器实际接受的语法，而不是设想语法。

## 1. 词法规则

### 1.1 Token 类型
- ident
- int
- string
- keyword
- symbol
- eof

### 1.2 关键字（`is_keyword`）
package, use, as, pub, func, let, var, const, static, struct, enum, trait, impl, for, if, else, while, switch, select, case, default, return, break, continue, sroutine, true, false, nil, unsafe, extern, mut, where, in

说明：词法层识别了 `let`，但当前 `parser.s` 的语句解析主路径主要使用 `var`、`:=`、`类型 名 = 值` 等形式。

### 1.3 注释与空白
- 空白：空格、tab、CR、LF
- 行注释：`// ...`
- 块注释：`/* ... */`，支持嵌套

### 1.4 符号
多字符优先匹配：
`-> : == != <= >= && || ++ ..= .. := << >> ::`

单字符符号：
`( ) [ ] { } . , : ; + - * / % ! = < > ? & | ^`

### 1.5 标识符与字面量
- 标识符首字符：字母或 `_`
- 后续字符：字母、数字或 `_`
- 整数字面量：数字及 `_` 组成（如 `1_000`）
- 字符串字面量：双引号包裹，支持转义

## 2. 源文件结构

源码入口 `parse_source_file` 对应结构：

```ebnf
source_file = "package" path, { use_decl }, { item | const_group } ;
use_decl    = "use" use_path, [ "as" ident ] ;
```

约束：
- 文件必须以 `package` 开头。
- `use` 声明位于顶层 item 之前。

## 3. 顶层声明（item）

```ebnf
item = function_decl
     | const_decl
     | struct_decl
     | enum_decl
     | trait_decl
     | impl_decl ;
```

### 3.1 const

```ebnf
const_decl  = "const" ident "=" expr [";"] ;
const_group = "const" "(" { const_entry [";"|","] } ")" ;
const_entry = ident ["=" expr] ;
```

组常量中允许省略值（用于 iota 风格索引）。

### 3.2 struct

```ebnf
struct_decl = "struct" ident [generic_params] "{" { named_type [","] } "}" ;
named_type  = ident ":" type_text | type_text ident ;
```

### 3.3 enum

```ebnf
enum_decl   = "enum" ident [generic_params] "{" { enum_variant [","] } "}" ;
enum_variant = ident ["(" type_text ")"] ;
```

### 3.4 trait

```ebnf
trait_decl = "trait" ident [generic_params] "{" { func_sig ";" } "}" ;
```

### 3.5 impl

```ebnf
impl_decl = "impl" [generic_params]
            path ["for" path]
            [where_clause]
            "{" { function_decl } "}" ;
```

`impl Trait for Type` 与 `impl Type` 两种形式都支持。

### 3.6 function / method

```ebnf
function_decl = "func"
                ["(" named_type ")"]
                ident
                [generic_params]
                "(" [params] ")"
                [return_type]
                [where_clause]
                block_expr ;

params       = named_type { "," named_type } ;
return_type  = type_text ;
generic_params = "[" ident_or_bound { "," ident_or_bound } "]" ;
ident_or_bound = ident | ident ":" path { "+" path } ;
where_clause = "where" type_text { "," type_text } ;
```

说明：
- 有接收者 `("..." )` 时，解析器会按方法处理。
- trait 方法签名无函数体，且以 `;` 结尾。

## 4. 路径与 use 选择器

```ebnf
path     = ident { "." ident | "::" ident } [bracket_group] ;
use_path = ident { "." ident }
         | ident { "." ident } "." "{" use_member { "," use_member } "}" ;
use_member = ident ["as" ident] ;
```

示例：
- `use a.b.c`
- `use a.b.{c, d as dd}`

## 5. 语句（statement）

语句出现在 `block_expr` 中。分号多数是可选消费（解析器 `eat_symbol(";")`）。

```ebnf
stmt = var_stmt
     | typed_var_stmt
     | short_var_stmt
     | assign_stmt
     | increment_stmt
     | return_stmt
     | defer_stmt
     | sroutine_stmt
     | cfor_stmt
     | expr_stmt ;
```

### 5.1 变量与赋值

```ebnf
var_stmt       = "var" ident [":" type_text] "=" expr [";"] ;
typed_var_stmt = named_type "=" expr [";"] ;
short_var_stmt = ident ":=" expr [";"] ;
assign_stmt    = ident "=" expr [";"] ;
increment_stmt = ident "++" [";"] ;
```

### 5.2 控制与其他语句

```ebnf
return_stmt  = "return" [expr] [";"] ;
defer_stmt   = "defer" expr [";"] ;
sroutine_stmt = "sroutine" expr [";"] ;

cfor_stmt    = "for" "(" for_clause ";" expr ";" for_clause ")" block_expr ;
for_clause   = var_stmt(no_semicolon)
             | typed_var_stmt(no_semicolon)
             | short_var_stmt(no_semicolon)
             | assign_stmt(no_semicolon)
             | increment_stmt(no_semicolon) ;
```

### 5.3 当前支持的变量形式

- `var` 声明：`var name = expr` 或 `var name: Type = expr`
- 短变量声明：`name := expr`
- 类型前置声明：`Type name = expr`
- 变量赋值：`name = expr`
- 自增语句：`name++`

说明：
- 词法层包含 `let` 关键字，但当前语句解析主路径未将 `let` 作为变量声明分支。

## 6. 表达式（expression）

入口优先级：
`select` > `switch` > `if` > `while` > `for-in` > 二元表达式

### 6.1 结构化表达式

```ebnf
if_expr    = "if" expr block_expr ["else" (if_expr | block_expr)] ;
while_expr = "while" expr block_expr ;
for_expr   = "for" ident "in" expr block_expr ;

switch_expr = "switch" expr "{" { pattern ":" expr [","] } "}" ;
```

### 6.2 select 表达式

```ebnf
select_expr = "select" "{" { "case" select_case ":" [";"] } "}" ;
select_case = "default"
            | recv_call
            | send_call
            | timeout_call ;
```

语义限制（解析阶段检查）：
- 不能混用 recv 与 send case。
- default 不能重复。
- timeout/after 不能重复。
- timeout 与 default 不能同时存在。

### 6.3 模式匹配 pattern

```ebnf
pattern = "_"
        | int_lit
        | string_lit
        | "true"
        | "false"
        | path ["(" [pattern {"," pattern}] ")"] ;
```

若 `path` 含 `.` 或首字母大写，会按 variant 模式处理。

### 6.4 运算符优先级（高到低）
1. `* / %`
2. `+ -`
3. `< <= > >=`
4. `== !=`
5. `&&`
6. `||`

### 6.5 一元与后缀

```ebnf
unary_expr = ["&" ["mut"]] unary_expr | call_expr ;

call_expr = primary_expr
            { "(" [expr {"," expr}] ")"
            | "." ident
            | "::" ident
            | "[" expr "]" } ;
```

### 6.6 primary

```ebnf
primary_expr = int_lit
             | string_lit
             | "true"
             | "false"
             | "nil"
             | block_expr
             | "(" expr ")"
             | array_literal
             | map_literal
             | ident ;
```

数组与 map：

```ebnf
array_literal = bracket_group [type_tail] "{" [expr {"," expr}] "}" ;
map_literal   = "map" bracket_group [type_tail] "{" [map_entry {"," map_entry}] "}" ;
map_entry     = expr ":" expr ;
```

## 7. block 表达式与末尾表达式

```ebnf
block_expr = "{" { stmt | expr_stmt } [final_expr] "}" ;
```

规则：
- 语句按 `starts_stmt` 判定。
- 表达式后若有 `;`，作为表达式语句。
- 最后一个无分号表达式可作为 `final_expr`。

## 8. 当前实现差异与注意点

- 词法关键字包含 `let`，但当前主解析路径并未提供 `let` 语句分支。
- `break`/`continue` 在关键字表中存在，但当前 `parse_stmt` 未直接解析这两类语句。
- 分号在多数场景可省略，是否需要由具体 `parse_*` 分支决定。

## 9. 最小可解析示例

```s
package demo

use std.vec.vec

const Pi = 3

struct Point {
    x: int
    y: int
}

func add(a: int, b: int) int {
    var sum = a + b
    return sum
}

func main() {
    x := add(1, 2)
    if x > 0 {
        x = x + 1
    }
}
```
