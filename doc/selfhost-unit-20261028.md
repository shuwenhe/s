# unit 名称绑定优先级修复（2026-10-28）

## 结果

`base/timings.s:42` 的 e3116 已消失。原始复现由新完整 Stage1 编译成原生 ELF 并执行 42。Stage2 已越过 timings_add_event，推进到 amd64_emit_edge 的 break；Stage2/Stage3 尚未生成，固定点未证明。

## 精确定位与对照

修复前的原生语义组件记录：

```text
checking=main.create
record field=unit expected=string actual=() package=main local_start=1
ast=name identifier=unit lexical_type=string
```

这证明 Parser 已构造普通名称节点，词法环境也保留了字符串参数；错误发生在 infer_expr_in_scope 的内建值识别先于环境查找。MIR expression lowering 也有同样的抢先匹配。

独立诊断 Seed（复制 C 源码，仅增加 stderr 观察，生产 Seed 未修改）记录：

```text
seed ast=AST_IDENT_EXPR name=unit symbol=parameter lexical_scope=bound actual_type=string
```

修复后的同源完整输入组件在原位置记录：

```text
checking=compile.internal.base.timings_add_event
record field=unit expected=string actual=string package=compile.internal.base local_start=658
ast=name identifier=unit lexical_type=string
checking=compile.internal.base.timings_write
```

## 最小修复边界

- 维持现有 AST 类型；真正的 () 和合成单元表达式使用不能作为源码标识符的内部拼写 `"()"`。此前它们与可遮蔽的普通名称 unit 共用字符串 `"unit"`，单纯交换查找顺序会误伤字面量。
- 普通 unit 名称先查词法绑定/可见函数，仅在没有绑定时回退到内建单元值。没有全局禁用 unit，也未将该名字固定成字符串。
- MIR 先识别真实单元字面量，再选最内层绑定；未绑定的内建 unit 保留。合成的单元返回直接生成 const_unit，避免重新经过名称查找。
- MIR 块内重复声明只检查本块边界；允许与 Semantic 一致的嵌套遮蔽，并保留外层值槽。重复本块声明仍被拒绝。
- 既有辅助旧后端同步同一识别顺序；原生编译没有调用解释器、C fallback 或占位产物。
- 没有更改类型兼容规则、泛型单态化或内存管理。独立静态审查未发现重要问题。

## 验证

新完整 Stage1 原生执行通过 7 个程序：字符串参数、整数局部、布尔参数、嵌套字符串/整数遮蔽、遮蔽作用域中的 () 字面量、未遮蔽内建 unit、合成单元返回。

3 个错误类型反例均被拒绝，并保留旧输出：将 () 传给 string、返回字符串参数给 () 返回类型、将 () 返回给 int。第二例由现有 MIR 返回类型验证拒绝；本轮没有借机扩大 Semantic 的过程返回规则。

Semantic 回归还覆盖包级常量 unit 的优先级、本块重复 unit 声明拒绝、不同类型 unit 绑定及错误返回。已结束的局部 unit 所有权作用域之后，未绑定内建 unit 的语义检查仍通过。

continue（9 固定程序、4 动态输入及循环外反例）、元组尾返回、八组生产回归、三包 nominal-scope 程序均通过新完整 Stage1。10 组 parser 和包含泛型遮蔽/枚举载荷/switch 合并的 semantic diagnostics 通过。

全局临时区、参数回收、只读快照、record borrow、receiver borrow、loop liveness 再通过；2000 次只读调用保持 5 次快照。未更改这些所有权边界。

## 完整构建与实测

冻结目录：`.bootstrap/selfhost-unit-final/source/`，268 个文件及逐文件哈希已复核，与最终工作源码一致。

| 运行 | 耗时 | 峰值 RSS | 结果 |
| --- | ---: | ---: | --- |
| Seed → Stage1 IR | 161.74 s | 678936 KiB | PASS |
| 原生 Stage1 生成 | 232.13 s | 717368 KiB | PASS，原生验证通过 |
| Stage1 → Stage2 | 50.761 s | 1049900 KiB（1025.3 MiB） | exit 1，e3010 |

Parser 完成于 23.021 s。50.761 s 是到下一处语义拒绝的耗时，不是成功编译耗时。

```text
source manifest: bbae89795a548bbe26d846dd2691c539d4cc6393b8023e046faa09c75cf5d5fe
Stage1 IR:      8621206c1d2d2dfb255e9833d138b1bf7fd13731f0a343229b71de19a1e9cba9
Stage1 ELF:     95b6345237fb582e5a9be57fd9ffe8b1063b2b3defbe2cd44e587550e662ff70
unit fixture:   49c8727df13d6751283f4219a39d93fca90237fc0f6eaab0f197a52f5e24d424
```

原始记录：`build.log`、`production.log`、`after-measurements.json`、`artifact-hashes.json`。Stage2/Stage3 产物哈希为空，没有 completion marker。

## 下一处 FIRST RED

- 文件：`src/cmd/compile/internal/codegen/amd64_program.s:248`。
- 函数：`compile.internal.amd64_emit_edge`（声明第 241 行）。
- 源码：`if seen == occurrence { predecessor = i; break }`。
- 错误：e3010，undefined identifier，锚点 break。
- 完整 Stage2：exit 1，50.761 s，1049900 KiB。
- 同源完整组件：exit 1，37.09 s，1049020 KiB，打印具体函数与 break 锚点。
- 独立复现：`test/selfhost/break-first-red/main.s`，Seed 编译并原生执行 42；新完整 Stage1 拒绝（exit 1，<0.01 s，2508 KiB）。

本轮未把 break 当成普通名字放行，也未重写编译器源码绕过它。下一轮需要按真实循环退出 CFG 与值合并实现 break。既有泛型单态化限制及 option[expr] fixture 保持独立跟踪。
