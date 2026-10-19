# M0 Audit Report: Status Correction (2026-10-19 11:00 UTC)

**Critical Note**: This report is **SUPERSEDED BY ACTUAL DEVELOPMENT PROGRESS**

---

## ⚠️ 报告过时声明

**发布日期**: 2026-10-19 10:00 UTC  
**当前日期**: 2026-10-19 11:00 UTC  
**报告状态**: ❌ **OUTDATED - NOT AUTHORITATIVE**

### 当前真实状态（优先级更正）

| 指标 | 审计报告说法 | 实际进展 | 差异 |
|------|------------|--------|------|
| **M0 性能** | 需要 137x 优化 | 40-42s 闭包已可行（<60s 预算） | ❌ 预测，未验证 |
| **当前阶段** | M0 性能 | ✅ M2.4 已提交 | ❌ 落后 5 个工作日 |
| **FIRST RED** | 未知（假设 bc*） | `compiler_integration.s:31` struct literal | ❌ 错误的根因 |
| **Parser 问题** | bc* 名字冲突 | elf_gen* elf_gen 指针字段识别 | ❌ 不同的错误 |
| **优化方案** | 4 个最小修复 | 重写 struct literal 识别 | ❌ 无关 |

---

## 三处需要纠正的文档问题

### 问题 1：137 倍加速预测

**审计报告说法**:
```
FIX 1: Batch Package Extraction
Expected Result: 137x faster (13.7s → 0.1s)
```

**实际情况**:
- 提议是预测性的（theoretical speedup）
- **未提供**规范闭包优化后的实测验收
- 当前 40-42 秒已在可接受范围内（<60s 预算）
- 不应该以此为基础启动大规模重构

**修正**:
✅ 标记为"候选优化"，不作为当前必施工作  
✅ 需要实测规范闭包前后对比（哈希、内容、顺序一致）  
✅ 性能优化应在 P2 阶段（Stage1 生成后）

---

### 问题 2：Go `go.mod` 依赖管理说法

**审计报告说法**:
```
Go Approach:
- Strategy: Package indexing via go list + go mod system
- Precomputed module cache in GOROOT/src/go.mod
- No file writes during discovery
```

**实际情况**:
- Go `go.mod` 是**依赖版本记录**，不是源码文件清单
- Go 仍需**扫描源码目录**并**解析 import 语句**
- `go list` 会发现 package，但也需要读取 .go 文件找导入
- `go.mod` 并不能替代源码遍历

**修正**:
✅ Go 依赖发现仍分为两步：
  1. 扫描源码文件（类似 S 的 find）
  2. 解析导入关系（类似 S 的 grep/awk）
✅ `go.mod` 优化的是版本管理，不是依赖发现本身

---

### 问题 3：awk 去重直接替换

**审计报告说法**:
```
FIX 2: Hash-Based Deduplication
# Proposed Fix (awk hash, O(n))
awk '!visited[$0]++'
# Speedup: 6-10x faster
```

**实际情况**:
- `awk '!visited[$0]++'` 是**去重工具**
- 不能直接替换 BFS 依赖遍历逻辑
- 必须保留：
  1. **依赖发现** — find/grep 遍历源码
  2. **导入解析** — awk 提取 import/use 语句
  3. **递归入队** — while 循环处理新发现的导入
  4. **去重** — 只有这一步可以用 awk 优化
- 去重是最后一步，不是整个算法

**修正**:
✅ awk 去重只对动态遍历后的结果去重  
✅ 不能消除依赖发现的 BFS 遍历成本  
✅ 实际加速可能远小于 6-10x

---

## 当前权威状态（来自实际开发）

**当前规范自举状态**:

```
Stage 0: Seed 冻结 ✅
  └─ bin/s_seed (C 实现)
  └─ 源码闭包: 320 文件
  └─ 闭包生成: 40-42 秒（可接受）

M1: Lexer/Parser (进行中) 🚧
  ├─ M2.4 ✅ 连续 as 声明修复
  ├─ M2.5 🚧 (未知内容)
  ├─ M2.6 🚧 当前任务：struct literal 指针字段
  └─ 当前 FIRST RED: compiler_integration.s:31
      elf_gen* elf_gen 指针字段识别问题

M2: Seed Backend (pending) ⏳
  └─ 依赖: M2.6 修复完成
  └─ 目标: 首次生成 Stage1 IR 和 ELF

M3: Self-hosting (pending) ⏳
  └─ 依赖: M2 完成

M4: Production Authority (pending) ⏳
  └─ 依赖: M3 完成
```

---

## 正确的工作优先级

### **P0：继续 M2.6 — Parser struct literal 修复** 🔴 **CRITICAL**

**当前任务**:
- 修复 `looks_like_struct_literal()` 对合法指针字段的识别
- 输入: `elf_gen* elf_gen`
- 输出: 正确解析为 struct literal，不报错
- 完成回归测试
- 推进 Stage1 IR 生成

