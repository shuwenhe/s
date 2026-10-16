# S Compiler 验收基线

日期：2026-10-16。基线 commit：`72451b2590645d7acd22c500f9f98436f710f468`。
本文件是项目进度主记录；自动检查的原始证据存于 `.bootstrap/compiler-status.*`。
本轮实际证据目录：`.bootstrap/compiler-status.fmk5iL/`（本地未提交产物）。
`BUILD_EXIT=0`、`DRIVER_HELP_EXIT=0`、`CLOSURE_EXIT=0`、`CLOSURE_REGRESSION_EXIT=0`；
`HELLO_COMPILE_EXIT=1`、`BACKEND_PARSE_EXIT=1`，因此检查脚本整体退出 `1`，符合当前阻断状态。
整体功能完成率和自举完成率均为 **UNKNOWN**：尚无经过批准的完整语言功能分母。

## 状态规则

状态仅使用：未实现、部分实现、局部测试通过、生产运行通过、端到端验证通过、未证明、阻断。
代码存在不算通过；局部测试不代表生产链通过；阶段打印不代表阶段实际执行。
已有测试文件只作为候选验收入口，未运行不得记为 PASS。

## 功能清单

| 功能 | 实现入口 / 输入输出及依赖 | 当前证据和验收入口 | 状态 |
|---|---|---|---|
| Driver | `internal/driver/driver.s`；参数 → 命令分派；依赖字符串 intrinsic、Pipeline | 新构建 `bin/s_compiler --help` 与 Hello 调用进入 Pipeline | 生产运行通过（入口范围） |
| Pipeline | `internal/pipeline/pipeline.s`；输入/输出路径 → Backend 调用；依赖 `authority.s`、Core | Hello 实际打印 Pipeline 日志，在 `backend_build` 失败 | 生产运行通过（编排范围） |
| Lexer | `seed/lexical/lexer.c`；Canonical `internal/parser/syntax/scanner.s`；文本 → token | 57 文件 Seed 构建提供局部证据；Canonical 生产路径未运行 | 部分实现 / Canonical 未证明 |
| Parser | `seed/syntax/parser.c`、`internal/parser/parser.s`；token → AST | Backend 单文件解析失败；候选 `script/canonical-parser-closure-check.sh` | 部分实现 |
| Semantic | `seed/semantic/analyzer.c`、`internal/semantic/semantic.s`；AST → 类型/诊断 | Seed 当前构建成功；Canonical 候选 `internal/tests/test_semantic.s` 未独立运行 | 部分实现 / Canonical 未证明 |
| Types / 泛型 | `internal/typesys/`、`internal/mono/`；类型声明 → 类型身份/实例 | 候选 `script/canonical-type-checking-check.sh`、`canonical-monomorphization-check.sh`；端到端未运行 | 未证明 |
| MIR | `internal/ir/lower.s:341`、`internal/mir/`；AST → MIR graph | 静态调用存在；候选 `script/canonical-lowering-check.sh` | 未证明 |
| SSA | `internal/ssa/`；MIR/hints → SSA；Backend 调用位于 `core/backend.s:318` | 候选 `test/ssa/check-p2.1.sh`；本次未运行 | 未证明（生产权威） |
| Optimizer | `internal/core/backend.s` 的 `run_midend_pipeline`；依赖 MIR | 候选 `script/canonical-optimization-check.sh`；本次未运行 | 未证明 |
| Backend | `internal/core/backend.s:286`；路径 → 可执行文件 | 不在现有 57 文件输入；单文件于 164 行解析失败 | 阻断 |
| Assembler | Backend 调用外部 `as`；另有 `internal/core/assembler.s` | 完整候选闭包曾于 assembler.s:50 解析失败；工具调用未到达 | 未证明 |
| Linker | Backend 调用外部 `ld`；另有 `internal/linker/` | `backend.s:378` 静态调用存在；内部 Linker 生产使用未证明 | 未证明 |
| Runtime | `seed/runtime/runtime.c`；IR 执行和 intrinsic 分派 | 字符访问、切片定向测试此前通过；本次状态脚本不重跑它们 | 局部测试通过 |
| Seed 构建工具 | `makefile` 的 `compiler`；57 个显式文件 → IR → `bin/s_compiler` | 当前可重建 Driver/Pipeline；依赖宿主 C 工具链及 Seed runtime | 部分可用 |

上表相对路径的 `internal/` 和 `seed/` 均位于 `src/cmd/compile/`。
更细的运算符、泛型、所有权、ABI、架构覆盖仍需逐项列出并验收；本表不是完整语言兼容性声明。

## 唯一主线与断点

`main → driver_main → pipeline_build` 已有运行证据。
当前生产运行 FIRST RED：`unknown function: backend_build`。
它是 `use compile.internal.core.build as backend_build` 的别名；定义为 `core/backend.s:286` 的 `build`。
Backend 单文件编译 FIRST RED：`core/backend.s:164` 的 `fn_map(fn_map_entry_value[])`，
Seed 报 `expected ')' after enum payload type, got [`。两个诊断属于运行链和候选构建链，不能互换。

