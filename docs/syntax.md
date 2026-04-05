# S Syntax Specification

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 的表面语法草案。

它的目标是：

- 固定词法结构
- 固定源文件和声明的基本形状
- 固定表达式与语句的主要产生式
- 固定模式匹配与泛型语法方向
- 为后续 parser 实现提供接近 EBNF 的语法依据

本文档是 [spec.md](/app/s/docs/spec.md) 的语法补充，与 [types.md](/app/s/docs/types.md) 和 [ownership.md](/app/s/docs/ownership.md) 配套使用。

## 2. Notation

本文档采用接近 EBNF 的记号：

- `A = B` 表示定义
- `A | B` 表示二选一
- `A?` 表示可选
- `A*` 表示零次或多次
- `A+` 表示一次或多次
- `()` 表示分组
- 字面终结符使用引号，例如 `"fn"`
- 词法类使用大写名称，例如 `IDENT`

为保持可读性，本文档不追求完全形式化的 parser grammar，而追求“足够严格、可落地实现”。

## 3. Lexical Structure

### 3.1 Source Text

源文件必须采用 UTF-8 编码。

词法分析器应将源文本切分为：

- 标识符
- 关键字
- 字面量
- 操作符
- 分隔符
- 注释
- 空白符

注释和空白符通常不进入语法分析阶段，除非实现需要保留位置信息。

### 3.2 Whitespace

```text
WHITESPACE = " " | "\t" | "\r" | "\n"
```

空白用于分隔 token，本身没有语义。

### 3.3 Comments

```text
LINE_COMMENT  = "//" { not_newline } newline?
BLOCK_COMMENT = "/*" { any_char } "*/"
```

Draft 0.1 推荐支持嵌套块注释，但这不是语义层强制要求。

### 3.4 Identifiers

```text
IDENT = XID_Start { XID_Continue }
```

约束：

- 不得与关键字完全相同
- 不得以数字开头

标准库和公共 API 推荐使用 ASCII 标识符。

### 3.5 Keywords

```text
package use as pub
fn let var const static
struct enum trait impl for
if else for while match
return break continue
true false
unsafe extern mut
```

### 3.6 Literals

```text
INT_LITERAL    = DEC_INT | HEX_INT | BIN_INT | OCT_INT
FLOAT_LITERAL  = DIGITS "." DIGITS EXP?
STRING_LITERAL = "\"" { string_char | escape } "\""
CHAR_LITERAL   = "'" char_or_escape "'"
```

说明：

- 整数字面量的精确后缀系统留待后续版本决定
- 浮点字面量至少支持十进制表示
- 字符串字面量默认为 UTF-8

### 3.7 Delimiters and Operators

```text
DELIMITERS = "(" ")" "[" "]" "{" "}" "," ":" ";" "." "->"

OPERATORS =
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

## 4. Compilation Unit

### 4.1 Source File

```text
SourceFile = PackageDecl UseDecl* Item*
```

### 4.2 Package Declaration

```text
PackageDecl = "package" PackagePath
PackagePath = IDENT ("." IDENT)*
```

每个源文件必须恰有一个 `package` 声明，并位于文件开头。

### 4.3 Imports

```text
UseDecl      = "use" ImportTree
ImportTree   = ImportPath ("as" IDENT)?
ImportPath   = IDENT ("." IDENT)* ImportGroup?
ImportGroup  = "." "{" ImportItem ("," ImportItem)* ","? "}"
ImportItem   = IDENT ("as" IDENT)?
```

示例：

```s
use net.http.Request
use io.{Reader, Writer}
use math as m
```

## 5. Top-Level Items

```text
Item =
    FunctionDecl
  | StructDecl
  | EnumDecl
  | TraitDecl
  | ImplDecl
  | ConstDecl
  | StaticDecl
```

```text
Visibility = "pub"
```

## 6. Declarations

### 6.1 Function Declaration

```text
FunctionDecl =
    Visibility? "fn" IDENT GenericParamList?
    "(" ParamList? ")" ReturnType?
    WhereClause? BlockExpr
```

```text
ParamList   = Param ("," Param)* ","?
Param       = Pattern ":" Type
ReturnType  = "->" Type
```

### 6.2 Struct Declaration

```text
StructDecl =
    Visibility? "struct" IDENT GenericParamList?
    StructBody

