# S Bootstrap Module Dependency and Capability Report

日期：2026-10-19  
仓库：`/home/shuwen/shuwen/s`  
审计提交：`bb6b4b016b5ccd5766782a934214bbe5b1ca626d`

## 结论摘要

S 具备按模块推进增量自举的代码基础，但当前仍未证明完整原生自举。

当前状态：

- `UNIT_PASS`：若干 Lexer、Parser、Semantic、MIR、SSA、Native Codegen 测试已存在并可单独运行。
- `INTEGRATION_PASS`：部分前端、MIR/SSA、Native ELF 和 driver 测试存在；尚未形成覆盖全部模块的统一交接矩阵。
- `BOOTSTRAP_PROVEN`：未达到。当前 Seed → Stage1 仍在编译完整生产闭包阶段失败。
- 规范自举入口：`src/cmd/dist/native-bootstrap-no-manifest.sh`。
- 可信 Seed：`bin/s_seed`。
- 当前已知 FIRST RED：`src/cmd/compile/bootstrap/bootstrap_demo.s:16:9`，`expected expression, got :=`。
- Stage1 IR/ELF、Stage2、Stage3 和 fixed-point：未生成/未运行。

此前规范基线曾观察到 320 个有序源码输入，Seed 退出码为 1，Stage1 IR 为 0 字节且 ELF 不存在；这只是失败证据，不是自举 PASS。本次审计重新调用 `source_closure.sh` 时未得到最终输出文件，因此没有把这次运行误记为新的闭包 PASS。

## 真实入口与依赖链

规范入口文件是 `src/cmd/compile/main.s`，其调用链为：

```text
src/cmd/compile/main.s
  use compile.driver
  main() -> driver_main(host_args())
        |
        +--> compile.internal.compiler
        +--> compile.internal.pipeline
        +--> std.io
                    |
                    +--> frontend / semantic / MIR / SSA / backend / ELF path
```

这条链由 `src/cmd/compile/internal/driver/driver.s` 的导入和 `driver_main` 实现确认。`source_closure.sh` 通过 `package`、`import` 和 `use` 解析该图；当前实现仍包含按包名和路径回退的启发式解析，必须在正式扩大闭包前增加契约测试。

## 八个逻辑模块

| 模块 | S 主要位置 | 输入 | 输出 | 当前证据 | 尚未支持/风险 |
|---|---|---|---|---|---|
| M0 Bootstrap / Driver | `src/cmd/dist/`、`src/cmd/compile/main.s`、`internal/driver` | 源码入口、目标参数、Seed/Stage 编译器 | 源码闭包、IR、ELF、阶段日志 | `driver-dispatch` 测试；bootstrap 脚本存在 | 完整闭包确定性、producer provenance、Stage1 失败 |
| M1 Lexer / Token | `src/cmd/compile/seed/lexical/lexer.c`、`internal/lexer`、`internal/parser/syntax` | 字符串源码 | Token 流、词法错误 | 字符串/注释/Token 相关实现与探针 | Seed 与 S Lexer 的语言覆盖和接口尚未在完整自举中证明 |
| M2 Parser / AST | `seed/syntax/parser.c`、`internal/parser/`、`internal/ast/` | Token 流 | AST、解析错误 | Parser 实现、frontend 测试、delta fixtures | 当前完整闭包 FIRST RED 在 S 语法 `bc* := alloc(...)`；Parser 语法契约仍需逐项扩展 |
| M3 Semantic / Types | `seed/semantic/analyzer.c`、`internal/semantic/`、`internal/typecheck/`、`internal/types/` | AST、符号表、类型环境 | 已解析/已类型化 AST 或诊断 | 类型检查测试、stage7/stage8 测试 | 完整生产依赖闭包中的类型/泛型/指针/所有权特性尚未经 Stage1 证明 |
| M4 MIR Lowering | `internal/mir/`、`internal/compiler/`、`internal/walk/` | 已验证 AST | MIR、所有权/借用事实、CFG | MIR tests、MIR C codegen 和 ownership tests | AST→MIR 权威交接尚未在规范 Seed→Stage1 链验证 |
| M5 SSA / Optimization | `internal/ssa/`、`internal/ssagen/` | MIR、CFG、数据流事实 | SSA 函数/块/值、优化后程序、Verifier 结果 | `test/ssa/`、`test/function-ssa/` | 完整编译器源码闭包尚未由 Stage1 运行 SSA；OOM/资源峰值未纳入阶段验收 |
| M6 Native Codegen | `internal/codegen/`、`internal/amd64/`、`internal/ssagen/` | SSA、目标配置 | AMD64 assembly/机器码 | native frontend/codegen、runtime authority tests | 完整 SSA→Native 权威链与 Stage2/3 producer 身份未证明 |
| M7 Link / Runtime | `internal/link/`、`internal/linker/`、`runtime/`、`core/native_build.s` | assembly/object、runtime、linker script | Native ELF、可执行程序、运行结果 | native build、ELF 和 runtime 测试 | Stage1 ELF 尚未生成；运行时和 fixed-point 行为尚未进入真实自举闭环 |

## 依赖闭包与循环风险

### 已确认的分层方向

```text
M0 Driver
  -> M1 Lexer/Token
  -> M2 Parser/AST
  -> M3 Semantic/Types
  -> M4 MIR
  -> M5 SSA/Optimization
  -> M6 Native Codegen
  -> M7 Link/Runtime
```

