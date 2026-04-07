# S Standard Library

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 最小标准库的边界与分层原则。

它不追求一次性覆盖所有生态需求，而是回答两个更关键的问题：

- 一个“可用的 S”最少需要哪些库能力
- 哪些能力应属于语言核心，哪些应属于标准库，哪些应留给第三方生态

本文档与以下文档配套：

- [spec.md](/app/s/doc/spec.md)
- [syntax.md](/app/s/doc/syntax.md)
- [types.md](/app/s/doc/types.md)
- [ownership.md](/app/s/doc/ownership.md)

## 2. Design Goals

S 标准库的设计目标如下：

1. 核心小而稳
2. API 与语言语义一致
3. 默认零惊喜
4. 不依赖 GC
5. 对系统编程友好
6. 对服务端和工具链场景够用

标准库不应成为语言复杂度的主要来源。

## 3. Layering

S 的标准库建议分为三层：

### 3.1 Language-Coupled Core

这一层与语言语义紧密耦合，通常需要编译器理解或特殊对待。

候选包括：

- `Option[T]`
- `Result[T, E]`
- `String`
- `Vec[T]`
- `Box[T]`
- `Copy` / `Clone` / `Drop`
- `Send` / `Sync`
- `Error`

### 3.2 Platform-Neutral Runtime Library

这一层提供跨平台的通用能力：

- 集合
- 字符串处理
- 文件与 IO 抽象
- 时间
- 并发原语
- 格式化与测试支持

### 3.3 Platform-Bound Modules

这一层提供更贴近平台的能力：

- 文件系统细节
- socket
- 进程
- 环境变量
- 路径
- 动态库

这部分应尽量隔离在清晰模块中，而不是污染核心 API。

## 4. What Belongs in the Language vs the Library

### 4.1 Language Responsibilities

语言本身应负责：

- 基本类型和语法
- 所有权与借用规则
- 模式匹配
- `unsafe`
- 基础 trait 语义

### 4.2 Standard Library Responsibilities

标准库应负责：

- 拥有型字符串
- 容器
- 错误类型抽象
- IO 抽象
- 并发原语
- 时间、路径、文件系统 API
- 测试与断言工具

### 4.3 Third-Party Ecosystem Responsibilities

第三方库更适合承载：

- Web 框架
- 数据库驱动
- 序列化格式实现
- GUI
- 机器学习
- 专业数值库

## 5. Minimal Package Layout

建议最小标准库以 `std` 为根包：

```text
std
std.cmp
std.error
std.fmt
std.io
std.fs
std.path
std.mem
std.str
std.string
std.vec
std.map
std.option
std.result
std.sync
std.task
std.time
std.test
std.ffi
```

命名不必完全冻结，但建议保持短、稳、可预期。

## 6. Core Semantic Modules

### 6.1 `std.option`

定义：

```s
enum Option[T] {
    Some(T)
    None
}
```

最小 API 方向：

- `is_some() bool`
- `is_none() bool`
- `unwrap() T`
- `unwrap_or(T default) T`
- `map[U](func(T) U f) Option[U]`

### 6.2 `std.result`

定义：

```s
enum Result[T, E] {
    Ok(T)
    Err(E)
}
```

最小 API 方向：

- `is_ok() bool`
- `is_err() bool`
- `unwrap() T`
- `unwrap_err() E`
- `map[U](func(T) U f) Result[U, E]`
- `map_err[F](func(E) F f) Result[T, F]`

### 6.3 `std.error`

应定义统一错误 trait：

```s
trait Error {
    func message(&self) str
}
```

后续可扩展：

- `source() Option[&dyn Error]`
- 错误分类
- backtrace 支持

Draft 0.1 先固定最小接口。

### 6.4 `std.cmp`

应提供基础比较 trait：

- `Eq`
- `Ord`

必要时补充：

- `PartialEq`
- `PartialOrd`

是否一开始就完整区分全序和偏序，取决于实现优先级；Draft 0.1 推荐先保留方向。

## 7. Memory and Ownership-Oriented Modules

### 7.1 `std.mem`

职责：

- 内存相关基础函数
- move/replace/take 等辅助操作
- 大小与对齐查询

最小 API 方向：

- `size_of[T]() usize`
- `align_of[T]() usize`
- `replace[T](&mut T place, T value) T`
- `take[T: Default](&mut T place) T`

### 7.2 `std.box`

若 S 采用显式堆分配包装器，则 `Box[T]` 应放在核心库中。

职责：

- 表示唯一拥有的堆对象
- 作为递归类型和 FFI 的基础工具

### 7.3 `std.sync`

最小并发同步原语建议包括：

- `Mutex[T]`
- `RwLock[T]`
- `Arc[T]`
- 原子类型家族

这些类型应与 `Send` / `Sync` 语义紧密协作。

## 8. String and Text

### 8.1 `std.str`

表示借用字符串视图相关能力。

最小职责：

- UTF-8 基础检查
- 基本遍历
- 子串与查找

### 8.2 `std.string`

定义拥有型字符串 `String`。

最小 API 方向：

- `new()`
- `from(s: &str)`
- `len() usize`
- `is_empty() bool`
- `push(ch: char)`
- `push_str(s: &str)`
- `as_str() &str`

设计要求：

- 不依赖 GC
- 明确容量与分配行为
- 能与 `&str` 高效协作

### 8.3 Formatting

推荐由 `std.fmt` 提供基础格式化能力，而不是把字符串拼接过度塞进语言层。

最小能力：

- `Display`
- `Debug`
- `println`
- `eprintln`

## 9. Collections

### 9.1 `std.vec`

`Vec[T]` 是最重要的标准容器之一。

最小 API 方向：

