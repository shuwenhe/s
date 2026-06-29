# s syntax specification

version: draft 0.1  
status: working draft

## 1. purpose

本文档定义 s 的表面语法草案。

它的目标是：

- 固定词法结构
- 固定源文件和声明的基本形状
- 固定表达式与语句的主要产生式
- 固定模式匹配与泛型语法方向
- 为后续 parser 实现提供接近 ebnf 的语法依据

本文档是 [spec.md](/app/s/doc/spec.md) 的语法补充，与 [types.md](/app/s/doc/types.md) 和 [ownership.md](/app/s/doc/ownership.md) 配套使用。

## 2. notation

本文档采用接近 ebnf 的记号：

- `a = b` 表示定义
- `a | b` 表示二选一
- `a?` 表示可选
- `a*` 表示零次或多次
- `a+` 表示一次或多次
- `()` 表示分组
- 字面终结符使用引号，例如 `"func"`
- 词法类使用大写名称，例如 `ident`

为保持可读性，本文档不追求完全形式化的 parser grammar，而追求“足够严格、可落地实现”。

## 3. lexical structure

### 3.1 source text

源文件必须采用 utf-8 编码。

词法分析器应将源文本切分为：

- 标识符
- 关键字
- 字面量
- 操作符
- 分隔符
- 注释
- 空白符

注释和空白符通常不进入语法分析阶段，除非实现需要保留位置信息。

### 3.2 whitespace

```text
whitespace = " " | "\t" | "\r" | "\n"
```

空白用于分隔 token，本身没有语义。

### 3.3 comments

```text
line_comment  = "//" { not_newline } newline?
block_comment = "/*" { any_char } "*/"
```

draft 0.1 推荐支持嵌套块注释，但这不是语义层强制要求。

### 3.4 identifiers

```text
ident = xid_start { xid_continue }
```

约束：

- 不得与关键字完全相同
- 不得以数字开头

标准库和公共 api 推荐使用 ascii 标识符。

### 3.5 keywords

```text
package use as pub
func var var const static
struct enum trait impl for
if else for while switch
return break continue
true false
unsafe extern mut
```

### 3.6 literals

```text
int_literal    = dec_int | hex_int | bin_int | oct_int
float_literal  = digits "." digits exp?
string_literal = "\"" { string_char | escape } "\""
char_literal   = "'" char_or_escape "'"
```

说明：

- 整数字面量的精确后缀系统留待后续版本决定
- 浮点字面量至少支持十进制表示
- 字符串字面量默认为 utf-8

### 3.7 delimiters and operators

```text
delimiters = "(" ")" "[" "]" "{" "}" "," ":" ";" "." " "

operators =
    "="
  | "+"
  | "-"
  | "*"
  | "/"
  | "%"
  | "!"
  | "&"
  | "&&"
  | "|"
  | "||"
  | "^"
  | "<<"
  | ">>"
  | "=="
  | "!="
  | "<"
  | "<="
  | ">"
  | ">="
  | ".."
  | "..="
  | "?"
```

## 4. compilation unit

### 4.1 source file

```text
sourcefile = packagedecl usedecl* item*
```

### 4.2 package declaration

```text
packagedecl = "package" packagepath
packagepath = ident ("." ident)*
```

每个源文件必须恰有一个 `package` 声明，并位于文件开头。

### 4.3 imports

```text
usedecl      = "use" importtree
importtree   = importpath ("as" ident)?
importpath   = ident ("." ident)* importgroup?
importgroup  = "." "{" importitem ("," importitem)* ","? "}"
importitem   = ident ("as" ident)?
```

示例：

```s
use net.http.request
use io.{reader, writer}
use math as m
```

## 5. top-level items

```text
item =
    functiondecl
  | structdecl
  | enumdecl
  | traitdecl
  | impldecl
  | constdecl
  | staticdecl
```

```text
visibility = "pub"
```

## 6. declarations

### 6.1 function declaration

```text
functiondecl =
    "func" ident genericparamlist?
    "(" paramlist? ")" returntype?
    whereclause? blockexpr
```

```text
paramlist   = param ("," param)* ","?
param       = pattern ":" type
returntype  = " " type
```

`returntype` 允许直接引用任意 `type`，因此单返回、单位返回和 tuple 返回都走同一条语法分支。draft 0.1 建议多返回统一写成 tuple type，不要再引入隐式的“逗号返回”变体。