Backend 静态候选闭包为 283 文件，相对现有输入新增 236 文件；当前入口候选闭包为 293 文件。
这些数量来自包级保守解析，不代表最小可编译闭包。清单无未解析导入不代表类型、运行时、链接完整。

独立的生产权威缺口：`core/backend.s:3188` 的 `compile_writes` 和 `:3203` 的 `compile_exit_code`
优先使用 `execute_source_main(source)`，失败后使用 MIR 解释结果。SSA 存在不能证明机器代码由 SSA 决定。
现阶段暂停扩大 Seed、Result、Enum Registry 或 Backend 实现。

## M0–M5 验收计划

| 里程碑 | 输入 → 输出 | 命令 / 成功标准 | 依赖、工作量与停止条件 |
|---|---|---|---|
| M0 构建基线 | 固定源码、入口 → 哈希清单、日志、产物身份 | `bash script/compiler-status-check.sh`；日志可重现，源码状态可核对，闭包 unresolved=0；已知失败准确记录 | 无前置；小规模证据维护。源码变化或旧产物被使用则证据无效；完整 Runtime/Link 闭包仍待验收 |
| M1 生产入口 | Source 路径 → 可运行 Hello | 同一脚本构建成功后执行帮助、Hello 编译和输出比较；Backend 确实执行且无隐式 fallback | M0；当前进行中，Backend 成本高且不确定。引入大量模块/不支持语言时先作路径决策 |
| M2 前端语义 | 正负例及固定源码 → 类型化 AST/诊断 | `script/canonical-parser-closure-check.sh`、`canonical-semantic-check.sh` 为候选；须审计命令对应生产实现，类型错误真实拒绝 | M1 可执行基础；中到大，覆盖未知。任何跳过检查或 unknown/any 伪通过即失败 |
| M3 IR 到机器代码 | 类型化 AST → MIR → SSA → machine → executable | `script/codegen-authority-handoff-check.sh`；运行行为回归并验证 SSA 改动影响机器代码，禁止 source-first；现有 stage gate 只能补充证据 | M2；高不确定性，可能跨层。发现解释结果替代 Codegen 时停止宣称通过 |
| M4 Stage0 → Stage1 | 固定编译器闭包与明确 Stage0 → 新编译器 | 命令尚未建立，标记 NOT_AVAILABLE；必须保存实际命令、输入哈希、Stage1 哈希，并由 Stage1 编译测试和自身 | M3 及 Stage0 能力闭合；工作量 UNKNOWN。预制产物、占位、隐式工具替代即失败 |
| M5 代际收敛 | 相同源码/配置、Stage1 → Stage2 → Stage3 | 命令尚未建立，NOT_AVAILABLE；代际构建、回归、完整产物比较或预先定义的规范化比较契约 | M4；工作量 UNKNOWN。输入不一致、隐式 Seed/CC fallback 或只比较部分产物即失败 |

M0 证据机制已建立，完整输入边界仍部分完成；M1 进行中；M2/M3 未验收；M4/M5 未证明。

## 自举身份

| 身份 | 生产者及状态 |
|---|---|
| 当前 `bin/s_seed` | 宿主 C 编译器生成的 Seed；只证明已验证子集，Canonical-capable Stage0 阻断 |
| 当前 `bin/s_compiler` | Seed 的 57 文件构建产物；Driver/Pipeline 可执行，不标记为可信 Canonical Stage1 |
| Canonical Stage1 | NOT_PROVEN |
| Stage2 / Stage3 / fixed-point | NOT_PROVEN；本次未运行 |

## 执行与报告纪律

每次只推进一个已声明目标。修改前记录 commit、dirty diff 与输入哈希，保留用户改动；
使用新构建产物执行测试，保存命令、退出码、输出、产物哈希；失败后停止依赖该结果的验证。
三个连续新增能力缺口仍无里程碑验收时，暂停功能编码并提交具体路径成本报告。
当前 Backend 已触及此类决策边界：不自动开启下一项 Seed 功能。

下一最小交付：基于 283 文件候选闭包、Backend Parser 阻断及 source-first 证据，
形成有范围和退出条件的 Backend 接入方案，完成后再批准实现。

固定报告字段：

```text
CURRENT_MILESTONE:
FEATURES_PROVEN:
FEATURES_PARTIAL:
FIRST_RED:
FILES_CHANGED:
TESTS_PASS:
TESTS_FAIL:
TESTS_NOT_RUN:
MILESTONE_ADVANCEMENT:
NEXT_ACTION:
SELFHOST_STATUS:
```

GitHub Issue/PR 尚未创建；本轮交付为本地基线与检查工具。
