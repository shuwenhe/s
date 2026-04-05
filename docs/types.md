# S Type System

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 的类型系统草案。

它重点描述：

- 类型分类
- 类型检查与推导原则
- 结构体、枚举和复合类型
- trait 模型
- 泛型与约束
- `Copy`、`Drop`、`Send`、`Sync` 等核心语义 trait
- 类型转换与一致性规则

本文档与以下文档配套使用：

- [spec.md](/app/s/docs/spec.md)：总规范
- [ownership.md](/app/s/docs/ownership.md)：所有权、借用与资源释放

## 2. Design Goals

S 的类型系统目标如下：

1. 静态强类型
2. 类型错误尽早暴露
3. 支持系统编程所需的精确控制
4. 不鼓励隐式魔法
5. 泛型足够强，但不走模板元编程失控路线
6. 能和所有权、并发模型自然协作

## 3. Type Categories

S 中的类型可以分为以下几类：

### 3.1 Primitive Types

内建原始类型：

```text
bool
i8 i16 i32 i64 isize
u8 u16 u32 u64 usize
f32 f64
char
str
```

### 3.2 Compound Types

复合类型包括：

- 数组：`[T; N]`
- 切片：`[]T`
- 元组：后续版本可选
- 引用：`&T`、`&mut T`
- 函数类型

### 3.3 User-Defined Types

用户自定义类型包括：

- `struct`
- `enum`
- `trait`

### 3.4 Library Types

标准库或第三方库可定义拥有型容器和资源类型，例如：

- `String`
- `Vec[T]`
- `Map[K, V]`
- `Result[T, E]`
- `Option[T]`

这些不是语言原语，但语言需要为其提供一致的类型规则。

## 4. Static Typing

S 是静态类型语言。每个表达式在编译期都应有确定类型。

编译器必须在编译期检查：

- 操作符是否适用于操作数类型
- 函数调用参数是否匹配
- 返回值类型是否一致
- 分支表达式是否可统一
- trait 约束是否满足

### 4.1 Type Inference

S 支持局部类型推导，但不允许推导变成阅读负担或隐藏成本。

示例：

```s
let x = 42
let s = String::from("hello")
```

编译器应能推导 `x` 和 `s` 的类型。

### 4.2 Required Explicitness

以下场景通常要求显式类型：

- 函数参数
- 函数返回值
- 公开 API 中的重要结构字段
- 推导结果可能歧义的表达式

示例：

