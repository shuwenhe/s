# S 编译器自举诊断计划

**创建日期**: 2026-09-02  
**目的**: 确定 S 编译器当前卡在哪个 Bootstrap Gate  
**时间**: 2-3 小时

---

## Phase 1: 运行诊断并收集日志 (30 分钟)

### Step 1.1: 清理并完整编译

```bash
cd /home/shuwen/shuwen/s
make clean
make bootstrap-stage0 2>&1 | tee /tmp/stage0.log

# 查看 stage0 是否成功
echo "Stage 0 exit code: $?"
wc -l /tmp/stage0.log
```

**预期结果**:
- 如果 Stage 0 编译失败 → 问题在 **Gate A (Language Closure)** 或 **Gate B (Frontend)**
- 如果 Stage 0 编译成功 → 继续 Stage 1

### Step 1.2: Stage 1 编译 (如果 Stage 0 成功)

```bash
cd /home/shuwen/shuwen/s
make bootstrap-stage1 2>&1 | tee /tmp/stage1.log

# 检查失败
tail -100 /tmp/stage1.log | grep -E "error|ERROR|Error|FAIL|failed"
```

**预期结果**:
- 失败 → 问题在 **Gate B/C/D/E**
- 成功 → 继续 Stage 2

### Step 1.3: Stage 2 运行 (关键诊断)

```bash
cd /home/shuwen/shuwen/s
./bin/s-stage1 --version 2>&1
./bin/s-stage1 compile internal/syntax/lexer.s 2>&1 | head -50
```

**预期结果**:
- 崩溃 (SIGSEGV/SIGABRT) → **Gate D/E/F** 的 ABI 或寄存器分配问题
- 编译错误 → **Gate C** 的 Typed IR 问题
- 编译成功但输出错误 → **Gate G** 的指令生成问题

---

## Phase 2: 各 Gate 的诊断工具 (1 小时)

### 诊断 Gate A: Language Closure

文件: `tools/diagnose_gate_a.s`

```s
// 测试最基本的编译能力
package test

func main() {
    x := 10
    y := 20
    z := x + y
}
```

运行:
```bash
./bin/s-stage1 compile tools/diagnose_gate_a.s 2>&1
echo "Exit code: $?"
```

**症状和对应**:
- `undefined identifier` → 缺少 symbol table
- `unknown type` → 缺少 type system
- `syntax error` → Parser 问题
- 成功 → 继续 Gate B

---

### 诊断 Gate B: Frontend Closure

文件: `tools/diagnose_gate_b.s`

```s
package test

struct point {
    int x
    int y
}

func add_points(p1: point, p2: point) point {
    return point { x: p1.x + p2.x, y: p1.y + p2.y }
}

func main() {
    a := point { x: 1, y: 2 }
    b := point { x: 3, y: 4 }
    c := add_points(a, b)
}
```

**症状和对应**:
- `struct not recognized` → Struct 类型系统缺失
- `method resolution failed` → 方法绑定缺失
- `type mismatch` → 类型推导缺失
- 成功编译但崩溃 → 继续 Gate C

---

### 诊断 Gate C: Typed IR Closure

文件: `tools/diagnose_gate_c.s`

```s
package test

func allocate() (int, string) {
    return 42, "hello"
}

func process() {
    v, err := allocate()
    // 验证多返回值 IR 是否正确构造
}
```

**症状和对应**:
- `multiple return values not supported` → IR 不支持多返回
- `unhandled IR node type` → IR 节点类型不完整
- 成功编译但代码错误 → 继续 Gate D

---

### 诊断 Gate D: ABI Closure (最关键)

文件: `test/abi/test_runner.s`

创建系列测试:

#### D1: 基本参数传递

```s
package test

func add_int(a: int, b: int) int {
    return a + b
}

func main() {
    result := add_int(5, 7)
    // expected: 12 in RAX
}
```

验证:
```bash
./bin/s-stage1 compile test/abi/d1.s -emit-asm
grep -E "mov.*rdi|mov.*rsi|call" d1.s | head -20
```

**预期汇编**:
```asm
mov    $0x5, %rdi        ; 第一个参数在 RDI
mov    $0x7, %rsi        ; 第二个参数在 RSI
call   add_int
mov    %rax, %rbx        ; 返回值在 RAX
```

**症状**:
- 参数不在正确寄存器 → ABI 实现错误
- 返回值放错位置 → ABI 返回值处理错误
- 栈溢出 → 栈帧布局错误

#### D2: 多参数

```s
func six_args(a: int, b: int, c: int, d: int, e: int, f: int) int {
    return a + b + c + d + e + f
}
```

