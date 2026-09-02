# S 编译器自举 - 功能分析汇总 (2026-09-02)

**版本**: v1.0  
**完成度**: Go vs S 详细对标分析完成  
**下一步**: 运行诊断计划，确定具体瓶颈

---

## 📊 已完成的分析

### 1. Go 编译器参考框架
- ✅ 714K 代码行数
- ✅ 45+ 模块结构
- ✅ 关键功能详解 (SSA/ABI/后端)
- ✅ 8+ 架构支持

### 2. S 编译器当前状态
- ✅ 42K 代码行数 (S 当前编译器)
- ✅ ~50 模块结构
- ✅ 各模块代码规模统计
- ✅ 完整性评估 (%)

### 3. 功能对标分析
- ✅ 前端 (Parser/TypeCheck) - S: 50% 完整 ❌ 缺泛型/接口
- ✅ IR/Semantic - S: 50% 完整 ❌ 缺完整节点类型
- ✅ **ABI 调用约定** - S: 30-40% 完整 🔴 **最关键缺陷**
- ✅ SSA 优化规则 - S: 10% 完整 ⚠️ 优化优先级低
- ✅ 中端优化 - S: 5% 完整 ⚠️ 优化优先级低
- ✅ 寄存器分配 - S: 20% 完整 🔴 高优先级
- ✅ 栈帧/Liveness - S: 20% 完整 🔴 高优先级
- ✅ 代码生成 - S: 40% 完整 🔴 需改进
- ✅ 链接 - S: 50% 完整 ⚠️ 中优先级

---

## 🎯 最关键的 5 项缺陷

### 🔴 Priority 1: ABI 不完整 (Gate D)
**影响**: Stage2 SIGSEGV 最可能根源  
**工作量**: 2-3 周  
**当前状态**: 30-40% (只支持简单 int/string 传递)

**具体缺失**:
1. Struct 参数传递
2. Array 参数传递
3. >6 参数的栈传递
4. 多返回值 ABI (>2 words)
5. String/Slice/Interface 两字值 ABI
6. Intrinsic 调用 (malloc/free/syscall)
7. 栈对齐 (16 字节)
8. 返回地址处理

### 🔴 Priority 2: 指令生成和后端 (Gate G)
**影响**: 输出代码正确性  
**工作量**: 3-4 周  
**当前状态**: 40% (基础代码生成存在)

**具体缺失**:
1. 指令选择系统性机制
2. 寻址模式 (SIB) 优化
3. 浮点指令生成
4. SIMD 支持
5. 调用序列完整性

### 🔴 Priority 3: Liveness 分析
**影响**: 栈帧优化、GC 根追踪  
**工作量**: 2-3 周  
**当前状态**: 20% (框架存在，无实现)

**具体缺失**:
1. 生存范围构造
2. 活跃性数据流分析
3. 栈位置复用
4. 指针活性追踪

### 🔴 Priority 4: 寄存器分配
**影响**: 生成代码的效率  
**工作量**: 3 周  
**当前状态**: 20% (线性扫描，图着色缺失)

**具体缺失**:
1. 干涉图构造
2. 图着色算法
3. 溅出处理
4. 两字值寄存器对

### 🟡 Priority 5: 前端完整性 (Gate C)
**影响**: 语言子集可编译性  
**工作量**: 2 周  
**当前状态**: 50% (基础类型系统存在)

**具体缺失**:
1. 泛型类型参数
2. 接口隐式满足验证
3. 完整的 IR 节点类型 (S: 20 种 vs Go: 50+ 种)
4. 方法集计算

---

## 🔄 Bootstrap Gate 状态评估

基于代码分析和缺失功能，预计当前状态:

| Gate | 功能 | 评估 | 诊断指标 |
|------|------|------|---------|
| **A** | 基本语言子集 | ✓ 应通过 | Syntax 错误率 |
| **B** | 前端闭包 | ⚠️ 部分通过 | 类型错误数 |
| **C** | Typed IR 闭包 | ⚠️ 部分通过 | IR 节点覆盖 |
| **D** | **ABI 闭包** | 🔴 **很可能失败** | 参数/返回错误 |
| **E** | Runtime 闭包 | 🔴 可能失败 | malloc/syscall 错误 |
| **F** | 可执行程序 | 🔴 很可能失败 | SIGSEGV/错结果 |
| **G** | Stage2 → Stage3 | 🔴 预期失败 | 编译器自身奔溃 |
| **H** | Stage3 ↔ Stage4 | 🔴 预期失败 | 二进制不一致 |

**最可能的瓶颈**: Gate D (ABI 不完整)

---

## 📋 文档已生成

### 📄 已生成的文件

1. **GO_VS_S_DETAILED_ANALYSIS.md** (20K)
   - 9 个功能模块的详细对标
   - 每个模块的 Go 实现参考
   - S 的当前状态和缺失功能
   - 优先级排序
   - 预计工作量

2. **IMMEDIATE_DIAGNOSTIC_PLAN.md** (18K)
   - 3 Phase 诊断流程
   - 7 个 Gate 的诊断脚本
   - ABI 系列测试用例 (D1-D7)
   - 症状对应的根本原因
   - 完整的诊断脚本模板

3. **本文件 (ANALYSIS_SUMMARY.md)**
   - 汇总和后续行动

---

## 🚀 立即后续步骤

### Step 1: 运行诊断 (当前)

