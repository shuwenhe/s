# S Compiler Roadmap

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 编译器的推荐实现路线。

目标不是先讨论最复杂的优化器，而是先把一条“可以落地、可以迭代、可以验证语言语义”的路线定下来。

本文档重点覆盖：

- 编译器分层
- lexer / parser / AST 路线
- 名称解析与类型检查
- borrow checker 的最小实现策略
- IR 与 backend 方向
- MVP 的构建顺序

本文档与以下规范配套：

- [spec.md](/app/s/doc/spec.md)
- [syntax.md](/app/s/doc/syntax.md)
- [types.md](/app/s/doc/types.md)
- [ownership.md](/app/s/doc/ownership.md)
- [stdlib.md](/app/s/doc/stdlib.md)

## 2. Implementation Principles

S 编译器建议遵循以下原则：

1. 先做正确，再做快
2. 先做可解释诊断，再做高级优化
3. 先冻结中间表示，再扩展语言表面
4. 先支持 MVP 语义闭环，再支持高级特性
5. 每个阶段都应有可运行测试样例

## 3. Compiler Pipeline Overview

推荐编译流程如下：

```text
Source
   Lexer
   Parser
   AST
   Name Resolution
   Type Checking
   Ownership / Borrow Checking
   Lowering to HIR / MIR
   Code Generation
   Link
```

说明：

- AST 用于忠实保留语法结构
- HIR 用于名称解析后、更规范化的语义层表示
- MIR 用于类型和所有权分析后的中层表示

对 MVP 来说，不必一开始就同时做 HIR 和 MIR，但至少应预留这一演化方向。

## 4. Phase Plan

### 4.1 Phase 0: Front-End Skeleton

目标：

- 能读取源码
- 能输出 token 流
- 能构造 AST
- 能打印友好语法错误

交付物：

- lexer
- parser
- AST 定义
- 基础 error reporter

### 4.2 Phase 1: Name Resolution and Basic Types

目标：

- 能处理 `package` / `use`
- 能解析顶层声明
- 能检查基础类型和函数调用

交付物：

- 符号表
- 路径解析
- 基础类型检查器

### 4.3 Phase 2: Semantic Core

目标：

- 支持 `struct` / `enum` / `trait`
- 支持 `Result` / `Option`
- 支持 `switch`
- 支持基础泛型

交付物：

- HIR
- trait bound 检查
- `switch` 穷尽性检查

### 4.4 Phase 3: Ownership

目标：

- 实现移动语义
- 实现借用检查
- 实现基本析构插入

交付物：

- 所有权分析
- borrow checker
- drop elaboration

### 4.5 Phase 4: Backend and Runtime Integration

目标：

- 产出可执行文件
- 跑通标准库最小模块
- 支持测试工具链

交付物：

- backend
- 链接流程
- 运行基础测试

## 5. Lexer

### 5.1 Responsibilities

lexer 负责：

- 读取 UTF-8 源文本
- 识别 token
- 跳过空白与注释
- 记录源码位置信息

### 5.2 Token Categories

最小 token 类别建议包括：

- 标识符
- 关键字
- 整数字面量
- 浮点字面量
- 字符串字面量
- 字符字面量
- 分隔符
- 操作符
- EOF

### 5.3 Lexer Output

推荐 token 结构：

```text
Token {
  TokenKind kind
  Span lexeme
}
```

其中 `Span` 至少包含：

- 文件
- 起始偏移
- 结束偏移
- 行列信息

### 5.4 Error Strategy

lexer 发现非法字符、未闭合字符串、非法转义时，应尽量继续扫描，允许 parser 拿到后续 token 并报告更多错误。

## 6. Parser

### 6.1 Parsing Strategy

推荐：

- 顶层声明使用递归下降
- 表达式使用 Pratt parser 或 precedence climbing

原因：

- 结构清晰
- 便于控制优先级
- 错误恢复更容易定制

### 6.2 AST Goals

AST 应忠实保留：

- 语法结构
- 原始 token span
- 可选分号与逗号信息
- 属性和泛型位置

AST 不应过早编码语义推断结果。

### 6.3 Error Recovery

parser 应至少支持以下恢复点：

- 顶层 item 边界
- `;`
- `}`
- `,`

这样一份有错误的源码仍然可以尽量构建部分 AST，提升诊断体验。