**预期**: 前 6 个参数在 RDI, RSI, RDX, RCX, R8, R9；结果在 RAX

#### D3: 栈参数 (>6 参数)

```s
func seven_args(a: int, b: int, c: int, d: int, e: int, f: int, g: int) int {
    return a + b + c + d + e + f + g
}
```

**预期**: 第 7 个参数在栈上 [RSP+8]

#### D4: 多返回值

```s
func divide(a: int, b: int) (int, int) {
    return a / b, a % b
}

func main() {
    q, r := divide(17, 5)
    // q 在 RAX，r 在 RDX
}
```

#### D5: Struct 参数

```s
struct pair { int x; int y }

func sum_pair(p: pair) int {
    return p.x + p.y
}
```

**预期**: struct 按值传递（RDI 中的第一个字，RSI 中的第二个字，或全在 RDI）

#### D6: String 参数

```s
func concat(s1: string, s2: string) string {
    // s1 = (RDI data, RSI len)
    // s2 = (RDX data, RCX len)
}
```

#### D7: 两字值 ABI

```s
func slice_ops(s: []int) int {
    // s = (data, len, cap)
    // data 在 RDI，len 在 RSI，cap 在 RDX
    return len(s)
}
```

---

### 诊断 Gate E: Runtime Closure

文件: `tools/diagnose_gate_e.s`

```s
package test

func test_malloc() {
    ptr := malloc(1024)
    free(ptr)
}

func test_string() {
    s := "hello"
    println(s)  // 调用 runtime
}

func main() {
    test_malloc()
    test_string()
}
```

**症状**:
- `malloc not defined` → Runtime 库缺失
- SIGSEGV in malloc → 内存管理破损
- Wrong output → 字符串处理错误

---

### 诊断 Gate F: Stage2 Executable

文件: `tools/diagnose_gate_f.s`

```s
package main

func fib(n: int) int {
    if n <= 1 { return n }
    return fib(n-1) + fib(n-2)
}

func main() {
    result := fib(10)
    println(result)
}
```

运行:
```bash
./bin/s-stage1 compile tools/diagnose_gate_f.s -o /tmp/test
/tmp/test
# 预期输出: 55
```

**症状**:
- 编译失败 → Gate E 不完整
- SIGSEGV at runtime → 指令生成或寄存器分配错误
- 错误的数字 → 算术指令错误
- 无输出 → syscall/println 错误

---

### 诊断 Gate G: Stage2 → Stage3

文件: `tools/diagnose_gate_g.sh`

```bash
# 用 stage1 编译编译器本身的一个子模块
./bin/s-stage1 compile internal/syntax/lexer.s -o lexer.o 2>&1 | tee /tmp/gate_g.log

# 检查:
# - 编译是否完成
# - 输出文件是否生成
# - 是否有未定义符号
nm lexer.o 2>&1 | grep " U " | head -10
```

**症状**:
- 编译失败 → Gate F 不完整
- 大量未定义符号 → 链接信息缺失
- 过慢（>30s） → 优化问题，不是阻塞问题

---

## Phase 3: 创建综合诊断脚本 (30 分钟)

文件: `tools/full_diagnostic.sh`

