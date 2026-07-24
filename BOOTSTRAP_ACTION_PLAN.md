# S 真正独立自举 - 行动计划 (2026-07-24)

## 现状总结

**目标**: 让 S 编译器在 Linux x86_64 上真正独立自举（不再需要 C seed 的代码生成后端）

**障碍**: `bin/s` 仍链接 C seed 编译器的符号：
```
$ nm ./bin/s | grep seed
000000000001ce70 T seed_compile_file
000000000001ccf0 T seed_compile_source_text
```

**解决方案**: 用 S 实现代码生成后端（IR → x86-64）

---

## 已完成的工作 ✅

### 1. 架构设计与分析
- ✅ 理解现有编译流程
- ✅ 分析 IR 格式（14 种指令，147 行编译器 IR）
- ✅ 验证可行性（bash test_bootstrap_feasibility.sh 通过）
- ✅ 设计纯 S 自举方案

### 2. 文档与规划
- ✅ `SELFHOST_IMPLEMENTATION_GUIDE.md` - 详细技术指南 (300+ 行)
- ✅ `PURE_S_SELFHOST_PLAN.md` - 项目计划 (200+ 行)
- ✅ `README_PURE_S_SELFHOST.md` - 快速指南
- ✅ `test_bootstrap_feasibility.sh` - 可行性验证脚本

### 3. 代码框架
- ✅ `src/cmd/compile/selfhost/ir_parser.s` - 完整的 IR 解析器
- ✅ `src/cmd/compile/selfhost/ir_codegen.s` - IR 处理框架
- ✅ `src/cmd/compile/selfhost/x86_64_codegen.s` - x86-64 生成框架
- ✅ `src/cmd/compile/selfhost/ir_to_binary.s` - 集成工具框架
- ✅ `src/cmd/compile/selfhost/elf_gen.s` - ELF 生成框架
- ✅ `src/cmd/compile/selfhost/asm_generation_examples.s` - 示例与说明

---

## 需要完成的工作 (优先级排序)

### 🔴 P0 - 必需 (实现真正自举)

#### Task P0.1: 完成 IR 解析器实现
**文件**: `src/cmd/compile/selfhost/ir_parser.s`  
**状态**: ⏳ 框架完成，需要集成测试  
**估计时间**: 1 天  

```bash
# 验收标准
./bin/s_seed src/cmd/compile/main.s /tmp/test.ir
# 然后用完成的 S IR 解析器读取和验证 /tmp/test.ir
```

#### Task P0.2: 实现 x86-64 代码生成器
**文件**: `src/cmd/compile/selfhost/x86_64_codegen.s`  
**状态**: ⏳ 框架完成，需要完整指令支持  
**估计时间**: 2-3 天  

需要实现的指令:
- [ ] MOV (数据移动)
- [ ] ADD/SUB (算术)
- [ ] CMP_EQ/CMP_NE (比较)
- [ ] JUMP/JUMP_IF_FALSE (控制流)
- [ ] CALL/RET (函数调用)
- [ ] 其他 9 种指令

#### Task P0.3: 集成 IR 解析器 + x86-64 生成
**文件**: `src/cmd/compile/selfhost/ir_to_binary.s`  
**状态**: ⏳ 框架完成  
**估计时间**: 1 天  

```bash
# 最终目标
./ir_to_binary /tmp/compiler.ir /tmp/compiler.bin
# 生成可执行的编译器二进制，不包含 C seed 符号
```

#### Task P0.4: 修改 Makefile 添加纯 S 自举目标
**文件**: `Makefile`  
**状态**: ⏳ 未开始  
**估计时间**: 半天  

新增 make 目标:
```bash
make pure-selfhost    # 生成不依赖 C seed 的 bin/s
```

#### Task P0.5: 验证真正自举成功
**文件**: 验证脚本  
**状态**: ⏳ 未开始  
**估计时间**: 半天  

验收标准:
```bash
# 1. 无 C 符号
nm ./bin/s | grep seed_compile    # 应为空

# 2. 能自我编译
./bin/s src/cmd/compile/main.s /tmp/self.ir

# 3. 结果一致
diff /tmp/self.ir $(previous)     # 应相同
```

### 🟡 P1 - 优化与扩展

- [ ] ELF 直接生成（不依赖 gcc）
- [ ] 代码优化（死代码消除、常量折叠）
- [ ] 性能改进（指令调度）
- [ ] 完整的错误处理

### 🟢 P2 - 将来

- [ ] 其他架构支持（ARM64、RISC-V）
- [ ] 完全 LTO 编译
- [ ] 集成测试套件

---

## 快速启动指南