## 7. AST, HIR, and MIR

### 7.1 AST

AST 用于表达“源码写了什么”。

适合承载：

- 原始语法节点
- 泛型参数语法
- 模式结构
- 块与表达式

### 7.2 HIR

HIR 用于表达“解析后真正参与语义分析的程序结构”。

HIR 适合做的规范化包括：

- 展开导入后的路径解析结果
- 统一函数与方法调用表示
- 去除多余括号等纯表面结构
- 给绑定分配唯一 ID

### 7.3 MIR

MIR 用于表达“适合做所有权和控制流分析的中层程序”。

MIR 适合包含：

- 基本块
- 显式控制流边
- 局部变量槽位
- move / borrow / drop 事件

若 MVP 资源有限，可以先从 AST 直接做基础类型检查，再引入 HIR；但要尽量避免把所有语义直接硬编码在 parser AST 上。

## 8. Name Resolution

### 8.1 Responsibilities

名称解析阶段负责：

- 解析包路径
- 解析导入项
- 构建模块级和局部级符号表
- 绑定变量和类型名称
- 处理遮蔽

### 8.2 Symbol Tables

建议至少维护三层名字空间：

- 模块项名字空间
- 类型名字空间
- 局部绑定名字空间

是否完全分离这些空间，可以后续细化；Draft 0.1 至少应避免明显歧义。

### 8.3 Binding IDs

建议在名称解析后为每个绑定分配稳定 ID，用于：

- 类型检查
- 借用分析
- 诊断引用

## 9. Type Checker

### 9.1 Responsibilities

类型检查器负责：

- 推导表达式类型
- 检查函数调用和返回类型
- 检查 `struct` / `enum` 构造
- 检查 `switch` 分支一致性
- 检查 trait bound

### 9.2 Type Representation

建议内部类型表示至少包含：

- 原始类型
- 引用类型
- 数组和切片
- 命名类型
- 泛型参数类型
- 函数类型
- 推导变量

### 9.3 Inference Strategy

推荐采用局部类型推导：

- 从绑定初始化式推导
- 从函数调用约束推导
- 从返回上下文补充推导

若约束不足，应明确报错，而不是引入过强的全局推导。

### 9.4 Trait Checking

trait 检查建议分为两步：

1. 解析类型上需要满足哪些约束
2. 检查目标类型是否实现了对应 trait

MVP 可以先支持：

- 显式 impl
- 编译器已知的核心语义 trait

## 10. Exhaustiveness Checking

`switch` 的穷尽性检查应作为类型检查的一部分或紧邻其后执行。

MVP 建议先支持：

- `bool`
- `Option`
- `Result`
- 简单枚举

高级模式空间分析可以后续增强。

## 11. Ownership Analysis

### 11.1 Responsibilities

所有权分析阶段负责：

- 判断赋值和传参是移动还是复制
- 标记已移动值
- 跟踪借用起止范围
- 检查借用冲突
- 为 drop 插入提供依据

### 11.2 Why Not Do This in the Parser

移动、借用和 drop 都依赖：

- 名称解析结果
- 类型信息
- 控制流信息

因此 borrow checker 不应直接挂在 parser 层，而应至少建立在已解析和已类型化的中间表示之上。

## 12. Borrow Checker

### 12.1 Recommended Scope for MVP

MVP borrow checker 建议只先覆盖：

1. move 后使用
2. `&` / `&mut` 冲突
3. 局部借用逃逸
4. 基本控制流合流点的有效性检查
5. 简单函数调用和返回的借用合法性

### 12.2 Internal Model

推荐以 MIR 为基础，跟踪：

- 局部变量状态
- 借用集合
- 活跃 loan
- drop 点

可将每个局部值建模为状态机，例如：

```text
Uninitialized
Initialized
Moved
BorrowedShared(n)
BorrowedMut
Dropped
```

这不一定是最终实现形式，但足以帮助定义 MVP 规则。

### 12.3 Non-Lexical Lifetimes

Draft 0.1 推荐 borrow checker 尽早支持近似 NLL 的策略，即：

- 借用持续到最后一次使用
- 而不是机械持续到整个块末尾

若 MVP 初期实现复杂度过高，也可以先采用更保守的块级策略，但应把 NLL 作为明确演进目标。

### 12.4 Diagnostics

