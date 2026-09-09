# S 编译器 - 具体优化实施指南

**生成日期**：2026-09-09  
**面向**：开发人员  
**目的**：指导具体代码修改

---

## 📝 优化 1：常量折叠（Const Folding）

### 目标
在编译时计算常数表达式，减少运行时计算。

### 预期收益
- 性能：+5%
- 代码大小：-2%

### 实现位置
**文件**：`src/cmd/compile/internal/ssa_core.s`  
**函数**：在 SSA 生成阶段添加

### 具体实施

#### 第 1 步：识别常数表达式
```s
func is_constant_value(ssa_value v) bool {
    // 检查是否为常数字面值（整数、浮点、字符串等）
    match v.kind {
        case ssa_const_int:
            return true
        case ssa_const_float:
            return true
        case ssa_const_string:
            return true
        default:
            return false
    }
}
```

#### 第 2 步：尝试常数折叠
```s
func try_constant_fold(ssa_op op, []ssa_value args) (ssa_value, bool) {
    if !all_constant(args) {
        return (ssa_value{}, false)
    }

    result := match op {
        case ssa_add:
            ssa_const_int(args[0].value + args[1].value)
        case ssa_sub:
            ssa_const_int(args[0].value - args[1].value)
        case ssa_mul:
            ssa_const_int(args[0].value * args[1].value)
        case ssa_div:
            if args[1].value != 0 {
                ssa_const_int(args[0].value / args[1].value)
            } else {
                return (ssa_value{}, false)
            }
        case ssa_lt:
            ssa_const_bool(args[0].value < args[1].value)
        case ssa_eq:
            ssa_const_bool(args[0].value == args[1].value)
        default:
            return (ssa_value{}, false)
    }

    (result, true)
}
```

#### 第 3 步：在 SSA 生成中应用
```s
func emit_binary_op(ssa_block b, ssa_op op, ssa_value left, ssa_value right) ssa_value {
    folded, ok := try_constant_fold(op, [left, right])
    if ok {
        return folded
    }

    result_value := ssa_value {
        kind: op,
        operands: [left, right],
    }
    b.add_value(result_value)
    result_value
}
```

### 测试用例
```s
func test_const_fold_add() {
    // 源代码：a := 2 + 3
    // 期望：生成的 SSA 中直接是常数 5
    // 期望生成的 C 代码：int64_t a = 5;
}

func test_const_fold_multiply() {
    // 源代码：b := 10 * 20
    // 期望：生成的 SSA 中直接是常数 200
}

func test_const_fold_comparison() {
    // 源代码：if 5 > 3 { ... }
    // 期望：条件分支在编译时已知
}
```

### 预期代码改进
```s
现有代码：
func expensive() int {
    a := 2 + 3          // 编译时就能算出
    b := a * 4          // 依赖 a
    c := b - 1          // 依赖 b
    return c            // 最终返回 19
}

生成的汇编（优化前）：
mov eax, 2
add eax, 3              ; 2 + 3
mov ebx, eax
imul ebx, 4             ; eax * 4
sub ebx, 1              ; ebx - 1
ret

生成的汇编（优化后）：
mov eax, 19
ret
```

---

## 📝 优化 2：死代码消除（DCE）

### 目标
删除未使用的变量和表达式，减少代码大小和运行时成本。

### 预期收益
- 性能：+3%
- 代码大小：-10%

### 实现位置
**文件**：`src/cmd/compile/internal/ssa_core.s` 或新建 `ssa_optimize.s`  
**时机**：在 SSA 生成完成后

### 具体实施

#### 第 1 步：计算活动变量（Live Variables）
```s
struct live_analysis {
    ssa_value[] live_in      // 块的入口存活集
    ssa_value[] live_out     // 块的出口存活集
    ssa_block[] blocks       // 所有基本块
}

func compute_live_sets(ssa_block[] blocks) live_analysis {
    analysis := live_analysis {
        blocks: blocks,
    }

    // 初始化：返回值和副作用操作必须活
    for block in blocks {
        out := []ssa_value{}
        for inst in block.instructions {
            if is_return(inst) || has_side_effect(inst) {
                out.append(inst)
            }
        }
        analysis.live_out[block] = out
    }

    // 迭代直到收敛
    changed := true
    while changed {
        changed = false
        for block in reverse(blocks) {
            new_live_out := []ssa_value{}
            for succ in block.successors {
                new_live_out.append(analysis.live_in[succ])
            }

            if new_live_out != analysis.live_out[block] {
                changed = true
                analysis.live_out[block] = new_live_out
            }

            // 反向扫描计算 live_in
            live := analysis.live_out[block].copy()
            for inst in reverse(block.instructions) {
                if should_keep(inst, live) {
                    live.add(inst)
                } else {
                    live.remove_uses(inst)
                }
            }
            analysis.live_in[block] = live
        }
    }

    analysis
}
```