### 6.2 struct declaration

```text
structdecl =
    visibility? "struct" ident genericparamlist?
    structbody

structbody =
    "{" structfieldlist? "}"

structfieldlist =
    structfield ("," structfield)* ","?

structfield =
    visibility? ident ":" type
```

### 6.3 enum declaration

```text
enumdecl =
    visibility? "enum" ident genericparamlist?
    enumbody

enumbody =
    "{" enumvariantlist? "}"

enumvariantlist =
    enumvariant ("," enumvariant)* ","?

enumvariant =
    ident enumvariantbody?

enumvariantbody =
    tuplevariantbody
  | recordvariantbody

tuplevariantbody  = "(" typelist? ")"
recordvariantbody = "{" structfieldlist? "}"
```

### 6.4 trait declaration

```text
traitdecl =
    visibility? "trait" ident genericparamlist?
    traitbody

traitbody =
    "{" traititem* "}"

traititem =
    functionsig ";"
```

```text
functionsig =
    "func" ident genericparamlist?
    "(" paramlist? ")" returntype?
    whereclause?
```

### 6.5 impl declaration

```text
impldecl =
    "impl" genericparamlist? implhead whereclause? implbody

implhead =
    type
  | traitref "for" type

implbody =
    "{" implitem* "}"

implitem =
    functiondecl
```

### 6.6 constants and statics

```text
constdecl =
    visibility? "const" ident ":" type "=" expr ";"

staticdecl =
    visibility? "static" ident ":" type "=" expr ";"
```

## 7. generic syntax

### 7.1 generic parameter list

```text
genericparamlist =
    "[" genericparam ("," genericparam)* ","? "]"

genericparam =
    ident traitboundlist?
```

```text
traitboundlist =
    ":" traitbound ("+" traitbound)*

traitbound =
    typepath
```

示例：

```s
func max[t: ord](t a, t b) t
func copy_pair[t: copy + clone](t a, t b) (t, t)
```

### 7.2 where clause

```text
whereclause =
    "where" wherepredicate ("," wherepredicate)* ","?

wherepredicate =
    type ":" traitbound ("+" traitbound)*
```

`where` 子句用于较复杂的约束表达。draft 0.1 固定方向，具体排版规则由 formatter 决定。

### 7.3 generic arguments

```text
genericarglist =
    "[" type ("," type)* ","? "]"
```

示例：

```s
vec[int32] v
result[string, ioerror] r
```

## 8. types

### 8.1 type grammar

```text
type =
    reftype
  | slicetype
  | arraytype
  | maptype
  | tupletype
  | functiontype
  | typepath
  | "(" type ")"
```

### 8.2 reference types

```text
reftype =
    "&" "mut"? type
```

### 8.3 slice and array types

```text
slicetype =
    "[" "]" type

arraytype =
    "[" constexpr "]" type
```

draft 0.1 建议把 `[]t` 作为切片 canonical form，把 `[n]t` 作为固定长度数组 canonical form。NeurX 一类数值代码应避免同时采用 `T[]` 和 `[]T` 两种主写法。

### 8.4 map types

```text
maptype =
    "map" "[" type "]" type
```

`map[K]V` 是 map 的唯一建议规范写法。空 map 推荐写作 `map[K]V{}`，不要再混入 `map<int]bool` 这类兼容写法。

### 8.5 tuple types

```text
tupletype =
    "(" typelist? ")"

typelist =
    type ("," type)* ","?
```

### 8.6 function types

```text
functiontype =
    "func" "(" typelist? ")" " " type
```

### 8.7 paths

```text
typepath =
    ident ("." ident)* genericarglist?

traitref =
    typepath
```

## 9. statements

```text
stmt =
    letstmt
  | varstmt
  | exprstmt
  | semistmt
  | returnstmt
  | breakstmt
  | continuestmt
```

### 9.1 var and var statements

```text
letstmt =
    "var" pattern typeannotation? ("=" expr)? ";"

varstmt =
    "var" pattern typeannotation? ("=" expr)? ";"

typeannotation =
    ":" type
```

draft 0.1 允许无初始化绑定是否最终保留，属于后续实现策略议题；若保留，编译器必须确保值在读取前已初始化。

### 9.2 expression statements

```text
exprstmt =
    expr

semistmt =
    expr ";"
```

约定：

- 块内最后一个无分号表达式可作为块值
- 带分号的表达式语句值为 `()`

