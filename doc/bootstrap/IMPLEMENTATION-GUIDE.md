# S 编译器自举：实现原理与路径

## 一句话总结

**S 编译器自举的本质是：用 Seed（C 实现的可信任编译器）编译 S 源码得到 Stage 1，然后用 Stage 1 编译自身产生 Stage 2，再用 Stage 2 验证 Stage 3，直到二进制收敛（fixed-point），证明编译器已独立能力生成可执行代码。**

---

## 一、为什么需要自举？

### 现状问题
- 当前 S 编译器由 **Seed 编译器**（C 语言实现）托管编译
- 这意味着 S 编译器代码本身必须用 C 来验证
- 无法用 S 语言证明 S 语言的完整性

### 自举目标
- **用 S 语言编写的编译器，用 S 编译器编译，生成能编译自己的二进制**
- 这是编程语言"成熟"的标志
- Go、Rust、GCC 等都经历过自举

### 关键意义
1. **语言完整性证明**：S 足够表达编译器复杂性
2. **独立能力**：不再依赖外部编译器
3. **可维护性**：用同一语言开发工具链
4. **性能验证**：生成的编译器能自我改进

---

## 二、自举链的工作原理

### 基本思路（参考 Go）

```
Stage 0: bin/go_bootstrap (C 或旧 Go 版本)
   ↓ 编译
Stage 1: go1（新 Go，由 bootstrap 编译）
   ↓ 编译自身（用 go1 重新编译所有源码）
Stage 2: go2（由 go1 生成，功能相同）
   ↓ 编译自身（用 go2 重新编译所有源码）
Stage 3: go3（由 go2 生成，应与 go2 完全相同）
   
如果 go2 == go3 (字节对字节相同)
   ✅ Fixed-point 达成 → 自举成功！
```

### S 的实现路径（当前）

```
Stage 0: bin/s_seed (C 实现)
   ↓ 运行自举脚本
   ├─ 加载源码闭包（所有 .s 文件）
   ├─ 调用 Seed 编译器处理
   ├─ 生成中间表示 (IR)
   ├─ 后端转换为 Native 代码
   └─ 链接生成 ELF 可执行文件
      ↓
Stage 1: .bootstrap/stage1 (由 s_seed 生成的 S 编译器)
   ↓ 如果 Stage 1 可执行且符合条件
   └─ 用 Stage 1 重新编译完整源码
      ↓
Stage 2: .bootstrap/stage2
   ↓ 再用 Stage 2 编译一次
      ↓
Stage 3: .bootstrap/stage3

检查: cmp -s .bootstrap/stage2 .bootstrap/stage3
   ✅ 相同 → Fixed-point 达成！
   ❌ 不同 → 继续调查原因
```

---

## 三、当前的五大障碍与解决方案

### 障碍 1：Seed 编译器有限制

**问题**：
- Seed 只支持 P0 子集（直线函数、int64、无循环）
- S 编译器源码使用了循环、条件、复杂类型
- Seed 无法解析

**解决方案**：
1. **扩展 Seed**：让 Seed Parser 支持完整 S 语法
2. **重写编译器**：用 P0 子集重写 S 编译器部分（消除循环/条件）
3. **分层**：编译器核心用 P0，库用 C 或其他语言

### 障碍 2：Parser 语法错误

**问题**：
```
error: parse error at src/cmd/compile/main.s:42
  'bc* := alloc(bootstrap_compiler)'
   ^^^
Expected TOKEN_IDENT, got TOKEN_STAR
```

**原因**：
- `bc*` 中的 `*` 被 Lexer 当作指针操作符
- Parser 不允许 `*` 出现在声明的左值

**解决方案**：
1. 改名：`bc* → bc_ptr` 或 `bootstrap_compiler_ptr`
2. 或更新 Lexer 让 `bc*` 作为单一标识符
3. 或改用不同的变量名

### 障碍 3：源码闭包不完整

**问题**：
```
error: undefined symbol 'compile.driver.main'
```

**原因**：
- `source_closure.sh` 没有追踪所有 `import` 和 `use`
- 某些依赖文件被遗漏

**解决方案**：
1. 增加闭包追踪深度
2. 手动审查所有导入关系
3. 确保闭包包含：
   - 所有编译器模块 (`src/cmd/compile/**/*.s`)
   - 所需运行时 (`src/runtime/**/*.s`)
   - 标准库 (`src/std/**/*.s`)

### 障碍 4：代码生成不完整

**问题**：
- Native backend 只支持 P0 子集
- 编译器源码可能使用了浮点、字符串、聚合类型等