borrow checker 错误信息应至少指出：

- 原始借用发生位置
- 冲突访问发生位置
- 被移动的位置
- 为何该值在此处已失效

诊断质量是这部分能否真正可用的关键。

## 13. Drop Elaboration

### 13.1 Purpose

在类型和所有权检查之后，编译器需要显式决定：

- 哪些局部值需要析构
- 在哪些控制流路径上插入 drop

### 13.2 Ordering

推荐规则：

- 局部变量按逆声明顺序 drop
- 被移动的值不再重复 drop
- 条件分支必须在所有可能路径上保持 drop 一致性

### 13.3 Relationship with MIR

drop 插入最适合发生在 MIR 或类似中层表示上，因为此时：

- 控制流已显式化
- 变量槽位已稳定
- move 信息已知

## 14. Backend Strategy

### 14.1 Recommended MVP Choice

MVP backend 有两条常见路线：

1. LLVM backend
2. 自研简化 backend

推荐优先路线：

- 早期使用 LLVM，尽快拿到可执行产物
- 等语义和 IR 稳定后，再评估是否需要自研 backend

原因：

- 能更快验证语言本身
- 降低前期 codegen 复杂度
- 把精力留给类型系统和 borrow checker

### 14.2 IR Lowering

建议 lowering 顺序：

```text
AST  HIR  MIR  LLVM IR
```

若实现简化，也可暂时：

```text
AST  Typed HIR  LLVM IR
```

但长期仍建议保留 MIR 层，以承载所有权和 drop 语义。

## 15. Tooling Integration

编译器不应只输出二进制，还应服务于工具链。

建议尽早支持：

- `s check`
- `s build`
- `s test`
- `s fmt`

其中编译器前端至少应能被 `s check` 复用，用于快速语义检查而不做完整链接。

## 16. Testing Strategy

### 16.1 Front-End Tests

建议为 lexer / parser / type checker / borrow checker 分别建立测试目录。

优先测试形式：

- token snapshot
- AST snapshot
- 类型错误快照
- borrow checker 错误快照

### 16.2 Golden Tests

很适合的测试方式是 golden tests：

- 输入源码
- 输出诊断或中间表示
- 比较与预期文本是否一致

### 16.3 Run Tests

对能成功编译的样例，建立端到端运行测试：

- hello world
- struct / enum / switch
- Result / Option
- borrow 合法/非法样例
- IO 和文件样例

## 17. Suggested Repository Layout

推荐编译器仓库布局方向：

```text
compiler/
  lexer/
  parser/
  ast/
  hir/
  mir/
  resolve/
  types/
  borrow/
  codegen/
  diagnostics/
  driver/
stdlib/
tests/
```

如果是单仓实现，也建议在逻辑边界上保持这种分层。

## 18. MVP Milestones

建议按以下里程碑推进：

### M1

- lexer
- parser
- AST dump

### M2

- 名称解析
- 基础类型检查
- `struct` / `enum` / `switch`

### M3

- `Result` / `Option`
- trait bound 基础检查
- HIR

### M4

- move 检查
- 基础 borrow checker
- drop 插入

### M5

- backend
- 最小标准库联调
- `s check` / `s build`

### M6

- `std.io` / `std.fs`
- `s test`
- 端到端样例程序

## 19. Deferred Work

以下内容建议后置，不阻塞 MVP：

- 高级优化器
- 增量编译
- trait 对象和动态分发优化
- async/await lowering
- 宏系统
- IDE 深度集成
- 自定义 backend

## 20. Open Questions

当前仍需继续澄清的问题包括：

1. HIR 和 MIR 是否从一开始同时引入
2. borrow checker 是数据流驱动还是约束求解驱动
3. trait bound 检查是否需要单独 solver
4. LLVM 是否会过早绑定某些 ABI 选择
5. 最小标准库与编译器 builtin 的边界如何划分
6. 是否为 `s check` 提供更轻量的无 codegen 路径

## 21. Summary

S 编译器最重要的不是“看起来先进”，而是要先建立一条稳的实现闭环：

- 语法能解析
- 名称能绑定
- 类型能检查
- 借用能验证
- drop 能插入
- 代码能生成

只要这条链路稳定，S 的语言设计就不再只是文档设想，而会开始变成一门真正可以逐步实现、逐步验证的系统语言。
