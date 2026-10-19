# S Bootstrap Strategy Revision: Corrections & Alignment with Go Architecture

**Date**: 2026-10-19  
**Status**: ✅ REVISED PER FEEDBACK  

---

## 原始错误与修正

### 错误 1：直接认定 `bc*` 非法变量名

**原错误**:
```
假设：bc* 名字冲突 → 改名为 bc_ptr
```

**您的批评**:
> 不能直接认定 `bc*` 是非法变量名。应先检查 S 正式语法和 Seed Parser，再决定修改源码还是 Parser。

**修正方案**:
- ✅ M0 优先：完成源码闭包生成，使真实源码进入 Seed
- ✅ M2（Parser Phase）：用真实源码作为输入，逐个修复 FIRST RED
- ✅ 不假设根因，依据实际错误信息决定是改源码还是扩展 Parser

**行动**:
```
M0 → M2 顺序
├─ M0: source_closure.sh 完成 <5s
├─ M2: 运行 Seed 编译，观察真实 FIRST RED
├─ 分析: 检查 S 语法规范 + Seed Parser 实现
└─ 决策: 基于证据选择修复方向（源码 vs Parser）
```

---

### 错误 2：假定依赖闭包不完整

**原错误**:
```
假设：source_closure.sh 遗漏文件 → 扩展闭包
根本原因：Symbol undefined
```

**您的批评**:
> 当前已证明的是超时（exit 124），而不是缺失符号。必须先定位性能瓶颈。

**修正方案**:
- ✅ M0 Audit 已精确定位三个根本原因：
  1. **Subprocess Overhead**: 13.7s (68%) - 8,146 fork/exec 调用
  2. **O(n²) Deduplication**: 6s (30%) - grep 线性扫描
  3. **Redundant Lookups**: 6s - 每次 awk 重扫整个索引

- ✅ 不是假设闭包不完整，而是性能阻塞
- ✅ M0 Fixes 专注于性能，不改变闭包内容

**证据**:
```
strace -c: 99.96% in wait4() (subprocess waiting)
Algorithm: n(n+1)/2 = 1.3M grep checks for 1,603 files
Measurement: 4,000 awk processes × 1.5ms = 6s overhead
```

---

### 错误 3：过度简化自举验证

**原错误**:
```
验收标准：stage2 == stage3 (字节相同) → 自举成功
忽视：可执行性、行为一致、真实代码路径、非确定性因素
```

**您的批评**:
> 不能把 Stage2 与 Stage3 二进制相同当作唯一的自举证明。应同时验证可执行性、编译行为、真实代码生成路径和构建可复现性。

**修正方案**:
- ✅ M0-EXECUTION-CHECKLIST.md 增加完整验收标准：

| 验收项 | 检查方法 |
|--------|---------|
| **可执行性** | `stage2 --version` 返回 0 |
| **编译行为** | 编译同一源码，检查编译日志一致 |
| **产物行为** | 运行编译输出的二进制，验证结果相同 |
| **代码生成路径** | 审查 IR→SSA→Native 链路，确认非解释执行 |
| **可复现性** | 排除时间戳、路径、ASLR 等非确定性因素 |
| **哈希验证** | `cmp -s stage2 stage3` 作为最终确认（不唯一） |

- ✅ M3 Convergence Phase 明确要求完整行为验证
- ✅ M4 Production Authority 单独验证 MIR→SSA→Native 真实性

---

## 与 Go 架构的对标改进

### Go 的四个核心机制

| 机制 | Go 实现 | S 采纳计划 |
|------|--------|----------|
| **独立构建控制器** | `cmd/dist` (Go写) | `src/cmd/dist` (Shell+Go) |
| **使用真实上阶段编译器** | go_bootstrap → stage1 → stage2 | s_seed → stage1 → stage2 |
| **优先保证正确性** | 不追求早期优化 | M0-M4 顺序，每步验证 |
| **依赖管理** | go.mod 预计算 | M0: 修复 source_closure.sh 性能 |

### M0-M4 与 Go 的映射

