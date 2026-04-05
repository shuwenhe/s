# S Ownership and Borrowing

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 的所有权、借用与资源释放模型。

它的目标不是把所有复杂度都暴露给开发者，而是在以下目标之间取得平衡：

- 默认内存安全
- 明确资源生命周期
- 可预测性能
- 足够简单的日常使用体验

本文档是 [spec.md](/app/s/docs/spec.md) 的补充，重点细化以下主题：

- 拥有值与借用值的区别
- 移动与复制的语义
- 借用检查的核心规则
- 析构与资源释放
- 与并发边界的关系
- `unsafe` 能绕过什么、不能绕过什么

## 2. Core Model

S 采用“拥有值 + 临时借用 + 作用域释放”的资源模型。

核心假设如下：

1. 每个拥有型值在任一时刻有且仅有一个逻辑拥有者
2. 值可以被移动到新的拥有者
3. 值可以被一个或多个只读借用引用
4. 值可以被唯一的可变借用临时独占
5. 值离开拥有者作用域时自动析构

这个模型的目的不是强迫开发者手工管理一切，而是让编译器能在编译期回答这些关键问题：

- 这个值由谁负责释放
- 这个引用是否可能悬空
- 这个可变访问是否与其他访问冲突
- 这个并发传递是否安全

## 3. Ownership Categories

S 中的值可按语义分为三类：

### 3.1 Owned Values

拥有型值负责资源生命周期。

示例：

```s
let name: String = String::from("alice")
let buf: Vec[u8] = Vec::with_capacity(1024)
```

`String` 和 `Vec[u8]` 是拥有型对象，它们通常持有堆资源，因此必须有清晰的析构责任。

### 3.2 Borrowed Values

借用值不拥有资源，只在有限作用域内引用其他值。

示例：

```s
func print_name(name: &str) {
    println(name)
}
```

这里的 `&str` 是只读借用，不负责释放底层数据。

### 3.3 Copy Values

部分无资源、纯值语义的小型类型可以在赋值或传参时复制而不是移动。

示例：

- `bool`
- 整数类型
- 浮点类型
- 不含资源字段的简单聚合类型

Copy 类型是否自动推导或要求显式声明，属于后续细化议题；Draft 0.1 推荐由编译器自动识别基础类型，并允许用户为安全类型显式声明。

## 4. Binding and Ownership

绑定本身不是资源，绑定只是资源拥有关系的承载位置。

```s
let a = String::from("hello")
let b = a
```

上例中：

- `a` 初始拥有该 `String`
- 赋值给 `b` 后，所有权转移到 `b`
- `a` 在移动后不再可用

对拥有型值来说，赋值默认解释为所有权移动，而不是隐式深拷贝。

## 5. Move Semantics

### 5.1 Default Rule

对非 `Copy` 类型：

- 赋值会移动
- 按值传参会移动
- 作为返回值传出会移动

示例：

```s
let a = make_buffer()
let b = a
use(a) // illegal
```

编译器必须拒绝对已移动值的再次使用。

### 5.2 Move Out of Aggregates

从聚合类型中移动字段会影响整个对象的可用性，除非类型系统明确支持部分移动并能跟踪剩余状态。

Draft 0.1 推荐采取保守策略：

- 默认不允许对普通结构体进行复杂部分移动
- 后续版本可在有充分语义保证时支持更细粒度分析

### 5.3 Moves in Control Flow

编译器必须在控制流合流点检查值是否仍然有效。

示例：

```s
let x = make_buffer()

if flag {
    consume(x)
}

use(x)
```

若 `consume(x)` 会移动 `x`，则 `use(x)` 是否合法取决于所有路径上 `x` 是否仍有效。若某条路径已失效，编译器必须拒绝。

## 6. Copy Semantics

### 6.1 Copy Types

若一个类型满足以下条件，则可以被视为 `Copy` 候选：

- 不持有需要显式析构的资源
- 复制后不会引入双重释放
- 复制语义与值语义一致

典型 `Copy` 类型包括：

- `bool`
- `i32`
- `u64`
- `f64`
- 由 `Copy` 字段组成的简单结构体

### 6.2 Copy vs Clone

S 应区分：

- 隐式复制：只适用于 `Copy` 类型
- 显式克隆：适用于非 `Copy` 类型

示例：

```s
let a = String::from("hello")
let b = a.clone()
```

这里 `clone()` 是显式语义，提醒开发者这可能涉及分配和数据复制。

## 7. Borrowing

借用允许代码在不转移所有权的情况下访问值。

S 支持两种借用：

- `&T`：只读借用
- `&mut T`：可变借用

### 7.1 Shared Borrow

只读借用允许多个并存：

```s
let a = &user
let b = &user
println(a.name(), b.name())
```

只读借用期间，不允许通过拥有者或其他路径对该值进行会破坏引用有效性的修改。

### 7.2 Mutable Borrow

可变借用是独占借用：

```s
let u = &mut user
u.activate()
```

当 `&mut` 借用存在时：