```bash
#!/usr/bin/env bash

set -e

RESULTS="/tmp/diagnostic_results.txt"
> "$RESULTS"

echo "=== S 编译器诊断 ===" >> "$RESULTS"
echo "时间: $(date)" >> "$RESULTS"
echo "" >> "$RESULTS"

run_test() {
    local name=$1
    local file=$2
    local expected=$3
    
    echo -n "[$name] ... " | tee -a "$RESULTS"
    
    if ./bin/s-stage1 compile "$file" 2>&1 | grep -q "$expected"; then
        echo "✓ PASS" | tee -a "$RESULTS"
        return 0
    else
        echo "✗ FAIL" | tee -a "$RESULTS"
        return 1
    fi
}

# Gate A
echo "== Gate A: Language Closure ==" | tee -a "$RESULTS"
run_test "basic_vars" "tools/diagnose_gate_a.s" "success" || echo "🔴 Gate A FAILED" >> "$RESULTS"

# Gate B
echo "== Gate B: Frontend Closure ==" | tee -a "$RESULTS"
run_test "struct_types" "tools/diagnose_gate_b.s" "success" || echo "🔴 Gate B FAILED" >> "$RESULTS"

# Gate C
echo "== Gate C: Typed IR Closure ==" | tee -a "$RESULTS"
run_test "multi_return" "tools/diagnose_gate_c.s" "success" || echo "🔴 Gate C FAILED" >> "$RESULTS"

# Gate D (ABI) - 多个子测试
echo "== Gate D: ABI Closure ==" | tee -a "$RESULTS"
run_test "basic_params" "test/abi/d1.s" "success" || echo "🔴 Gate D.1 FAILED" >> "$RESULTS"
run_test "six_params" "test/abi/d2.s" "success" || echo "🔴 Gate D.2 FAILED" >> "$RESULTS"
run_test "stack_params" "test/abi/d3.s" "success" || echo "🔴 Gate D.3 FAILED" >> "$RESULTS"

# Gate E
echo "== Gate E: Runtime Closure ==" | tee -a "$RESULTS"
run_test "malloc_free" "tools/diagnose_gate_e.s" "success" || echo "🔴 Gate E FAILED" >> "$RESULTS"

# Gate F
echo "== Gate F: Stage2 Executable ==" | tee -a "$RESULTS"
if ./bin/s-stage1 compile tools/diagnose_gate_f.s -o /tmp/test 2>&1 && /tmp/test | grep -q "55"; then
    echo "✓ Gate F PASS" | tee -a "$RESULTS"
else
    echo "🔴 Gate F FAILED" | tee -a "$RESULTS"
fi

# Gate G
echo "== Gate G: Stage2 → Stage3 ==" | tee -a "$RESULTS"
if ./bin/s-stage1 compile internal/syntax/lexer.s -o lexer.o 2>&1; then
    echo "✓ Gate G PASS" | tee -a "$RESULTS"
else
    echo "🔴 Gate G FAILED" | tee -a "$RESULTS"
fi

echo ""
echo "=== 诊断结果 ==="
cat "$RESULTS"
```

---

## 预期诊断矩阵

基于我们的分析，预期结果应该是:

| Gate | 功能 | 预期状态 | 诊断方法 |
|------|------|---------|---------|
| **A** | 基本编译 | ✓ 大概通过 | syntax 错误数量 |
| **B** | Struct/类型系统 | ⚠️ 部分通过 | 类型识别错误 |
| **C** | Typed IR | ⚠️ 部分通过 | IR 节点错误 |
| **D** | ABI 完整 | 🔴 很可能失败 | 寄存器/栈异常 |
| **E** | Runtime | 🔴 可能失败 | malloc/syscall 错误 |
| **F** | 可执行性 | 🔴 很可能失败 | SIGSEGV 或错结果 |
| **G** | 自举 | 🔴 预期失败 | 编译器输入可能成功，但依然有 bug |

---

## 如果诊断失败怎么办？

### 如果在 Gate A 失败

问题: Parser 或 symbol table 坏

行动:
1. 运行简单的单语句编译
2. 检查 `src/cmd/compile/internal/syntax/lexer.s`
3. 验证 token 生成是否正确

### 如果在 Gate D 失败

问题: **这是最可能的** - ABI 不完整

行动:
1. 生成汇编: `./bin/s-stage1 compile test.s -emit-asm`
2. 检查: 参数是否在 RDI/RSI/RDX
3. 检查: 返回值是否在 RAX
4. 检查: RSP 对齐是否正确

### 如果在 Gate E 失败

问题: Runtime 库缺失或损坏

行动:
1. 检查 `src/runtime/` 是否存在
2. 验证 malloc/free 是否编译
3. 测试 syscall 是否工作

### 如果在 Gate F 失败

问题: 指令生成或寄存器分配错

行动:
1. 编译简单函数并检查汇编
2. 运行 GDB 调试: `gdb -x ./bin/s-stage1`
3. 检查栈帧是否正确

---

## 立即行动清单

- [ ] 清理 build
- [ ] 运行 `make bootstrap-stage0`，记录完整日志
- [ ] 如果成功，运行 `make bootstrap-stage1`
- [ ] 如果成功，运行 `./bin/s-stage1 --version`
- [ ] 创建 `tools/diagnose_gate_*.s` 测试文件
- [ ] 运行诊断脚本
- [ ] **记录第一个失败的 Gate**
- [ ] 为该 Gate 创建 minimal repro
- [ ] 在 Go 编译器中找对应功能作为参考

---

## 时间表

- **现在**: 运行 Stage 0/1 诊断 (15 min)
- **10 分钟后**: 创建 Gate 诊断文件 (30 min)
- **40 分钟后**: 运行完整诊断脚本 (15 min)
- **55 分钟后**: 有一个明确的故障点和行动计划

总耗时: ~1 小时，获得明确的修复方向。

