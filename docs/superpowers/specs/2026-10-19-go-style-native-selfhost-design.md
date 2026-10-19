# S Compiler Go-style Native Self-hosting Design

## Goal

建立 S 的真实原生自举链：`Seed → Stage1 → Stage2 → Stage3 → Fixed-point`，并保留 S 自己的 Frontend、MIR、SSA 与 Native Backend。

## Scope and non-goals

- 参考 Go `cmd/dist` 的职责划分、阶段环境隔离、源码闭包和收敛验证。
- 不复制 Go 编译器源码或 Go 的 IR/后端实现。
- 不缩小规范生产源码闭包，不使用旧二进制、模拟 IR 或跳过阶段伪造成功。
- 不修改已冻结的 Pipeline Top-Level Control Phase 1，除非新证据证明自举入口无法工作。
- Production Authority（AST → MIR → SSA → Native ELF）作为独立验证线记录，不把 Pipeline 22/22 PASS 计为自举通过。

## Current evidence

- 规范入口：`src/cmd/dist/native-bootstrap-no-manifest.sh`。
- 当前可信编译器：`bin/s_seed`。
- 当前闭包入口：`src/cmd/dist/source_closure.sh`。
- 已知源码首错曾为 `src/cmd/compile/bootstrap/bootstrap_demo.s:57:11` 的未闭合字符串；修复后暴露新的 Parser 首错 `bc* := alloc(bootstrap_compiler)`。
- Stage1 尚未生成可执行 ELF，因此 Stage2/Stage3/fixed-point 尚未开始。

## Architecture

### Bootstrap control plane

`src/cmd/dist` 负责所有阶段的目录、环境、日志、资源统计、输入闭包和失败边界。每一阶段只接收上一阶段生成的编译器，不由被编译的 S 源码自行推进自举。

### Source closure

闭包生成器输出规范化、排序、去重且可审计的源文件清单；入口、包身份、导入边和实际文件路径都写入旁车证据。闭包必须覆盖规范生产源码，过滤测试源码只能依据明确的生产规则。

### Stage artifacts

每阶段固定产生：`stageN.sources`、`stageN-compile.log`、`stageN.ir`、`stageN-emit.log`、`stageN`，以及包含退出码、耗时、最大 RSS、输入 SHA-256 和产物 SHA-256 的 `stageN.meta`。缺少或为空的中间产物立即失败。

### Convergence

Stage2 和 Stage3 使用完全相同的规范源码闭包。验证包括：两个阶段都能运行、IR/ELF 非空、目标架构正确、运行时 smoke test、机器码/ELF 可复现性比较；若二进制包含不稳定时间或构建 ID，则先定义并验证归一化比较，而不是放宽比较。

## Acceptance gates

1. P0：Seed 编译完整规范闭包，生成并运行 Stage1 ELF。
2. P1：Stage1 使用同一闭包生成并运行 Stage2 ELF。
3. P2：Stage2 生成并运行 Stage3 ELF，记录峰值 RSS。
4. P3：Stage2/Stage3 通过行为、产物和可复现性 fixed-point 验证。
5. P4：单独报告 Production Authority，不与自举结果混合。

每个 gate 都必须保留失败日志和 FIRST RED；未通过前不得宣称后续 gate 成功。
