# 元组尾返回修复与自举实测（2026-10-28）

后续 unit 名称遮蔽修复及最新 FIRST RED 见 [selfhost-unit-20261028.md](selfhost-unit-20261028.md)。


## 结论

原始 e3004 已修复。原始复现 `test/selfhost/tuple-tail-return/main.s` 由新完整 Stage1 编译成原生 ELF 并执行 42。Stage2 仍被下一处 e3116 拒绝，Stage3 未运行，固定点未证明。

## 规范与 AST/类型证据

本仓库语言说明 `doc/s:53` 规定最后一个表达式作为返回值；第 57–65 行规定多返回值声明和显式返回语法。没有元组隐式返回例外。本次依据这些规则、实际 AST 和严格成员类型检查，不以 Seed 接受作为唯一判断。

诊断前原生 checker 实测：

```text
function=relay
expected=(string,string)
actual=(string, string)
tail_expr_kind=call
expected_arity=2; actual_arity=2
expected_element_types=[string,string]
actual_element_types=[string,string]
```

独立诊断 Seed（仅复制 C 源码添加 stderr 观察，未修改生产 Seed）记录：

```text
seed explicit_return declared=string,string list_arity=2
seed tail declared=string,string actual=string,string ast_kind=32 AST_CALL_EXPR=32
```

Seed 的体尾是 AST_EXPR_STMT 包装的 AST_CALL_EXPR，Canonical AST 是 expr.call。均保留两个返回成员，没有被解析成标量。

## 精准修复

`semantic.s:instantiate_type` 曾使用 `", "` 拼接实例化类型，而声明及 tuple 字面量使用 `","`。`same_type` 严格比较文本；因此合法尾调用产生 e3004。

唯一接受规则相关修复：该类型实例化函数的分隔符改为 `","`。保留 same_type、成员数、成员类型、名义身份及 unknown 检查。没有修改类型系统的兼容规则。

先只规范顶层 tuple 后，新增嵌套泛型用例仍失败：

```text
expected=(main.Box[int,string],int)
actual=(main.Box[int, string],int)
```

因此同一实例化生产者递归统一分隔符，也覆盖 tuple 的泛型成员。最终修复仍为一处分隔符变化；第一轮快照 `.bootstrap/selfhost-tuple-final/` 保留（IR 构建 158.60 s，679372 KiB，后因嵌套用例而中止原生生成，exit 130，无 Stage1 ELF）。

新增 e3004 诊断包含函数/方法名、expected/actual、尾 AST 种类、元组 arity 和成员列表。该诊断只在失败路径构造，未跳过任何检查。独立静态审查没有发现可操作问题。

## 回归结果

- 原生 tuple 尾调用、字面量及显式 return 三种程序，动态输入 1/7 分别返回 42/48。
- 错误成员类型、错误长度、tuple 当作标量：均 e3004，保留旧输出，诊断包含 call 种类。
- 语义正反例覆盖泛型 tuple、嵌套 tuple、含泛型记录的 tuple、不同包同名记录、tuple/result 区别。
- continue（9 固定程序、4 动态输入、3 循环外反例）、八组生产回归及三包名义类型程序通过，全部使用新完整 Stage1。
- 泛型遮蔽、枚举载荷作用域、switch 合并语义回归通过。
- 全局临时区、参数回收、只读快照、record borrow、receiver borrow、loop liveness 再通过。2000 次只读调用仍为 5 次快照。

### 独立泛型原生限制

附加原生泛型调用探索遇到 `missing concrete type arguments for main.relay`。修复前的完整 Stage1 对不含 tuple 的 scalar identity 也报相同单态化错误，证明它独立于本修复。已保留 `test/selfhost/generic-call-monomorphization/`；不将其计作通过的原生测试，也未修改单态化或使用 fallback。Seed 接受该 scalar fixture 编译，但其当前优化 Seed 原生程序对参数 1 触发 signal 11；不将该执行当作规范依据或 reference pass。泛型 tuple 的类型检查回归独立通过。

## 最新完整构建与实测

冻结目录 `.bootstrap/selfhost-tuple-v2/source/`，全部 268 个文件哈希已复核且与最终工作源码一致。

| 运行 | 耗时 | 峰值 RSS | 退出/产物 |
| --- | ---: | ---: | --- |
| Seed → Stage1 IR | 164.08 s | 679100 KiB | PASS |
| 原生 Stage1 生成 | 238.90 s | 716892 KiB | PASS，原生验证通过 |
| Stage1 → Stage2 | 48.311 s | 1043576 KiB（1019.1 MiB） | exit 1，e3116 |

Parser 完成于 23.027 s。48.311 s 为语义拒绝耗时，不是成功编译耗时。

```text
source-manifest sha256: 24b05f02f5b1b60e96cdb5a84f0188a3c3d9a7aae5b3070aaec6413a5158329a
Stage1 IR sha256:       57d9f51bc852c43de868b03ce9a09e53102ee3788e0b1a76d91c8aa4b59cf415
Stage1 ELF sha256:      a3a1413551e150aa34c3c7a4424abbb9676b9dd7c67e717656572f6b3a641b04
original tuple ELF:    64754ef2f63b5d6291d0673bb946aa97ced45997f44765a63ea2294e5fb06eef
```

原始记录：`after-measurements.json`、`production.log`、`build.log`、`artifact-hashes.json`。Stage2/Stage3 的产物哈希为空，未生成 completion marker。

## 下一处 FIRST RED

- 文件：`src/cmd/compile/internal/base/timings.s:42`。
- 函数：`compile.internal.base.timings_add_event`（声明第 40 行）。
- 错误：e3116，record field type mismatch，字段 unit。
- 完整 Stage2：exit 1，48.311 s，1043576 KiB。
- 同源全量语义组件：exit 1，35.28 s，1043164 KiB，打印具体函数及 unit 锚点。
- 最小复现：`test/selfhost/unit-name-shadow/main.s`。Seed 编译并原生返回 42；新完整 Stage1 拒绝（exit 1，<0.01 s，2156 KiB）。

源码声明 `string unit`，但 infer_expr_in_scope 在查局部环境前把名字 unit 固定解释成类型 () 的内建单元值。此问题独立于 tuple 的成员和格式，尚未修复。