```bash
cd /home/shuwen/shuwen/s

# 清理
make clean

# Stage 0 诊断
make bootstrap-stage0 2>&1 | tee /tmp/stage0_$(date +%s).log
STAGE0_STATUS=$?

# 如果 Stage 0 通过，继续 Stage 1
if [ $STAGE0_STATUS -eq 0 ]; then
    make bootstrap-stage1 2>&1 | tee /tmp/stage1_$(date +%s).log
    STAGE1_STATUS=$?
    
    # 如果 Stage 1 通过，测试 Stage2 可执行性
    if [ $STAGE1_STATUS -eq 0 ]; then
        ./bin/s-stage1 --version
        echo "✓ Stage1 编译器可执行"
    fi
fi
```

**预期耗时**: 15-30 分钟

### Step 2: 创建诊断测试文件

```bash
# 创建目录
mkdir -p /home/shuwen/shuwen/s/tools
mkdir -p /home/shuwen/shuwen/s/test/abi

# 复制诊断计划中的测试文件 (见 IMMEDIATE_DIAGNOSTIC_PLAN.md)
# tools/diagnose_gate_a.s 到 diagnose_gate_g.s
# test/abi/d1.s 到 d7.s
```

**预期耗时**: 20 分钟

### Step 3: 运行诊断脚本

```bash
cd /home/shuwen/shuwen/s

# 运行完整诊断
bash tools/full_diagnostic.sh 2>&1 | tee diagnostic_results.txt

# 查看结果
grep -E "Gate|PASS|FAIL" diagnostic_results.txt
```

**预期耗时**: 30 分钟

### Step 4: 分析结果并制定修复计划

根据诊断结果，确定:
1. **第一个失败的 Gate** (最可能是 D)
2. **具体的错误症状** (参数错误 / 返回值错误 / 栈错误)
3. **修复优先级** (应该先修 Gate D，然后 E，然后 F)

---

## 📈 长期路线图修订

基于本次分析，修订的 18 周计划:

```
Week 1-2:   诊断 + 确定瓶颈
            目标: 明确第一个卡在哪个 Gate
            
Week 3-4:   ABI test matrix 建立
            目标: 20+ ABI 测试用例全通过
            
Week 5-6:   ABI 完整性修复
            目标: Gate D 通过
            
Week 7-8:   Runtime 完整化
            目标: malloc/free/syscall 工作
            Gate E 通过
            
Week 9-10:  指令生成改进
            目标: 基本函数可正确编译运行
            Gate F 通过
            
Week 11-14: 编译器自身编译
            目标: stage2 可编译编译器子模块
            Gate G 通过
            
Week 15-16: 验证和调整
            目标: stage3 收敛
            Gate H 通过
            
Week 17-18: 优化和完善
            目标: 基础 SSA 规则 (500 条)
            性能达到 0.5× Go 速度
```

---

## 💡 关键洞察

### 1. ABI 是隐藏杀手

很容易被忽视，但是:
- 参数传递 ABI 错→所有函数调用都崩溃
- 返回值 ABI 错→所有多返回值函数崩溃
- 栈帧布局错→栈溢出/内存破坏

**诊断方法**: 生成汇编检查参数位置

### 2. Liveness 分析被严重低估

看起来是"优化"问题，实际上:
- 缺少→栈帧过大
- 缺少→GC 误判活跃指针→内存泄漏
- 缺少→无法实现栈溢出检测

**诊断方法**: 打印栈帧大小，比对 Go

### 3. 图着色 vs 线性扫描

很多人认为性能差异在这里，实际上:
- 线性扫描可以工作得很好
- 真正的问题是正确性，不是性能
- 除非性能目标是 0.9× Go，否则先用线性扫描

**建议**: 保留现有线性扫描，专注正确性

### 4. SSA 规则数量被过度强调

Go 有 13,711 条规则。S 不需要全部才能自举:
- 通用规则 (常数折叠等) 150 条 → Week 17
- AMD64 基础规则 100 条 → Week 18
- 其余是优化，不影响自举

**建议**: 先做框架和诊断，后做规则

### 5. Go 1.17 ABI 变化是隐藏复杂性

Go 1.17 改了 ABI (寄存器→更多参数):
- 需要理解这个变化
- S 可能还在用老 ABI 或混淆中

**诊断方法**: 对比 Go 1.16 vs 1.17 ABI

---

## ✅ 建议的立即行动 (优先级)

1. **🔴 URGENT** - 运行 `make bootstrap-stage0` + 创建诊断脚本 (Today, 1 小时)
2. **🔴 URGENT** - 确定第一个失败的 Gate (Today, 2 小时)
3. **🔴 HIGH** - 为该 Gate 创建 minimal repro (Today + Tomorrow, 4 小时)
4. **🔴 HIGH** - 修复第一个 Gate，验证 (1-2 周)
5. **🔴 HIGH** - 重复 Step 2-4 直到所有 Gate 通过 (Weeks 3-10)

---

## 📚 参考文档

- `GO_VS_S_DETAILED_ANALYSIS.md` - 详细对标
- `IMMEDIATE_DIAGNOSTIC_PLAN.md` - 诊断脚本
- `SELFHOST_CORRECTED_ROADMAP.md` - 长期计划
- `/memories/session/feature_gap_analysis_2026_09_02.md` - 会话记录

---

## 🎓 总结

S 编译器自举不是缺少 XXX 功能，而是需要:

1. **系统的诊断** (确定当前卡在哪里)
2. **精确的 ABI 测试** (确保函数调用工作)
3. **逐个 Gate 闭包** (从 A 到 H，一个一个)
4. **验证每一步** (不跳过验证)
5. **简化优先级** (闭包第一，优化第二)

关键不是有多少代码，而是有多正确的代码。

