# S Self-Hosting Plan

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义 S 编译器从 Python 原型逐步迁移到 S 自举实现的推荐路线。

目标不是一次性把整个编译器重写完，而是用最小风险、最清晰依赖顺序，逐步把前端和语义核心迁移到 S。

本文档重点回答：

- 哪些 Python 模块应优先迁移
- 每个模块的前置依赖是什么
- 每个阶段完成后应达到什么验收标准
- 哪些模块不适合过早迁移

## 2. Guiding Principles

迁移过程建议遵循以下原则：

1. 先迁纯数据结构，再迁复杂分析
2. 先迁前端流水线，再迁语义与所有权系统
3. 先保证行为等价，再追求性能与重构
4. 每迁一个模块，都必须有可重复验证的测试
5. 保持 Python 实现与 S 实现一段时间并行，避免一次性切换

## 3. Migration Priorities

### Priority P0: Foundational Data Model

#### Module: `compiler/ast.py`

- 优先级：P0
- 迁移价值：
  - AST 是前端与语义层共享的核心数据结构
  - 一旦迁到 S，后续 lexer、parser、semantic 都能复用同一套本地表示
- 前置依赖：
  - 无
- 迁移目标：
  - 用 S 定义顶层声明、表达式、模式、语句节点
  - 保持与当前 Python AST 结构一一对应
- 验收标准：
  - S 版本 AST 能表达当前测试样例中的全部语法节点
  - AST dump 输出与当前 Python 版本保持一致或只有可接受的格式差异
  - `sample.s`、`match_sample.s` 等夹具都能生成等价 AST

#### Module: `compiler/lexer/tokens.py`

- 优先级：P0
- 迁移价值：
  - TokenKind 和 Token 是整个前端最稳定、最基础的抽象
  - 迁移成本低，但能尽早形成前端公共基础设施
- 前置依赖：
  - 无
- 迁移目标：
  - 用 S 定义 token 枚举、token 结构和关键词集合
  - 保持行列信息和 dump 格式稳定
- 验收标准：
  - S 版本 token 输出与 Python 版本对同一输入保持一致
  - 关键字分类和符号分类结果一致

### Priority P1: Front-End Input Path

#### Module: `compiler/lexer/lexer.py`

- 优先级：P1
- 迁移价值：
  - lexer 是最适合早期自举的执行模块之一
  - 输入输出简单，规则相对封闭，适合先验证 S 的字符串和切片处理能力
- 前置依赖：
  - `compiler/lexer/tokens.py`
- 迁移目标：
  - 在 S 中实现标识符、关键字、数字、字符串、注释和符号扫描
  - 保持错误行为与 token 位置跟踪一致
- 验收标准：
  - `sample.tokens` 能稳定复现
  - 非法字符、未闭合字符串、未闭合块注释能给出稳定错误
  - 对所有现有测试夹具，S lexer 与 Python lexer 输出一致

### Priority P2: Shared Type Infrastructure

#### Module: `compiler/typesys.py`

- 优先级：P2
- 迁移价值：
  - 类型表示会被 parser、semantic、ownership、prelude 多处复用
  - 该模块仍以纯函数和数据结构为主，适合作为中前期迁移目标
- 前置依赖：
  - 建议先有基础 AST 和字符串处理能力
- 迁移目标：
  - 在 S 中实现类型节点、类型解析、类型打印、替换和 copy 判断
  - 保持 `parse_type` 与 `dump_type` 的往返稳定性
- 验收标准：
  - `bool`、`int32`、`string`、引用、切片、泛型类型都能正确解析和打印
  - `substitute_type` 行为与 Python 实现一致
  - 所有现有 semantic 测试依赖的类型文本都能被 S 版本处理

#### Module: `compiler/prelude.py`

- 优先级：P2
- 迁移价值：
  - 该模块是内建类型和方法查询层，逻辑集中，适合在类型系统之后迁移
  - 继续保留 `prelude.json` 作为数据源，可以显著降低迁移难度
- 前置依赖：
  - `compiler/typesys.py`
- 迁移目标：
  - 在 S 中实现 prelude 数据加载、结构化表示和查询 API
  - 第一阶段继续复用 `compiler/builtins/prelude.json`
- 验收标准：
  - builtin type、builtin method、index type 查询结果与 Python 版本一致
  - 所有依赖 prelude 的 semantic 测试行为一致

### Priority P3: Syntax Construction

#### Module: `compiler/parser/parser.py`

- 优先级：P3
- 迁移价值：
  - parser 是前端闭环的关键一环
  - 在 AST、token、lexer、typesys 稳定后迁移，风险显著降低
- 前置依赖：
  - `compiler/ast.py`
  - `compiler/lexer/tokens.py`
  - `compiler/lexer/lexer.py`
  - `compiler/typesys.py` 中涉及的类型文本约定
- 迁移目标：
  - 在 S 中实现 source file、top-level item、statement、expression 和 pattern 解析
  - 保持错误位置和主要错误消息语义稳定
- 验收标准：
  - `sample.ast`、`match_sample.ast`、`binary_sample.ast`、`control_flow_sample.ast`、`member_method_sample.ast` 能稳定复现
  - 现有 golden tests 在 S parser 下通过
  - 基本错误恢复机制可用，至少能定位主要语法错误

### Priority P4: Early Ownership Layer

#### Module: `compiler/ownership.py`

- 优先级：P4
- 迁移价值：
  - 当前实现简单，是从类型系统过渡到更复杂 borrow 分析的理想切入点
  - 可以先把 ownership 决策逻辑迁到 S，减少后续 borrow 模块的 Python 依赖
