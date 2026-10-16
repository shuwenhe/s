# M1 Backend 接入决策（2026-10-16）

基线 commit：72451b2590645d7acd22c500f9f98436f710f468。本轮不修改编译器功能代码。
推荐：暂停直接向 57 文件构建追加完整 Backend。先提出有界的 Canonical IR 发射契约与执行宿主方案，
明确谁能执行 S 实现，再批准实现。当前并未找到可直接使用的较小自举编译器。

## 缺失依赖分类

Backend 候选闭包 283 文件，其中 47 已在构建输入，236 缺失。分类采用目录归属，
优化辅助归 SSA、类型检查与所有权归 Semantic；这是保守的包闭包，不是实际必需文件下限。

| 分类 | 缺失文件数 | 目录分组 |
|---|---:|---|
| Frontend | 33 | ast 10、parser 23 |
| Semantic/Types | 36 | typecheck 17、types 12、ownership 2、typesys 2、mono 1、safety 1、semantic 1 |
| MIR/IR | 37 | ir 35、mir 2 |
| SSA/优化 | 90 | ssa 77、escape 10、inline 2、dispatch 1 |
| Backend/支持 | 40 | core 24、base 12、abi 1、bounds 1、prelude.s 1、stage5_gate.s 1 |
| Runtime | 0 个已纳入源码清单 | 外部依赖单独列出；完整性未证明 |
| 合计 | 236 | 目录相对 src/cmd/compile/internal/ |

外部运行时依赖为 s、std、std.fs、std.io、std.option、std.prelude、std.process、std.result。
不得将 Runtime 源文件计数 0 解释为没有运行时需求。其源码交付、ABI、系统调用和链接输入未冻结。
闭包还包含 bootstrap_true/false、多个架构 rewrite、示例模块，条件选择和包内文件选择未证明。

复现命令：

```bash
python3 script/canonical_closure.py --entry src/cmd/compile/internal/core/backend.s --out-dir /tmp/s-backend-closure
./bin/s_seed --compile-unit /tmp/s-backend-probe.ir src/cmd/compile/internal/core/backend.s
```

闭包 Manifest 哈希：1cdaa77fd7028fc747ca4577bd19e3f7d8add3581b82103392b0bafa37148ebc。
分类输入是生成的 canonical-closure.txt；对比 Makefile 行首 COMPILER_SOURCES 的路径集合，
不得误匹配 SEED_COMPILER_SOURCES。闭包生成及分类已执行；本轮未重新运行生产构建。

## Seed 能力与必需改动的证据等级

| 层 | 已确认边界 | 必要工作及不确定性 |
|---|---|---|
| Parser | backend.s:164 的 fn_map(fn_map_entry_value[]) 报 expected ')' after enum payload type, got [ | parse_enum_decl 当前只读取 identifier payload；需完整类型解析。其余 Parser 缺口 UNKNOWN |
| Semantic | analyzer.c:2068 对 AST_ENUM_DECL 直接返回成功 | 枚举身份/变体注册、泛型替换、payload 绑定、构造器和穷尽性检查尚未闭合 |
| 符号绑定 | Pipeline 调用 backend_build，定义名是 core.build | use 别名从声明到 IR/执行的重定位尚未验证，不能认为加文件就解决 |
| IR/运行时 | 当前能执行 Driver/Pipeline；尚不能编译 Backend | 枚举 tag/payload、泛型、多返回、fs/process、数组与所有权组合覆盖 UNKNOWN |

这些是已知能力下限，不是完整必改清单。总代价、工时与剩余错误数 UNKNOWN。
不得通过未知类型降为 any、跳过检查或改写成占位行为取得通过。

## IR → Native 交接成本

backend.s:306-327 创建 MIR/SSA 与诊断，但 :362 的 emit_asm 输入是 write_op[] 和 exit_code。
:3188-3215 的 compile_writes/compile_exit_code 优先 execute_source_main，失败后解释 MIR。
这意味着仅删除 Source-first 并改成 MIR 解释仍不满足一般程序的 IR-to-machine 权威要求。
:292-294 对特定输入生成 runtime launcher，也不能计入编译自身的证据。

所需交接包括：选定一种生产 SSA 类型及操作数/控制流/调用/内存契约；指令选择；
寄存器和栈布局；ABI；目标发射和重定位；链接。候选文件是 core/ssa_lower.s、
core/codegen_x86_64.s、core/machine_prog.s、ssa/program.s。
其中 ssa_lower.s:26 的 lower_value 为空，不能把它算作已完成实现。
仓库多套 SSA 模型也不能仅凭相同名字直接连接。修改范围跨层，工作量 UNKNOWN。

## 路线比较

| 路线 | 首个交付物 | 成本与风险 | 建议 |
|---|---|---|---|
| 直接追加完整 Backend | 可运行 Backend | 236 新输入、跨层 Seed 缺口；之后仍需 IR-to-native 重建；工时 UNKNOWN | 暂停 |
| 分阶段验证 Canonical IR 发射 | 有运行期控制流的 amd64 程序及证据 | 需要先证明执行该 S 实现的宿主；尚未解决 Stage0 | 优先制定有界方案 |
| Legacy emit-c / subset | 简单程序 | 不能满足当前 Canonical 权威契约 | 不作为自举路线 |

推荐依据：完整 Backend 编译与 Native Codegen 是两个独立缺口。先限定后者的输入与运行证据，
能避免为源码解释器的巨大依赖付出无限 Seed 扩展成本；但不能保证总代价更低，不能绕过 Stage0。

## 下一有界里程碑

下一设计交付：选定 SSA 类型、操作集合、实际执行宿主、ABI/链接输入和拟修改文件列表。
只检查上述四个候选文件及直接接口；必须明确哪个现有工具能执行 S 实现。
若无可用宿主，应报告 Stage0 缺口与需批准的预算范围，不启动新的发射器开发。

后续获批实现的首个可运行交付应为固定 amd64 目标：运行期输入影响分支、循环和跨函数结果；
改变 SSA 操作数应改变执行结果；非法 IR 必须拒绝；禁止 Source-first/隐式 fallback。
外部 as/ld 可作为声明的工具依赖。Hello 只算 smoke test。
此交付只提供 M3 局部证据，M1 仍需真实 Backend 接入，M4 仍需完整编译器闭包生成下一代。

停止条件：执行宿主无法确定；需第二套完整 Parser/Semantic；需同时展开多架构；
需要占位 ELF、源码执行或 launcher 才能通过；连续三个新能力缺口而未完成限定验收。
出现上述情况暂停实现，提交具体路径比较。Runtime/ABI/源码身份未验收不得进入 Stage0→Stage1。

## 进度记账

当前 M1 = BLOCKED；生产 FIRST RED = unknown function: backend_build。
Backend 构建 FIRST RED = backend.s:164。Self-host = NOT_PROVEN。

本次是否推进 M0–M5 实际验收状态：NO。
本次是否减少下一里程碑的未解决实现能力缺口：NO。
本次完成的是范围量化与决策交付，不描述为编译器功能进展。
以后每次报告必须分别回答这两个问题；均为 NO 时不得称为功能进展。

工作区 docs/COMPILER_STATUS.md 的已有删除保持原状；未恢复或覆盖该文件。
