# S Language Specification

Version: Draft 0.1  
Status: Working Draft

## 1. Overview

S 是一门面向系统软件、基础设施和高性能服务的静态类型编程语言。

本规范定义 S 的核心语言行为，包括：

- 词法与语法
- 声明与作用域
- 类型系统
- 所有权、借用与资源管理
- 错误处理
- 并发模型
- 模块与包系统
- `unsafe` 与 FFI 边界

本规范暂不定义：

- 完整标准库 API
- 完整 runtime 实现细节
- 优化器与 backend 的实现策略
- 调试信息、反射与宏系统

除特别说明外，本规范中的“必须”、“应当”、“可以”分别表示强制要求、推荐要求和允许行为。

## 2. Design Goals

S 的设计目标如下：

1. 默认安全
2. 可预测性能
3. 值语义优先
4. 零成本抽象导向
5. 单一官方工具链
6. 对 C ABI 友好

S 不以垃圾回收为前提，不以面向继承为核心，也不把复杂元编程作为主设计方向。

## 3. Terminology

本规范使用以下术语：

- 绑定：名称到值或存储位置的关联
- 值：拥有完整语义的运行时对象
- 拥有者：负责某个值生命周期的绑定或对象
- 借用：对某值的临时引用，不转移所有权
- 只读借用：`&T`
- 可变借用：`&mut T`
- 移动：将值的所有权从一个位置转移到另一个位置
- 复制：保留源值，同时创建语义等价的新值
- 析构：值离开作用域时触发的资源释放逻辑
- 模块：单个源文件声明的命名空间单元
- 包：由一个或多个模块组成的分发与编译单元

## 4. Source File Structure

一个 S 源文件应满足如下高层结构：

```s
package pkg.name

use std.io.Reader
use net.http.{Request, Response}

struct Config {
    String addr
}

func main() -> Result[(), Error] {
    ...
}
```

推荐顺序如下：

1. `package` 声明
2. `use` 导入
3. 类型声明
4. trait 声明
5. `impl` 块
6. 常量与全局静态项
7. 函数定义

每个源文件必须且只能声明一个 `package`。

## 5. Lexical Elements

### 5.1 Character Set

S 源文件应采用 UTF-8 编码。

标识符可以包含 Unicode 字符，但标准库和公共 API 推荐使用 ASCII 标识符。

### 5.2 Whitespace

空格、Tab、换行用于分隔 token。除字符串字面量和字符字面量外，连续空白字符没有语义差异。

### 5.3 Comments

S 支持以下注释形式：

```s
// line comment

/* block comment */
```

块注释可以跨多行。是否支持嵌套块注释属于实现定义，Draft 0.1 推荐支持。

### 5.4 Identifiers

标识符用于命名：

- 包
- 模块项
- 变量
- 类型
- trait
- 泛型参数

标识符不得以数字开头。

以下为保留关键字：

```text
package use func var const struct enum trait impl
if else for while match return break continue
true false unsafe extern as mut
```

## 6. Grammar Sketch

本节给出非正式语法草图，用于固定表面语法方向。正式 EBNF 可在后续版本补充。

```text
SourceFile   = PackageDecl UseDecl* Item*
PackageDecl  = "package" PackagePath
UseDecl      = "use" ImportPath

Item         = FunctionDecl
             | StructDecl
             | EnumDecl
             | TraitDecl
             | ImplDecl
             | ConstDecl
             | StaticDecl

FunctionDecl = "func" Ident GenericParams? "(" ParamList? ")" ReturnType? Block
StructDecl   = Visibility? "struct" Ident GenericParams? StructBody
EnumDecl     = Visibility? "enum" Ident GenericParams? EnumBody
TraitDecl    = Visibility? "trait" Ident GenericParams? TraitBody
ImplDecl     = "impl" Type GenericParams? ImplBody

Stmt         = LetStmt
             | VarStmt
             | ExprStmt
             | ReturnStmt
             | BreakStmt
             | ContinueStmt

Expr         = Literal
             | PathExpr
             | CallExpr
             | MemberExpr
             | IndexExpr
             | UnaryExpr
             | BinaryExpr
             | MatchExpr
             | BlockExpr
```

## 7. Declarations and Visibility

### 7.1 Visibility

S 采用 Go 风格的可见性规则。

- 首字母小写的顶层项仅在当前包内可见
- 首字母大写的顶层项可被其他包导入

示例：

```s
struct tokenizer { ... }

struct Parser { ... }
```

### 7.2 Bindings

S 支持两种基础绑定形式：

```s
var y = 2
const max_conn = 1024
```

规则如下：

- `var` 绑定可变
- `const` 必须在编译期可求值