```s
fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

## 5. Primitive Types

### 5.1 Boolean

`bool` 只有两个值：

- `true`
- `false`

### 5.2 Integers

S 提供固定宽度和平台相关整数类型：

- 有符号：`i8` `i16` `i32` `i64` `isize`
- 无符号：`u8` `u16` `u32` `u64` `usize`

规则：

- 固定宽度整数必须满足对应位宽
- `isize` 和 `usize` 与目标平台指针宽度一致

### 5.3 Floating-Point

支持：

- `f32`
- `f64`

默认浮点字面量的推导规则属于后续细化议题；Draft 0.1 推荐优先推导为 `f64`，除非上下文要求更窄类型。

### 5.4 Character and String Slice

- `char` 表示单个 Unicode 标量值
- `str` 表示 UTF-8 字符串切片视图

`str` 不是拥有型字符串，拥有型字符串由标准库 `String` 提供。

## 6. References

引用类型由所有权模型约束：

- `&T`：共享只读引用
- `&mut T`：唯一可变引用

类型系统必须将引用视为独立类型构造，而不是语法糖。

示例：

```s
fn len(s: &str) -> usize
fn push(v: &mut Vec[i32], value: i32)
```

引用类型与底层拥有型类型不同，不应隐式退化为裸地址。

## 7. Arrays, Slices, and Collections

### 7.1 Arrays

固定长度数组：

```s
[T; N]
```

规则：

- `N` 必须为编译期常量
- 数组长度是类型的一部分

因此 `[i32; 4]` 与 `[i32; 5]` 是不同类型。

### 7.2 Slices

切片表示对连续元素区间的借用视图：

```s
[]T
```

切片通常不拥有底层存储，其有效性受原始数据生命周期约束。

### 7.3 Collection Traits

后续标准库应围绕集合类型定义统一 trait，例如：

- `Iterable`
- `Index`
- `Extend`
- `FromIterator`

Draft 0.1 先固定方向，不冻结具体命名。

## 8. Struct Types

结构体是具名字段聚合类型：

```s
struct User {
    id: u64
    name: String
    active: bool
}
```

### 8.1 Field Types

每个字段必须有明确类型。

字段类型可以是：

- 原始类型
- 复合类型
- 用户自定义类型
- 泛型实例化类型

### 8.2 Recursive Types

递归类型必须通过间接层表达，避免无限大小。

允许方向：

- `Box[T]`
- 引用
- 指针

禁止方向：

- 直接把自身按值嵌入自身

## 9. Enum Types

枚举用于描述多个离散变体：

```s
enum Result[T, E] {
    Ok(T)
    Err(E)
}
```

### 9.1 Variant Forms

枚举分支建议支持：

- 空分支
- 单值分支
- 多值分支
- 具名字段分支

### 9.2 Exhaustiveness

对 `enum` 进行 `match` 时，编译器应进行穷尽性检查。

### 9.3 Discriminant Layout

枚举的内存布局和 discriminant 编码属于实现层议题，但语言层面应保证语义一致。

若后续版本需要 C ABI 兼容布局，应通过显式属性开启，而不是默认承诺所有枚举布局稳定。

## 10. Function Types

函数拥有明确的参数和返回类型。

概念上，一个函数类型可写作：

```text
fn(T1, T2) -> R
```

是否允许函数类型作为一等值直接书写、是否支持闭包 trait，属于后续版本细化议题；Draft 0.1 先要求语义层支持函数值和闭包值的区分。

## 11. Type Equality and Compatibility

S 默认采用名义类型与结构类型混合但偏名义的策略：

- 原始类型按名称区分
- `struct` 和 `enum` 按名义区分
- 引用、数组、切片等复合类型按构造规则区分

例如：

- 两个字段完全相同但名称不同的 `struct` 默认不是同一类型
- `[i32; 4]` 与 `[i32; 5]` 不兼容
- `&T` 与 `&mut T` 不兼容

## 12. Type Inference Rules

### 12.1 Local Inference

局部绑定可以依赖初始化表达式推导类型：

```s
let x = 1
let ok = true
```

### 12.2 Branch Unification

`if`、`match` 等表达式各分支必须可统一为单一类型。

示例：

```s
let value = if flag { 1 } else { 2 }
```

合法，因为两边都是 `i32` 候选。

以下应视为非法，除非存在显式转换：

```s
let value = if flag { 1 } else { "x" }
```

### 12.3 Generic Inference

调用泛型函数时，编译器可以根据参数和上下文推导类型参数。

示例：

```s
let m = max(1, 2)
```

若约束和上下文足够明确，则 `T` 可推导为 `i32`。

若存在多个可能结果且无进一步线索，编译器应要求显式标注。

## 13. Casts and Conversions

### 13.1 No Implicit Numeric Conversion

S 默认不允许隐式数值转换。

```s
let a: i32 = 1
let b: i64 = 2
let c = a as i64 + b
```

### 13.2 Safe vs Potentially Lossy Conversions

语言层面可允许统一使用 `as`，但工具链应区分：

- 明显安全转换
- 可能截断或丢精度的转换

后者宜提供 lint 或更严格的替代 API。

### 13.3 Trait-Based Conversion

对于非原始类型转换，推荐采用 trait 驱动：

- `From[T]`
- `Into[T]`
- `TryFrom[T]`
- `TryInto[T]`

这样可以避免把复杂对象转换硬编码为语言特例。

## 14. Traits

trait 是 S 中描述行为能力的主要机制。

### 14.1 Trait Definition

```s
trait Writer {
    fn write(&mut self, data: []u8) -> Result[usize, IoError]
}
```

trait 可以包含：

- 方法签名
- 关联类型：后续版本可选
- 默认实现：后续版本可选

Draft 0.1 至少要求支持方法签名和约束用途。

### 14.2 Trait Implementation

```s
impl Writer for File {
    fn write(&mut self, data: []u8) -> Result[usize, IoError] {
        ...
    }
}
```

是否允许孤儿规则放宽、是否允许特化，属于后续高级议题；Draft 0.1 建议采取保守一致的实现规则。

### 14.3 Trait Bounds

trait 可作为泛型约束：

```s
fn flush_all[T: Writer](items: []T) -> Result[(), IoError] {
    ...
}
```

### 14.4 Trait Objects

是否支持动态分发 trait 对象属于后续细化议题。

Draft 0.1 可以先只要求静态分发语义，等泛型与 trait 基础稳定后再引入动态对象模型。

## 15. Generics

### 15.1 Generic Parameters

S 支持参数化类型和参数化函数：

```s
struct Vec[T] {
    ...
}

