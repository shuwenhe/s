# 编译流水线实现状态（2026-10-17）

当前开发目标为 P0 Function-Level Native Codegen。实现范围、命令和验收证据见
[函数级原生代码生成](native-codegen.md)，实施记录见
[计划](plans/2026-10-17-p0-native-codegen.md)。

默认路径已接通：

`driver → native_source_to_mir → lower_function_mir_to_ssa → emit_function_ssa_amd64 → as → ld`

| 环节 | 当前状态 | 仍需完成 |
| --- | --- | --- |
| 函数 MIR | 保留直线 int/void 函数、参数、调用、返回；全部函数检查 | 完整语言 AST/语义、导入、泛型、聚合与 CFG |
| 函数 SSA | 真实 MIR 转换，保留常量/参数位置/调用边，运行校验 | 多块 lowering、Phi 构造/消除、多结果 |
| amd64 后端 | 真实运算/调用/返回；System V ABI；栈槽保存值 | 优化寄存器分配、完整类型和运行时 ABI |
| 对象及链接 | GNU as 输出编码/重定位/ELF；GNU ld 链接；提供对象命令 | S 自身对象编码、调试/栈图/导出元数据 |
| 生产 build | 当前 seed-hosted 编译器和 shell driver 均实际执行 Native 链 | 完整 canonical 前端闭包的独立执行 |
| 自举 | 尚未验证完整原生自举 | 编译器完整源码支持、消除宿主依赖、stage2/stage3 收敛 |

旧解释执行代码仍在 `core/backend.s` 中，公共 `build`/`build_object` 的旧实现已分别
隔离为 `build_interpreted_legacy`/`build_object_interpreted_legacy`。当前默认路径不调用
它们；显式 C 兼容路径保留。

`make native-codegen-check` 验证 P0.1–P0.4；`make compiler-unit-check` 验证驱动及
结构化 SSA 校验。`make pipeline` 的 Stage 22 已移除 legacy fallback，并实际运行同一
Native 可执行文件验证动态输入。Source/Lexer/AST 三个 optional gate 仍跳过，其他旧
报告/源码 gate 尚不代表完整 Native 阶段验收。