### 7.3 Shadowing

内层作用域可以遮蔽外层同名绑定：

```s
var x = 1
{
    var x = 2
    println(x)
}
```

是否对重复遮蔽发出 lint 警告由工具链决定，但语言层面允许。

## 8. Primitive Types

S 的内建基础类型包括：

```text
bool
i8 i16 i32 i64 isize
u8 u16 u32 u64 usize
f32 f64
char
str
```

规则：

- `bool` 的值仅为 `true` 或 `false`
- `char` 表示一个 Unicode 标量值
- `str` 表示 UTF-8 字符串切片视图
- `String` 不是内建原语，而是标准库拥有型字符串

### 8.1 Numeric Conversions

S 默认不进行隐式数值扩宽或截断。

```s
i32 a = 1
i64 b = 2
let c = a as i64 + b
```

所有可能改变数值范围、符号或精度的转换都必须显式使用 `as`。

## 9. Composite Types

### 9.1 Arrays and Slices

Draft 0.1 建议采用如下形式：

- 固定长度数组：`[T; N]`
- 切片：`[]T`

示例：

```s
[i32; 4] a = [1, 2, 3, 4]
[]i32 s = a[1..3]
```

### 9.2 Struct Types

结构体定义具名字段聚合类型：

```s
struct User {
    u64 id
    String name
    bool active
}
```

字段默认遵循声明顺序布局，但 ABI 稳定布局是否默认保证属于后续版本议题。

### 9.3 Enum Types

枚举用于定义代数数据类型：

```s
enum Result[T, E] {
    Ok(T)
    Err(E)
}
```

枚举分支可以是：

- 无载荷分支
- 单值分支
- 多字段元组分支
- 具名字段分支

Draft 0.1 推荐同时支持上述几类形式。

## 10. Functions

### 10.1 Function Declaration

函数声明形式如下：

```s
func add(i32 a, i32 b) -> i32 {
    a + b
}
```

规则：

- 参数类型必须显式声明
- 返回类型可以省略，省略时表示返回 `()`
- 函数体最后一个表达式可以作为隐式返回值

### 10.2 Parameter Passing

参数传递遵循签名中写明的语义：

- `T`：按值传递，可能发生移动或复制
- `&T`：只读借用
- `&mut T`：可变借用

示例：

```s
func len(&str s) -> usize
func push(&mut Vec[i32] v, i32 value)
func consume(Buf buf) -> Result[(), Error]
```

### 10.3 Methods

方法通过 `impl` 块声明：

```s
impl User {
    func activate(&mut Self self) {
        self.active = true
    }

    func name(&Self self) -> str {
        self.name.as_str()
    }
}
```

Draft 0.1 推荐将方法接收者统一建模为显式的：

- `self`
- `&Self self`
- `&mut Self self`

## 11. Expressions and Statements

S 是表达式优先的语言，但仍保留清晰的语句结构。

### 11.1 Block Expressions

块既是语句容器，也是表达式：

```s
let port = {
    let base = 8000
    base + 80
}
```

块的值为其最后一个表达式的值；若最后一项不是表达式，则块值为 `()`。

### 11.2 Control Flow

S 支持：

- `if`
- `for`
- `while`
- `match`
- `break`
- `continue`
- `return`

示例：

```s
if ready {
    run()
} else {
    wait()
}
```

### 11.3 Match

`match` 必须覆盖所有可能情况，除非存在显式的通配分支。

```s
match result {
    Ok(value) => println(value),
    Err(err) => eprintln(err.message()),
}
```

对于布尔值、枚举和有限状态类型，编译器应进行穷尽性检查。

## 12. Ownership, Move, and Borrowing

### 12.1 Ownership Model

S 采用“单一拥有者 + 显式借用”的基础模型。

规则如下：

1. 每个拥有型值在任一时刻有且仅有一个逻辑拥有者
2. 值可以被移动到新位置
3. 值可以被临时借用
4. 离开作用域时，拥有者负责触发析构

### 12.2 Move Semantics

默认情况下，非 `Copy` 类型按值传递时发生移动：

```s
let a = make_buffer()
let b = a
// a 在此后不可再使用
```

### 12.3 Copy Semantics

对小型、纯值、无资源语义的类型，可以实现 `Copy`：

```s
trait Copy
```

`Copy` 类型在赋值和传参时复制而非移动。

### 12.4 Borrowing Rules

S 借用模型的核心约束如下：

1. 任意时刻允许存在多个只读借用
2. 任意时刻至多存在一个可变借用
3. 当可变借用存在时，不允许同时存在其他借用
4. 借用不得超过被借用值的有效生命周期

示例：