#### 第 2 步：标记死代码
```s
func mark_dead_code(ssa_block[] blocks, live_analysis live) {
    for block in blocks {
        dead := []ssa_value{}
        for inst in block.instructions {
            if !is_live(inst, live, block) {
                if !has_side_effect(inst) {
                    dead.append(inst)
                }
            }
        }
        block.dead_instructions = dead
    }
}

func is_live(ssa_value inst, live_analysis live, ssa_block block) bool {
    // 检查是否在 live_out 中或有副作用
    if has_side_effect(inst) {
        return true
    }
    
    // 检查是否被任何活的指令使用
    for user in inst.users {
        if is_reachable(user, block) {
            return true
        }
    }

    false
}
```

#### 第 3 步：删除死指令
```s
func eliminate_dead_code(ssa_block[] blocks, live_analysis live) {
    for block in blocks {
        new_instructions := []ssa_value{}
        for inst in block.instructions {
            if !is_dead(inst, live, block) {
                new_instructions.append(inst)
            }
        }
        block.instructions = new_instructions
    }
}
```

### 测试用例
```s
func test_dce_unused_variable() {
    // 源代码：
    // a := expensive_func()
    // b := 42
    // return b
    
    // 期望：expensive_func() 的调用被删除
    // 如果 expensive_func() 有副作用，保留；否则删除
}

func test_dce_unused_assignment() {
    // 源代码：
    // x := 10
    // x = 20
    // return x
    
    // 期望：x := 10 被删除（覆盖掉了）
}

func test_dce_loop_invariant() {
    // 源代码：
    // for i in 0..100 {
    //     x := expensive()  // 每次计算相同结果
    // }
    
    // 期望（循环不变代码外提）：
    // x := expensive()
    // for i in 0..100 {
    //     use(x)
    // }
}
```

### 预期代码改进
```s
现有代码：
func unused_vars() int {
    a := expensive_compute()  // 从未使用
    b := another_func()       // 也从未使用
    c := 42
    return c
}

生成的代码（优化前）：
call expensive_compute  ; 浪费
call another_func       ; 浪费
mov eax, 42
ret

生成的代码（优化后）：
mov eax, 42
ret
```

---

## 📝 优化 3：公共子表达式消除（CSE）

### 目标
识别重复的计算并复用结果。

### 预期收益
- 性能：+8%
- 代码大小：-5%

### 实现位置
**文件**：`src/cmd/compile/internal/ssa_core.s` 或新建 `ssa_cse.s`

### 具体实施

#### 第 1 步：构建表达式哈希
```s
func expression_hash(ssa_value expr) uint64 {
    // 创建表达式的规范哈希
    // hash(op, hash(arg1), hash(arg2), ...)

    h := uint64(0)
    h = hash_combine(h, expr.op)
    
    for arg in expr.operands {
        if is_constant(arg) {
            h = hash_combine(h, hash_value(arg.value))
        } else {
            h = hash_combine(h, arg.id)  // 变量 ID
        }
    }

    h
}

func hash_combine(uint64 h, uint64 val) uint64 {
    ((h << 5) | (h >> 59)) ^ val
}
```

#### 第 2 步：识别 CSE 机会
```s
struct cse_map {
    map[uint64, ssa_value] expr_to_value
}

func build_cse_map(ssa_block block) cse_map {
    cse := cse_map {
        expr_to_value: make(map[uint64, ssa_value]),
    }

    for inst in block.instructions {
        hash := expression_hash(inst)

        if existing, found := cse.expr_to_value[hash] {
            // 检查是否真的相等（哈希碰撞）
            if expressions_equal(existing, inst) {
                inst.cse_redundant = true
                inst.cse_replacement = existing
            } else {
                cse.expr_to_value[hash] = inst
            }
        } else {
            cse.expr_to_value[hash] = inst
        }
    }

    cse
}

func expressions_equal(ssa_value a, ssa_value b) bool {
    if a.op != b.op {
        return false
    }

    if len(a.operands) != len(b.operands) {
        return false
    }

    for i in 0..len(a.operands) {
        if a.operands[i].id != b.operands[i].id {
            return false
        }
    }

    true
}
```