这是验收层次，不是声明当前源码严格无环。实际源码中存在以下需要单独审计的交叉边：

- `internal/mir/mir.s` 导入 borrow、ownership、typesys 和标准库接口，不能只凭目录名判定 MIR 最小闭包。
- `internal/codegen/amd64_program.s` 直接导入 SSA，Native Codegen 的最小闭包必须包含 SSA 数据结构和目标配置。
- `internal/pipeline/pipeline.s` 导入 `internal.core`，并通过日志/构建辅助函数连接后端；Pipeline 是编排边界，不等于所有后端模块都已真实接入。
- `seed/` 是可信 C Bootstrap Compiler 的实现，不应被误记为 S 原生自举模块；它只能作为 Stage1 producer。
- `testing/`、`internal/tests/`、`*_test.s`、`testdata/` 与生产源码混杂，闭包工具必须按明确规则排除测试输入，同时对可达测试依赖报错。

## 测试矩阵

| 模块 | 代表测试 | 等级 | 说明 |
|---|---|---|---|
| M0 | `test/driver-dispatch/check.sh`、`test/native-bootstrap-diagnostic/` | UNIT/INTEGRATION | driver 分派和诊断存在；完整 Stage1 未通过 |
| M1 | `test/compiler/string_char_at_intrinsic.s`、`test/selfhost/bootstrap_native_string.s`、Seed lexical tests | UNIT | 词法/字符串能力有探针，未等于完整自举 |
| M2 | `test/delta-fixtures/`、`test/native-frontend/`、Parser 相关 fixtures | UNIT/INTEGRATION | 覆盖部分表达式、声明和前端路径 |
| M3 | `test/compiler/stage7_type_checking_*`、`stage8_canonical_type_ref_*` | UNIT/INTEGRATION | 覆盖部分类型/解析；完整闭包仍被 Parser 首错阻塞 |
| M4 | `test/program-ir/`、`test/mir-c-codegen/`、ownership tests | INTEGRATION | 有 MIR 及 C/native 交接探针 |
| M5 | `test/ssa/`、`test/function-ssa/`、`test/mir_ref_liveness/` | UNIT/INTEGRATION | SSA、Verifier、liveness 有测试 |
| M6 | `test/native-codegen/`、`test/native-build/`、`test/compiler/codegen_authority_runtime.s` | INTEGRATION | 有 native codegen/ELF 运行验证 |
| M7 | `test/native-build/`、`test/selfhost/`、`test/aot/` | INTEGRATION | 有 ELF/运行探针；规范 Stage1 ELF 尚不存在 |

当前没有一份统一测试能够为每个模块同时给出 `UNIT_PASS`、`INTEGRATION_PASS` 和 `BOOTSTRAP_PROVEN` 三个独立结果。下一步应建立模块验收表，而不是把现有脚本名称直接映射为自举证明。

## 当前 FIRST RED 与最小验证路径

```text
Seed
  -> source_closure.sh
  -> 规范生产源码闭包（历史基线 320 文件）
  -> bin/s_seed
  -> bootstrap_demo.s:16:9
     expected expression, got :=
  -> Stage1 IR empty / ELF absent
```

最小复现应继续保持为单文件 Seed 编译：

```bash
bin/s_seed --compile-unit /tmp/demo.ir \
  src/cmd/compile/bootstrap/bootstrap_demo.s
```

该探针越过此前字符串未闭合错误后，暴露了 S Parser 对 `bc* := alloc(bootstrap_compiler)` 的当前不支持/不兼容语法。修复前不得进入 Stage2；修复后必须重新运行规范完整闭包，而不是只以单文件通过为准。

## 推荐实施顺序

1. **P0：依赖图与闭包契约**。固定入口、生产文件分类、排序/去重、闭包 hash 和测试依赖失败规则。
2. **P1：M1 Lexer/Token**。以最小 S 源码契约验证字符串、注释、操作符、关键字和错误位置。
3. **P2：M2 Parser/AST**。先修复当前 `bootstrap_demo.s:16:9`，再扩大到声明、函数、结构体、指针、数组和调用表达式。
4. **P3：M3 Semantic/Types**。以真实 AST→semantic 交接验证名称、类型、签名和错误诊断。
5. **P4：M4/M5 MIR/SSA**。验证真实程序对象、CFG/dataflow 和 SSA Verifier，不以 fixture-only 输出替代。
6. **P5：M6/M7 Native/ELF**。验证 SSA→assembly→ELF→执行，并记录目标架构和 runtime 依赖。
7. **P6：完整组装**。恢复完整规范生产闭包，重新执行 Seed→Stage1；只有 Stage1 IR/ELF 和运行验证通过才放行。
8. **P7：Stage2/Stage3/fixed-point**。使用相同闭包、真实 producer SHA-256、原始 ELF 和受限归一化规则验证收敛。

## 结论

推荐采用“模块化增量自举 + 完整规范自举最终验收”双层机制。模块测试可以降低调试成本，但任何模块只有在真实上下游交接中通过后才可标记 `INTEGRATION_PASS`；只有它在规范 Seed→Stage1→Stage2→Stage3 链中被真实使用并保留 producer/输入/输出证据，才可标记 `BOOTSTRAP_PROVEN`。