### 9.3 control transfer statements

```text
returnstmt   = "return" expr? ";"
breakstmt    = "break" expr? ";"
continuestmt = "continue" ";"
```

## 10. block expressions

```text
blockexpr =
    "{" stmt* finalexpr? "}"

finalexpr =
    expr
```

块既是语句容器，也是表达式。

## 11. expressions

### 11.1 expression categories

```text
expr =
    assignmentexpr
```

### 11.2 precedence overview

从低到高：

1. assignment
2. logical-or
3. logical-and
4. equality
5. comparison
6. range
7. additive
8. multiplicative
9. unary
10. postfix
11. primary

### 11.3 assignment

```text
assignmentexpr =
    logicalorexpr
  | unaryexpr "=" assignmentexpr
```

左值是否合法由语义层检查。

### 11.4 logical operators

```text
logicalorexpr  = logicalandexpr ("||" logicalandexpr)*
logicalandexpr = equalityexpr ("&&" equalityexpr)*
```

### 11.5 equality and comparison

```text
equalityexpr =
    compareexpr (("==" | "!=") compareexpr)*

compareexpr =
    rangeexpr (("<" | "<=" | ">" | ">=") rangeexpr)*
```

### 11.6 range

```text
rangeexpr =
    addexpr ((".." | "..=") addexpr)?
```

### 11.7 additive and multiplicative

```text
addexpr =
    mulexpr (("+" | "-") mulexpr)*

mulexpr =
    unaryexpr (("*" | "/" | "%") unaryexpr)*
```

### 11.8 unary

```text
unaryexpr =
    postfixexpr
  | ("!" | "-" | "&") unaryexpr
  | "&" "mut" unaryexpr
  | "*" unaryexpr
  | "unsafe" blockexpr
```

说明：

- `*` 作为解引用操作的合法性由类型和安全规则决定
- `unsafe` 作为表达式前缀时引入不安全块

### 11.9 postfix

```text
postfixexpr =
    primaryexpr postfixop*

postfixop =
    callsuffix
  | membersuffix
  | indexsuffix
  | trysuffix
```

```text
callsuffix   = "(" arglist? ")"
membersuffix = "." ident
indexsuffix  = "[" expr "]"
trysuffix    = "?"

arglist =
    expr ("," expr)* ","?
```

### 11.10 primary expressions

```text
primaryexpr =
    literal
  | pathexpr
  | tupleexpr
  | arrayexpr
  | mapexpr
  | structexpr
  | blockexpr
  | ifexpr
  | whileexpr
  | forexpr
  | switchexpr
  | "(" expr ")"
```

### 11.11 path expressions

```text
pathexpr =
    ident ("." ident)* genericarglist?
```

### 11.12 tuple and array expressions

```text
tupleexpr =
    "(" exprlist? ")"

arrayexpr =
    "[" exprlist? "]"

mapexpr =
    "map" "[" type "]" type "{" mapentrylist? "}"

mapentrylist =
    mapentry ("," mapentry)* ","?

mapentry =
    expr ":" expr

exprlist =
    expr ("," expr)* ","?
```

### 11.13 struct expressions

```text
structexpr =
    typepath "{" fieldinitlist? "}"

fieldinitlist =
    fieldinit ("," fieldinit)* ","?

fieldinit =
    ident ":" expr
  | ident
```

typed composite literals are allowed in draft 0.1 for framework code and should be normalized by formatter:

- slice literal: `[]T{...}`
- array literal: `[N]T{...}`
- map literal: `map[K]V{...}`
- struct literal: `Type{...}`

This is the recommended surface for NeurX-style code that needs stable container initialization.

For typed composite literals, the intended shape is:

```text
typedcompositeliteral =
    slicetype "{" exprlist? "}"
  | arraytype "{" exprlist? "}"
  | maptype "{" mapentrylist? "}"
  | typepath "{" fieldinitlist? "}"
```

`typedcompositeliteral` is not a separate parser node requirement; it is a normalization rule for the formatter and parser front-end.

### 11.14 if expression

```text
ifexpr =
    "if" expr blockexpr ("else" elsebranch)?

elsebranch =
    blockexpr
  | ifexpr
```

### 11.15 while expression

```text
whileexpr =
    "while" expr blockexpr
```

### 11.16 for expression

```text
forexpr =
    "for" pattern "in" expr blockexpr
```