**解决方案**：
1. 扩展 Native backend（长期工作）
2. 或改写编译器消除不支持的特性
3. 或使用混合后端（部分用 C）

### 障碍 5：ABI 不匹配

**问题**：
- Generated code 的调用约定与 System V amd64 不一致
- 链接失败或运行时段错误

**解决方案**：
1. 审查 System V amd64 ABI 实现
2. 检查 Codegen 的参数传递、栈对齐
3. 用独立 C harness 测试生成的对象文件

---

## 四、立即可执行的 3 个命令

### 第一步：冻结基线（5 分钟）

```bash
cd /home/shuwen/shuwen/s

# 1. 记录 Seed
sha256sum bin/s_seed > .bootstrap/seed.sha256

# 2. 记录 Git 提交
git rev-parse HEAD > .bootstrap/seed-commit.txt

# 3. 生成源码闭包
mkdir -p .bootstrap/audit
S_SOURCE_ROOT=. src/cmd/dist/source_closure.sh \
    src/cmd/compile/main.s > .bootstrap/audit/complete-closure.tsv

echo "Seed frozen. Closure contains:"
wc -l .bootstrap/audit/complete-closure.tsv
```

### 第二步：定位 FIRST RED（10-30 分钟）

```bash
cd /home/shuwen/shuwen/s

# 运行自举脚本，捕获第一个错误
mkdir -p .bootstrap/audit
bash src/cmd/dist/native-bootstrap-no-manifest.sh \
    .bootstrap/audit/stage1 2>&1 | tee .bootstrap/audit/bootstrap.log

# 查看首个错误
echo "=== FIRST RED ==="
grep -n "error\|FAIL\|panic" .bootstrap/audit/bootstrap.log | head -1

# 查看完整日志
tail -100 .bootstrap/audit/bootstrap.log
```

### 第三步：分析与修复（取决于错误类型）

**如果是 Parser 错误**：
```bash
# 找出所有问题代码行
grep -rn "bc\*" src/cmd/compile --include="*.s"

# 改名为有效标识符
sed -i 's/bc\*/bc_ptr/g' src/cmd/compile/**/*.s

# 重新运行自举验证
bash src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/audit/stage1-v1
```

**如果是 Symbol 缺失**：
```bash
# 检查闭包是否包含该文件
grep -i "driver" .bootstrap/audit/complete-closure.tsv

# 手动添加缺失的文件（如需要）
echo "src/cmd/compile/internal/driver/driver.s" >> .bootstrap/audit/complete-closure.tsv

# 重新运行
bash src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/audit/stage1-v2
```

**如果是代码生成错误**：
```bash
# 查看具体错误
grep -A 5 "Codegen error\|unsupported" .bootstrap/audit/bootstrap.log

# 需要：
#  1. 扩展 backend 以支持该操作
#  2. 或改写源码消除该操作
#  3. 或报告限制条件
```

---

## 五、完整自举验证流程

