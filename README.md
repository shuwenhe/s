# S Language

S 是一门面向系统软件、基础设施和高性能服务的编程语言草案。

它希望提取 C、Go、Rust、C++ 各自最有价值的部分，而避开它们最容易拖累工程体验的部分：

- 从 C 借用贴近硬件、布局可控、ABI 友好的能力
- 从 Go 借用统一工具链、简洁语法和高效工程体验
- 从 Rust 借用默认安全、显式危险边界和健壮的错误模型
- 从 C++ 借用 RAII、零成本抽象和值语义表达力

S 的目标不是做“四门语言的拼盘”，而是做一门系统级、默认安全、表达直接、工具链完整的现代语言。

## 设计宣言

S 试图回答一个很实际的问题：

为什么写系统软件时，我们总要在几组矛盾里选一边？

- 要性能，就常常失去安全
- 要安全，就常常失去可预测性
- 要抽象能力，就常常失去编译速度和可读性
- 要工程效率，就常常失去底层控制力

S 的答案是：

- 默认安全，但不牺牲底层控制
- 值语义优先，但允许显式引用和可控共享
- 抽象应该接近零成本，而不是依赖运行时魔法
- 工具链必须官方统一，避免生态级碎片化
- 危险能力必须存在，但必须被明确隔离在 `unsafe`

一句话概括：

> S = C 的控制力 + Go 的工程体验 + Rust 的安全边界 + C++ 的零成本抽象

## 语言定位

S 适合的场景：

- 服务端基础设施
- 网络服务与网关
- 数据处理与存储引擎
- 编译器、运行时、中间件
- 嵌入式与系统组件
- 需要 C ABI 互操作的高性能模块

S 暂时不把自己定位成：

- 以 GC 为核心的业务脚本语言
- 以元编程为核心的研究型语言
- 以极端类型体操为卖点的学术语言

## 核心原则

### 1. 默认安全

普通 S 代码默认不允许出现明显未定义行为来源：

- 空悬引用
- double free
- 越界访问
- 数据竞争

需要直接操作裸指针、手工管理内存、调用不安全 FFI 时，必须进入 `unsafe` 边界。

### 2. 值语义优先

S 优先鼓励：

- 小对象按值传递
- 资源通过作用域自动释放
- 所有权清晰流动

引用和共享不是默认行为，而是显式行为。

### 3. 可预测性能

S 语言本身不鼓励隐式堆分配，不依赖 GC 才能正常写程序。

开发者应该能较容易回答：

- 这段代码会不会分配
- 这次传参会不会拷贝
- 这个对象何时释放
- 这次并发是否需要同步

### 4. 工程优先于技巧

S 更重视：

- 易读
- 易学
- 易维护
- 易编译
- 易部署

而不是让开发者通过复杂技巧“战胜语言”。

### 5. 单一官方工具链

S 自带统一工具：

- `s build`
- `s run`
- `s test`
- `s fmt`
- `s lint`
- `s doc`
- `s pkg`

语言、包管理、测试、格式化、文档和构建应由同一套官方体验串起来。

## 语法草案

S 语法目标是“接近 Go/Rust 的清晰度”，但保留系统语言需要的明确性。

### Hello World

```s
package main

fn main() {
    println("hello, world")
}
```

### 变量与常量

```s
let x = 42
let price: f64 = 12.5
var count = 0
const max_conn = 1024
```

约定：

- `let` 表示默认不可变绑定
- `var` 表示可变绑定
- `const` 表示编译期常量

### 基本类型

```s
bool
i8 i16 i32 i64 isize
u8 u16 u32 u64 usize
f32 f64
char
str
```

说明：

- `str` 是 UTF-8 字符串切片视图
- 堆上可增长字符串使用 `String`
- 字节序列使用 `[]u8`

### 控制流

```s
if score > 90 {
    grade = "A"
} else if score > 80 {
    grade = "B"
} else {
    grade = "C"
}

for item in items {
    println(item)
}

for i in 0..10 {
    println(i)
}

while running {
    tick()
}
```

### 函数

```s
fn add(a: i32, b: i32) -> i32 {
    a + b
}

fn open_file(path: str) -> Result<File, IoError> {
    ...
}
```

默认规则：

- 函数签名必须显式
- 返回值使用 `->`
- 单表达式函数体可以隐式返回最后一个表达式

### 结构体与方法

```s
struct User {
    id: u64
    name: String
    active: bool
}

impl User {
    fn activate(mut self) {
        self.active = true
    }

    fn display_name(self) -> str {
        self.name.as_str()
    }
}
```

### 枚举与模式匹配

```s
enum Option[T] {
    Some(T)
    None
}

enum Result[T, E] {
    Ok(T)
    Err(E)
}

match result {
    Ok(value) => println(value),
    Err(err) => eprintln(err.message()),
}
```

### 泛型

```s
fn max[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}
```

S 支持泛型，但只追求工程上够用、可读、可编译，不鼓励模板元编程式的复杂化。

## 类型系统

S 使用静态强类型系统，默认支持类型推导，但拒绝模糊不清的隐式转换。

### 类型系统目标

