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

- 规范入口暂定为 `src/cmd/compile/main.s`，但 Task 1 必须通过其 `use compile.driver` → `driver_main` 调用链和闭包输出确认它是规范生产入口。
- 当前可信编译器：`bin/s_seed`。
- 当前闭包入口：`src/cmd/dist/source_closure.sh`。
- 最新已复现 FIRST RED：`src/cmd/compile/bootstrap/bootstrap_demo.s:16:9`，`expected expression, got :=`；此前的 `57:11` 和 `90:11` 未闭合字符串已越过，不再作为当前基线。
- Stage1 尚未生成可执行 ELF，因此 Stage2/Stage3/fixed-point 尚未开始。

## Architecture

### Bootstrap control plane

`src/cmd/dist` 负责所有阶段的目录、环境、日志、资源统计、输入闭包和失败边界。每一阶段只接收上一阶段生成的编译器，不由被编译的 S 源码自行推进自举。

### Source closure

闭包生成器输出规范化、排序、去重且可审计的源文件清单；入口、包身份、导入边和实际文件路径都写入旁车证据。

生产文件判定规则固定为：路径必须位于 `src/`，扩展名为 `.s`，不能位于任意 `testdata/` 目录，且 basename 不能以 `_test.s` 结尾；包必须由入口的 `use`/`import` 可达。若可达依赖只存在于测试过滤集合，闭包生成失败并报告依赖，而不是静默删除。`bootstrap_demo.s` 等非测试生产包文件仍必须保留。

### Stage artifacts and identity

每阶段固定产生：`stageN.sources`、`stageN-compile.log`、`stageN.ir`、`stageN-emit.log`、`stageN` 和 `stageN.meta`。metadata 必须包含实际调用命令、producer ELF 的 SHA-256、producer `readelf -h`/目标架构、输入闭包 SHA-256、输出 SHA-256、退出码、耗时和最大 RSS。Stage1 的 producer 是 `bin/s_seed`；Stage2 的 producer 必须是 Stage1 ELF；Stage3 的 producer 必须是 Stage2 ELF。文件名、环境变量或旧产物不能单独证明 producer 身份。

### Convergence

Stage2 和 Stage3 使用相同路径、相同顺序、相同 SHA-256 的规范源码闭包。保留原始 ELF/IR，不原地修改。fixed-point 比较默认是原始 ELF SHA-256 相等；若工具链明确写入不稳定字段，允许仅对 ELF section header 的 `sh_offset`/`sh_size` 之外由证据确认的构建时间或 build-id 字段做副本归一化，并同时报告原始 hash、归一化 hash、字段清单和归一化前后差异。未知字段差异直接失败。两阶段还必须通过同一 smoke test 与目标架构检查。

## Acceptance gates

1. P0：确认规范入口；Seed 编译完整规范闭包，生成并运行 Stage1 ELF。
2. P1：Stage1 使用同一闭包生成并运行 Stage2 ELF，metadata 证明 producer 身份。
3. P2：Stage2 生成并运行 Stage3 ELF，记录峰值 RSS。
4. P3：Stage2/Stage3 通过原始或明确归一化后的产物、行为和可复现性 fixed-point 验证。
5. P4：单独报告 Production Authority，不与自举结果混合。

每个 gate 都必须保留失败日志和 FIRST RED；未通过前不得宣称后续 gate 成功。