```bash
#!/usr/bin/env bash
# 完整自举链验证

cd /home/shuwen/shuwen/s
STAGE_DIR=.bootstrap/audit/stages

mkdir -p $STAGE_DIR

# === Stage 0: 冻结基线 ===
echo "Stage 0: Freezing baseline"
sha256sum bin/s_seed > $STAGE_DIR/seed.sha256
git rev-parse HEAD > $STAGE_DIR/seed-commit.txt

# 生成源码闭包
S_SOURCE_ROOT=. src/cmd/dist/source_closure.sh \
    src/cmd/compile/main.s > $STAGE_DIR/closure.tsv
cp $STAGE_DIR/closure.tsv $STAGE_DIR/closure-for-all-stages.tsv

# === Stage 1: Seed → Compiler v1 ===
echo "Stage 1: Seed compiles Stage 1"
mkdir -p $STAGE_DIR/stage1
bash src/cmd/dist/native-bootstrap-no-manifest.sh \
    $STAGE_DIR/stage1 > $STAGE_DIR/stage1.log 2>&1

if [ -x $STAGE_DIR/stage1/stage1 ]; then
    echo "✅ Stage 1 generated"
else
    echo "❌ Stage 1 failed"
    tail -30 $STAGE_DIR/stage1.log
    exit 1
fi

# === Stage 2: Stage 1 → Compiler v2 ===
echo "Stage 2: Stage 1 compiles Stage 2"
mkdir -p $STAGE_DIR/stage2
$STAGE_DIR/stage1/stage1 --compile-unit $STAGE_DIR/stage2.ir \
    $(cat $STAGE_DIR/closure-for-all-stages.tsv) \
    > $STAGE_DIR/stage2.log 2>&1

if [ -x $STAGE_DIR/stage2/stage2 ]; then
    echo "✅ Stage 2 generated"
else
    echo "❌ Stage 2 failed"
    tail -30 $STAGE_DIR/stage2.log
    exit 1
fi

# === Stage 3: Stage 2 → Compiler v3 ===
echo "Stage 3: Stage 2 compiles Stage 3"
mkdir -p $STAGE_DIR/stage3
$STAGE_DIR/stage2/stage2 --compile-unit $STAGE_DIR/stage3.ir \
    $(cat $STAGE_DIR/closure-for-all-stages.tsv) \
    > $STAGE_DIR/stage3.log 2>&1

if [ -x $STAGE_DIR/stage3/stage3 ]; then
    echo "✅ Stage 3 generated"
else
    echo "❌ Stage 3 failed"
    tail -30 $STAGE_DIR/stage3.log
    exit 1
fi

# === Fixed-point 验证 ===
echo ""
echo "Fixed-point Check:"
if cmp -s $STAGE_DIR/stage2/stage2 $STAGE_DIR/stage3/stage3; then
    echo "✅ FIXED-POINT ACHIEVED!"
    echo "   Stage 2 == Stage 3 (byte-for-byte identical)"
    echo "   Self-hosting is complete."
    exit 0
else
    echo "⚠️  Binaries differ"
    SIZE2=$(stat -c%s $STAGE_DIR/stage2/stage2)
    SIZE3=$(stat -c%s $STAGE_DIR/stage3/stage3)
    echo "   Stage 2: $SIZE2 bytes"
    echo "   Stage 3: $SIZE3 bytes"
    cmp -l $STAGE_DIR/stage2/stage2 $STAGE_DIR/stage3/stage3 | head -5
    exit 1
fi
```

---

## 六、成功的标志

### 短期（本周）
- ✅ Seed 版本冻结
- ✅ 源码闭包生成
- ✅ 首个自举脚本运行
- ✅ FIRST RED 定位

### 中期（2 周）
- ✅ Stage 1 成功编译
- ✅ Stage 1 可以执行
- ✅ Stage 2 编译开始

### 长期（4 周+）
- ✅ Stage 2/3 编译成功
- ✅ Fixed-point 达成
- ✅ 所有测试通过
- ✅ 完整自举验证报告

---

## 七、与其他编程语言的对比

| 语言 | 何时自举 | 方法 | 状态 |
|------|---------|------|------|
| **C** | 1970s | 用 B 语言自举 | ✅ 完全自举 |
| **Go** | 1.5 (2015) | 3 阶段 bootstrap | ✅ 完全自举 |
| **Rust** | 2010s | 阶段编译 | ✅ 完全自举 |
| **S** | 2026? | 本计划 | 🚧 进行中 |

---

## 八、关键资源

### 文档
- `doc/bootstrap/BOOTSTRAP-STRATEGY.md` - 详细战略
- `doc/bootstrap/ROADMAP.md` - 里程碑和清单
- `doc/bootstrap/diagnose-and-run.sh` - 自动诊断脚本

### 代码
- `src/cmd/dist/native-bootstrap-no-manifest.sh` - 主自举脚本
- `src/cmd/dist/source_closure.sh` - 依赖追踪
- `src/cmd/compile/main.s` - 编译器入口

### Go 参考
- `/home/shuwen/shuwen/go/src/cmd/dist/` - Go 的自举实现

---

## 九、下一步行动

### 立即（今天）
```bash
cd /home/shuwen/shuwen/s

# 运行诊断脚本
bash doc/bootstrap/diagnose-and-run.sh

# 查看结果
cat .bootstrap/audit/P0-AUDIT.md
```

### 短期（本周）
1. 分析 FIRST RED 的根本原因
2. 生成最小复现案例
3. 实施修复
4. 重新运行诊断验证

### 后续
按照 BOOTSTRAP-STRATEGY.md 中的迭代流程继续

---

## 总结

S 编译器自举的核心是建立一条**可反复验证的闭环**：

1. **冻结 Seed** → 确定基线
2. **编译 Stage 1** → 获得第一代 S 编译器
3. **用 Stage 1 编译自身** → 获得 Stage 2
4. **验证收敛** → Stage 2 == Stage 3 → 完成

每一步都必须能独立验证，不能跳过，不能使用旧二进制冒充。这是 Go 的成功经验，也是 S 应该遵循的路径。