`for` 依赖 `in` 关键语义，但 `in` 是否作为保留关键字还是上下文关键字，可由 lexer/parser 联合决定。draft 0.1 建议将其视为上下文关键字。

### 11.17 match expression

```text
switchexpr =
    "switch" expr "{" switcharmlist? "}"

switcharmlist =
    switcharm ("," switcharm)* ","?

switcharm =
    pattern matchguard? ":" expr

matchguard =
    "if" expr
```

## 12. patterns

### 12.1 pattern grammar

```text
pattern =
    wildcardpattern
  | bindingpattern
  | literalpattern
  | tuplepattern
  | arraypattern
  | structpattern
  | enumpattern
  | refpattern
```

### 12.2 basic patterns

```text
wildcardpattern = "_"

bindingpattern =
    "mut"? ident

literalpattern =
    literal
```

### 12.3 tuple and array patterns

```text
tuplepattern =
    "(" patternlist? ")"

arraypattern =
    "[" patternlist? "]"

patternlist =
    pattern ("," pattern)* ","?
```

### 12.4 struct and enum patterns

```text
structpattern =
    typepath "{" patternfieldlist? "}"

patternfieldlist =
    patternfield ("," patternfield)* ","?

patternfield =
    ident ":" pattern
  | ident
```

```text
enumpattern =
    typepath
  | typepath "(" patternlist? ")"
  | typepath "{" patternfieldlist? "}"
```

### 12.5 reference patterns

```text
refpattern =
    "&" "mut"? pattern
```

## 13. literals

```text
literal =
    int_literal
  | float_literal
  | string_literal
  | char_literal
  | "true"
  | "false"
```

## 14. function parameters and receivers

### 14.1 parameters

参数语法复用普通模式：

```text
param = pattern ":" type
```

### 14.2 method receivers

draft 0.1 推荐在语法层把方法接收者视为参数列表中的特殊首参数，允许以下写法：

```text
receiver =
    "self"
  | "&" "self"
  | "&" "mut" "self"
```

```text
methodparam =
    receiver
  | param
```

若函数位于 `impl` 块中，则首个参数可以是 `receiver`。

## 15. semicolons and newlines

s 的基本规则如下：

- 语句分隔主要依靠显式分号
- 块中的最后一个表达式可以省略分号，以产生块值
- 顶层声明之间不依赖换行作为语法边界

换行不参与语义，除非后续版本引入自动分号推断。draft 0.1 不建议依赖自动分号插入。

## 16. ambiguity notes

以下语法点在实现时需要特别注意：

1. 泛型参数列表 `[]` 与数组/切片语法都使用方括号，parser 需要依赖上下文区分
2. `typepath "{" ... "}"` 可能是结构体构造，也可能与块表达式相邻，需要按表达式上下文解析
3. `pathexpr` 与 `enumpattern` 在 `switch` 中共享前缀，需要在模式上下文解析
4. `for pattern in expr` 中的 `in` 建议作为上下文关键字处理
5. 元组表达式与括号表达式需要依赖逗号区分

## 17. minimal parser scope

最小版本的 parser 建议优先支持：

1. `package` 和 `use`
2. `func` / `struct` / `enum` / `trait` / `impl`
3. 基础类型语法
4. `var` / `var` / `return`
5. `if` / `while` / `for` / `switch`
6. 函数调用、成员访问、下标、`?`
7. 泛型参数和泛型实参
8. 基础模式匹配

可以后置的高级语法包括：

- 属性系统
- 闭包字面量
- 宏
- `async` / `await`
- 更复杂的模式展开

## 18. open questions

当前仍需进一步冻结的语法问题包括：

1. 泛型统一使用 `[]` 是否会与数组语法造成过高认知负担
2. 元组是否进入最小语言版本
3. 是否引入属性语法，例如 `@repr(c)` 或 `#[derive(...)]`
4. 闭包字面量的最终语法形式
5. `unsafe` 是否仅支持块，还是也支持函数/trait 级别修饰
6. 是否为模式匹配引入更丰富的 `..` 模式和守卫语法

## 19. neurx compatibility checklist

NeurX 这类深度学习框架代码建议优先遵循以下统一写法：

