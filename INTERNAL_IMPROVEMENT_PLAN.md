# S 编译器 internal/ 改进计划 - 基于证据的行动路线

**制定日期**: 2026-10-12  
**基于**: S vs Go 架构对比分析  
**原则**: 只做有证据支持的改进，停止条件明确

---

## 现状评估

### 关键指标

| 指标 | 数值 | 与 Go 的对比 | 评价 |
|------|------|-----------|------|
| SSA 模块 | 9.9K | vs 481K | ⚠️ 可能不足 |
| core 模块 | 28 文件 | vs 分散 | ⚠️ 过度集中 |
| 优化位置 | 分散 | vs 集中 ssacompile | ⚠️ 不清晰 |
| Pipeline 使用 | 不清楚 | vs 无对应 | ❓ 需要验证 |

**问题**: 代码量小不是问题，**功能覆盖度不清楚**才是问题

---

## 三个立即可做的验证任务

### 任务 1: 优化覆盖度审计 (1-2 天)

**目标**: 确认 S 实现了 Go 的所有主要优化

**验证清单** (Go ssacompile 包含的优化):

```
□ Dead Code Elimination (死代码消除)
  实现位置: ?
  
□ Dead Store Elimination (死存储消除)
  实现位置: ?
  
□ Common Subexpression Elimination (公共子表达式)
  实现位置: ?
  
□ Branch Elimination (分支消除)
  实现位置: ?
  
□ Copy Elimination (拷贝消除)
  实现位置: ?
  
□ Inline (内联)
  实现位置: inline/ ✓
  
□ Escape Analysis (逃逸分析)
  实现位置: ir/escape.s (部分)
  
□ Devirtualize (反虚拟化)
  实现位置: devirtualize/ ✓
  
□ Monomorphize (泛型单形化)
  实现位置: mono/ ✓
  
□ Bounds Check Elimination
  实现位置: ?
  
□ Redundant Nil Check Elimination
  实现位置: ?
  
□ Loop Optimizations
  实现位置: ?
  
□ Register Allocation
  实现位置: core/register_allocator.s ?
  
□ Instruction Selection
  实现位置: core/instruction_selector.s ?
  
□ Address Mode Selection
  实现位置: ?
```

**执行方式**:
1. 逐个在 src/cmd/compile/internal 中搜索
2. 找到实现位置和文件
3. 评估实现完整度 (简单/完整/缺失)

**停止条件**: 
- 每个优化都找到了位置
- 或确认某个优化缺失

**产出**: 优化覆盖度矩阵 (CSV 或表格)

---

### 任务 2: core 模块职责清单 (1 天)

**目标**: 理解 core 的 28 个文件在做什么

**清单** (需要逐个检查):

```
core/ (9.1K, 28 文件)
├─ assembler.s                      → 职责: ?
├─ assembly_generator.s              → 职责: ?
├─ backend_elf64.s                   → 职责: ELF64 生成
├─ backend_native.s                  → 职责: ?
├─ backend.s                         → 职责: 后端接口?
├─ backend_test.s                    → 职责: 测试
├─ codegen_core.s                    → 职责: 代码生成核心
├─ codegen_demos.s                   → 职责: 演示?
├─ codegen_x86_64.s                  → 职责: x86-64 代码生成
├─ compilation_driver.s              → 职责: ?
├─ compiler_pipeline.s               → 职责: ?
├─ direct_codegen.s                  → 职责: ?
├─ elf64_gen.s                       → 职责: ELF 生成
├─ end_to_end.s                      → 职责: 端到端测试?
├─ graph_coloring_allocator.s        → 职责: 寄存器分配
├─ instr_select.s                    → 职责: 指令选择
├─ instruction_select.s              → 职责: 指令选择（重复?）
├─ linker.s                          → 职责: 链接
├─ liveness_analysis.s               → 职责: 活跃性分析
├─ live_range.s                      → 职责: 活跃范围
├─ machine_prog.s                    → 职责: 机器程序
├─ native_compiler.s                 → 职责: ?
├─ optimizer.s                       → 职责: 优化器（哪些优化?）
├─ register_allocator.s              → 职责: 寄存器分配
├─ ssa_lower.s                       → 职责: SSA 降级
├─ stack_frame.s                     → 职责: 栈帧
├─ test_backend.s                    → 职责: 测试
└─ (28 files total)
```

