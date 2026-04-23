# S 编译器 ↔ Go 编译器 对照与实现计划

目的：将仓库中 `s` 语言编译器的主要模块逐项映射到 `golang/go` 中 `cmd/compile` 的对应组件，帮助后续按阶段用 S 语言实现完整编译器路径。

说明：左侧为本仓库 `s` 的模块或文件夹（相对路径），右侧为 golang 源码树中 `cmd/compile` 的对应或可比拟组件，备注简要说明差异与实现要点。

---

- `s/src/cmd/compile/main.s`  → `golang/src/cmd/compile/main.go`
  - 说明：两者都是编译器入口。`s` 的入口更薄，负责把参数转发到内部 `compiler`/`build` 流程；Go 的入口还负责 `buildcfg.Check()`、选择架构初始化并调用 `gc.Main`。

- `s/src/cmd/compile/internal/main.s` → `cmd/compile/internal/gc`（入口包装）
  - 说明：`s` 有兼容性 wrapper；Go 使用 `internal/gc.Main(archInit)` 作为主要驱动。

- `s/src/cmd/compile/internal/compiler/compiler.s` → `cmd/compile/internal/gc/main.go`（驱动/调度）
  - 说明：调度流程（初始化、架构、调用 build）对应；Go 的实现更复杂，包含大量标志、计时器、诊断和并发编译队列。

- `s/src/cmd/compile/internal/syntax/` → `cmd/compile/internal/syntax`
  - 说明：词法与语法解析器；功能上对应，但 Go front-end 更完整（位置信息、注释、错误 URL、并发解析等）。

- `s/src/cmd/compile/internal/semantic.s` → `cmd/compile/internal/typecheck` + 部分 `noder`
  - 说明：`s` 的语义检查器（类型推断、函数签名、作用域）是精简实现；Go 使用 `types2` + `typecheck` 并生成 Unified IR（noder）。

- `s/src/cmd/compile/internal/typesys.s` → `cmd/compile/internal/types` / `types2`
  - 说明：类型描述与比较在 `s` 中以字符串规范化为主；Go 有完整的类型系统数据结构与尺寸计算、内建包处理等。

- `s/src/cmd/compile/internal/mir.s` → Go 的中端 IR（`ir`/`noder`/部分 `ssa`）
  - 说明：`MIR` 在 `s` 中是轻量化、可文本化的中间表示，偏向 borrow 分析与控制流追踪；Go 的 IR 分层更多（noder→ir→walk→ssa→ssagen）。

- `s/src/cmd/compile/internal/borrow.s`, `ownership.s` → `cmd/compile/internal/escape` / `devirtualize` / `inline`（相关分析）
  - 说明：借用/所有权概念在 `s` 中有专门分析模块；Go 在 escape analysis、inlining/devirtualize 阶段处理内存与闭包捕获问题。

- `s/src/cmd/compile/internal/build/` → `internal/buildcfg` + 构建工具链整合
  - 说明：`s` 的 `build`/`exec` 提供 `check/tokens/ast/build/run` 子命令；Go 的 `buildcfg` 提供平台常量、arch 选择和工具链约定。

- `s/src/cmd/compile/internal/backend_elf64.s` → `cmd/compile/internal/ssagen` + `cmd/internal/obj` + 链接/asm 调用
  - 说明：`s` 后端直接把 AST/执行语义转成汇编文本并用 `as`/`ld` 生成 ELF；Go 的后端是 SSA -> 后端代码生成 -> obj 格式导出 -> 链接，支持 DWARF、覆盖率、ABI 等。

- `s/src/cmd/compile/internal/amd64/`, `arm64/`, `riscv64/` 等 → `cmd/compile/internal/ssagen` 的架构特定重写/规则
  - 说明：`s` 已有架构目录骨架；Go 有成熟的架构表、rewrite 规则和生成器（_gen）来生产 SSA 重写。

- `s/src/cmd/compile/internal/inline/`、`ownership.s`、`prelude.s` → `cmd/compile/internal/inline`、`ir` 的内建/预置实现

