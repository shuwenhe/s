# P0 Function-Level Native Codegen

用户已指定 P0.1–P0.4 的实现目标及切换约束。本计划直接执行该设计，旧解释执行模块保留；完整自举另行验收。

## 范围和接口

首个可执行切片支持 Linux/amd64、signed int64、直线函数、参数、局部绑定、直接调用、单整数或 void 返回。所有函数都进入 IR，未支持语法或类型报错，不回退到编译时执行。除零运行时退出 86，整数加减乘按 64 位环绕，INT64_MIN/-1 保持 INT64_MIN、余数为零。

- `mir/program.s` 保持已有模块结构。
- `ssa/program.s` 中结构类型改为 `function_ssa_*`，避免与旧 SSA 类型冲突；值新增 `integer_value`、`parameter_index`。旧校验 API 保持名称。
- `ssa/function_lower.s`: `lower_function_mir_to_ssa(mir_program) function_ssa_result`，返回 `.program` 与 `.error`。
- `codegen/amd64_program.s`: `emit_function_ssa_amd64(function_ssa_program) amd64_program_result`，返回 `.assembly` 与 `.error`，导出 System V ABI 的 `s_native_entry`。
- 同一后端提供 `amd64_executable_startup(function_ssa_program) amd64_program_result`：Linux `_start`，0 参数入口正常调用，1 个 int 参数入口严格解析 argv[1]，错误退出 2，返回值作为退出状态。
- 第一版用栈槽分配所有值，保留 caller/callee ABI 和 16 字节调用栈对齐；支持寄存器和栈参数。S 负责指令选择，GNU as 负责真实指令编码/重定位与 ELF 对象输出，GNU ld 链接。此边界必须在证据中写明。

## 任务

- [x] P0.1：先写失败测试；类型迁移；实现 MIR→SSA，保留模块/函数顺序、参数 ID/位置、常量、调用边、void 调用和返回。校验输入与输出；不支持多结果/外部链接时明确报错。
- [x] P0.2：先写失败测试；实现 SSA amd64 指令选择/栈槽/ABI；用独立 C ABI harness 运行生成对象，检查动态整数、调用后活跃值、7/8 参数、负除法、溢出、void 和错误 IR。
- [x] P0.3：审计实际生产闭包。当前 canonical backend 无法由 seed 解析，且实际 build 调用缺失的 backend_build；用可执行 S 前端复用现有 lexer 产生结构化 MIR，接入实际 shell build 的 as/ld 路径。同步修复 canonical backend 的函数 IR 消费入口，明确区分已运行路径与未验证 canonical 路径。旧 --legacy 保留显式入口，Native build 不作隐式回退。
- [x] P0.4：同一个生产构建产物传不同运行时整数得到不同退出状态；源/常量/运算/被调用函数变更影响产物；readelf/objdump 验证 ELF 指令和调用；产物无 seed 解释器依赖。新增统一验收命令，回归旧显式 C 路径和 SSA/驱动测试。
- [x] 独立代码审查，修正发现，记录每个里程碑的实际命令、结果及未覆盖边界，不宣称自举。

## 审查重点

参数顺序、稀疏 ID、调用后存活值、栈参数与对齐、signed division 特例、void 调用 ID、未支持语法拒绝、不覆盖输入源文件、工具失败时不安装半成品。

## 执行结果

P0.1–P0.4 的直线 int/void Linux/amd64 切片通过 `make native-codegen-check`。
默认 build 与对象输出已接入，共用结构化 MIR/SSA 后端；canonical AST 包装入口
已改接同一后端，但其完整闭包不能由当前 seed 执行，未扩大 P0 的实际验收范围。

工程决策：当前 S 指令选择交由 GNU as 编码/产生 ELF，GNU ld 链接；值先落栈保证
ABI 正确，优化分配器后续接入。完整 selfhost 独立未验收。

代码审查发现并修复：源码 NUL 截断、保留字标识符、汇编目标配置和带前导零的
INT64_MIN。额外 seed 网络回归失败/超时与 HEAD 对照一致，详细证据见
`doc/native-codegen.md`。