fn max[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}
```

### 15.2 Generic Constraints

泛型参数可以附带 trait 约束：

```s
fn sort[T: Ord](items: &mut []T)
```

一个参数拥有多个约束的具体语法可在后续版本细化，例如：

```text
T: Ord + Copy
```

### 15.3 Monomorphization and Shared Instantiation

S 的语言语义不强制单一实现策略，但要求：

- 泛型行为对用户可预测
- 不同 backend 策略不改变可观察语义

可接受实现路线包括：

- 单态化
- 字典传递
- 混合策略

## 16. Core Semantic Traits

S 需要一组核心 trait 来表达类型语义边界。

这些 trait 有两种可能来源：

- 语言内建 trait
- 标准库预定义但被编译器识别的 trait

Draft 0.1 更推荐第二种做法：语义上核心、表面上像普通 trait。

### 16.1 `Copy`

`Copy` 表示类型可在赋值和传参时隐式复制。

语义要求：

- 值复制后，源值仍然有效
- 复制不引入双重释放
- 复制语义应接近按位安全复制或等价行为

典型候选：

- 标量类型
- 全部字段均为 `Copy` 的简单结构体

不适合 `Copy` 的类型：

- `String`
- `Vec[T]`
- 文件句柄包装器
- 锁、socket、数据库连接等资源对象

### 16.2 `Drop`

`Drop` 表示类型在离开作用域时需要执行析构逻辑。

语义要求：

- `Drop` 类型拥有资源释放责任
- 实现 `Drop` 的类型通常不应同时实现 `Copy`

示例：

```s
trait Drop {
    fn drop(&mut self)
}
```

### 16.3 `Clone`

`Clone` 表示类型支持显式复制语义。

与 `Copy` 的区别：

- `Copy` 是隐式、廉价、无歧义复制
- `Clone` 是显式、可能昂贵、可能分配的复制

示例：

```s
trait Clone {
    fn clone(&self) -> Self
}
```

### 16.4 `Send`

`Send` 表示值可安全地跨线程移动。

语义要求：

- 移动到另一个线程后，不会破坏内存安全
- 不会引入未同步共享可变状态

### 16.5 `Sync`

`Sync` 表示 `&T` 可被多个线程安全共享。

语义要求：

- 对共享引用的并发访问不会造成数据竞争

### 16.6 Relationship Between `Send` and `Sync`

这两个 trait 相关但不同：

- 某类型可以 `Send` 但不 `Sync`
- 某类型可以 `Sync` 但其拥有型值的移动语义仍需单独判断

编译器或标准库不应把两者简单视作同义词。

## 17. Trait Derivation

为减轻样板代码，S 可以在后续版本支持受控的派生机制。

候选包括：

- `Copy`
- `Clone`
- `Eq`
- `Ord`
- `Debug`

但派生必须满足两个条件：

1. 规则简单透明
2. 不引入难以理解的隐式行为

Draft 0.1 只固定方向，不冻结具体语法。

## 18. Pattern Matching and Types

模式匹配应与类型系统紧密结合。

示例：

```s
match result {
    Ok(value) => println(value),
    Err(err) => eprintln(err.message()),
}
```

编译器在类型检查时应：

- 为每个分支引入正确绑定类型
- 检查所有分支返回类型是否一致
- 检查枚举分支是否穷尽

## 19. Error Types

S 推荐把错误也建模为普通类型。

建议存在统一错误 trait：

```s
trait Error {
    fn message(&self) -> str
}
```

这允许：

- `Result[T, E]` 中的 `E` 参与泛型约束
- 错误类型保持普通值语义
- 错误处理不依赖特殊异常对象

## 20. Type System and Ownership

类型系统必须与所有权系统协同工作。

关键交叉点包括：

- `&T` / `&mut T` 是不同类型
- `Copy` 决定赋值是复制还是移动
- `Drop` 决定值离开作用域时是否需要析构
- `Send` / `Sync` 决定类型能否穿越并发边界

换句话说，S 的类型系统不是纯静态分类系统，而是资源语义的一部分。

## 21. Diagnostics

类型错误的诊断应尽量指出：

- 期望类型与实际类型
- 哪个 trait 约束未满足
- 为什么某类型不能 `Copy`
- 为什么某值不能跨线程发送
- 为什么某个 `match` 分支类型不一致

推荐诊断包含：

- 失败位置
- 约束来源
- 可能修复路径，例如补类型标注、改借用、加 `clone()`、补实现 trait

## 22. Minimal Type Checker Scope

为了让 S 尽快落地，最小版本的类型检查器可优先支持：

1. 原始类型检查
2. `struct` / `enum` 类型检查
3. 函数签名匹配
4. 基础泛型参数替换
5. 基础 trait bound 检查
6. `Result` / `Option` 和 `match` 的类型检查
7. `Copy` / `Drop` / `Send` / `Sync` 的最小语义判断

可以后置的高级能力包括：

- trait 对象
- 关联类型
- 高级类型推导
- 更复杂的自动派生
- 特化和重叠实现

## 23. Open Questions

以下问题仍需后续收束：

1. `trait` 是否支持关联类型和默认实现
2. 泛型约束的完整语法如何设计
3. trait 实现是否采用严格孤儿规则
4. 是否支持 trait 对象和动态分发
5. `Copy` 是否允许自动派生到用户结构体
6. `Send` / `Sync` 是编译器自动推导还是显式声明
7. 数字字面量默认类型如何精确规定

## 24. Summary

S 的类型系统希望做到三件事：

- 让类型表达足够强，能支撑系统编程
- 让语义 trait 足够清晰，能和资源模型配合
- 让规则足够克制，不把语言演化成类型技巧竞赛

如果这套设计成立，S 就可以同时拥有：

- 静态类型语言的可靠性
- 系统语言的可控性
- 现代工程语言的可维护性