**执行方式**:
1. 每个文件读前 50 行，确认职责
2. 检查是否有重复（e.g., instr_select.s vs instruction_select.s）
3. 检查职责是否应该独立成模块

**停止条件**:
- 所有文件职责明确
- 确认是否存在重复或过度集中

**产出**: core 模块职责清单 (CSV)

---

### 任务 3: Pipeline + Authority 框架审查 (1 天)

**目标**: 确认这两个模块是否被真正使用，是否带来收益

**检查项**:

```
pipeline/ 检查:
  □ pipeline_build() 是否是真实的入口点?
  □ pipeline_compile() 的职责是什么?
  □ authority 是否被正确传递?
  □ 与 backend_elf64.build() 的关系是什么?

authority/ 检查:
  □ 权威是如何定义的?
  □ 是否在 runtime 中被真正检查?
  □ 还是只是装饰性的?

dispatcher/ 检查:
  □ 任务分配的具体含义?
  □ 是否支持并行编译?
  □ 还是只是顺序执行?

实际效果评估:
  □ 这些框架是否改进了代码清晰度?
  □ 是否影响了编译性能?
  □ 是否为多核编译做了准备?
```

**执行方式**:
1. 读 pipeline/pipeline.s 理解流程
2. 追踪 authority 的传递
3. 检查是否有对应的优化或并行化逻辑

**停止条件**:
- 理解了框架的实际作用
- 或确认它们未被充分利用

**产出**: Pipeline 框架评估报告

---

## 四个可能的后续改进 (基于验证结果)

### 改进 A: 补充缺失的优化

**触发条件**: 任务 1 发现某些优化缺失或不完整

**行动**:
```
如果缺失死代码消除:
  → 在 ssa/ 或 mir/ 中补充实现
  → 参考 Go ssacompile/deadcode.go
  → 争取 1-2 周完成

如果缺失 CSE (公共子表达式):
  → 在 ssa/ 或 mir/ 中补充
  → 参考 Go ssacompile/cse.go
  → 争取 2-3 周完成

等等...
```

**成功指标**: 覆盖度从 X% 提升到 95%+

---

### 改进 B: 拆分 core 模块

**触发条件**: 任务 2 确认 core 有以下问题:
- [ ] 文件数 > 20 (已满足，28 个)
- [ ] 平均文件行数 < 500 (需要检查)
- [ ] 职责 > 3 (指令选择 + 寄存器分配 + 优化 + 链接)

**拆分方案** (如果触发):
```
当前:
  core/ (28 文件, 9.1K)
    └─ backend_elf64.s + codegen + regalloc + optimizer + linker

建议:
  backend/       (orchestration)
    └─ backend_elf64.s, compilation_driver.s
  
  regalloc/      (寄存器分配)
    └─ register_allocator.s, graph_coloring_allocator.s, live_range.s
  
  instr_select/  (指令选择)
    └─ instruction_selector.s, instr_select.s (去重)
  
  optim/         (优化器)
    └─ optimizer.s, ssa_lower.s
  
  elf_gen/       (ELF 生成)
    └─ elf64_gen.s, assembler.s, assembly_generator.s
  
  linker/        (已存在，可能需要扩展)
    └─ linker.s
```

**成功指标**: 每个模块 1-2K 行，职责单一

---

### 改进 C: 统一优化框架

**触发条件**: 任务 1 发现优化分散在:
- inline/
- devirtualize/
- ir/escape.s
- core/optimizer.s
- mono/