```s
let n = user.name()
let a = &user
let b = &user
```

以下情形应视为非法：

```s
let a = &user
let b = &mut user
```

### 12.5 Lifetime Inference

Draft 0.1 采用 borrow-lite 方向：

- 大多数局部借用生命周期由编译器推断
- 简单函数参数与返回借用可使用省略规则
- 复杂跨函数返回借用场景允许后续版本引入显式生命周期标注

这意味着生命周期是语言语义的一部分，但不要求在最小版本里全面暴露为显式语法。

## 13. Resource Management

### 13.1 RAII

S 使用基于作用域的资源释放模型。

示例：

```s
func load() -> Result[String, IoError] {
    let file = File::open("config.toml")?
    file.read_all()
}
```

当 `file` 离开作用域时，其资源应自动释放。

### 13.2 Drop

拥有外部资源的类型可以定义析构行为。Draft 0.1 建议提供一个类似 `Drop` 的 trait：

```s
trait Drop {
    func drop(&mut Self self)
}
```

当值离开作用域时，编译器自动插入相应析构逻辑。

### 13.3 Allocation Model

S 的默认执行模型不依赖 GC。分配策略分层如下：

1. 栈上值
2. 标准库拥有型堆对象
3. 自定义 allocator
4. `unsafe` 下的原始分配

语言应尽量避免隐式堆分配。

## 14. Traits and Generics

### 14.1 Traits

trait 用于描述共享行为约束：

```s
trait Writer {
    func write(&mut Self self, []u8 data) -> Result[usize, IoError]
}
```

trait 的用途包括：

- 约束泛型参数
- 统一接口行为
- 描述能力边界，如 `Copy`、`Send`、`Sync`

### 14.2 Generic Functions

```s
func max[T: Ord](T a, T b) -> T {
    if a > b { a } else { b }
}
```

规则：

- 泛型参数列表写在名称后
- 约束使用 `:` 指定
- 一个参数可以拥有多个 trait 约束，具体分隔语法留待后续版本确定

### 14.3 Instantiation Strategy

泛型实例化策略属于实现层议题，但语言层面应允许以下两种实现路线：

- 单态化
- 基于字典或 witness table 的共享实例化

Draft 0.1 不强制固定 backend 策略，但要求表面语义独立于实现选择。

## 15. Error Handling

### 15.1 Result and Option

S 采用 `Result[T, E]` 作为可恢复错误的标准建模方式，采用 `Option[T]` 表示值可能缺失。

```s
enum Option[T] {
    Some(T)
    None
}

enum Result[T, E] {
    Ok(T)
    Err(E)
}
```

### 15.2 Error Propagation

S 支持 `?` 用于传播错误：

```s
func run() -> Result[(), Error] {
    let cfg = load_config("app.conf")?
    let conn = connect(cfg.addr)?
    conn.start()?
    Ok(())
}
```

规则：

- `?` 只能用于返回 `Result` 或兼容错误载体的上下文
- 若表达式结果为错误，则立即返回
- 若表达式结果为成功值，则解包继续执行

### 15.3 Panic

`panic` 表示不可恢复错误，不应用于普通业务错误流。

以下机制属于不可恢复路径：

- `panic`
- `assert`
- `unreachable`

标准库应为其提供明确语义，但代码风格上应限制其滥用。

## 16. Concurrency

### 16.1 Model

S 推荐采用结构化并发作为主模型。

```s
task::scope(|scope| {
    let a = scope.spawn(|| fetch_price("BTC-USDT"))
    let b = scope.spawn(|| fetch_price("ETH-USDT"))

    let pa = a.join()?
    let pb = b.join()?
    println(pa, pb)
})
```

结构化并发要求：

- 子任务受父作用域管理
- 离开作用域前必须完成、取消或转交任务所有权
- 不鼓励无边界后台任务泄漏

### 16.2 Channels

消息传递是推荐并发通信方式：

```s
let (tx, rx) = channel[Job](1024)
```

标准库应提供：

- 有界 channel
- 可选无界 channel
- 关闭语义
- 超时与取消机制

### 16.3 Shared State

S 允许共享状态，但必须显式同步。

建议标准并发原语包括：

- `Mutex[T]`
- `RwLock[T]`
- `Atomic*`

### 16.4 Send and Sync

跨线程传递和共享应由 trait 约束控制：

```s
trait Send
trait Sync
```

规则建议如下：

- 满足 `Send` 的类型可以跨线程移动
- 满足 `Sync` 的类型可以被多线程共享只读引用

编译器应阻止不满足约束的类型进入并发边界。

## 17. Modules and Packages

### 17.1 Modules

