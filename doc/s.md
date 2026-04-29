# S 语言完整语法清单（基于源码提取）

本文仅基于当前仓库实现提取，不基于外部文档推测。

语法来源：
- `src/s/lexer.s`
- `src/s/tokens.s`
- `src/s/parser.s`
- `src/s/ast.s`

---

## 1. 词法层（Lexer）

### 1.1 Token 种类

```ebnf
token_kind = ident | int | string | keyword | symbol | eof
```

### 1.2 关键字集合

`package use as pub func var const static struct enum trait impl for if else while switch select case default return break continue sroutine true false nil unsafe extern mut where in`

说明：
- 关键字被词法识别，不代表都已在语法层完整实现。

### 1.3 注释和空白

```ebnf
whitespace    = " " | "\t" | "\r" | "\n"
line_comment  = "//" ... "\n"
block_comment = "/*" ... "*/"    ; 支持嵌套
```

### 1.4 标识符、数字、字符串

```ebnf
ident_start    = "_" | ascii_letter
ident_continue = ident_start | digit
identifier     = ident_start , { ident_continue }

int_literal    = digit , { digit | "_" }

string_literal = '"' , { char | escape } , '"'
```

### 1.5 符号

多字符优先匹配：

`-> : == != <= >= && || ++ ..= .. := << >> ::`

单字符符号：

`( ) [ ] { } . , : ; + - * / % ! = < > ? & | ^`

---

## 2. 文件级语法

```ebnf
source_file = "package" path , { use_decl } , { item_or_const_group }

use_decl = "use" use_path , [ "as" ident ]

item_or_const_group = const_group | item
```

约束：
- 文件必须以 `package` 开头。
- 所有 `use` 必须位于顶层 item 之前。

---

## 3. 顶层声明（item）

```ebnf
item = function_decl
     | const_decl
     | struct_decl
     | enum_decl
     | trait_decl
     | impl_decl
```

### 3.1 常量

```ebnf
const_decl  = "const" ident "=" expr [";"]

const_group = "const" "(" { const_entry [","|";"] } ")"
const_entry = ident ["=" expr]
```

说明：
- 单个 `const` 声明需要值。
- 分组 `const(...)` 允许省略值（解析器记录 `iota_index`）。

### 3.2 结构体

```ebnf
struct_decl = "struct" ident [generic_params] "{" { named_type [","] } "}"
```

### 3.3 枚举

```ebnf
enum_decl    = "enum" ident [generic_params] "{" { enum_variant [","] } "}"
enum_variant = ident ["(" type_text ")"]
```

### 3.4 trait

```ebnf
trait_decl = "trait" ident [generic_params] "{" { func_sig ";" } "}"
```

### 3.5 impl

```ebnf
impl_decl = "impl" [generic_params]
            path [ "for" path ]
            [ where_clause ]
            "{" { function_decl } "}"
```

### 3.6 函数与方法

```ebnf
function_decl = "func"
                [ "(" named_type ")" ]
                ident
                [ generic_params ]
                "(" [ params ] ")"
                [ return_type ]
                [ where_clause ]
                block_expr

params      = named_type { "," named_type }
return_type = type_text
```

说明：
- 可声明 receiver（方法形式）。
- trait 内方法签名没有函数体，要求以 `;` 结束。

---

## 4. 类型与路径相关语法

### 4.1 命名类型（两种写法）

```ebnf
named_type = ident ":" type_text
           | type_text ident
```

### 4.2 泛型参数与约束

```ebnf
generic_params = "[" generic_item { "," generic_item } "]"
generic_item   = ident | ident ":" path { "+" path }
```

### 4.3 where 子句

```ebnf
where_clause = "where" type_text { "," type_text }
```

### 4.4 路径

```ebnf
path = ident
       { "." ident | "::" ident }
       [ bracket_group ]

use_path = ident { "." ident }
         | ident { "." ident } "." "{" use_member { "," use_member } "}"

use_member = ident [ "as" ident ]
```

---

## 5. 语句语法（statement）

```ebnf
stmt = var_stmt
     | typed_var_stmt
     | short_var_stmt
     | assign_stmt
     | increment_stmt
     | c_for_stmt
     | return_stmt
     | defer_stmt
     | sroutine_stmt
     | expr_stmt
```

### 5.1 变量与赋值

```ebnf
var_stmt       = "var" ident [ ":" type_text ] "=" expr [";"]
typed_var_stmt = named_type "=" expr [";"]
short_var_stmt = ident ":=" expr [";"]
assign_stmt    = ident "=" expr [";"]
increment_stmt = ident "++" [";"]
```

### 5.2 控制与并发相关语句