- `s/src/cmd/compile/internal/tests/` → `cmd/compile` 的测试套与基准
  - 说明：`s` 包含很多 fixtures，用于语义、MIR、golden 测试；映射到 Go 的单元/集成测试思路一致，但覆盖与复杂度较少。

---

实现优先级建议（迭代路线）
- M0：驱动与工具链（完成 `main`、`build`、`exec` 子命令，保证 `check/tokens/ast/build/run` 可用）
- M1：稳健的 `syntax`（词法、解析、位置/错误报告）和 `semantic/typesys`（类型、作用域、基本泛型）
- M2：统一 IR（将 `syntax+types` 转为 `mir`/`ir`）、实现 borrow/escape 分析
- M3：简单 SSA 后端（小型寄存器分配、目标汇编后端）以支持 amd64 初始输出
- M4：优化和并行编译、测试覆盖、跨架构扩展

下一步：如果确认该映射文档无误，我会把第 1 步标记为完成并开始第 2 步：定义统一数据模型与接口（AST/Types/MIR），并创建 `s/src/cmd/compile/internal/ir/README.md` 或等效草稿。

---

维护者：已生成于 2026-04-20

## 2026-04-23 执行版里程碑（按优先级）

### P0: 完整 SSA 主干（CFG -> SSA -> RegAlloc 最小闭环）

- 目标
  - 从 MIR 图构建显式 CFG（基本块、前驱、后继）
  - 将 MIR 指令映射到 SSA value（先实现线性 value 和 block 归属）
  - 完成最小寄存器分配（线性扫描 + 架构寄存器池）
- 验收标准
  - 能输出稳定的 SSA dump（包含 block/value/reg）
  - arm64 / amd64 至少各有一条回归用例覆盖 regalloc 分配
  - 后端 build 流程接入 SSA 构建（可观测、不破坏现有产物）
- 当前状态
  - 已落地最小闭环实现：`internal/ssa/ssa.s`

### P1: 类型系统和 Typecheck 完整化

- 目标
  - 从“字符串归一化类型”升级到结构化 Type（基础类型/指针/切片/函数签名/泛型实例）
  - 补全赋值、调用、返回、match/switch、泛型推断规则
  - 形成错误码和定位信息规范（包含源码位置）
- 里程碑
  - M1.1: 类型表示统一（`typesys` 与 `semantic` 对齐）
  - M1.2: 调用与重载决议稳定（含泛型实参推断）
  - M1.3: 控制流分支下的类型收敛与 unreachable 检查
  - M1.4: 语义错误快照测试扩展（fixtures + golden）

### P2: 后端从“可运行”到“ABI 与性能可用”

- 目标
  - 固化 arm64/amd64 调用约定（参数、返回值、caller/callee 保存）
  - 补齐函数序言/尾声、栈帧布局、临时寄存器溢出策略
  - 降低冗余 mov/load/store，建立最小 peephole 优化
- 里程碑
  - M2.1: ABI 文档和汇编约束落地（每架构一份）
  - M2.2: 栈帧生成器 + 调用点保存恢复
  - M2.3: 指令选择与寄存器约束联动（从 SSA regalloc 读取）
  - M2.4: 后端性能回归基线（指令数/可执行体积/编译时）

### P3: 高级优化（inline/escape/devirtualize）与调试信息

- 目标
  - 优化阶段变为可配置 pass pipeline（按函数/包运行）
  - 输出最小可用调试信息（符号、行号映射），支持问题定位
- 里程碑
  - M3.1: inliner（小函数阈值 + 递归保护）
  - M3.2: escape 分析（堆栈分配决策）
  - M3.3: 去虚调用（单态调用点优先）
  - M3.4: debug line table 和符号映射输出

### 建议推进顺序

1. 先完成 P0 并把 SSA dump 接入 CI
2. 并行推进 P1（类型系统）和 P2（ABI），以 P1 规则驱动 P2 指令选择
3. 最后做 P3，把优化和调试信息建立在稳定中端/后端之上
