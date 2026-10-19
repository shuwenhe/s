# S 编译器自举战略分析

## 一、当前状态快照

### 1.1 已有的核心组件

| 组件 | 位置 | 状态 |
|------|------|------|
| Seed 编译器 | `bin/s_seed` | ✅ C 实现，可执行 |
| 编译器入口 | `src/cmd/compile/main.s` | ✅ S 语言实现 |
| 前端（Lexer/Parser） | `src/cmd/compile/internal/compiler/` | ⚠️ 部分实现 |
| MIR 生成 | `src/cmd/compile/internal/mir/` | ⚠️ 结构化函数级 |
| SSA 中间层 | `src/cmd/compile/internal/ssa/` | ⚠️ 限制条件 |
| Native 代码生成 | `src/cmd/compile/internal/codegen/` | ⚠️ amd64/arm64 基础 |
| 运行时 | `src/runtime/` | ⚠️ 基础设施 |
| 自举脚本 | `src/cmd/dist/` | ⚠️ Import-driven 模型 |

### 1.2 P0（当前验收阶段）的限制

**支持**：
- 单块直线函数
- int64 算术 (+ - * / %)
- 直接调用、参数传递
- System V amd64 ABI
- ELF 生成和链接

**不支持**：
- 分支、循环、phi 节点
- 聚合类型、字符串、浮点
- 全局变量、外部链接
- 导入、泛型、多结果调用
- 任何超出支持范围的输入会报错，不会回退

---

## 二、自举链的五个阶段

### 2.1 Stage 0：Seed 冻结

**目标**：固定当前 Seed 编译器的可重现性

**必须做**：
```bash
# 1. 记录 Seed 二进制
sha256sum bin/s_seed > .bootstrap/seed.sha256

# 2. 记录 Seed 源码版本
git rev-parse HEAD > .bootstrap/seed-commit.txt

# 3. 列出完整源码闭包
S_SOURCE_ROOT=. src/cmd/dist/source_closure.sh src/cmd/compile/main.s \
  > .bootstrap/complete-closure.tsv

# 4. 验证闭包文件
wc -l .bootstrap/complete-closure.tsv
sha256sum .bootstrap/complete-closure.tsv
```

**验收标准**：
- Seed 二进制哈希稳定
- 源码闭包文件数和内容不变
- 两次运行的闭包列表完全相同

---

### 2.2 Stage 1：第一次编译（Seed → S Compiler v1）

**输入**：
- Seed 编译器 `bin/s_seed`
- 完整源码闭包（所有 .s 文件）

**输出**：
- `S_Compiler_v1`（可执行）
- `S_Compiler_v1.ir`（中间表示）
- `S_Compiler_v1.o` 或 `.elf`

**过程**：
```bash
# 1. 编译（Seed 生成完整 IR）
bin/s_seed --compile-unit .bootstrap/stage1.ir \
  $(cat .bootstrap/complete-closure.tsv)

# 2. 验证 IR
# - 包含 main 函数入口
# - 所有导入已解析
# - 无未定义符号
# - IR 大小非零

# 3. 从 IR 生成 Native 代码
# - 后端处理：MIR → SSA → amd64 机器码
# - 生成 .o（可重定位目标）
# - 链接生成 ELF 可执行文件

# 4. 检查输出
ls -lh .bootstrap/stage1 .bootstrap/stage1.ir
file .bootstrap/stage1
```

**验收标准**：
- ✅ `stage1` 文件存在、非空、可执行
- ✅ `stage1 --version` 或类似命令能运行
- ✅ IR 包含主要函数体
- ✅ 可以执行简单测试程序
- ✅ 二进制大小合理（不是零或只有头部）

**常见失败点**：
1. **Seed 找不到源文件** → 检查 `source_closure.sh` 输出
2. **Parser 错误** → "Expected token" / FIRST RED 在此
3. **Symbol 未定义** → 闭包不完整，检查导入
4. **IR 生成失败** → Semantic 或 Codegen 错误
5. **链接失败** → 符号重定位问题或 ABI 不匹配

---

### 2.3 Stage 2：自编译（S Compiler v1 → S Compiler v2）

**前置条件**：
- Stage 1 可执行且能处理相同的源码闭包
- 没有"隐藏的旧二进制"

**过程**：
```bash
# 使用 Stage 1 编译相同的源码闭包
.bootstrap/stage1 --compile-unit .bootstrap/stage2.ir \
  $(cat .bootstrap/complete-closure.tsv)

# 后续步骤同 Stage 1
```

**验收标准**：
- ✅ `stage2` 生成、可执行
- ✅ `stage2 == stage1` 的候选（不必完全相同，但主函数行为一致）

---

### 2.4 Stage 3：验证收敛（S Compiler v2 → S Compiler v3）

**过程**：
```bash
.bootstrap/stage2 --compile-unit .bootstrap/stage3.ir \
  $(cat .bootstrap/complete-closure.tsv)
```