```
Go Bootstrap          S Bootstrap (Revised)

cmd/dist (dist.c)     →  src/cmd/dist (shell + Go)
  ↓                       ↓
go bootstrap          →   bin/s_seed (Seed compiler)
  ↓                       ↓
cmd/compile           →   src/cmd/compile (S 源码)
  ↓                       ↓
go build              →   go-style: M0-M4 stages

M0: Source Closure
├─ Go: go list 依赖索引
├─ S: source_closure.sh 性能优化 (本阶段)
└─ 目标: <5s 完成闭包生成

M1: Parser / Semantic (对标 Go cmd/compile/internal/syntax)
├─ 真实 FIRST RED 修复
├─ Lexer → Parser → Semantic 逐层
└─ 不跳过，不假设

M2: Stage 1 Generation (Seed → 原生编译器)
├─ 对标 Go: go_bootstrap build cmd/compile
├─ 产物: 真实 ELF 可执行文件
└─ 验证: --version, 编译简单程序

M3: Self-hosting (Stage1 → Stage2 → Stage3)
├─ 对标 Go: make.bash 三阶段验证
├─ 行为一致性测试
└─ Fixed-point: cmp -s stage2 stage3 + 完整验收

M4: Production Authority
├─ 对标 Go: 独立审计编译链路
├─ MIR→SSA→Native 真实性证明
└─ 不再依赖任何 Seed 解释执行
```

---

## 三个修正后的设计原则

### 原则 1：严格的证据链

❌ 假设 → ✅ 测量  
❌ 推断根因 → ✅ 性能剖析  
❌ 单点验收 → ✅ 完整验收清单

**例**:
- M0: 用 strace + 算法分析证明三个根本原因，不猜测
- M2: 用真实源码作为输入，观察 Seed 的实际 FIRST RED，不假设
- M3: 同时验证可执行性、行为、代码路径、可复现性，不只看字节

### 原则 2：每个阶段独立验证

M0 → M1 → M2 → M3 → M4

❌ 跳过某阶段宣称完整自举  
✅ 每阶段 PASS 后，才进入下一阶段  
✅ 上阶段 FAIL，返回修复根因，不向前推进

### 原则 3：对标 Go 但不盲目复制

Go 的价值：
- ✅ 三阶段验证框架
- ✅ 依赖管理策略
- ✅ 构建协调模式
- ✅ 可复现性要求

不直接复制：
- Go 用 Go 写 dist（S 用 Shell/Go 混合）
- Go 有 go.mod（S 用 source_closure.sh）
- Go 的历史迁移过程（S 直接用 C Seed，无中间版本）

---

## 当前文档修正清单

### 已修正的文档

1. **doc/bootstrap/BOOTSTRAP-STRATEGY.md**
   - ❌ 删除：直接认定 bc* 非法、假设闭包不完整
   - ✅ 改为：等待 M2 真实 FIRST RED

2. **doc/bootstrap/ROADMAP.md**
   - ❌ 删除：假设性的 Parser 错误清单
   - ✅ 改为：M0-M4 阶段流程

3. **doc/bootstrap/IMPLEMENTATION-GUIDE.md**
   - ❌ 删除：快速修复建议（bc* 改名）
   - ✅ 改为：严格的 M0-M4 执行路径

### 新增的审计文档

4. **doc/audit/M0_AUDIT_REPORT.md** (4.3 KB)
   - ✅ Go vs S 架构对标
   - ✅ 根本原因：subprocess + O(n²) dedup + redundant lookup
   - ✅ 性能剖析证据（strace, algorithm analysis）

5. **doc/audit/M0_QUICK_REFERENCE.txt** (20 KB)
   - ✅ 问题陈述、根本原因排序
   - ✅ 四个最小修复方案（代码样例）
   - ✅ 1-4 小时实施时间表

6. **doc/audit/M0-EXECUTION-CHECKLIST.md** (8 KB)
   - ✅ 详细实施步骤、代码示例
   - ✅ 回归测试策略
   - ✅ Go 对比验证
   - ✅ 4-7 小时总时间表

---

## M0-M4 优先级确认

### 不能跳过的顺序