- 前置依赖：
  - `compiler/typesys.py`
- 迁移目标：
  - 在 S 中实现 copyable / droppable 判定和 ownership plan 生成
- 验收标准：
  - 基础类型、引用类型和命名类型的 ownership 判定与 Python 版本一致
  - semantic 和 borrow 调用 ownership API 时结果一致

### Priority P5: Semantic Core

#### Module: `compiler/semantic.py`

- 优先级：P5
- 迁移价值：
  - 这是前端真正进入“语言语义”的核心模块
  - 一旦迁移成功，S 将具备更强的自解释能力和自举价值
- 前置依赖：
  - `compiler/ast.py`
  - `compiler/typesys.py`
  - `compiler/prelude.py`
  - `compiler/ownership.py`
  - parser 全面可用
- 迁移目标：
  - 在 S 中实现名称加载、类型检查、成员访问检查、switch 检查、trait/impl 基础校验
  - 保持诊断文本和失败场景尽量稳定
- 验收标准：
  - `test_semantic.py` 核心测试可在 S 版本 checker 下通过
  - `check_ok.s`、`check_fail.s`、`generic_bound_fail.s`、`method_conflict_fail.s`、`builtin_field_ok.s` 等样例行为一致
  - `s check` 对成功与失败输入给出与 Python 版本一致的结论

### Priority P6: IR and Borrow Analysis

#### Module: `compiler/mir.py`

- 优先级：P6
- 迁移价值：
  - MIR 是 borrow 分析和后续 backend 的桥梁
  - 迁移成功后，S 编译器中层表示将不再依赖 Python
- 前置依赖：
  - parser、semantic、ownership 均已稳定
- 迁移目标：
  - 在 S 中实现 block lowering、control edge、local slot、move/copy/drop/eval 等 MIR 结构与构造流程
- 验收标准：
  - MIR 图结构在关键样例上与 Python 版本等价
  - `test_mir.py` 的核心测试通过
  - lowering 后的控制流和局部变量版本逻辑保持一致

#### Module: `compiler/borrow.py`

- 优先级：P6
- 迁移价值：
  - borrow checker 是语言安全模型的关键能力
  - 但它依赖语义、MIR、ownership 三层稳定后才适合迁移
- 前置依赖：
  - `compiler/mir.py`
  - `compiler/ownership.py`
  - semantic 中变量与类型环境行为稳定
- 迁移目标：
  - 在 S 中实现 move/use-after-move、共享借用、可变借用和 drop 相关分析
- 验收标准：
  - `borrow_fail.s`、`branch_move_fail.s`、`receiver_auto_borrow_ok.s` 等样例行为一致
  - 关键诊断结果与 Python 版本一致
  - 对控制流合流和 switch 分支的状态合并行为一致

## 4. Recommended Phase Plan

### Phase A

- 迁移 `compiler/ast.py`
- 迁移 `compiler/lexer/tokens.py`

阶段目标：

- 建立 S 自己的前端公共数据模型

### Phase B

- 迁移 `compiler/lexer/lexer.py`

阶段目标：

- 让 S 能稳定把 `.s` 源码转换为 token 流

### Phase C

- 迁移 `compiler/typesys.py`
- 迁移 `compiler/prelude.py`

阶段目标：

- 建立语义分析所需的类型基础设施和内建查询层

### Phase D

- 迁移 `compiler/parser/parser.py`

阶段目标：

- 形成 S 版本前端闭环：source  tokens  AST

### Phase E

- 迁移 `compiler/ownership.py`

阶段目标：

- 为后续 borrow 分析建立可复用的所有权决策层

### Phase F

- 迁移 `compiler/semantic.py`

阶段目标：

- 让 S 版本编译器具备基本语义检查能力

### Phase G

- 迁移 `compiler/mir.py`
- 迁移 `compiler/borrow.py`

阶段目标：

- 建立中层表示和安全分析能力，为真正自举打基础

## 5. Modules To Avoid Migrating Too Early

以下模块不建议在早期阶段优先迁移：

- `compiler/semantic.py`
  - 原因：职责多，横跨名称解析、类型检查、成员检查、trait/impl 校验
- `compiler/mir.py`
  - 原因：涉及 lowering、控制流图和局部变量生命周期，调试成本高
- `compiler/borrow.py`
  - 原因：依赖 MIR 和 ownership 的稳定行为，属于后期高风险模块

## 6. Parallel Run Strategy

在正式切换到 S 实现前，建议保留 Python 版本作为对照实现。

推荐策略：

1. 先实现一个模块的 S 版本
2. 用同一组夹具同时跑 Python 与 S 实现
3. 比较输出、诊断和失败模式
4. 只有在结果稳定后，才让上层模块改为依赖 S 版本

## 7. Definition of Done

一个模块完成自举迁移，至少应满足以下条件：

1. 有明确的 S 版本实现
2. 有对应的回归测试或 golden fixtures
3. 在关键样例上与 Python 版本行为一致
4. 已被上游模块真实调用，而不是只停留在孤立实验代码
5. 有文档说明剩余差距和已知限制

## 8. Immediate Next Step

当前最值得开始的第一批模块是：

1. `compiler/ast.py`
2. `compiler/lexer/tokens.py`
3. `compiler/lexer/lexer.py`

原因：

- 依赖浅
- 风险低
- 最容易尽快形成可验证的自举前端能力
- 能为 parser 迁移提供直接支撑