- 不允许其他只读借用并存
- 不允许其他可变借用并存
- 不允许通过原拥有者直接访问同一值

### 7.3 Borrow Scope

借用的有效范围称为借用作用域。

Draft 0.1 建议采用“非词法生命周期”方向：

- 借用持续到最后一次实际使用，而不必机械延续到整个块末尾

示例：

```s
let a = &user
println(a.name())

let b = &mut user
b.activate()
```

若编译器能证明 `a` 在创建 `b` 前已经不再使用，则这段代码可以合法。

## 8. Borrowing Rules

编译器至少必须执行如下检查：

### 8.1 Aliasing Rule

任意时刻：

- 可以有多个 `&T`
- 或者有一个 `&mut T`
- 但不能同时存在两者

非法示例：

```s
let a = &user
let b = &mut user
```

### 8.2 Use-After-Move Rule

已被移动的值不得再次使用。

非法示例：

```s
let x = String::from("a")
let y = x
println(x)
```

### 8.3 Outliving Rule

借用的生命周期不得超过被借用值本身。

非法示例：

```s
func bad() -> &str {
    let s = String::from("hello")
    s.as_str()
}
```

这里返回的借用指向局部变量 `s`，在函数返回后将悬空，因此必须拒绝。

### 8.4 Mutation Through Shared Reference

只读借用不可用于修改底层值。

非法示例：

```s
func bad(user: &User) {
    user.active = false
}
```

### 8.5 Escaping Mutable Borrow

可变借用不得在拥有者已失效后继续存在，也不得以不受约束的方式逃逸。

这条规则对于闭包、异步任务和并发边界尤其重要。

## 9. Borrow Inference

S 不希望要求开发者在日常代码里显式书写大量生命周期参数，因此采用 borrow-lite 方向。

### 9.1 Inference Goals

编译器应优先自动推断：

- 局部借用的起止范围
- 简单参数和返回值的借用关系
- 方法接收者的借用有效期

### 9.2 Explicit Syntax Boundary

Draft 0.1 建议：

- 最小版本不强制公开完整生命周期语法
- 复杂跨函数借用场景可先限制表达能力
- 等语义稳定后，再决定是否引入显式生命周期参数

这种策略的优点是：

- 让常见代码更易学
- 减少规范初期复杂度
- 把难度集中到少数真正需要的地方

代价是：

- 某些高级借用模式暂时无法表达
- 编译器诊断需要足够清楚，帮助用户理解为何被拒绝

## 10. Function Interfaces

函数签名决定所有权边界。

### 10.1 By Value

```s
func consume(buf: Buf) -> Result[(), Error]
```

按值参数通常意味着：

- 调用方移动值
- 被调用方获得所有权

若参数类型是 `Copy`，则表现为复制。

### 10.2 By Shared Borrow

```s
func len(s: &str) -> usize
```

表示调用方保留所有权，被调用方只做只读访问。

### 10.3 By Mutable Borrow

```s
func push(v: &mut Vec[i32], value: i32)
```

表示调用方保留所有权，但临时把唯一修改权交给被调用方。

### 10.4 Return Values

返回值默认按值返回。

若返回拥有型对象，则所有权转移给调用方。

若返回借用，则编译器必须能证明该借用来自仍然有效的输入或静态存储。

## 11. Methods and Receivers

方法接收者是所有权规则的重要入口。

### 11.1 `self`

```s
func into_bytes(self) -> Vec[u8]
```

表示方法消费接收者。

### 11.2 `&self`

```s
func len(&self) -> usize
```

表示方法只读访问接收者。

### 11.3 `&mut self`

```s
func clear(&mut self)
```

表示方法临时独占修改接收者。

方法调用语法虽然看起来简洁，但语义上应等价于显式传参。

## 12. Destruction and Drop

### 12.1 Scope Exit

拥有型值在离开作用域时自动析构。

示例：

```s
func load() -> Result[String, IoError] {
    let file = File::open("config.toml")?
    let data = file.read_all()?
    Ok(data)
}
```

上例中：

- `file` 在函数结束前被析构
- `data` 被移动到返回值，因此不在本地析构

### 12.2 Reverse Destruction Order

Draft 0.1 推荐局部变量按逆声明顺序析构。

这样通常更符合资源依赖直觉，也与许多系统语言习惯一致。

### 12.3 Custom Drop

拥有资源的类型可以定义自定义析构逻辑：

```s
trait Drop {
    func drop(&mut self)
}
```

一旦类型定义了 `Drop` 或等价机制，它通常不再适合作为 `Copy` 类型。

## 13. Partial Initialization and Invalid States

所有权系统不仅关心释放，还关心对象是否始终处于有效状态。

Draft 0.1 建议采用保守规则：

- 普通安全代码中，不允许读取未初始化字段
- 不允许构造只初始化一半的公开结构体值
- 需要这类能力时，必须进入 `unsafe`

这类规则能明显降低系统编程中最危险的一类错误。

## 14. Closures and Captures