### Step 1: 环境准备
```bash
cd /home/shuwen/shuwen/s

# 检查种子编译器
./bin/s_seed --help

# 生成测试 IR
./bin/s_seed src/cmd/compile/main.s /tmp/test.ir
```

### Step 2: 理解 IR 格式
```bash
# 查看生成的 IR
head -50 /tmp/test.ir

# 统计指令类型
cut -d'|' -f1 /tmp/test.ir | sort | uniq -c
```

### Step 3: 实现 IR 解析器
```bash
# 当前进度
cat src/cmd/compile/selfhost/ir_parser.s | wc -l
# 应该已有约 150 行

# 编译和测试 (完成后)
./bin/s_seed src/cmd/compile/selfhost/ir_parser.s /tmp/parser.ir
./bin/s_seed --emit-bin /tmp/parser.ir /tmp/parser_tool
```

### Step 4: 实现 x86-64 生成器
```bash
# 从最简单的开始
# 支持 main() 函数的序言/尾声
# 然后逐步添加指令支持
```

### Step 5: 集成与验证
```bash
# 完成后运行
make pure-selfhost

# 验证
nm ./bin/s | grep seed_compile    # 应为空
./bin/s src/cmd/compile/main.s /tmp/final.ir
```

---

## 代码统计

| 组件 | LOC | 状态 |
|------|-----|------|
| IR 解析器 | 150 | ✅ 框架 |
| x86-64 生成 | 0 | ⏳ 待做 |
| 寄存器分配 | 0 | ⏳ 待做 |
| 集成工具 | 80 | ✅ 框架 |
| 文档 | 800+ | ✅ 完成 |
| 测试脚本 | 80 | ✅ 完成 |
| **总计** | **1100+** | |

---

## 工作分解结构 (WBS)

```
S 真正自举 (0-100%)
├─ 分析与规划 (70% 完成)
│  ├─ 理解现有流程 ✅
│  ├─ 分析 IR 格式 ✅
│  └─ 验证可行性 ✅
├─ 实现代码生成 (0% 完成)
│  ├─ IR 解析器 (框架完成)
│  ├─ x86-64 生成 (未开始)
│  ├─ 寄存器分配 (未开始)
│  └─ 集成测试 (未开始)
└─ 验证与部署 (0% 完成)
   ├─ Makefile 集成 (未开始)
   ├─ 性能验证 (未开始)
   └─ 发布 (未开始)
```

---

## 立即可行的行动项

### 今天可以做:

1. ✅ 理解这个计划
   ```bash
   cat /home/shuwen/shuwen/s/README_PURE_S_SELFHOST.md
   ```

2. ✅ 运行可行性验证
   ```bash
   bash /home/shuwen/shuwen/s/test_bootstrap_feasibility.sh
   ```

3. ✅ 研究 IR 格式
   ```bash
   cd /home/shuwen/shuwen/s
   ./bin/s_seed src/cmd/compile/main.s /tmp/study.ir
   cat /tmp/study.ir
   ```

### 本周可以完成:

4. 🔴 完成 IR 解析器（第一优先级）
5. 🔴 实现 x86-64 代码生成（第二优先级）
6. 🔴 集成工具（第三优先级）

### 本月目标:

7. 🎯 第一个可工作的 pure-selfhost 版本
8. 🎯 验证真正的自举成功

---

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解 |
|------|--------|------|------|
| x86-64 生成复杂 | 中 | 高 | 先做 MVP（简化版）|
| S 语言功能不完善 | 低 | 中 | 使用已证实的功能 |
| 调用约定不对 | 低 | 高 | 参考 System V ABI |
| 测试数据不充分 | 低 | 中 | 使用种子生成的 IR |

---

## 成功标志

✅ 完成本计划意味着:

1. [ ] `nm ./bin/s | grep seed_compile` 返回空
2. [ ] `./bin/s src/cmd/compile/main.s /tmp/a.ir` 能运行
3. [ ] `./bin/s src/cmd/compile/main.s /tmp/b.ir` 结果与 a.ir 相同
4. [ ] 项目通过 `make true-selfhost-check`
5. [ ] 文档更新（可选）

---

## 相关文档

- [实现指南](SELFHOST_IMPLEMENTATION_GUIDE.md) - 详细技术细节
- [项目计划](PURE_S_SELFHOST_PLAN.md) - 更新的计划
- [快速指南](README_PURE_S_SELFHOST.md) - 概览
- [可行性报告](test_bootstrap_feasibility.sh) - 验证脚本

---

## 联系与反馈

如有问题或建议，请查看相关文档或运行 `test_bootstrap_feasibility.sh` 进行诊断。

---

**创建日期**: 2026-07-24  
**最后更新**: 2026-07-24  
**下一个检查点**: 完成 P0.1 (IR 解析器实现)