**改进方案** (参考 Go ssacompile):
```
当前 (分散):
  IR → mono/ → ir/ → mir/ → ssa/ → core/optimizer.s
                              ↓
  inline/ (单独)
  devirtualize/ (单独)
  ir/escape.s (部分)

建议 (集中):
  方案 A: SSA 层集中
    IR → mono/ → ir/ → mir/ → ssa/
                              ↓
                         ssa_optim/ (新模块)
                         ├─ inline.s
                         ├─ devirtualize.s
                         ├─ deadcode.s
                         ├─ cse.s
                         ├─ ...
                         └─ ssa_gen.s
  
  方案 B: MIR 层集中
    IR → mono/ → ir/ → mir/
                       ├─ inline.s
                       ├─ devirtualize.s
                       ├─ escape.s
                       ├─ deadcode.s
                       └─ mir_to_ssa.s
                             ↓
                            ssa/ (较简单)
```

**成功指标**: 优化集中在 1-2 个模块，易于理解和维护

---

### 改进 D: 实践 Pipeline + Authority

**触发条件**: 任务 3 确认框架有潜力但未充分使用

**改进方案**:
```
如果发现 pipeline/authority 只是装饰:
  → 完整实现权威链传递
  → 添加运行时检查
  → 文档化每个阶段的权威所有者
  → 目标: 明确化编译流程，为并行化做准备

如果发现框架确实有用:
  → 逐步在其他模块中应用
  → 例如优化、链接等
  → 目标: 统一的权威管理模型
```

**成功指标**: 代码清晰度提升，易于理解权威关系

---

## 执行顺序建议

### Phase 1: 验证 (第 1 周)
```
周一-周二: 任务 1 (优化覆盖度)
周三:     任务 2 (core 职责)  
周四-周五: 任务 3 (Pipeline 框架)
周末:     生成验证报告
```

**产出**: 三份验证报告 + 发现的问题清单

### Phase 2: 决策 (第 1-2 周)
```
基于 Phase 1 的发现:
  ✓ 如果优化不足 → 启动改进 A
  ✓ 如果 core 过度 → 启动改进 B
  ✓ 如果优化分散 → 启动改进 C
  ✓ 如果框架有用 → 启动改进 D
```

### Phase 3: 改进 (第 3-6 周)
```
根据决策，逐个实施改进
每个改进 2-4 周，包括:
  - 代码实现
  - 单元测试
  - 集成测试
  - 文档更新
```

---

## 停止条件与成功指标

### 停止优化何时:
```
✓ 优化覆盖度 >= 95% (与 Go 相当)
✓ 每个模块职责清晰 (不超过 3 个)
✓ 代码行数合理 (平均 1-2K/模块)
✓ 编译速度不下降
✓ 代码清晰度提升
```

### 不做什么:
```
✗ 不基于代码行数猜测
✗ 不做没有证据的大规模重构
✗ 不改变 API 或编译结果
✗ 不破坏自托管编译能力
✗ 不停止 P0 duplicate main 调查（如果继续的话）
```

---

## 与 P0 问题的关系

**现状**: 
- Native Bootstrap `duplicate main` 问题需要调查
- 但优化/结构改进可以并行进行

**建议**:
- 让不同的人同时进行
  - 一人: P0 调查 (寻找 Seed 编译器的重复检测位置)
  - 另一人: 内部优化验证 (上述四个任务)

**不冲突的原因**:
- P0 是编译器 bug（需要在 Seed 中修复）
- 结构改进是代码质量（改善 S 自身）
- 两者可以独立进行

---

## 下一步

**立即行动** (今天):
1. 确认要做哪些任务 (1, 2, 3, 或全部)
2. 分配人员
3. 制定每个任务的详细检查清单

**第一周目标**:
- 完成三个验证任务
- 生成清晰的发现报告
- 确定后续改进优先级

---

**文档版本**: 1.0  
**状态**: 待执行  
**风险**: 低（纯验证阶段，无破坏性改动）  
**预期收益**: 
- 清晰理解当前状态
- 发现真实问题（非猜测）
- 制定有针对性的改进计划