StructBody =
    "{" StructFieldList? "}"

StructFieldList =
    StructField ("," StructField)* ","?

StructField =
    Visibility? IDENT ":" Type
```

### 6.3 Enum Declaration

```text
EnumDecl =
    Visibility? "enum" IDENT GenericParamList?
    EnumBody

EnumBody =
    "{" EnumVariantList? "}"

EnumVariantList =
    EnumVariant ("," EnumVariant)* ","?

EnumVariant =
    IDENT EnumVariantBody?

EnumVariantBody =
    TupleVariantBody
  | RecordVariantBody

TupleVariantBody  = "(" TypeList? ")"
RecordVariantBody = "{" StructFieldList? "}"
```

### 6.4 Trait Declaration

```text
TraitDecl =
    Visibility? "trait" IDENT GenericParamList?
    TraitBody

TraitBody =
    "{" TraitItem* "}"

TraitItem =
    FunctionSig ";"
```

```text
FunctionSig =
    "fn" IDENT GenericParamList?
    "(" ParamList? ")" ReturnType?
    WhereClause?
```

### 6.5 Impl Declaration

```text
ImplDecl =
    "impl" GenericParamList? ImplHead WhereClause? ImplBody

ImplHead =
    Type
  | TraitRef "for" Type

ImplBody =
    "{" ImplItem* "}"

ImplItem =
    FunctionDecl
```

### 6.6 Constants and Statics

```text
ConstDecl =
    Visibility? "const" IDENT ":" Type "=" Expr ";"

StaticDecl =
    Visibility? "static" IDENT ":" Type "=" Expr ";"
```

## 7. Generic Syntax

### 7.1 Generic Parameter List

```text
GenericParamList =
    "[" GenericParam ("," GenericParam)* ","? "]"

GenericParam =
    IDENT TraitBoundList?
```

```text
TraitBoundList =
    ":" TraitBound ("+" TraitBound)*

TraitBound =
    TypePath
```

示例：

```s
fn max[T: Ord](a: T, b: T) -> T
fn copy_pair[T: Copy + Clone](a: T, b: T) -> (T, T)
```

### 7.2 Where Clause

```text
WhereClause =
    "where" WherePredicate ("," WherePredicate)* ","?

WherePredicate =
    Type ":" TraitBound ("+" TraitBound)*
```

`where` 子句用于较复杂的约束表达。Draft 0.1 固定方向，具体排版规则由 formatter 决定。

### 7.3 Generic Arguments

```text
GenericArgList =
    "[" Type ("," Type)* ","? "]"
```

示例：

```s
let v: Vec[i32]
let r: Result[String, IoError]
```

## 8. Types

### 8.1 Type Grammar

```text
Type =
    RefType
  | SliceType
  | ArrayType
  | TupleType
  | FunctionType
  | TypePath
  | "(" Type ")"
```

### 8.2 Reference Types

```text
RefType =
    "&" "mut"? Type
```

### 8.3 Slice and Array Types

```text
SliceType =
    "[" "]" Type

ArrayType =
    "[" Type ";" ConstExpr "]"
```

### 8.4 Tuple Types

```text
TupleType =
    "(" TypeList? ")"

TypeList =
    Type ("," Type)* ","?
```

### 8.5 Function Types

```text
FunctionType =
    "fn" "(" TypeList? ")" "->" Type
```

### 8.6 Paths

```text
TypePath =
    IDENT ("." IDENT)* GenericArgList?

TraitRef =
    TypePath
```

## 9. Statements

```text
Stmt =
    LetStmt
  | VarStmt
  | ExprStmt
  | SemiStmt
  | ReturnStmt
  | BreakStmt
  | ContinueStmt
```

### 9.1 Let and Var Statements

```text
LetStmt =
    "let" Pattern TypeAnnotation? ("=" Expr)? ";"

VarStmt =
    "var" Pattern TypeAnnotation? ("=" Expr)? ";"

TypeAnnotation =
    ":" Type
```

Draft 0.1 允许无初始化绑定是否最终保留，属于后续实现策略议题；若保留，编译器必须确保值在读取前已初始化。

### 9.2 Expression Statements

```text
ExprStmt =
    Expr

SemiStmt =
    Expr ";"