```ebnf
return_stmt   = "return" [expr] [";"]
defer_stmt    = "defer" expr [";"]
sroutine_stmt = "sroutine" expr [";"]

c_for_stmt = "for" "(" for_clause_stmt ";" expr ";" for_clause_stmt ")" block_expr

for_clause_stmt = var_stmt_no_semi
                | typed_var_stmt_no_semi
                | short_var_stmt_no_semi
                | assign_stmt_no_semi
                | increment_stmt_no_semi
```

---

## 6. 表达式语法（expression）

入口顺序：

`select` -> `switch` -> `if` -> `while` -> `for-in` -> binary

### 6.1 结构表达式

```ebnf
if_expr    = "if" expr block_expr [ "else" ( if_expr | block_expr ) ]
while_expr = "while" expr block_expr
for_expr   = "for" ident "in" expr block_expr

switch_expr = "switch" expr "{" { pattern ":" expr [","] } "}"
```

### 6.2 select 表达式

```ebnf
select_expr = "select" "{" { "case" select_case ":" [";"] } "}"

select_case = "default"
            | recv_call
            | send_call
            | timeout_call
```

解析阶段额外约束：
- 不允许混用 recv 与 send case。
- default 只能出现一次。
- timeout/after 只能出现一次。
- timeout 与 default 不能并存。

### 6.3 模式匹配

```ebnf
pattern = "_"
        | int_literal
        | string_literal
        | "true"
        | "false"
        | path [ "(" [ pattern { "," pattern } ] ")" ]
```

### 6.4 运算符优先级（高到低）

1. `* / %`
2. `+ -`
3. `< <= > >=`
4. `== !=`
5. `&&`
6. `||`

### 6.5 一元、调用、成员、索引

```ebnf
unary_expr = [ "&" ["mut"] ] unary_expr
           | call_expr

call_expr = primary_expr
            { "(" [ expr { "," expr } ] ")"
            | "." ident
            | "::" ident
            | "[" expr "]" }
```

### 6.6 primary

```ebnf
primary_expr = int_literal
             | string_literal
             | "true"
             | "false"
             | "nil"
             | block_expr
             | "(" expr ")"
             | array_literal
             | map_literal
             | ident
```

```ebnf
array_literal = bracket_group [type_tail] "{" [ expr { "," expr } ] "}"
map_literal   = "map" bracket_group [type_tail] "{" [ map_entry { "," map_entry } ] "}"
map_entry     = expr ":" expr
```

说明：
- `map` 在当前实现中按 `ident("map")` 进入 map 字面量分支。

---

## 7. block 与末尾表达式

```ebnf
block_expr = "{" { stmt | expr_stmt } [ final_expr ] "}"
expr_stmt  = expr [";"]
final_expr = expr     ; 仅当它是 block 内最后一个且无分号
```

规则：
- `starts_stmt` 命中时按语句解析。
- 否则按表达式解析。

---

## 8. 语义/实现差异（源码真实状态）

### 8.1 词法存在但语法层未直接解析为 stmt 的关键字

- `break`
- `continue`
- `pub`
- `unsafe`
- `extern`

说明：这些词在 `is_keyword` 中存在，但当前 `parse_stmt` 未提供对应直接分支。

### 8.2 AST 与解析器存在的不一致点

- `ast.s` 的 `for_expr` 字段是 `names + declare + iterable` 形式。
- `parser.s` 的 `parse_for_expr` 目前按单变量 `for ident in expr` 构建。

---

## 9. 解析入口覆盖清单（已全部纳入本文）

本文覆盖了 `parser.s` 的所有语法入口函数：

- `parse_source_file`
- `parse_use_decl`
- `parse_item`
- `parse_const_decl`
- `parse_const_group_items`
- `parse_function_decl`
- `parse_struct_decl`
- `parse_enum_decl`
- `parse_trait_decl`
- `parse_impl_decl`
- `parse_function`
- `parse_params`
- `parse_generic_params`
- `parse_where_clause`
- `parse_named_type`
- `parse_block_expr`
- `parse_stmt`
- `parse_var_stmt`
- `parse_short_var_stmt`
- `parse_typed_var_stmt`
- `parse_assign_stmt`
- `parse_increment_stmt`
- `parse_cfor_stmt`
- `parse_return_stmt`
- `parse_expr`
- `parse_select_expr`
- `parse_switch_expr`
- `parse_if_expr`
- `parse_while_expr`
- `parse_for_expr`
- `parse_pattern`
- `parse_binary_expr`
- `parse_unary_expr`
- `parse_call_expr`
- `parse_primary_expr`
- `parse_use_path`
- `parse_path`
- `parse_type_text`
- `parse_bracket_group`

---

## 10. 最小示例（符合当前解析器）

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