1. 切片统一写作 `[]t`，固定长度数组统一写作 `[n]t`。
2. map 统一写作 `map[K]V`，空 map 统一写作 `map[K]V{}`。
3. 多返回值统一写作 tuple return，例如 `func f(...) (t1, t2)`。
4. 复合字面量统一写作 `[]T{...}`、`[N]T{...}`、`map[K]V{...}`、`Type{...}`。
5. 容器初始化不要混用 `[]`, `{}`, `[]T{cap:n}` 和别的兼容写法。
6. 深度学习主干代码优先使用一种 `for in` 或范围循环风格，不要在同一模块里分裂成多种循环习惯。
7. 条件表达式、`select`、`switch`、`blockexpr` 的边界要固定，不要依赖实现细节推断。

典型优先整改文件：

- [transformer.s](/Users/feifei/shuwen/neurx/model/transformer/transformer.s)
- [loss.s](/Users/feifei/shuwen/neurx/train/loss.s)
- [text_generator.s](/Users/feifei/shuwen/neurx/infer/text_generator.s)
- [sampling_penalties.s](/Users/feifei/shuwen/neurx/infer/sampling_penalties.s)
- [sampling_beam.s](/Users/feifei/shuwen/neurx/infer/sampling_beam.s)

## 20. neurx migration notes

以下是按文件拆分的优先迁移建议，便于把规范直接落到代码：

### 20.1 transformer and training core

- [transformer.s](/Users/feifei/shuwen/neurx/model/transformer/transformer.s) 应优先统一多维容器写法，避免 `[][][]float hidden_states`、`[][]int attention_mask` 之外又混入旧式后缀声明。
- [loss.s](/Users/feifei/shuwen/neurx/train/loss.s) 应统一损失输入张量的数组语法，并把返回值风格固定下来，避免同类损失函数各自使用不同容器声明。
- [checkpoint_manager.s](/Users/feifei/shuwen/neurx/train/checkpoint_manager.s) 应优先清理空容器、空 map、状态初始化的写法，让 checkpoint 状态能稳定序列化和反序列化。

### 20.2 inference and sampling

- [text_generator.s](/Users/feifei/shuwen/neurx/infer/text_generator.s) 应先收敛条件表达式、生成结果构造和多序列输出的写法。
- [sampling_penalties.s](/Users/feifei/shuwen/neurx/infer/sampling_penalties.s) 应统一 `map`、`for in`、范围循环和空集合初始化语法。
- [sampling_beam.s](/Users/feifei/shuwen/neurx/infer/sampling_beam.s) 应统一 beam 容器的初始化、排序与返回方式，尽量避免在同一文件里同时出现空列表、容量列表和结构体字面量的不同风格。

### 20.3 migration strategy

建议按下面顺序推进：

1. 先改 `map` 和空容器初始化。
2. 再改多维数组和复合字面量。
3. 再统一函数返回值和 tuple return。
4. 最后收敛控制流和表达式糖。

### 20.4 PR checklist

在每个 NeurX 相关 PR 里，至少确认下面几项：

- 代码里不再新增 `T[]` 作为主容器写法。
- 不再新增 `map<int]bool`、`[string:int {` 这类非 canonical 语法。
- 新函数若需要多返回，优先使用 tuple return。
- 容器初始化要明确区分空值、预分配和字面量。
- 同一模块内只保留一种主循环风格。

### 20.5 pr short form

NeurX PR 可直接用这 5 条快速自检：

1. 容器只用 `[]t` / `[n]t` / `map[K]V` 的 canonical 形式。
2. 不新增非标准 map 或多维数组写法。
3. 多返回统一 tuple return。
4. 空容器、预分配、字面量初始化要区分清楚。
5. 同模块内只保留一种主循环风格。

一行版：`[]t` / `[n]t` / `map[K]V` 统一，tuple return 统一，初始化分清空值与预分配，循环风格只保留一种。

标题版：NeurX 语法统一只抓四件事，容器、map、返回值、循环。

commit 版：unify NeurX syntax around containers, maps, returns, and loops.

## 21. summary

这份语法规范的目的不是一次性把 s 的每个字符都锁死，而是先把最关键的表面结构冻结到足以实现 parser 和 formatter 的程度。

当前 draft 0.1 已经固定了这些核心方向：

- 明确的顶层声明结构
- 明确的类型与泛型写法
- 表达式优先级和后缀链规则
- `switch` 与模式匹配的基础形状
- 方法、借用和 `unsafe` 在语法层的位置

下一步若继续细化，最适合拆出的子议题是：

- 闭包语法
- 属性与派生语法
- `async` / `await`
- 完整 ebnf 和 lexer token 规范
