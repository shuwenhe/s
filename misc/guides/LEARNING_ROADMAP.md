# S 编译器学习路线图 — 快速吸收指南

**Date:** 2026-09-16  
**Level:** 从零到理解当前工作状态  
**Duration:** 分阶段，可按需进行

---

## 第 0 层：30 秒理解（核心概念）

```
S 编译器有个"自托管"问题：
  用 C 编译器（种子） 
    ↓ 编译 S 编译器源代码
    ↓ 得到 S 编译器 v1
    ↓ 用 v1 编译 S 编译器源代码
    ↓ 得到 v2
    ↓ 如果 v1 和 v2 生成的代码一样，就"收敛"了

现在卡在：
  C 编译器不理解"std.io.eprintln"这种带点名字
  所以停在第一步

我们的工作：
  让 C 编译器理解这种带点名字
  这样就能生成 v1
  然后就能测试 v2
```

---

## 第 1 层：背景（为什么这么重要？）

### A. Bootstrap 为什么难？

```
一般编程语言：
  我是 C 编写的
  用现成的 C 编译器编译我
  完成

自托管语言（如 Rust, Go, S）：
  我是 Go 编写的
  但我需要用 Go 编译器编译我
  但 Go 编译器也是 Go 编写的
  所以需要一个"种子" Go 编译器
  
问题：
  如何证明种子编译器的正确性？
  如何逐步升级？
```

### B. S 的 Bootstrap 策略

```
Stage 0（种子）: C 编译器 → bin/s_seed
  │ 用 C 编写
  │ 编译"最小 S"（只有基本功能）
  │ 生成 IR（中间表示）
  │
  ↓
Stage 1: 用 s_seed 编译 S 自身
  │ 输入：S 编译器源代码
  │ 输出：S 编译器 IR
  │ （如果失败 → 问题在 s_seed）
  │
  ↓
Stage 2, 3: 逐级验证
  │ 如果 stage2 == stage3 → 收敛
  │ 说明编译过程是稳定的
  │
  ↓
✅ 编译器可自托管
```

### C. 当前问题的位置

```
从 Stage 0 → Stage 1 失败
  
原因：
  main.s 用了 std.io.eprintln
  但 bin/s_seed 不理解"std.io"这种限定符名字
  
这是 bootstrap 过程中的**第一个真实断点**
```

---

## 第 2 层：代码地图（知道怎么找东西）

### A. 关键目录结构

```
s/
├── src/cmd/compile/
│   ├── main.s                          ← 要编译的 S 代码
│   ├── seed/
│   │   ├── parser/
│   │   │   └── parser.c               ← 解析 S 语法
│   │   ├── semantic/
│   │   │   └── analyzer.c             ← 类型检查、名字解析 ← 我们要改这里
│   │   └── ir/
│   │       └── emit.c                 ← 生成中间表示
│   └── stage0/
│       └── bootstrap_subset.c         ← 最小化验证用（不在主路上）
│
├── doc/
│   ├── bootstrap-subset.md            ← 冻结合同（定义最小能力）
│   └── bootstrap-contract.md
│
├── misc/probes/
│   ├── probe_01_integer.s             ← 测试：整数
│   ├── probe_02_parameter.s           ← 测试：参数
│   ├── probe_08_qualified_call.s      ← 测试：std.io.eprintln ← 失败的
│   └── ...
│
└── misc/reports/
    ├── b6.7.3e0b.2a-*.txt             ← 第一次红色测试
    ├── b6.7.3e0b.2b-*.md              ← 错误假设（后来被证明错了）
    ├── b6.7.3e0b.2c-*.md              ← 实证测试（证明了什么真正支持）
    ├── b6.7.3e0b.2d-*.md              ← 设计审计（Path A-lite 可行性）
    └── ...
```

### B. 最关键的 3 个文件

**文件 1: src/cmd/compile/main.s**
- 这是要编译的 S 代码
- 只有 26 行
- 唯一失败点：第 23 行的 `std.io.eprintln`