- 对新手友好
- 对系统编程足够强
- 对错误足够早暴露
- 对编译器实现足够可控

### 设计要点

#### 1. 默认无隐式数值转换

```s
let a: i32 = 1
let b: i64 = 2
let c = a as i64 + b
```

这样做虽然略显严格，但能大幅减少系统编程中的边界错误。

#### 2. 代数数据类型

S 原生支持：

- `enum`
- `Option[T]`
- `Result[T, E]`
- 模式匹配

这让错误处理、状态建模和协议建模更自然。

#### 3. trait 风格约束

```s
trait Writer {
    fn write(mut self, data: []u8) -> Result[usize, IoError]
}
```

用途：

- 抽象行为
- 为泛型提供约束
- 避免面向继承的复杂对象层级

#### 4. 明确区分值、借用与拥有

S 不要求像 Rust 那样把生命周期复杂度全面显式暴露给用户，但仍然保留核心语义：

- 值有单一明确的拥有者
- 临时借用必须受作用域约束
- 可变借用在同一时刻必须唯一

这里可以采用一种更“工程化”的 borrow-lite 方案：

- 大多数生命周期由编译器推断
- 只有在复杂跨函数返回借用时才要求显式注解

### 建议的引用模型

```s
fn len(s: &str) -> usize
fn push(v: &mut Vec[i32], value: i32)
fn consume(buf: Buf) -> Result[(), Error]
```

含义：

- `T` 表示拥有值
- `&T` 表示只读借用
- `&mut T` 表示可变借用

这样既保留系统语言的精确性，也不会完全失去熟悉感。

## 内存与资源管理

这是 S 的核心。

### 主路线：RAII + move 语义

S 默认使用基于作用域的资源释放。

```s
fn main() -> Result[(), IoError] {
    let file = File::open("a.txt")?
    let data = file.read_all()?
    println(data)
    Ok(())
}
```

当 `file` 离开作用域，资源自动释放。

### 不以 GC 为前提

S 不把垃圾回收设为默认依赖，这样可以保证：

- 延迟更稳定
- 内存行为更可预测
- 更适合系统组件和高性能服务

### 分层内存模型

S 应支持三层内存能力：

#### 1. 安全默认层

- 栈对象
- RAII 资源对象
- 标准容器

#### 2. 高性能控制层

- arena
- pool allocator
- 自定义 allocator

#### 3. 危险能力层

- 裸指针
- 手工释放
- 非托管内存

这些能力必须通过 `unsafe` 暴露。

### unsafe 边界

```s
unsafe {
    let p: *mut u8 = alloc(1024)
    raw_write(p, 0xff)
    free(p)
}
```

原则：

- `unsafe` 是能力开关，不是性能开关
- 安全代码可以调用被良好封装的 `unsafe` 库
- 不安全实现应尽量缩小到少数模块

## 错误处理

S 采用 `Result[T, E]` 作为主流错误处理模型，不把异常作为默认机制。

### 基础形式

```s
fn parse_port(s: str) -> Result[u16, ParseError] {
    ...
}
```

### 传播操作符

```s
fn run() -> Result[(), Error] {
    let cfg = load_config("app.conf")?
    let conn = connect(cfg.addr)?
    conn.start()?
    Ok(())
}
```

### 不可恢复错误

对于真正不可恢复的问题，可以提供：

- `panic`
- `assert`
- `unreachable`

但它们不应替代正常错误建模。

### 错误设计原则

- 错误必须可组合
- 错误应带上下文
- 错误打印应友好
- 标准库要提供统一错误 trait

例如：

```s
trait Error {
    fn message(self) -> str
    fn source(self) -> Option[&Error]
}
```

## 并发模型

S 的并发设计建议同时吸收 Go 和 Rust 的优点：

- 写法上尽量简单
- 数据安全上尽量严格

### 建议主模型：结构化并发

```s
fn main() -> Result[(), Error] {
    task::scope(|scope| {
        let a = scope.spawn(|| fetch_price("BTC-USDT"))
        let b = scope.spawn(|| fetch_price("ETH-USDT"))

        let pa = a.join()?
        let pb = b.join()?
        println(pa, pb)
    })
}
```

特点：

- 子任务生命周期受父作用域约束
- 降低 goroutine 泄漏类问题
- 更适合服务端工程

### channel 通信

```s
let (tx, rx) = channel[Job](1024)

spawn || {
    tx.send(job)?
}

let item = rx.recv()?
```

### 并发安全约束

S 可以借鉴 Rust 的思想，但用更轻量的形式表达：

- 只有满足 `Send` 的类型可跨线程移动
- 只有满足 `Sync` 的类型可被多线程共享引用

```s
trait Send
trait Sync
```

### 不鼓励裸共享可变状态

首选：

- 消息传递
- 作用域任务
- 显式 `Mutex` / `RwLock` / `Atomic`

而不是默认自由共享。

## 模块与包系统

S 不应采用 C/C++ 头文件模型。

### 模块

```s
package net.http

pub struct Request { ... }

fn parse_header(...) -> Header { ... }
```

建议规则：

- 一个文件属于一个模块
- 一个目录构成一个包
- `pub` 控制导出
- 默认私有

