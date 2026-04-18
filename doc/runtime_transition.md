# runtime transition plan

version: draft 0.1  
status: working draft

## 1. purpose

本文档定义 `runtime/*.py` 如何逐步退出主执行链，而不是一次性删除。

目标是把当前：

```text
s source
   hosted python frontend
   intrinsiccall
   python_bridge.py
   host value
```

推进到：

```text
s source
   s frontend / s test entry
   runtime abi
   thin host adapter
   backend or native runtime
```

## 2. current python responsibilities

当前 python bridge 还承担三类职责：

- intrinsic registry 与 dispatch
- 字符串 / 数组 / io 的宿主实现
- golden validation 与 hosted execution glue

这些职责分别位于：

- [python_bridge.py](/app/s/src/runtime/python_bridge.py)
- [intrinsic_dispatch.py](/app/s/src/runtime/intrinsic_dispatch.py)
- [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py)
- [check_bridge.py](/app/s/src/runtime/check_bridge.py)
- [validate_outputs.py](/app/s/src/runtime/validate_outputs.py)

## 3. transition phases

### phase a: freeze the abi

先把 intrinsic 看成稳定 abi，而不是 python helper 名称集合。

建议固定三层：

- `std/*.s` 中声明的 `extern "intrinsic"`
- 一份独立的 intrinsic manifest
- host adapter 对 abi 的实现

完成标准：

- 每个 intrinsic 都有稳定签名
- 字符串、数组、io、panic 分类清晰
- 新 intrinsic 通过 manifest 增量注册

current status:

- a machine-readable manifest now lives in
  [intrinsics_manifest.json](/app/s/src/runtime/intrinsics_manifest.json)
- [python_bridge.py](/app/s/src/runtime/python_bridge.py) now loads and validates
  that manifest instead of treating the local registry as the source of truth

### phase b: move validation entry to s

把验证入口先迁到 `.s`，让 python 只负责执行 abi。

当前已经开始对应的 s 入口：

- [test_golden.s](/app/s/src/cmd/compile/internal/tests/test_golden.s)
- [test_semantic.s](/app/s/src/cmd/compile/internal/tests/test_semantic.s)
- [test_mir.s](/app/s/src/cmd/compile/internal/tests/test_mir.s)

完成标准：

- golden / semantic / mir 的 case 列表在 s 侧定义
- python 只负责运行这些入口或提供最薄适配

### phase c: replace hosted frontend glue

把 [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py) 的“解释执行 parser helper”角色拆开。

建议拆成：

- s 侧 execution plan builder
- host 侧 abi executor

完成标准：

- `intrinsiccall` 数据结构在 s 侧可表达
- lexer / parser / command driver 不再需要 python 专用 helper class

### phase d: thin host adapter

把 [python_bridge.py](/app/s/src/runtime/python_bridge.py) 缩成最薄的宿主适配层。

只保留：

- 文件读取
- 标准输出
- 字符串与数组基础操作
- trap / panic 传播

完成标准：

- host adapter 不再知道 parser / semantic / mir 细节
- runtime 逻辑只通过 abi 暴露

### phase e: replace python host

最后才考虑真正去掉 python。

候选方向：

- s 自己的解释器
- 更低层的 native runtime
- 小型 vm

完成标准：

- `check_bridge.py` 与 `validate_outputs.py` 的职责已被新 runner 替代
- python 不再处于必经执行路径

current progress:

- a minimal non-python runner now exists in
  [runner.s](/app/s/src/runtime/runner.s)
- it can build the current
  [hello.s](/app/s/misc/examples/s/hello.s) and
  [sum.s](/app/s/misc/examples/s/sum.s)
  subset without python
- it does not yet execute the full `cmd/s.s  compiler.main(args)` path

## 4. near-term work

当前最近两步建议是：

1. 为 `compiler/tests/*.s` 增加统一的 s runner
2. 把 intrinsic manifest 从 python registry 中抽离成仓库内数据文件

当前状态：

- 已新增统一 runner [main.s](/app/s/src/cmd/test_compiler/main.s)
- 下一步更适合转到 intrinsic manifest 和 host adapter 拆分

## 5. exit criteria

只有满足以下条件，才适合删除 `runtime/*.py` 主文件：

- s 侧测试入口已覆盖 golden / semantic / mir
- `executionplan` 可以在 s 侧产出
- host adapter 只剩 abi 调用，不再包含 frontend 逻辑
- 至少有一个非 python 的执行后端原型
