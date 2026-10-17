# 编译流水线实现状态（2026-10-17）

本记录对照 `/app/shuwen/go` 的实际源码，区分可执行实现、未接入模块和证明报告。
当前入口是 `src/cmd/compile/main.s` → `internal/driver/driver.s`，不是旧的
`internal/sc/main_pipeline.s`。`make compiler` 的源文件清单见 `makefile` 的
`COMPILER_SOURCES`。

## 本轮已补齐

- 驱动恢复全部 15 个现有 proof 命令的路由及 `--help` 可发现性；转发调用实际
  存在的 `compiler_main`，修复 `--emit-c` 等命令的未知函数错误。
- `internal/ssa/program.s` 的结构化 SSA 校验补齐：函数内值 ID 唯一性、值所属块、
  CFG 双向边及重复边数量、终结指令形状和类型、定义顺序、支配关系、Phi 参数与
  前驱顺序、调用边和调用值一一对应、调用参数及返回类型。
- 校验支持稀疏块 ID、循环回边、平行边及不可达块。直接调用支持单结果和 `void`；
  当前结构无法表达多结果调用，因此明确拒绝。
- `test/ssa/check-p2.1.sh` 现在执行原有但未接入的 `p2_verifier_test.s`，以及新增
  CFG/Phi/调用测试。负例检查具体拒绝原因，避免因为无关的 IR 损坏而误报通过。

这些 SSA 测试通过 seed 托管执行 S 实现；它们证明校验器行为，不证明原生 SSA
代码生成。新的 `program.s` 尚未成为生产后端的输入。

## 对照 Go 后仍缺失的部分

| 环节 | Go 源码依据 | S 当前状态与下一步 |
| --- | --- | --- |
| 完整前端与生产入口 | `gc/main.go` 的 `noder.LoadPackage` | S 有解析、语义和名称解析模块；`core/backend.s` 的 `should_skip_semantic_check` 仍跳过编译器源码检查，旧 `sc/*` 流程仍有打印和空实现。需要让实际编译器源码通过同一前端。 |
| 函数级 IR → SSA | `ssagen/ssa.go`，`ssacompile/check.go` | S 的 `mir/program.s` 与 `ssa/program.s` 已有结构，生产仍使用 `ssa_core.s` 的另一套表示，且从 `lower_main_to_mir` 起步。需要统一模块、函数、参数、调用及 CFG 的数据交接。 |
| 优化产物贯穿后端 | `gc/main.go` 的内联、逃逸分析及函数编译，`ssacompile/compile.go` | S 有真实的部分 CFG 优化，但 `run_midend_pipeline` 中多个 pass 仍产生估算/文本报告。需要让优化后的结构化图驱动最终指令生成，并验证改写前后行为。 |
| SSA → 机器指令 | `ssagen/pgen.go` 及架构后端 | `core/ssa_lower.s` 的 `lower_value` 为空且未接入。生产 `compile_writes`/`compile_exit_code` 在编译时执行源码或 MIR，然后 `emit_asm` 输出固定写操作和退出码。需要生成运行时计算、分支及真实函数调用。 |
| 寄存器与栈分配闭环 | `ssa/regalloc.go`、`ssa/stackalloc.go` | S 有独立分配器和统计，但它们尚未贯穿上述生产机器指令路径。需要真实活跃区间、调用约束、spill/reload，并由机器码使用分配结果。 |
| 对象及运行时元数据 | `gc/obj.go`、`ssagen` 与 `cmd/link` | 当前 `.stackmap`、`.dwarf`、`.cfi`、`.export` 等多为文本旁路产物。需要对象内可消费的符号、重定位、栈图、安全点及调试/包信息。 |
| 自举 | Go 直接编译完整编译器 | S 的 `build` 对编译器入口仍有 runtime launcher 特例，`internal/compiler/main.s` 的 `handle_emit_bin` 明确未实现。需要消除语义与后端特例后验证 stage2/stage3 收敛。 |

Go 的 GC/逃逸分析与 S 的所有权/MIR 检查服务于不同内存模型，不能逐项机械移植。
这里对照的是阶段的数据交接与产物真实性。

## 验证命令与边界

```sh
make compiler-unit-check
make pipeline
```

`compiler-unit-check` 执行真实驱动解析/分发的边界测试，以及三套结构化 SSA
校验测试。`pipeline` 重建当前编译器，再运行仓库已有的 22 阶段检查。

现有 pipeline 的 PASS 不代表上述缺口消失：Source/Lexer/AST 三个阶段缺少独立
gate，当前被标为 optional；Stage 17 明确接受 `ssa-program-direct-input=no` 和
`machine-ir-artifact=none`；Stage 22 在常规 build 失败时仍允许显式 legacy C 路径。
部分后端 gate 只检查源码或证明文本，没有消费真实机器指令产物。

本轮实际运行结果：

- `make compiler-unit-check`：驱动测试和三套 SSA 测试通过。
- `make pipeline`：重新构建成功，19 个 required gate 通过，3 个 optional gate
  跳过；报告位于 `.bootstrap/pipeline/compile-pipeline-check.txt`。
- 重建后的 `bin/s_compiler --emit-c test/cli/hello.s` 输出经
  `cc -std=c11 -O2 -Wall -Wextra -Werror` 编译，程序输出 `Hello, world!`。
- 独立代码审查及 `git diff --check` 通过。当前支配关系实现使用矩阵，空间为
  O(B²)、时间最坏 O(B³)；接入大规模生产 pass 前需要改用可扩展的支配树实现。

下一步优先实现结构化 MIR → SSA → 机器指令的直线标量函数和直接调用切片，使用
运行时参数、源代码变更和调用返回值验证产物；之后再扩展分支/Phi、寄存器溢出和
完整语言自举。不能用编译时求值或 gate 文本通过替代这些验收。