模块是源文件级命名空间单元。每个源文件属于一个 `package`。

导入语法建议如下：

```s
use net.http.Request
use io.{Reader, Writer}
use math as m
```

### 17.2 Packages

包是构建、发布和版本管理单元。

一个包应至少包含：

- 源码目录
- manifest 文件
- 可选测试与文档目录

建议 manifest 形式如下：

```toml
[package]
name = "demo"
version = "0.1.0"
edition = "2026"

[dependencies]
http = "1.2"
json = "0.8"
```

### 17.3 Editions

S 推荐引入 edition 机制，用于承载语言演化而不破坏既有项目。

edition 主要用于：

- 语法扩展
- 标准库默认行为调整
- 编译器 lint 与保守规则升级

## 18. Unsafe Code

### 18.1 Unsafe Boundary

任何可能绕过语言安全保证的操作都必须位于 `unsafe` 上下文中。

示例：

```s
unsafe {
    *mut u8 p = alloc(1024)
    raw_write(p, 0xff)
    free(p)
}
```

### 18.2 Unsafe Operations

以下操作应被归类为 `unsafe`：

- 解引用裸指针
- 调用未经验证的 FFI
- 访问未初始化内存
- 手工管理非托管资源
- 承诺编译器无法自行验证的不变量

### 18.3 Safety Contract

`unsafe` 代码必须承担额外义务：

- 明确维护内存安全不变量
- 明确维护线程安全不变量
- 将不安全区域缩小到最小范围

安全代码可以调用内部使用 `unsafe` 实现、但接口已被封装证明安全的库。

## 19. Foreign Function Interface

### 19.1 C ABI

S 应优先支持 C ABI。

示例：

```s
extern "C" func puts(*const u8 s) -> i32
```

FFI 至少应支持：

- 声明外部函数
- 导出 S 函数
- 指定调用约定
- 明确结构体布局

### 19.2 Layout Control

为满足 FFI 和系统场景需要，后续版本建议引入属性或修饰符以控制：

- 结构体字段布局
- 对齐
- 调用约定
- 符号导出名

Draft 0.1 先固定方向，不强制固定具体语法。

## 20. Standard Toolchain

S 官方工具链至少应包括：

- `s build`
- `s run`
- `s test`
- `s fmt`
- `s lint`
- `s doc`
- `s pkg`

工具链目标：

- 默认统一
- 可复现构建
- workspace 友好
- monorepo 友好

## 21. Undefined and Implementation-Defined Areas

为避免过早冻结设计，以下内容在 Draft 0.1 中属于未定或实现定义区域：

- 块注释是否嵌套
- 泛型实例化的 backend 策略
- 生命周期显式语法
- trait 对象与动态分发形式
- 完整数组、切片和迭代器语法
- 属性系统
- 宏系统
- 反射与编译期执行

后续版本应将这些区域逐步收束成正式规范。

## 22. Open Questions

当前仍需明确的关键设计问题包括：

1. 借用规则中哪些场景需要显式生命周期语法
2. `Copy`、`Drop`、`Send`、`Sync` 是内建 trait 还是标准库 trait
3. 结构体默认布局是否承诺稳定
4. 泛型更偏单态化还是混合实例化
5. 并发 runtime 是语言绑定还是标准库实现
6. `async` 是否成为一等语法，还是保持库级模型
7. 错误类型是否要求统一实现 `Error` trait

## 23. Minimal Viable Language

S 的最小可用版本应至少支持：

- 基本类型
- `let` / `var` / `const`
- `func`
- `struct`
- `enum`
- `if` / `for` / `while` / `match`
- `Result` / `Option`
- `impl`
- `trait`
- `&` / `&mut`
- `unsafe`
- 模块与包导入

只要这些能力稳定，S 就已经足以支撑：

- CLI 工具
- 配置与文件处理程序
- 小型网络服务
- 系统组件原型

## 24. Conformance

一个实现若要声称支持本规范 Draft 0.1，至少应：

1. 支持本规范定义的核心声明形式
2. 支持静态类型检查
3. 支持 `Result` / `Option` 与 `match`
4. 支持基础所有权与借用检查
5. 支持 `unsafe` 边界
6. 支持 `package` / `use` 基础模块系统

若某实现对未定区域作出具体选择，应在文档中明确说明。

## 25. Evolution Notes

本规范是工作草案，不承诺当前语法最终冻结。

后续推荐拆分为以下子文档：

- `syntax.md`
- `types.md`
- `ownership.md`
- `concurrency.md`
- `ffi.md`
- `toolchain.md`

这样可以让 S 在保持整体方向稳定的前提下，逐步把各部分从设计草案推进为可执行规范。