**文件 2: src/cmd/compile/seed/semantic/analyzer.c**
- 这是语义分析器（类型检查 + 名字解析）
- 现在：能处理参数、字符串、if、但不能处理限定符名字
- 需要修改的地方：第 1200-1290 行左右（analyze_expr 函数中的 AST_MEMBER_EXPR 处理）

**文件 3: misc/reports/b6.7.3e0b.2d-minimal-fix-boundary-audit.md**
- 这是设计文档
- 说明要改什么，怎么改，改多少

---

## 第 3 层：理解错误信息

### 运行这个命令看到什么？

```bash
make bootstrap-convergence
```

输出：
```
Bootstrap stage0 ready: ./bin/s_seed (trusted C seed)
error[5] at 23:20: type 'any' has no method 'eprintln'
```

这行错误的意思：
```
error[5]         ← 错误代码 5
at 23:20         ← 在 main.s 第 23 行第 20 列
type 'any'       ← std.io 被识别为类型 'any'（未解析）
has no method    ← 不知道怎么找它的方法
'eprintln'       ← 方法名叫 eprintln
```

### 现在的过程（哪一步失败）

```
1. bin/s_seed 读入 main.s            ✅
2. 词法分析（tokenize）              ✅
3. 语法分析（parse）                  ✅ （包括 std.io.eprintln）
4. 语义分析（semantic）
   ├─ 检查 import "std.io"           ✅
   ├─ 登记 std 为 import 符号        ✅
   ├─ 看到 std.io.eprintln
   ├─ 尝试找 eprintln 在 std.io 上
   └─ ❌ FAIL: 不知道 std.io 是什么
```

---

## 第 4 层：理解当前代码（analyzer.c）

### A. import 处理（已经有）

位置：`src/cmd/compile/seed/semantic/analyzer.c` 第 1460-1550 行

```c
// 当看到 import ("std.io") 时：

// 1. 提取根名字 "std"
char *module_root = "std";

// 2. 登记符号 "std"
scope_define(ctx->current_scope,
    "std",           // 符号名
    SYMBOL_IMPORT,   // 类型：导入
    0,
    0,
    0,
    "module",        // 类型名 ← 这里！
    NULL, 0);

// 3. 加载函数签名
resolve_import_signature("std.io", ...);
// 这会从 import_signatures.meta 加载信息
```

**关键：** `import_signatures` 已经有 `"std.io.eprintln"` 的信息（参数数、返回类型）

### B. 限定符调用处理（现在失败）

位置：`src/cmd/compile/seed/semantic/analyzer.c` 第 1200-1290 行

```c
// 当看到 std.io.eprintln(...) 时：

case AST_MEMBER_EXPR:
    // 1. 分析左边 "std.io"
    analyze_expr(ctx, member->as.member_expr.object, &lhs_type);
    // lhs_type 现在是 ??? (没有正确的解析规则)
    
    // 2. 查找右边 "eprintln" 在 lhs_type 上
    // ❌ 失败：不知道怎样处理限定符名字
```

**问题就在这里。** 代码需要能够：
1. 识别 "std.io" 是一个限定符路径
2. 查找 "std.io.eprintln" 在 import_signatures 中
3. 返回它的类型

---

## 第 5 层：学习检查点（验证理解）

### 检查点 1: 运行 probe 测试
```bash
cd /Users/feifei/shuwen/s
for probe in misc/probes/probe_*.s; do
    echo "=== $(basename $probe) ==="
    ./bin/s_seed "$probe" /tmp/test.ir 2>&1 | tail -1
done
```

**预期结果：**
- probe_01 到 probe_07：都说 "compiled successfully"
- probe_08：说 "type 'any' has no method 'eprintln'"

**理解：** 这证明了除了限定符以外，其他特性都工作。

### 检查点 2: 阅读错误代码
打开 `src/cmd/compile/seed/semantic/analyzer.c`，找到这行（约 1282 行）：
```c
"type '%s' has no method '%s'", lhs_type ? lhs_type : TYPE_ANY, member->as.member_expr.member);
```

**问题：** 这行错误是怎么被触发的？
**答案：** 当 lhs_type 没有被正确赋值时。

### 检查点 3: 追踪 import_signatures
打开同一文件，找到 `load_import_signatures` 函数（约 190 行）。