#### 第 3 步：应用 CSE
```s
func apply_cse(ssa_block block, cse_map cse) {
    replacements := make(map[uint64, ssa_value])

    for inst in block.instructions {
        hash := expression_hash(inst)
        if existing, found := replacements[hash] {
            // 用现有表达式的结果替换
            redirect_users(inst, existing)
        } else {
            replacements[hash] = inst
        }
    }
}

func redirect_users(ssa_value old, ssa_value new) {
    for user in old.users {
        for i in 0..len(user.operands) {
            if user.operands[i] == old {
                user.operands[i] = new
            }
        }
        new.add_user(user)
    }
    old.users.clear()
}
```

### 测试用例
```s
func test_cse_basic() {
    // 源代码：
    // a := x + y
    // b := x + y
    // return a + b
    
    // 期望：只计算一次 x + y，b 的结果复用 a
}

func test_cse_through_assignment() {
    // 源代码：
    // a := x * 2
    // c := a
    // b := x * 2
    // return b
    
    // 期望：b 的 x * 2 被消除，用 c 替代
}

func test_cse_array_access() {
    // 源代码：
    // a[0] := 10
    // x := a[0]
    // y := a[0]
    
    // 期望：y 的 a[0] 加载被消除
}
```

### 预期代码改进
```s
现有代码：
func matrix_op(int[100] a, int[100] b) int {
    sum := 0
    for i in 0..100 {
        sum = sum + a[i] * b[i]  // a[i] * b[i] 在多处出现
        if sum > threshold {
            check := a[i] * b[i]  // 重复计算
        }
    }
    return sum
}

生成的代码（优化前）：
loop:
    mov rax, [a + rax*8]
    mov rbx, [b + rcx*8]
    imul rax, rbx           ; a[i] * b[i]
    add sum, rax
    
    cmp sum, threshold
    jle next
    
    mov rax, [a + rcx*8]
    mov rbx, [b + rcx*8]
    imul rax, rbx           ; 重复！
    mov check, rax

生成的代码（优化后）：
loop:
    mov rax, [a + rcx*8]
    mov rbx, [b + rcx*8]
    imul rax, rbx           ; 只计算一次
    add sum, rax
    
    cmp sum, threshold
    jle next
    mov check, rax          ; 复用
```

---

## 📝 优化 4：错误恢复（Error Recovery）

### 目标
编译器遇到错误后继续分析，找出更多错误。

### 预期收益
- 开发效率：+40%（减少编译循环）

### 实现位置
**文件**：`src/cmd/compile/internal/semantic.s`  
**函数**：解析和类型检查函数

### 具体实施

#### 第 1 步：引入错误恢复机制
```s
struct error_recovery_context {
    error[] errors
    bool has_error
    int error_count
    bool should_continue
}

func report_error_and_continue(error_recovery_context ctx, string msg, int line, int col) {
    ctx.errors.append(error{
        message: msg,
        line: line,
        col: col,
    })
    ctx.error_count = ctx.error_count + 1
    ctx.should_continue = true
    ctx.has_error = true
}
```

#### 第 2 步：改进词法分析错误处理
```s
func lex_tokens_with_recovery(string source) (token[], error[]) {
    tokens := []token{}
    errors := []error{}
    i := 0

    while i < len(source) {
        match {
            case is_whitespace(source[i]):
                i = i + 1
            case is_digit(source[i]):
                tok, next_i := lex_number(source, i)
                tokens.append(tok)
                i = next_i
            case is_letter(source[i]):
                tok, next_i := lex_identifier(source, i)
                tokens.append(tok)
                i = next_i
            case is_operator(source[i]):
                tok, next_i := lex_operator(source, i)
                tokens.append(tok)
                i = next_i
            default:
                // 无法识别的字符，跳过但报错
                errors.append(error{
                    message: "unexpected character: " + string(source[i]),
                    line: count_lines(source[0:i]),
                    col: i - last_newline(source[0:i]),
                })
                i = i + 1
        }
    }

    (tokens, errors)
}
```