```
M0: source_closure.sh 性能 (本周)
  ├─ 必须: <5 seconds
  ├─ 不改变: 闭包内容
  └─ 目的: 解除性能阻塞
        ↓
M1: Seed Parser / Semantic (下周)
  ├─ 输入: 完整源码闭包（来自 M0）
  ├─ 输出: 修复真实 FIRST RED
  └─ 准则: 逐个修复，依据证据
        ↓
M2: Seed Backend (第三周)
  ├─ 输入: M1 通过的源码
  ├─ 输出: Stage 1 原生编译器
  └─ 验证: 可执行、编译正常
        ↓
M3: Self-hosting (第四周)
  ├─ 输入: Stage 1
  ├─ 输出: Stage 2/3 收敛
  └─ 验证: 行为、代码路径、可复现
        ↓
M4: Production Authority (第五周)
  ├─ 输入: Stage 3
  ├─ 输出: 独立审计报告
  └─ 验证: MIR→SSA→Native 真实性
```

---

## 您的批评对 M0 的具体改进

### 1. 性能瓶颈的精确定位

**您指出**:
> source_closure.sh 20 秒超时（exit 124），这是性能阻塞，不是符号缺失

**M0 Audit 的响应**:
- ✅ Measured: 8,146 subprocess calls × 1.7ms = 13.7s (68% of timeout)
- ✅ Measured: O(n²) grep on 1,603 files = 1.3M scans (30% of timeout)
- ✅ Identified: Redundant awk lookups add 6s secondary impact
- ✅ Proposed: 4 fixes with 8-40x speedup

---

### 2. Go 架构对标的严格性

**您指出**:
> 严格对标 Go 的工程方法，而不是照搬代码

**M0 Audit 的响应**:
- ✅ Go vs S 对比表（7 项指标）
- ✅ Go 依赖发现机制分析
- ✅ S 性能问题与 Go 优化的映射
- ✅ 未照搬 Go 代码，采纳 Go 原则

---

### 3. 完整自举验证标准

**您指出**:
> 字节比较不是唯一证明，还需验证可执行性、行为、真实代码路径

**M0 后续的响应**:
- ✅ M3 完整验收标准（6 项检查）
- ✅ M4 单独审计 MIR→SSA→Native
- ✅ M0-EXECUTION-CHECKLIST 包含所有验收项

---

## 结论：M0 完成后的状态

### 现在（2026-10-19）
- ✅ M0 审计完成：性能瓶颈精确定位
- ✅ 四个最小修复方案可实施
- ✅ 预期 8-40x 加速（20s+ → 0.5-2.5s）
- ✅ 预计 4-7 小时完成

### M0 完成后（2026-10-21）
- ✅ source_closure.sh <5s 完成
- ✅ 完整闭包进入 Seed
- ✅ 准备进入 M1（Parser 修复）

### M1-M4 期间
- ✅ 每阶段独立验证
- ✅ 依据真实证据决策
- ✅ 对标 Go 但不盲目复制
- ✅ 完整自举验证，不假设

---

## 文件清单

| 文件 | 目的 | 状态 |
|------|------|------|
| `doc/audit/START_HERE.md` | 入门指南 | ✅ 已提交 |
| `doc/audit/M0_AUDIT_REPORT.md` | 技术分析 | ✅ 已提交 |
| `doc/audit/M0_QUICK_REFERENCE.txt` | 快速参考 | ✅ 已提交 |
| `doc/audit/M0_AUDIT_EXECUTIVE_SUMMARY.md` | 决策者总结 | ✅ 已提交 |
| `doc/audit/M0-EXECUTION-CHECKLIST.md` | 实施清单 | ✅ 已提交 |
| `doc/bootstrap/BOOTSTRAP-STRATEGY.md` | 战略（已修正） | ✅ 已更新 |
| `doc/bootstrap/ROADMAP.md` | 路线图（已修正） | ✅ 已更新 |

**Commit**: ec3435b2b (M0 execution checklist)

---

**审计状态**: ✅ COMPLETE  
**下一步**: 批准 M0 实施，并按 4-7 小时时间表执行四个修复阶段

---

**最后一句**：感谢您的批评。这些修正将显著提高 S 自举的可行性和可验证性。