```

约定：

- 块内最后一个无分号表达式可作为块值
- 带分号的表达式语句值为 `()`

### 9.3 Control Transfer Statements

```text
ReturnStmt   = "return" Expr? ";"
BreakStmt    = "break" Expr? ";"
ContinueStmt = "continue" ";"
```

## 10. Block Expressions

```text
BlockExpr =
    "{" Stmt* FinalExpr? "}"

FinalExpr =
    Expr
```

块既是语句容器，也是表达式。

## 11. Expressions

### 11.1 Expression Categories

```text
Expr =
    AssignmentExpr
```

### 11.2 Precedence Overview

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

### 11.3 Assignment

```text
AssignmentExpr =
    LogicalOrExpr
  | UnaryExpr "=" AssignmentExpr
```

左值是否合法由语义层检查。

### 11.4 Logical Operators

```text
LogicalOrExpr  = LogicalAndExpr ("||" LogicalAndExpr)*
LogicalAndExpr = EqualityExpr ("&&" EqualityExpr)*
```

### 11.5 Equality and Comparison

```text
EqualityExpr =
    CompareExpr (("==" | "!=") CompareExpr)*

CompareExpr =
    RangeExpr (("<" | "<=" | ">" | ">=") RangeExpr)*
```

### 11.6 Range

```text
RangeExpr =
    AddExpr ((".." | "..=") AddExpr)?
```

### 11.7 Additive and Multiplicative

```text
AddExpr =
    MulExpr (("+" | "-") MulExpr)*

MulExpr =
    UnaryExpr (("*" | "/" | "%") UnaryExpr)*
```

### 11.8 Unary

```text
UnaryExpr =
    PostfixExpr
  | ("!" | "-" | "&") UnaryExpr
  | "&" "mut" UnaryExpr
  | "*" UnaryExpr
  | "unsafe" BlockExpr
```

说明：

- `*` 作为解引用操作的合法性由类型和安全规则决定
- `unsafe` 作为表达式前缀时引入不安全块

### 11.9 Postfix

```text
PostfixExpr =
    PrimaryExpr PostfixOp*

PostfixOp =
    CallSuffix
  | MemberSuffix
  | IndexSuffix
  | TrySuffix
```

```text
CallSuffix   = "(" ArgList? ")"
MemberSuffix = "." IDENT
IndexSuffix  = "[" Expr "]"
TrySuffix    = "?"

ArgList =
    Expr ("," Expr)* ","?
```

### 11.10 Primary Expressions

```text
PrimaryExpr =
    Literal
  | PathExpr
  | TupleExpr
  | ArrayExpr
  | StructExpr
  | BlockExpr
  | IfExpr
  | WhileExpr
  | ForExpr
  | MatchExpr
  | "(" Expr ")"
```

### 11.11 Path Expressions

```text
PathExpr =
    IDENT ("." IDENT)* GenericArgList?
```

### 11.12 Tuple and Array Expressions

```text
TupleExpr =
    "(" ExprList? ")"

ArrayExpr =
    "[" ExprList? "]"

ExprList =
    Expr ("," Expr)* ","?
```

### 11.13 Struct Expressions

```text
StructExpr =
    TypePath "{" FieldInitList? "}"

FieldInitList =
    FieldInit ("," FieldInit)* ","?

FieldInit =
    IDENT ":" Expr
  | IDENT
```

### 11.14 If Expression

```text
IfExpr =
    "if" Expr BlockExpr ("else" ElseBranch)?

ElseBranch =
    BlockExpr
  | IfExpr
```

### 11.15 While Expression

```text
WhileExpr =
    "while" Expr BlockExpr
```

### 11.16 For Expression

```text
ForExpr =
    "for" Pattern "in" Expr BlockExpr
```

`for` 依赖 `in` 关键语义，但 `in` 是否作为保留关键字还是上下文关键字，可由 lexer/parser 联合决定。Draft 0.1 建议将其视为上下文关键字。

### 11.17 Match Expression

```text
MatchExpr =
    "match" Expr "{" MatchArmList? "}"

MatchArmList =
    MatchArm ("," MatchArm)* ","?

MatchArm =
    Pattern MatchGuard? "=>" Expr

MatchGuard =
    "if" Expr
```

## 12. Patterns

### 12.1 Pattern Grammar

```text
Pattern =
    WildcardPattern
  | BindingPattern
  | LiteralPattern
  | TuplePattern
  | ArrayPattern
  | StructPattern
  | EnumPattern
  | RefPattern
