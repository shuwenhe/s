# S 编译器自举实现路线图

## 核心自举链路图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        S Compiler Native Bootstrap Chain                │
└─────────────────────────────────────────────────────────────────────────┘

Stage 0: Seed 冻结 (Baseline)
└─ bin/s_seed (C 实现，可信任)
   └─ 版本: git SHA, 文件哈希
   └─ 源码闭包: complete-closure.tsv (所有 .s 文件清单)
   └─ 状态: ❌ FIRST RED (parse error 或 symbol undefined)

         │
         ├─ 修复 FIRST RED
         │  ├─ Parser 错误? → 更新 Seed Parser
         │  ├─ Symbol 缺失? → 扩展源码闭包
         │  └─ 代码生成? → 报告详情或重写源码
         │
         ▼

Stage 1: 第一次编译 (Seed → Compiler v1)
└─ bin/s_seed --compile-unit stage1.ir < complete-closure.tsv
   └─ 产物: .bootstrap/stage1 (Native ELF 二进制)
   └─ 验收:
      ├─ ✅ 文件存在、可执行、大小合理
      ├─ ✅ IR 包含 main 入口和所有函数
      ├─ ✅ 可运行简单测试程序
      └─ ✅ 与 bin/s_seed 功能相同

         │
         ├─ 如果失败? 返回 Stage 0 修复
         │
         ▼

Stage 2: 自编译 (Compiler v1 → Compiler v2)
└─ .bootstrap/stage1 --compile-unit stage2.ir < complete-closure.tsv
   └─ 产物: .bootstrap/stage2 (Native ELF 二进制)
   └─ 验收:
      ├─ ✅ 文件存在、可执行
      ├─ ✅ 编译同一源码闭包
      └─ ✅ 生成相同或等价的二进制

         │
         ├─ 如果失败? 调查并修复 Stage 1 的 bug
         │
         ▼

Stage 3: 收敛验证 (Compiler v2 → Compiler v3)
└─ .bootstrap/stage2 --compile-unit stage3.ir < complete-closure.tsv
   └─ 产物: .bootstrap/stage3 (Native ELF 二进制)
   └─ 验收:
      ├─ ✅ cmp -s stage2 stage3 (完全相同)
      ├─ 意义: 编译器状态已稳定，不再递归改进
      └─ 可宣布: Stage 2 ≈ Stable Compiler v2

         │
         ├─ Fixed-point 验证成功 ✅
         │
         ▼

完整性审计
└─ 运行所有编译器测试
└─ 验证二进制不依赖 Seed 解释执行
└─ 检查运行时 ABI 一致性
└─ 独立审查 IR→SSA→Native 的代码路径
```

---

## 当前障碍诊断树

```
FIRST RED 原因分析
│
├─ Parser Error: "Expected TOKEN_X, got TOKEN_Y"
│  ├─ 原因 1: 标识符规则过严格
│  │  └─ 例: bc* 中的 * 被当作指针操作符
│  │     └─ 修复: 允许 bc* 作为标识符 或 改名为 bc_ptr
│  │
│  ├─ 原因 2: 声明语句格式不支持
│  │  └─ 例: bc* := alloc(T) 中 bc* 作为左值
│  │     └─ 修复: 扩展 Parser 支持该模式 或 重写源码
│  │
│  └─ 原因 3: 保留字冲突
│     └─ 例: bc* 是关键字的一部分
│        └─ 修复: 改用完全不同的名字
│
├─ Undefined Symbol: "undefined symbol 'pkg.func'"
│  ├─ 原因 1: source_closure.sh 遗漏文件
│  │  └─ 修复: 增加导入追踪深度
│  │
│  ├─ 原因 2: 循环导入或条件导入
│  │  └─ 修复: 手动审查导入关系
│  │
│  └─ 原因 3: 编译器需要未实现的库函数
│     └─ 修复: 实现该库函数 或 重写编译器代码
│
├─ Type Error: "type mismatch" / "undefined type"
│  └─ 原因: P0 子集不支持
│     └─ 修复: 重写源码消除不支持的语法
│        ├─ 消除分支和循环
│        ├─ 消除聚合类型
│        ├─ 消除字符串和浮点
│        └─ 限制在 int64 和 void
│
└─ Codegen Error: "unsupported instruction" / "IR mismatch"
   ├─ 原因 1: Native backend 不支持该 IR 节点
   │  └─ 修复: 扩展 backend 或 重写源码
   │
   └─ 原因 2: ABI 不匹配
      └─ 修复: 审查 System V amd64 实现
```

---

## 源码闭包验证

```
完整性检查清单:

[ ] 编译器入口
    └─ src/cmd/compile/main.s
    └─ src/cmd/compile/internal/driver/driver.s

