# Phase 1.6.3 Blocker - Upgraded Definition

## Previous Error (Insufficient)

原始定义只关注"语法识别"：
```
Collect binding names but do NOT do semantic resolution
Names are syntactically recognized but not looked up
```

❌ **问题**: 这只是识别 `x := 17`，然后跳过。但:
- 最小 FAIL case 中 `return x` 必须知道 `x == 17`
- 不生成正确的 native 代码，无法验证执行结果
- 允许 fake-green：编译通过，但 exit code 错误

## Corrected Definition: Source-Dependent Execution

Phase 1.6.3 的真实目标不是"识别语法"，而是**"本地绑定影响执行结果"**：

```
local-variable-binding
        +
local-variable-reference
        +
source-dependent execution
```

### 严格的证明标准

**PASS**: 编译 + 执行结果匹配源码常量

❌ FAIL case 1: `func main() int { x := 17; return x }` 返回错误 exit code
❌ FAIL case 2: `func main() int { x := 29; return x }` 返回错误 exit code  
❌ FAIL case 3: `func main() int { x := 17; y := x; return y }` 返回错误 exit code

**✅ PASS**: 所有 exit code 都与源码一致
```
delta-010: x := 17; return x      → exit 17
delta-011: x := 29; return x      → exit 29
delta-012: x := 17; y := x; return y → exit 17
delta-013: x := 99; y := x; return y → exit 99
```

这防止了 "fake-green"：必须真正通过 `local binding → reference → native value` 链路。

## Implementation Scope (Strictly Limited)

✅ **MUST DO**:
```
✓ identifier := <simple-expression>
✓ 保存 local binding (x → 17, y → 29, ...)
✓ expression 中读取 local identifier
✓ 多条简单 binding (x := 17; y := 29)
✓ binding chain (x := 17; y := x; return y)
✓ 最终 return expression 中使用本地变量
✓ 生成正确代码使 native exit code 反映源值
```

❌ **DO NOT DO** (even if canonical source needs it):
```
✗ type inference system (beyond simple int literals)
✗ scopes/shadowing
✗ mutable assignment (x = 17 reassignment)
✗ control flow (if/for blocks with locals)
✗ qualified imported symbols (std.env.args())
✗ production symbol table or type checker
✗ function call evaluation (even simple ones)
```

## Canonical Blocker Origin

```
func main() int {
    args := std.env.args()    ← byte 530
```

Note: Phase 1.6.3 is NOT about solving `std.env.args()` yet.
Phase 1.6.3 only solves the already-proven minimal case:
```
x := <literal>;
return x;
```

Whether `std.env.args()` becomes Phase 1.6.4 blocker depends on canonical 
compilation after 1.6.3 is implemented.

## Test Infrastructure

### Execution Verification Gate
File: `misc/scripts/stage1-local-binding-execution-check.sh`

Tests:
```
delta-003: return 0            → exit 0     ✅ (baseline, already works)
delta-009: return 42           → exit 42    ✅ (baseline, already works)
delta-010: x := 17; return x   → exit 17    ⏳ (will FAIL until 1.6.3)
delta-011: x := 29; return x   → exit 29    ⏳ (will FAIL until 1.6.3)
delta-012: x := 17; y := x; return y → exit 17 ⏳ (binding chain)
delta-013: x := 99; y := x; return y → exit 99 ⏳ (binding chain variant)
```

Each test:
1. Compile via stage1
2. Execute the binary
3. Verify exit code matches expected value
4. FAIL if any mismatch

This proves bootstrap_subset generates code that truly reflects source values.

## Implementation Sequence (Strict Order)

1. **Create gate (already done)**
   - `stage1-local-binding-execution-check.sh` ready
   - Fixtures ready (delta-010 through delta-013)

2. **Run gate baseline (MUST RED)**
   ```
   bash misc/scripts/stage1-local-binding-execution-check.sh \
     .bootstrap/modular/s_modular-stage1
   ```
   Expected: delta-010, 011, 012, 013 all FAIL (gate RED)

3. **Implement minimum capability in bootstrap_subset.c**
   - Add local binding storage structure
   - Modify bs_unit() to save bindings from `:=` statements
   - Modify bs_expression() to lookup local identifiers
   - Ensure generated C code uses correct local variable values

4. **Run gate verification (MUST GREEN)**
   ```
   bash misc/scripts/stage1-local-binding-execution-check.sh \
     .bootstrap/modular/s_modular-stage1
   ```
   Expected: All 6 tests PASS

5. **Also verify baseline gates remain GREEN**
   ```
   bash misc/scripts/stage1-import-carry-check.sh ...
   bash misc/scripts/canonical-bootstrap-capability-check.sh ...
   ```

6. **Commit Phase 1.6.3**
   ```
   git commit -m "Phase 1.6.3: local-variable-binding with source-dependent execution

   Implements minimal binding semantics in bootstrap_subset.c:
   - Local variable declaration: identifier := expression
   - Local variable reference: use identifier in return expression
   - Source-dependent execution: different values → different exit codes
   
   Gate: stage1-local-binding-execution-check.sh (6 tests, all PASS)
   Constraints: no scope, no type inference, no control flow
   Frozen: all other bootstrap_subset.c behavior from Phase 1.6.1-2
   "
   ```

7. **Identify Phase 1.6.4 blocker**
   ```
   bash misc/scripts/canonical-bootstrap-capability-check.sh \
     .bootstrap/modular/s_modular-stage1 \
     .bootstrap/modular/canonical-closure.txt \
     .bootstrap/modular/phase-1-6-4-check
   ```
   Expected: canonical compilation progresses past byte 530
   New error: next real blocker (likely qualified calls or imports)

## Why This Matters

### Prevents Fake Green
Before this definition: Gate could pass by just recognizing syntax.
After this definition: Gate PROVES semantic impact by checking runtime values.

### Maintains Authority
Phase 1.5 established: "Let canonical source drive blocker identification"
Phase 1.6.3 must obey: "Let concrete execution prove semantic correctness"

### Enables Progressive Verification
If delta-010 through delta-013 all PASS with correct exit codes, then:
- Binding works ✅
- Reference works ✅
- Multiple bindings work ✅
- Binding chains work ✅
- Generated code matches semantics ✅

Then move to Phase 1.6.4 with high confidence in bootstrap_subset.

## Next: Implementation

Ready to implement when authorized. Bootstrap_subset.c changes will be minimal:
- Add local binding map (identifier → value)
- Modify statement parsing to capture bindings
- Modify expression evaluation to lookup local identifiers
- Ensure generated C emits correct values