**验收标准**：
- ✅ `stage3` 生成
- ✅ `cmp -s stage2 stage3` → 二进制完全相同（fixed-point）

**意义**：
- 证明编译器状态稳定
- Stage 2 已经是"成熟"的编译器
- 不再有自引用的递归改进

---

## 三、当前的三大障碍

### 3.1 语法解析 FIRST RED

**症状**：
```
error: parse error at src/cmd/compile/internal/compiler/main.s:42
  'bc* := alloc(bootstrap_compiler)'
   ^^^
Expected TOKEN_IDENT, got TOKEN_STAR
```

**诊断**：
- `bc*` 中的 `*` 被解析为指针
- Parser 不认识这种声明形式
- Seed Lexer 如何分词

**根本原因**：
- S 的正式语法规范中，`bc*` 可能不是有效的标识符
- 或 Parser 的声明语句不支持这种模式

**修复方向**：
1. 查看 S 语法规范（EBNF）
2. 确认 `bc*` 是否允许在声明中
3. 如果允许，更新 Seed Parser 的 identifier 识别
4. 如果不允许，改用 `bc_ptr` 或类似的有效名字

---

### 3.2 依赖闭包不完整

**症状**：
```
error: undefined symbol 'compile.driver.main'
```

**诊断**：
- `source_closure.sh` 没有追踪所有导入
- 某些 `.s` 文件被遗漏
- 递归导入深度不足

**修复**：
1. 增加 `source_closure.sh` 的导入追踪深度
2. 手动验证编译器所有 `use` 和 `import` 语句
3. 确保闭包包含：
   - `src/cmd/compile/**/*.s`（所有编译器模块）
   - `src/runtime/**/*.s`（所需运行时）
   - `src/std/**/*.s`（标准库）

---

### 3.3 Native 代码生成的限制

**当前**：
- 仅支持 P0 子集（直线函数、int64、基本 ABI）
- 复杂源码（分支、循环、泛型）无法编译

**影响**：
- 编译器自身的代码可能用了循环、条件
- Seed 后端如何处理？

**长期方案**：
1. 先用 P0 子集重写编译器部分（消除循环/条件）
2. 或在 Seed 中扩展 P0 支持
3. 或编译器分层

---

## 四、立即可执行的 5 步计划

### Step 1：冻结 Seed 和源码闭包

```bash
mkdir -p .bootstrap/audit

# 1. 记录 Seed
sha256sum bin/s_seed > .bootstrap/audit/seed-v0.sha256
git rev-parse HEAD > .bootstrap/audit/seed-commit.txt

# 2. 生成完整闭包
S_SOURCE_ROOT=. src/cmd/dist/source_closure.sh \
  src/cmd/compile/main.s > .bootstrap/audit/complete-closure-v0.tsv
wc -l .bootstrap/audit/complete-closure-v0.tsv
sha256sum .bootstrap/audit/complete-closure-v0.tsv
```

**交付**：`.bootstrap/audit/seed-v0.sha256`、`.bootstrap/audit/complete-closure-v0.tsv`

---

### Step 2：定位 FIRST RED

```bash
# 1. 运行自举脚本，捕获第一个错误
mkdir -p .bootstrap/audit
bash src/cmd/dist/native-bootstrap-no-manifest.sh \
  .bootstrap/audit/stage1 2>&1 | tee .bootstrap/audit/bootstrap.log

# 2. 提取错误
grep -n "error\|FAIL\|panic" .bootstrap/audit/bootstrap.log | head -1

# 3. 如果是 'bc*' 问题，找出所有出现
grep -rn "bc\\*" src/cmd/compile --include="*.s"
```

**交付**：`.bootstrap/audit/bootstrap.log`、FIRST RED 位置与最小复现

---

### Step 3：分析语法规范

检查 S 的正式语法定义和 Parser 实现

**交付**：语法规范文档、Parser 实现摘录

---

### Step 4：修复或改写

**如果是 `bc*` 名字冲突**：
- 改名所有 `bc*` 为 `bc_ptr` 或 `bootstrap_compiler_ptr`
- 验证语法正确性
- 重新运行 Step 2 的最小测试

---

### Step 5：完整自举验证

完整验证 Stage 1 → Stage 2 → Stage 3 的编译链

---

## 五、成功指标

✅ **短期（本周）**
- 冻结 Seed v0
- 定位 FIRST RED
- 提出修复方案
- 通过最小测试用例

✅ **中期（2 周）**
- Stage 1 编译成功
- Stage 2 编译成功
- Fixed-point 验证

✅ **长期（4 周+）**
- 完整源码自举
- 运行时 ABI 验证
- 独立审计

---

## 结论

S 自举的**关键路径**是：

1. **冻结** → Seed 和闭包确定性
2. **修复** → Parser、依赖、代码生成的最小障碍
3. **编译** → 每次修复后完整验证
4. **收敛** → Fixed-point 三阶段
5. **审计** → 独立确认无隐藏回退

不要同时尝试多个修复；每个 FIRST RED 修复后重新运行完整编译。