### 导入

```s
use net.http.Request
use io.{Reader, Writer}
use math as m
```

### 包管理

每个项目有一个清晰 manifest：

```toml
[package]
name = "demo"
version = "0.1.0"
edition = "2026"

[dependencies]
http = "1.2"
json = "0.8"
```

### 版本与构建

S 需要：

- 锁文件
- 可复现构建
- workspace
- monorepo 友好

## 标准库方向

标准库建议“核心小而稳，外围包分层扩展”。

核心至少包括：

- 基础类型与容器
- 字符串与 UTF-8
- 文件与 IO
- 网络
- 并发原语
- 时间
- 序列化接口
- 测试框架
- FFI

## FFI 与系统能力

为了真正进入系统领域，S 必须优先做好 C ABI 互操作。

### C FFI 示例

```s
extern "C" fn puts(s: *const u8) -> i32
```

设计目标：

- 可导入 C 函数
- 可导出 S 函数给 C
- 结构体布局可控
- 调用约定明确

如果 C FFI 做不好，S 很难成为真正可落地的系统语言。

## 与 C / Go / Rust / C++ 的取舍

### 从 C 学什么

- 简洁
- 可预测布局
- 贴近硬件
- FFI 友好

### 不学什么

- 默认裸指针
- 宏替代语言机制
- 未定义行为泛滥

### 从 Go 学什么

- 工具链统一
- 构建体验统一
- 包管理和测试内建
- 语法简洁

### 不学什么

- 过度依赖 GC
- 容易变成样板的错误写法

### 从 Rust 学什么

- 默认安全
- `Option` / `Result`
- trait 抽象
- 模式匹配
- `unsafe` 边界

### 不学什么

- 把所有复杂度都直接暴露给用户
- 让简单程序也被生命周期语法淹没

### 从 C++ 学什么

- RAII
- move 语义
- 零成本抽象
- 强大的库表达力

### 不学什么

- 过重历史包袱
- 规则爆炸
- 模板错误灾难

## 一个可能的最小语言子集

S 的第一个可用版本不需要一次性解决所有问题。

最小可用子集可以只包含：

- 基本类型
- `struct`
- `enum`
- `fn`
- `let/var/const`
- `if/for/while/match`
- `Result` / `Option`
- `&` / `&mut`
- `impl` / `trait`
- `package` / `use`
- `unsafe`
- 基础标准库
- `s build` / `s run` / `s test` / `s fmt`

这样就已经足够写：

- CLI 工具
- 简单网络服务
- 文件处理程序
- 小型系统组件

## Roadmap

### Phase 0: 愿景与规范

目标：

- 明确语言定位
- 冻结核心语法方向
- 明确内存模型和错误模型

产出：

- 语言宣言
- 语法草案
- 类型系统草案
- 标准库最小清单

### Phase 1: 最小编译器

目标：

- 能编译最小可执行程序
- 支持基本类型、函数、控制流和模块

优先实现：

- lexer
- parser
- AST
- type checker
- 简单 IR
- LLVM backend 或自研最小 backend

### Phase 2: 资源与错误模型

目标：

- 实现 `Result`
- 实现 RAII
- 实现 move 和借用基础规则

优先实现：

- 作用域销毁
- 所有权转移
- `?` 操作符
- 模式匹配

### Phase 3: 标准库与工具链

目标：

- 让语言可用于真实小项目

优先实现：

- `String`
- `Vec`
- `Map`
- IO
- 文件系统
- 测试框架
- formatter
- package manager

### Phase 4: 并发与 runtime

目标：

- 支持服务端场景

优先实现：

- task runtime
- channel
- timer
- socket API
- 结构化并发

### Phase 5: FFI 与生态接入

目标：

- 能与现有 C 生态共存
- 能构建系统模块和高性能服务

优先实现：

- C ABI
- 动态库/静态库输出
- allocator API
- profiling hooks

## 成功标准

如果 S 设计成功，它应该满足这些标准：

- 一个熟悉 Go 的工程师能在几天内上手
- 一个熟悉 Rust 的工程师不会觉得它“不安全到不可用”
- 一个熟悉 C/C++ 的工程师不会觉得它“失去控制力”
- 一个中型服务项目能在不依赖 GC 的情况下自然落地
- 工具链体验比传统系统语言明显更统一

## 当前状态

当前仓库中的 S 仍然处于设计草案阶段。

下一步最值得继续推进的内容：

1. 写出正式语法规范草案
2. 设计 borrow-lite 的精确规则
3. 设计 `trait` 与泛型实例化策略
4. 设计标准库最小 API
5. 决定编译器实现路线和 IR 方案

## 许可证与协作方向

欢迎围绕以下议题继续演化这份草案：

- 语法是否足够简洁
- 所有权模型是否足够实用
- 并发模型是否应更偏 Go 还是更偏 Rust
- 标准库边界应画在哪里
- 是否需要 edition 机制来承载未来演化

S 不是为了“重新发明一切”，而是为了把现代系统语言里那些已经被证明有价值的设计，重新组合成一个更统一、更可学、更适合工程落地的整体。