[ ] 前端
    └─ src/cmd/compile/internal/compiler/frontend*.s
    └─ src/cmd/compile/internal/compiler/lexer.s (如果有)
    └─ src/cmd/compile/internal/compiler/parser.s (如果有)

[ ] 中间表示
    └─ src/cmd/compile/internal/mir/*.s
    └─ src/cmd/compile/internal/ssa/*.s

[ ] 代码生成
    └─ src/cmd/compile/internal/codegen/*.s
    └─ src/cmd/compile/internal/codegen/amd64*.s (或 arm64)

[ ] 运行时
    └─ src/runtime/*.s
    └─ 必要的库: fmt, syscall, os 等

[ ] 工具库
    └─ src/std/strings/*.s
    └─ src/std/bytes/*.s
    └─ 等等

验证方法:
  1. wc -l .bootstrap/complete-closure-v0.tsv
  2. grep "^src/cmd/compile/" < closure.tsv | sort | uniq
  3. 检查所有 use/import 语句是否都被闭包覆盖
```

---

## Seed 冻结清单

```
冻结必要信息:

┌─────────────────────────────────────┐
│ Seed Compiler Freeze (v0)           │
├─────────────────────────────────────┤
│ File: bin/s_seed                    │
│ SHA-256: <hash>                     │
│ Created: <date>                     │
│ Git Commit: <commit>                │
│ Size: <bytes>                       │
│ ELF Target: Linux/amd64             │
│ Capabilities:                       │
│   - Lexical analysis ✅             │
│   - Parsing (Limited) ⚠️            │
│   - Semantic (Limited) ⚠️           │
│   - IR generation (Partial) ⚠️      │
│   - ELF output ✅                   │
└─────────────────────────────────────┘

┌──────────────────────────────────────┐
│ Source Closure (v0)                  │
├──────────────────────────────────────┤
│ Version: 0                           │
│ Total Files: <count>                 │
│ Closure Hash: <hash>                 │
│ Last Updated: <date>                 │
│ Format: TSV (path | hash | type)     │
│ Generation Tool: source_closure.sh   │
│ Verification:                        │
│   - All files readable ✅            │
│   - All hashes match ✅              │
│   - No circular imports ✅           │
│   - Entry point included ✅          │
└──────────────────────────────────────┘

存储位置:
  .bootstrap/audit/
    ├─ seed-v0.sha256
    ├─ seed-commit.txt
    ├─ complete-closure-v0.tsv
    ├─ bootstrap-v0.log
    └─ FREEZE-v0.md (此清单副本)
```

---

## Stage 1 验收标准（详细）

```
编译后检查:

1. 文件存在性
   [ ] .bootstrap/stage1 exists
   [ ] .bootstrap/stage1.ir exists
   [ ] file .bootstrap/stage1 | grep -q ELF
   [ ] stat -c%s .bootstrap/stage1 > 0

2. 可执行性
   [ ] .bootstrap/stage1 --version 返回 0
   [ ] .bootstrap/stage1 --help 返回 0
   [ ] .bootstrap/stage1 build --help 返回 0

3. IR 完整性
   [ ] grep -q "func main" .bootstrap/stage1.ir
   [ ] grep -q "package" .bootstrap/stage1.ir
   [ ] 文件大小合理 (不是几百字节)

4. 简单编译测试
   [ ] echo 'func test() { return 42 }' > /tmp/test.s
   [ ] .bootstrap/stage1 build /tmp/test.s -o /tmp/test
   [ ] /tmp/test; echo "Exit: $?"

5. 与 Seed 的行为对标
   [ ] bin/s_seed < input.s > seed.ir
   [ ] .bootstrap/stage1 < input.s > stage1.ir
   [ ] diff seed.ir stage1.ir (应该一致或等价)

失败时:
  → 返回 Stage 0，修复 FIRST RED
  → 重新运行自举脚本
  → 收集完整日志 (.bootstrap/audit/bootstrap-*.log)
```

---

## 修复迭代模板

```
修复循环 (每个 FIRST RED):

Iteration N:
├─ 日期: <date>
├─ 错误: <error message>
├─ 位置: <file:line>
├─ 原因: <root cause>
├─ 修复:
│  ├─ 改动文件: <file>
│  ├─ 改动行: <lines>
│  └─ 验证: <how to verify>
├─ 新闭包版本: v<N>
├─ 重新运行自举
├─ 结果: ✅ / ❌
└─ 下一步: <next action>

示例:

Iteration 1:
├─ 日期: 2026-10-19
├─ 错误: Parse error: 'bc*' unexpected
├─ 位置: src/cmd/compile/main.s:42
├─ 原因: Parser 不允许 * 在标识符中
├─ 修复:
│  ├─ 改动文件: src/cmd/compile/main.s
│  ├─ 改动行: 42 (bc* → bc_ptr)
│  └─ 验证: grep -n "bc_ptr" src/cmd/compile/main.s
├─ 新闭包版本: v1
├─ 重新运行自举
├─ 结果: ✅ 通过 FIRST RED，发现第二个错误
└─ 下一步: 修复 Iteration 2
```

---

## 长期里程碑

```
Timeline:

Week 1 (Oct 19-25):
├─ Day 1: 冻结 Seed v0 + 源码闭包 v0
├─ Day 2-3: 定位 FIRST RED
├─ Day 3-4: 修复第一轮错误
├─ Day 5: 重新运行自举，获得 Stage 1
└─ Week 1 结尾: P0 审计报告

Week 2 (Oct 26-Nov 1):
├─ Stage 1 编译 Stage 2 (自编译)
├─ 修复 Stage 2 的任何错误
├─ Stage 2 编译 Stage 3
├─ Fixed-point 验证
└─ 发布 Stage 1/2 二进制

Week 3+:
├─ 完整性测试
├─ 运行时 ABI 验证
├─ 编译器所有测试套件 PASS
├─ 独立审计报告
└─ 宣布完整自举
```

---

## 关键文件清单

```
需要追踪的文件:

核心脚本:
  src/cmd/dist/native-bootstrap-no-manifest.sh
  src/cmd/dist/source_closure.sh
  src/cmd/dist/target-env.sh

编译器入口:
  src/cmd/compile/main.s
  src/cmd/compile/internal/driver/driver.s

重要模块:
  src/cmd/compile/internal/compiler/*.s
  src/cmd/compile/internal/mir/*.s
  src/cmd/compile/internal/ssa/*.s
  src/cmd/compile/internal/codegen/*.s

运行时:
  src/runtime/*.s (全部必要)

审计日志:
  .bootstrap/audit/seed-v0.sha256
  .bootstrap/audit/complete-closure-v0.tsv
  .bootstrap/audit/bootstrap-v0.log
  .bootstrap/audit/bootstrap-v1.log
  ... (多次迭代)

产物:
  .bootstrap/stage1
  .bootstrap/stage2
  .bootstrap/stage3
```

---

## 与 Go 的实现对标

```
Go Bootstrap (参考):

bin/go_bootstrap (C 实现)
  ↓ (cmd/dist 协调)
  └─ pkg/obj
  └─ cmd/compile (Go 实现)
  └─ cmd/link
  └─ cmd/asm
  └─ src/runtime (Go 实现)

Stage 1 (Go:bootstrap → Go:1.0):
  go_bootstrap build ./cmd/compile
  go_bootstrap build ./cmd/link
  go_bootstrap build ./cmd/asm

Stage 2 (Go:1.0 → Go:1.1):
  ./go1 build ./cmd/compile
  ...

Stage 3 (Go:1.1 → Go:1.2):
  ./go2 build ...

S Bootstrap (当前):

bin/s_seed (C 实现) ← 需要冻结
  ↓ (src/cmd/dist/native-bootstrap-no-manifest.sh)
  └─ src/cmd/compile/main.s
  └─ src/cmd/compile/internal/**/*.s
  └─ src/runtime/*.s

Stage 1 (s_seed → s_compiler:v1):
  bin/s_seed --compile-unit stage1.ir < closure.tsv

Stage 2 (s_compiler:v1 → v2):
  .bootstrap/stage1 --compile-unit stage2.ir < closure.tsv

主要区别:
  ✅ Go: 多工具 (compile, link, asm) 分离
  ⚠️ S: 单体编译器 (IR → ELF 一步)

  ✅ Go: 标准库完整
  ⚠️ S: P0 子集限制

  ⚠️ S: 尚未成功完成一轮 Stage 1
```

---

## 立即行动清单

```
优先级 P0 (今天执行):

[ ] 1. 冻结 Seed
    bin/s_seed
      └─ 记录 SHA-256
      └─ 记录 Git 提交
      └─ 保存到 .bootstrap/audit/

[ ] 2. 冻结源码闭包
    src/cmd/dist/source_closure.sh
      └─ 生成完整清单
      └─ 记录文件数和哈希
      └─ 保存到 .bootstrap/audit/

[ ] 3. 运行自举脚本
    bash src/cmd/dist/native-bootstrap-no-manifest.sh .bootstrap/audit/stage1
      └─ 捕获所有输出到日志
      └─ 记录首个错误

[ ] 4. 分析 FIRST RED
    grep -n "error" .bootstrap/audit/bootstrap.log | head -1
      └─ 定位确切位置和类型
      └─ 生成最小复现

[ ] 5. 生成审计报告
    编写 .bootstrap/audit/P0-AUDIT.md
      └─ 冻结状态
      └─ 首个错误
      └─ 修复建议
      └─ 下一步行动
```