闭包如何捕获外部变量，直接影响所有权语义。

Draft 0.1 建议支持三种捕获方式：

- 按借用捕获
- 按可变借用捕获
- 按值捕获

示例方向：

```s
let name = String::from("alice")

let f = || {
    println(name)
}
```

编译器应根据闭包体的使用方式推断捕获模式，或在歧义场景要求显式标注。

关键规则：

- 若闭包逃逸当前作用域，捕获的借用必须同样有效
- 若闭包在线程间传递，捕获值必须满足并发约束

## 15. Ownership Across Concurrency Boundaries

并发是所有权系统的重要应用场景。

### 15.1 Moving into Tasks

当值被传入新任务时，默认应发生所有权移动：

```s
let buf = make_buffer()

spawn move || {
    process(buf)
}
```

任务启动后，原作用域不得再使用 `buf`。

### 15.2 Borrowing Across Tasks

把普通局部借用直接传给可能异步执行的任务通常是不安全的，除非编译器能证明：

- 任务不会超过借用对象的生命周期
- 访问模式满足借用别名规则

因此 Draft 0.1 推荐：

- 对跨线程、跨任务边界优先使用所有权移动
- 对借用共享施加更严格限制

### 15.3 Send and Sync

只有满足并发 trait 约束的类型才能跨线程边界安全传播。

```s
trait Send
trait Sync
```

规则建议：

- `Send`：值可安全移动到其他线程
- `Sync`：`&T` 可安全被多个线程共享

拥有内部可变状态的类型若无同步保证，不应自动实现这些 trait。

## 16. Interaction with Unsafe

`unsafe` 允许开发者绕过部分编译期检查，但不意味着语言不再有语义边界。

### 16.1 What Unsafe Can Do

`unsafe` 中可以允许：

- 解引用裸指针
- 构造未初始化内存
- 手工管理分配和释放
- 调用未经 S 类型系统验证的外部函数

### 16.2 What Unsafe Must Still Respect

即使在 `unsafe` 中，也仍应视以下规则为必须维护的不变量：

- 不返回悬空借用给安全代码
- 不制造可观察的数据竞争
- 不破坏安全 API 对外承诺的别名与生命周期约束

换句话说：

- `unsafe` 可以关闭“检查”
- 但不能取消“责任”

## 17. Examples

### 17.1 Legal Shared Borrow

```s
let user = get_user()
let a = &user
let b = &user

println(a.name(), b.name())
```

### 17.2 Legal Mutable Borrow

```s
let mut user = get_user()
let u = &mut user
u.activate()
```

### 17.3 Illegal Mixed Borrow

```s
let a = &user
let b = &mut user
```

原因：

- 同一时刻存在共享借用和可变借用

### 17.4 Illegal Use After Move

```s
let s = String::from("hello")
consume(s)
println(s)
```

原因：

- `s` 已在 `consume(s)` 中移动

### 17.5 Legal Clone

```s
let s = String::from("hello")
let t = s.clone()
println(s, t)
```

原因：

- `clone()` 显式产生独立拥有的新值

## 18. Diagnostics

所有权系统若想真正可用，诊断质量必须和规则本身同样重要。

编译器在拒绝代码时，应尽量指出：

- 是“已移动后使用”
- 是“借用冲突”
- 是“返回了局部借用”
- 是“可变借用仍在生效”
- 是“跨并发边界的类型不满足 `Send` / `Sync`”

推荐诊断内容包括：

- 冲突发生的位置
- 原始借用或移动发生的位置
- 建议修复路径，例如改为借用、改为 `clone()`、改为缩短借用范围

## 19. Minimal Borrow Checker Scope

为了尽快落地编译器，最小版本的 borrow checker 不必一次性支持所有高级场景。

Draft 0.1 的最小目标建议是：

1. 检查移动后使用
2. 检查共享借用与可变借用冲突
3. 检查局部借用逃逸
4. 检查基本函数调用中的借用合法性
5. 检查简单控制流中的值有效性

可以暂缓的高级能力包括：

- 完整部分移动分析
- 复杂闭包推断
- 高级生成器/协程借用
- 高级自引用结构支持

## 20. Open Questions

以下问题仍需后续版本收束：

1. 是否公开显式生命周期语法
2. `Copy` 是否自动推导到用户结构体
3. 是否允许更丰富的部分移动和部分借用
4. 闭包捕获语法是否需要显式 `move`
5. async/await 若引入，其状态机借用规则如何表达
6. 自引用类型是否需要语言级限制或库级模式

## 21. Summary

S 的所有权系统不追求“把一切都交给程序员自己证明”，也不追求“完全依赖运行时兜底”。

它的核心取舍是：

- 让拥有关系默认清晰
- 让借用规则默认严格
- 让复杂度优先由编译器承担
- 让危险能力只在显式边界中出现

如果这套模型成立，S 就能同时获得：

- 接近系统语言的控制力
- 接近现代安全语言的可靠性
- 接近工程语言的日常可用性