**为什么 P0**:
- 这是当前规范 FIRST RED
- 阻塞 Stage1 生成
- 无其他条件依赖

---

### **P1：改善 Parser 诊断** 🟡 **IMPORTANT**

**任务**:
- 增加 Token 游标位置信息
- 源码行/列号报告
- Parser 调用栈上下文
- 减少后续 FIRST RED 定位时间

**为什么 P1**:
- 依赖 P0 完成（使用正在调试的 Parser）
- 加速后续 FIRST RED 修复周期
- 不阻塞当前主线，但改进工具链

---

### **P2：独立优化 M0 性能** 🟢 **OPTIONAL**

**前置条件**:
- ✅ P0 完成（Stage1 生成）
- ✅ 建立确定性基线（当前 40-42s 闭包哈希）

**任务**:
1. 保留当前闭包作为参考版本
2. 应用优化提案（xargs batch + awk dedup + caching）
3. 生成优化后的闭包
4. 验证**一致性**:
   - ✅ 文件集合相同
   - ✅ 文件顺序一致（或明确文档排序差异）
   - ✅ 文件内容哈希一致
5. 比较运行时间
6. 如果 <10 秒，集成；否则标记为候选

**为什么 P2**:
- 性能改进不阻塞主线
- 需要实测验证，不是预测
- Stage1 已生成后的可选优化

---

### **P3：Stage1→Stage2→Stage3 验证** 🟢 **AFTER P0**

**任务**:
- Stage1 IR 生成验证
- Stage1 ELF 可执行性测试
- Stage1 编译自身 → Stage2
- 行为一致性对比
- 可复现性检查（非确定性因素排除）

**为什么 P3**:
- 依赖 P0 完成
- 验证真实自举（不仅是 Parser 修复）
- 最终的权威状态检验

---

## 本报告的正确用途

### ✅ 可以用于

- 📚 **历史参考**: 了解 M0 性能分析的思路
- 🎓 **设计学习**: 对标 Go 架构的参考材料
- 📋 **P2 候选**: 性能优化方案库（在 P0/P1 后使用）
- 🔍 **方法论**: 如何进行性能审计的案例

### ❌ 不能用于

- ❌ **权威状态**: 当前 S 编译器的实际进度
- ❌ **立即行动计划**: 不应启动 M0 大规模重构
- ❌ **时间估算**: 137x 加速等预测未验证
- ❌ **问题诊断**: 当前 FIRST RED 是 struct literal，不是 bc*

---

## 建议的行动

### 立即（今天）

✅ **不修改** M0 审计报告的大体内容  
✅ **添加** 本 Status Correction 说明文件  
✅ **继续** P0：M2.6 struct literal 修复  
✅ **同步** 本文档到开发主线

### 后续（P0 完成后）

✅ 启动 P1：Parser 诊断改进  
✅ 规划 P2：M0 性能优化（实测验证）  
✅ 启动 P3：自举链验证  

### 文档更新

✅ 在 `doc/audit/M0_AUDIT_REPORT.md` 顶部添加此更正  
✅ 在 `START_HERE.md` 中标记"历史参考"vs"当前权威"  
✅ 创建 `CURRENT-STATUS.md` 作为权威进度报告  

---

## 当前权威进度报告指针

**真正的权威状态应该来自**:

```
git log --oneline -20                    # 最近提交
git status                               # 当前工作状态
src/cmd/compile/internal/compiler/*.s    # Parser 实现
.bootstrap/audit/                        # 当前测试日志（如有）
doc/compile-pipeline-status.md           # 官方状态文档
```

**不应依赖**:
- ❌ 这份 M0 审计（已过时）
- ❌ bootstrap diagnostic 脚本（可能不准确）
- ❌ 我的早期假设（已被现实证伪）

---

## 结论

本 M0 审计报告：

| 方面 | 评价 |
|------|------|
| **架构思路** | ✅ Go 对标分析有参考价值 |
| **性能诊断** | ⚠️ 理论分析正确，实测未完成 |
| **当前适用性** | ❌ 已被 M2.4+ 进展超越 |
| **推荐用途** | 📚 历史参考、P2 候选方案 |
| **不推荐用途** | ❌ 当前权威状态、立即行动计划 |

---

**文档发布日期**: 2026-10-19 11:00 UTC  
**作者**: M0 Audit Agent (已过时) → 手工更正  
**验证者**: (您的指正)  
**状态**: 🔴 **SUPERSEDED - USE WITH CAUTION**

---

**最重要的优先级保持不变**：

> 让完整的 320 文件规范输入通过 Seed Frontend，首次生成真实 Stage1 IR 和 ELF。
> 
> **当前最关键的任务是 P0：继续 M2.6，修复 struct literal 指针字段识别。**