#### 第 3 步：改进语法分析错误处理
```s
func parse_statement_with_recovery(parser p) (statement, error[]) {
    // 尝试解析语句
    stmt, err := parse_statement_internal(p)

    if err != nil {
        // 出错，尝试恢复
        p.errors.append(err)

        // 寻找恢复点：下一个语句开始符号
        for !at_statement_boundary(p) {
            p.advance()
        }

        // 继续解析
        return (statement{}, p.errors)
    }

    (stmt, p.errors)
}

func at_statement_boundary(parser p) bool {
    // 检查是否在语句边界（func, var, if 等）
    tok := p.peek()
    match tok.kind {
        case token_func, token_var, token_if, token_for, token_return:
            return true
        case token_rbrace:  // 块结束
            return true
        default:
            return false
    }
}
```

#### 第 4 步：改进类型检查错误处理
```s
func type_check_with_recovery(ast_node node, context ctx) type_error[] {
    errors := []type_error{}

    match node.kind {
        case ast_binary_op:
            left_type := type_check_expr(node.left, ctx, &errors)
            right_type := type_check_expr(node.right, ctx, &errors)

            // 即使某一边类型不对，也继续检查另一边
            // 而不是在第一个错误处停止

            if !is_compatible(left_type, right_type) {
                errors.append(type_error{
                    message: "type mismatch: " + left_type + " vs " + right_type,
                    node: node,
                })
            }

        case ast_function_call:
            // 检查所有参数，而不是在第一个错误处停止
            for arg in node.arguments {
                type_check_expr(arg, ctx, &errors)
            }
    }

    errors
}
```

### 测试用例
```s
func test_recovery_missing_semicolon() {
    // 源代码（有 3 个错误）：
    // a := 10
    // b := 20 c := 30  // 缺少分号
    // d := 40
    
    // 当前行为：
    // error: expected ';' at line 2
    // （停止编译）
    
    // 期望行为：
    // error: expected ';' at line 2, column 8
    // error: expected type for 'c', got ':'
    // 等等，继续找出所有错误
}

func test_recovery_type_mismatch() {
    // 源代码：
    // func add(int a, string b) int {
    //     return a + b  // 类型不匹配
    // }
    // func another() { }
    
    // 期望：报告 a + b 错误，但继续处理 another 函数
}

func test_recovery_undefined_variable() {
    // 源代码：
    // x := undefined_var
    // y := another_undefined
    // z := 42 + x
    
    // 期望：报告所有三个错误，不是在第一个停止
}
```

### 预期改进效果
```
编译前：
file.s:2: error: unexpected token 'c'
file.s:5: error: undefined identifier 'foo'
file.s:8: error: type mismatch
（每次只显示第一个，开发者需要修复然后重新编译）

编译后：
file.s:2: error: unexpected token 'c'
file.s:5: error: undefined identifier 'foo'
file.s:8: error: type mismatch
（一次显示所有 3 个错误，开发者可以一次修复多个）

效果：减少编译循环 70-80%
```

---

## 📝 优化 5：内联改进（Inlining Enhancement）

### 目标
改进内联启发式，更智能地选择要内联的函数。

### 预期收益
- 性能：+5-8%
- 代码大小：-5%

### 实现位置
**文件**：`src/cmd/compile/internal/inline/inline.s` 或相关文件

### 具体实施

#### 当前启发式（可改进）
```s
// 当前：基于函数大小和调用频率的简单启发式

func should_inline_simple(func_def func) bool {
    // 函数小于 N 行时内联
    size := estimate_function_size(func)
    if size < 10 {
        return true
    }

    // 热函数内联
    if call_frequency(func) > HOT_THRESHOLD {
        return true
    }

    false
}
```