```

### 12.2 Basic Patterns

```text
WildcardPattern = "_"

BindingPattern =
    "mut"? IDENT

LiteralPattern =
    Literal
```

### 12.3 Tuple and Array Patterns

```text
TuplePattern =
    "(" PatternList? ")"

ArrayPattern =
    "[" PatternList? "]"

PatternList =
    Pattern ("," Pattern)* ","?
```

### 12.4 Struct and Enum Patterns

```text
StructPattern =
    TypePath "{" PatternFieldList? "}"

PatternFieldList =
    PatternField ("," PatternField)* ","?

PatternField =
    IDENT ":" Pattern
  | IDENT
```

```text
EnumPattern =
    TypePath
  | TypePath "(" PatternList? ")"
  | TypePath "{" PatternFieldList? "}"
```

### 12.5 Reference Patterns

```text
RefPattern =
    "&" "mut"? Pattern
```

## 13. Literals

```text
Literal =
    INT_LITERAL
  | FLOAT_LITERAL
  | STRING_LITERAL
  | CHAR_LITERAL
  | "true"
  | "false"
```

## 14. Function Parameters and Receivers

### 14.1 Parameters

参数语法复用普通模式：

```text
Param = Pattern ":" Type
```

### 14.2 Method Receivers

Draft 0.1 推荐在语法层把方法接收者视为参数列表中的特殊首参数，允许以下写法：

```text
Receiver =
    "self"
  | "&" "self"
  | "&" "mut" "self"
```

```text
MethodParam =
    Receiver
  | Param
```

若函数位于 `impl` 块中，则首个参数可以是 `Receiver`。

## 15. Semicolons and Newlines

S 的基本规则如下：

- 语句分隔主要依靠显式分号
- 块中的最后一个表达式可以省略分号，以产生块值
- 顶层声明之间不依赖换行作为语法边界

换行不参与语义，除非后续版本引入自动分号推断。Draft 0.1 不建议依赖自动分号插入。

## 16. Ambiguity Notes

以下语法点在实现时需要特别注意：

1. 泛型参数列表 `[]` 与数组/切片语法都使用方括号，parser 需要依赖上下文区分
2. `TypePath "{" ... "}"` 可能是结构体构造，也可能与块表达式相邻，需要按表达式上下文解析
3. `PathExpr` 与 `EnumPattern` 在 `match` 中共享前缀，需要在模式上下文解析
4. `for Pattern in Expr` 中的 `in` 建议作为上下文关键字处理
5. 元组表达式与括号表达式需要依赖逗号区分

## 17. Minimal Parser Scope

最小版本的 parser 建议优先支持：

1. `package` 和 `use`
2. `fn` / `struct` / `enum` / `trait` / `impl`
3. 基础类型语法
4. `let` / `var` / `return`
5. `if` / `while` / `for` / `match`
6. 函数调用、成员访问、下标、`?`
7. 泛型参数和泛型实参
8. 基础模式匹配

可以后置的高级语法包括：

- 属性系统
- 闭包字面量
- 宏
- `async` / `await`
- 更复杂的模式展开

## 18. Open Questions

当前仍需进一步冻结的语法问题包括：

1. 泛型统一使用 `[]` 是否会与数组语法造成过高认知负担
2. 元组是否进入最小语言版本
3. 是否引入属性语法，例如 `@repr(C)` 或 `#[derive(...)]`
4. 闭包字面量的最终语法形式
5. `unsafe` 是否仅支持块，还是也支持函数/trait 级别修饰
6. 是否为模式匹配引入更丰富的 `..` 模式和守卫语法

## 19. Summary

这份语法规范的目的不是一次性把 S 的每个字符都锁死，而是先把最关键的表面结构冻结到足以实现 parser 和 formatter 的程度。

当前 Draft 0.1 已经固定了这些核心方向：

- 明确的顶层声明结构
- 明确的类型与泛型写法
- 表达式优先级和后缀链规则
- `match` 与模式匹配的基础形状
- 方法、借用和 `unsafe` 在语法层的位置

下一步若继续细化，最适合拆出的子议题是：

- 闭包语法
- 属性与派生语法
- `async` / `await`
- 完整 EBNF 和 lexer token 规范