**问题：** 这个函数加载什么数据？
**答案：** 从 `import_signatures.meta` 加载所有导入函数的签名。

**问题：** 签名里有 "std.io.eprintln" 吗？
**答案：** 应该有（这个文件由 bootstrap 过程生成）。

---

## 第 6 层：理解修复方案（Path A-lite）

### 修复的逻辑

现在的代码：
```c
// 看到 std.io.eprintln

1. 分析 "std.io"
   → lhs_type = ???（失败）
   
2. 查找 eprintln 方法
   → ERROR
```

修复后的代码：
```c
// 看到 std.io.eprintln

1. 检查是否这是限定符调用？
   yes → 走特殊路径
   
2. 构造完整名字 "std.io.eprintln"

3. 在 import_signatures 中查找
   → 找到 { arity: 1, return: int }
   
4. 返回该函数的类型
   → OK
```

### 代码位置

修改地点：`src/cmd/compile/seed/semantic/analyzer.c`

在这个 case 之前加入新 case：
```c
case AST_MEMBER_EXPR:
    // 新加：检查限定符模式
    if (is_qualified_member_call(node)) {
        // 查表，返回
    }
    
    // 原有代码继续
    ... 原代码 ...
```

大约 30-50 行新代码。

---

## 第 7 层：下一步具体工作（如果继续）

### 步骤 1: 实现限定符查找
**文件：** src/cmd/compile/seed/semantic/analyzer.c  
**函数：** analyze_expr 中的 AST_MEMBER_EXPR  
**代码量：** ~50 行  
**验证：** probe_08 通过

### 步骤 2: 运行完整测试
```bash
make bootstrap-convergence
```

**预期：** 要么通过，要么在不同地方失败（然后修那个新错误）

### 步骤 3: 逐级修复
如果第 2 步失败，重复：
```
找第一个真实错误
  ↓
修复它
  ↓
重新运行
  ↓
看下一个错误
```

---

## 学习资源快速索引

| 想学什么 | 看哪个文件 |
|---------|----------|
| Bootstrap 是什么 | doc/bootstrap-subset.md |
| 为什么现在失败 | misc/reports/b6.7.3e0b.2a-*.txt |
| 哪些特性已支持 | misc/reports/b6.7.3e0b.2c-*.md |
| 怎么修 | misc/reports/b6.7.3e0b.2d-*.md |
| 代码在哪 | src/cmd/compile/seed/semantic/analyzer.c |
| 错误信息 | 第 1282 行附近 |
| 需要加什么 | 见 e0b.2d 的"最小代码增加"部分 |

---

## 快速事实清单

```
✅ bin/s_seed 支持：参数、字符串、if、import、函数
❌ bin/s_seed 不支持：限定符名字（pkg.mod.func）

✅ import_signatures.meta 已有：所有需要的函数签名
❌ 使用这些数据的代码：不存在

✅ 修复可以：很小（~50 行），很受限（只在 bootstrap），很安全（用现有数据）
❌ 修复不能：展开成第二个编译器，或者弄成双重权威

修复用到的数据：
  import_signatures 全局变量（第 67-69 行）
  scope_lookup 函数（已有）
  AST_MEMBER_EXPR 节点（已有）
```

---

## 总结：3 个关键认识

### 1️⃣ 问题明确
S 编译器自托管卡在第一步，原因是 C 种子编译器不理解限定符名字。

### 2️⃣ 修复有界
修复不需要建立完整模块系统，只需要利用已有的签名表做查表。

### 3️⃣ 下一步清晰
如果选择继续，就是：
- 改 analyzer.c 中 50 行代码
- 运行测试看是否前进
- 如果前进了，继续修下一个错误
- 直到收敛

---

## 如果只有 10 分钟

读这个（顺序很重要）：
1. 这个文档的第 0 层 + 第 1 层（2 分钟）
2. misc/reports/b6.7.3e0b.2d-minimal-fix-boundary-audit.md 的问题 3（3 分钟）
3. 代码地图：第 2 层关键的 3 个文件（2 分钟）
4. 明白的关键点：import_signatures 已有数据，需要用它做查表（3 分钟）

这样就足够理解现状和下一步了。