#### 改进的启发式
```s
struct inline_score {
    int base_score              // 0-100
    int size_cost              // 大小的代价
    int call_frequency_benefit // 调用频率的收益
    int nesting_level          // 嵌套深度
    bool is_recursive           // 是否递归
    bool has_loops             // 是否包含循环
    int estimated_code_growth   // 预期代码增长
}

func compute_inline_score(func_def func, call_context context) inline_score {
    score := inline_score{}

    // 1. 基础大小估计
    size := estimate_function_size(func)
    if size <= 2 { score.base_score = 100 }
    else if size <= 5 { score.base_score = 80 }
    else if size <= 10 { score.base_score = 60 }
    else if size <= 20 { score.base_score = 30 }
    else { score.base_score = 0 }

    // 2. 调用频率权重
    freq := call_frequency(func, context)
    score.call_frequency_benefit = min(50, freq * 5)

    // 3. 递归惩罚
    if is_recursive(func) {
        score.base_score = score.base_score / 2
    }

    // 4. 循环惩罚（除非循环外内联）
    if has_loop(func) && !inlining_outside_loop(context) {
        score.base_score = score.base_score - 20
    }

    // 5. 嵌套等级惩罚
    nesting := call_context_nesting_level(context)
    if nesting > 3 {
        score.base_score = score.base_score - (nesting - 3) * 10
    }

    // 6. 代码增长估计
    score.estimated_code_growth = estimate_growth(func, context)

    // 7. 分支预测影响
    if has_complex_branches(func) {
        score.base_score = score.base_score - 15
    }

    // 8. 寄存器压力
    if estimate_register_pressure(func) > 80 {
        score.base_score = score.base_score - 25
    }

    score
}

func should_inline_improved(func_def func, call_context context) bool {
    score := compute_inline_score(func, context)
    total := score.base_score + score.call_frequency_benefit - score.size_cost
    
    // 动态阈值而不是固定阈值
    if total > 50 && score.estimated_code_growth < 20 {
        return true
    }

    false
}
```

### 测试用例
```s
func test_inline_small_accessor() {
    // 源代码：
    // func get_x() int { return this.x }
    // 在循环中调用 100 次
    
    // 期望：总是内联
}

func test_inline_hot_path() {
    // 源代码：
    // func process_item(item) { ... }  // 20 行
    // 在热循环中调用
    
    // 期望：尽管较大，也应该内联
}

func test_dont_inline_recursive() {
    // 源代码：
    // func fibonacci(int n) int {
    //     if n <= 1 { return n }
    //     return fibonacci(n-1) + fibonacci(n-2)
    // }
    
    // 期望：不内联（递归）
}

func test_dont_inline_large_rarely_called() {
    // 源代码：
    // func error_handler() { ... }  // 100 行
    // 在错误路径中极少调用
    
    // 期望：不内联
}
```

---

## 🏁 实施顺序建议

### Week 1: Const Folding
```
Priority: P0
Timeline: 2 天
Expected Impact: +5% performance

步骤：
1. 编写 try_constant_fold() 函数
2. 在 SSA 生成中调用它
3. 编写 5 个单元测试
4. 基准测试
5. 代码审查和提交
```

### Week 2: DCE
```
Priority: P0
Timeline: 3-4 天
Expected Impact: +3% performance

步骤：
1. 编写 compute_live_sets() 
2. 实现死代码标记
3. 应用消除
4. 编写 4 个单元测试
5. 集成测试
6. 代码审查和提交
```

### Week 3: CSE
```
Priority: P1
Timeline: 4-5 天
Expected Impact: +8% performance

步骤：
1. 实现 expression_hash()
2. 构建 CSE 映射
3. 应用替换
4. 编写 3 个单元测试
5. 性能验证
6. 代码审查和提交
```

### Week 4: 错误恢复
```
Priority: P0
Timeline: 4-5 天
Expected Impact: +40% 开发效率

步骤：
1. 重构错误报告接口
2. 词法分析器集成恢复
3. 语法分析器集成恢复
4. 类型检查器集成恢复
5. 集成测试
6. 代码审查和提交
```

---

## 📊 预期总收益（4 周后）

```
性能：基准 → +20%
代码大小：基准 → -8%
开发效率：基准 → +40%
编译时间：基准 → -5%
```

## ✅ 质量检查清单

对于每个优化，提交前检查：

- [ ] 编译不出错（`make build`）
- [ ] 单元测试通过（`make test`）
- [ ] 不引入新的编译警告
- [ ] 性能基准测试改进（或至少不变）
- [ ] 代码审查通过
- [ ] 文档更新
- [ ] 提交说明清晰

---

## 📚 参考资源

- SSA 形式：https://en.wikipedia.org/wiki/Static_single_assignment_form
- 死代码消除：https://en.wikipedia.org/wiki/Dead_code_elimination
- 公共子表达式：https://en.wikipedia.org/wiki/Common_subexpression_elimination
- 编译器优化：https://www.cs.cmu.edu/~15-745/