- `new()`
- `with_capacity(n: usize)`
- `len() usize`
- `capacity() usize`
- `push(value: T)`
- `pop() Option[T]`
- `get(index: usize) Option[&T]`
- `get_mut(index: usize) Option[&mut T]`
- `as_slice() []T`

### 9.2 `std.map`

建议最小版本提供一种通用关联容器，例如 `Map[K, V]`。

最小 API 方向：

- `new()`
- `insert(K key, V value) Option[V]`
- `get(key: &K) Option[&V]`
- `get_mut(key: &K) Option[&mut V]`
- `remove(key: &K) Option[V]`
- `contains(key: &K) bool`

具体选择哈希映射还是有序映射作为默认 `Map`，属于设计决策点。Draft 0.1 可以先保留抽象名。

### 9.3 Optional Early Containers

如果实现资源允许，可额外补：

- `Set[T]`
- `Deque[T]`
- `SmallVec[T]`

但它们不应阻塞 MVP。

## 10. IO and Filesystem

### 10.1 `std.io`

应定义基础 IO 抽象：

- `Reader`
- `Writer`
- `Seek`

最小 API 方向：

```s
trait Reader {
    func read(&mut Self self, []u8 buf) Result[usize, IoError]
}

trait Writer {
    func write(&mut Self self, []u8 buf) Result[usize, IoError]
    func flush(&mut Self self) Result[(), IoError]
}
```

### 10.2 `std.fs`

最小文件系统 API 建议包括：

- `File`
- 读写文件
- 元数据查询
- 创建目录

示例方向：

- `File::open(path: &Path) Result[File, IoError]`
- `File::create(path: &Path) Result[File, IoError]`
- `read_to_string(path: &Path) Result[String, IoError]`

### 10.3 `std.path`

应提供 `Path` 与 `PathBuf` 的分层：

- `Path`：借用路径视图
- `PathBuf`：拥有型路径对象

这能与 `str` / `String` 的设计保持一致。

## 11. Concurrency and Tasks

### 11.1 `std.task`

应提供结构化并发方向的任务 API。

最小能力建议：

- `scope`
- `spawn`
- `join`
- 取消语义

示例方向：

```s
task::scope(|scope| {
    let h = scope.spawn(|| work())
    h.join()
})
```

### 11.2 Channels

channel 可以放入 `std.sync` 或 `std.task`，但必须是标准并发体验的一部分。

最小能力建议：

- 有界 channel
- `send`
- `recv`
- 关闭检测

## 12. Time and Duration

### 12.1 `std.time`

最小能力建议：

- `Duration`
- `Instant`
- `SystemTime`

用途：

- 超时控制
- 性能测量
- 定时任务

## 13. FFI and Platform Interop

### 13.1 `std.ffi`

最小能力建议：

- C 字符串桥接
- 原始指针包装辅助
- 布局与 ABI 辅助类型

如果 S 要落地系统编程，这部分虽然小，但不能缺位。

## 14. Testing and Assertions

### 14.1 `std.test`

标准库或官方工具链应提供最小测试支持。

最小能力建议：

- `assert`
- `assert_eq`
- `assert_ne`
- 测试发现与运行约定

### 14.2 Panic Support

`panic`、`unreachable`、`todo` 等宏式或函数式接口，可由 `std.test` 或 `std.panic` 承载。

命名可以后续细化，但最小工程体验必须有这些基础工具。

## 15. Default Prelude

S 应谨慎设计默认预导入内容。

推荐只自动引入最常用、最稳定的少量项，例如：

- `Option`
- `Result`
- `Copy`
- `Clone`
- `Drop`
- `println`

不建议把过多 API 放入默认 prelude，否则会降低可读性并增加命名冲突。

## 16. What Should Not Be in the Minimal Standard Library

以下内容不应阻塞 MVP：

- HTTP 客户端/服务端框架
- JSON/YAML/TOML 全家桶
- ORM
- 加密协议高级封装
- GUI
- WebAssembly 专用工具
- 宏生态
- 重型异步 runtime

这些更适合作为官方扩展包或第三方生态。

## 17. Stability Strategy

标准库应分层稳定：

- 核心语义模块最稳定
- 平台模块可更谨慎演进
- 实验性模块应显式标记

建议引入：

- edition 兼容策略
- API 废弃流程
- 稳定性标签

## 18. Minimal Stdlib for MVP

若目标是尽快产出一个可用的 S MVP，建议最先实现这些模块：

1. `std.option`
2. `std.result`
3. `std.error`
4. `std.string`
5. `std.vec`
6. `std.io`
7. `std.fs`
8. `std.mem`
9. `std.fmt`
10. `std.test`

若要更进一步支撑服务端开发，再追加：

11. `std.sync`
12. `std.task`
13. `std.time`
14. `std.path`
15. `std.ffi`

## 19. Open Questions

当前仍需继续明确的问题包括：

1. `Map[K, V]` 默认选哈希表还是有序树
2. `Box[T]` 是否进入最小标准库
3. channel 放在 `std.sync` 还是 `std.task`
4. 是否一开始就引入 `Arc[T]`
5. `Display` / `Debug` 是否作为核心 trait 同步进入 MVP
6. 默认 prelude 的精确名单
7. `std.io` 的 trait 边界是否需要更细分

## 20. Summary

S 的最小标准库不应以“功能多”为目标，而应以“把语言真正变得可用”为目标。

这意味着它首先要解决的是：

- 值和错误怎么表达
- 字符串和容器怎么使用
- 文件和 IO 怎么访问
- 并发和同步怎么落地
- 工程测试怎么起步

只要这些边界定得清楚，S 就能先作为一门真正可做项目的语言站住，而不是停留在语法展示层面。
