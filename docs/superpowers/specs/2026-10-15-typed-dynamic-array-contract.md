# S `T[]` 静态类型与 Typed IR 构造契约

状态：第六版设计草案，未批准实现

范围：动态数组 `T[]` 与空构造 `T[]()`。固定长度数组 `T[N]`、`vec[T]`、Runtime/Backend 实现修改不在本设计范围内。

## 1. 类型规范化

S 的动态数组类型只有一种语义表示：

```text
T[]
```

其中 `T` 是元素类型。实现内部必须使用唯一规范形式，不能同时把 `[]T`、`T[]` 或通用 `array` 当作等价的权威类型表示。

最低要求：

- `canonical_type(T[]) = T[]`；
- `element_type(T[]) = T`；
- `array_kind(T[]) = dynamic`；
- 元素类型必须是已知的合法 S 类型；
- `T[N]` 不得在本契约中被隐式转换为 `T[]`；
- 未知类型、缺失元素类型和非法嵌套类型必须产生诊断。

`array` 可以作为尚未类型化的中间状态，但不能作为通过类型检查后的结果类型。

### 1.1 唯一内部表示

契约层的权威表示为结构化类型对象：

```text
ArrayType {
    kind: dynamic_array
    element: Type
}
```

`T[]` 是其源码和诊断格式。`[]T` 只能作为兼容输入形式（若语法层仍产生该形式），进入类型规范化后必须立即转换为同一个 `ArrayType(dynamic_array, T)`。字符串 `"array"` 只允许表示未类型化的旧中间状态，不能进入通过验证的 Typed IR。

类型相等规则：

```text
equal(T[], T[]) = equal(T, T)
equal(T[], U[]) = false            if T != U
equal(T[N], T[]) = false
```

本契约不引入数组协变，也不定义 `T[N]` 与 `T[]` 的隐式转换。

## 2. 构造表达式

```s
int[] values = int[]()
```

`T[]()` 是动态数组构造表达式，不是普通函数调用。

语义规则：

- 调用目标必须表示一个合法元素类型 `T`；
- 构造参数数量必须为零；
- `type_of(T[]()) = T[]`；
- `length(T[]()) = 0`；
- 构造结果是独立的动态数组值；
- 构造结果可作为变量初值、函数参数、函数返回值和结构体字段值；
- `T[N]()` 不由本契约自动支持；
- `value[]()`、未知类型或带参数构造必须被拒绝。

AST 可以继续使用现有 `CALL_EXPR(INDEX_EXPR)` 形状，但 Semantic 必须先确认它是数组类型构造，再绕过普通“callee 必须为标识符”的函数调用规则。不能仅凭 `INDEX_EXPR` 节点种类判定构造语义。

### 2.1 AST 消歧规则

`CALL_EXPR(INDEX_EXPR)` 只有同时满足以下条件时，才可解释为数组构造：

1. `INDEX_EXPR` 的类型语法部分能规范化为元素类型 `T`；
2. 类型解析确认该部分是类型，而不是值表达式或可调用符号；
3. 后缀表示为空动态数组构造，而不是运行时索引表达式；
4. 参数列表为空。

如果左侧解析为变量、函数返回值或普通表达式，则按普通索引/调用语义处理，不得转成 `array_new`。消歧失败时应报告“数组构造需要合法元素类型”或“该表达式不是可调用目标”，不能继续使用含糊的通用数组类型。

### 2.2 类型和值命名空间

类型名和运行时值名属于分离的命名空间：

- `T[]()` 的 `T` 必须在类型上下文中解析；
- 局部值绑定不得遮蔽类型绑定；
- 若同一拼写同时存在类型名和值名，类型上下文选择类型绑定，值上下文选择值绑定；
- `a[i]()` 首先按普通索引结果调用处理；若索引结果类型不可调用，产生静态类型错误；
- 若 `a` 在类型上下文不存在，不能把 `a[i]()` 猜测为数组构造；
- 类型解析失败、索引结果不可调用和构造参数错误必须产生不同的诊断类别。

## 3. Typed IR

建议的逻辑操作为：

```text
array_new
    result_type = T[]
    element_type = T
    length = 0
```

`array_new` 是拟议操作名，不代表当前代码中已经存在该 IR 指令。

### 3.1 `array_new` 字段

逻辑字段必须明确为：

```text
array_new {
    result: ValueId
    result_type: ArrayType(dynamic_array, T)
    element_type: Type(T)
    length: ConstantInt(0)
}
```

`result_type` 是验证权威，`element_type` 是便于验证和 Backend 消费的冗余投影；两者不一致必须拒绝。`length` 在本构造中只能为零，运行时扩容不改变静态 `ArrayType`。

IR 不变量：

- `result_type` 必须是规范化的 `T[]`；
- `element_type` 必须等于 `result_type` 的元素类型；
- `length` 为常量零；
- 不能用无类型 `array` 替代 `T[]`；
- 不能将 `T[]()` 降低为普通函数调用或 `vec` 操作；
- 后续 `array_index_get`、`array_index_set`、参数传递和返回值必须引用同一静态数组类型；
- IR 验证器必须拒绝元素类型不匹配的写入、调用和返回。

如果现有字符串式 MIR 暂时承载类型，则至少要保证类型字段同时保存 `T[]`，而不是只保存 `array`。长期实现应使用结构化数组类型，而不是让 Backend 重新解析字符串猜测元素类型。

## 4. 函数边界与数组操作

函数签名示例：

```s
func make_values() int[]
func consume(int[] values) int
```

必须验证：

- 实参类型与参数 `T[]` 完全匹配；
- 返回表达式类型与返回签名 `T[]` 完全匹配；
- `U[]` 不能隐式传给 `T[]`，除非未来语言规范明确规定协变规则；
- 数组赋值保持元素类型；
- 索引读取结果类型为 `T`；
- 索引写入值类型必须为 `T`；
- 空数组经过参数传递和返回后仍保持静态类型 `T[]`；
- 数组长度是运行时值，但不改变静态元素类型。

### 4.1 值语义与所有权

本契约采用值语义作为可观察语义，并规定以下边界行为：

- 数组赋值执行深拷贝等价语义，修改副本不得改变原数组；
- 参数传递执行 Copy 语义，函数内部修改参数不得改变调用方数组；
- 函数返回执行值转移语义；转移是实现优化，调用方观察到的结果必须等价于独立返回值；
- 普通 Move 仅发生在语言明确规定转移的位置；Move 后源绑定在可达路径上不可再读、写或作为参数使用；
- 普通 Copy 不消耗源绑定，Copy 后源值保持有效并可再次读取；
- 赋值表达式默认采用 Copy，除非语言语法明确标记转移；
- 返回表达式 `return a` 是函数返回边界上的 Move；返回前对 `a` 的合法读取不构成 use-after-move；
- 返回后源局部值不会再次被语言程序观察，Backend 不得暴露可用的悬空 moved-from 值；
- `return a` 会在返回边界转移 `a` 的所有权；返回语句后的语句按 S 既有不可达代码规则处理，不得把该规则替代 use-after-move 检查；
- 在可达路径上读取已被 Move 的变量必须产生静态诊断；
- 若实现采用共享底层存储，必须有明确的复制/写时复制规则；
- 扩容不得使已有数组值中的元素引用失效；
- 嵌套数组和结构体数组必须递归遵守相同规则；
- `T[]()` 每次求值产生独立的零长度数组，不得共享可变全局容器。

递归 Copy 规则：

- 数组元素按元素自身类型的 Copy 规则递归复制；
- 嵌套数组复制后，修改副本的任意嵌套元素不得改变原数组；
- 结构体数组复制时，各字段按字段类型递归复制；
- 字符串保持独立的可观察值语义，允许内部共享不可变存储；
- 若元素类型不可复制，数组赋值、参数 Copy 和对应返回操作必须在静态检查阶段拒绝，不能静默退化为浅引用。

深拷贝可以由共享存储、写时复制或其他优化实现，但必须保持上述可观察语义。Backend/Runtime 必须为赋值、参数、返回、扩容和嵌套值选择一致的内部策略，并通过行为测试证明等价。

固定数组 `T[N]` 的长度检查、转换和 ABI 另行设计，不得由本契约推导。

## 5. Backend 与 Runtime 责任

Backend 的输入是已经完成类型检查的 Typed IR。Backend 不得从运行时数组值反推元素类型，也不得把 `T[]` 降级为未类型化容器后继续生成代码。

Runtime 可以只保存：

```text
array_items
array_len
```

不要求 Runtime 保存 `T`，前提是：

- Semantic 已完成所有静态元素类型检查；
- Typed IR 保留了 `T[]`；
- Backend 根据 Typed IR 选择正确的元素访问、复制和 ABI 行为；
- Runtime 的复制、索引、扩容和返回行为不破坏数组值语义。

Runtime 的零长度容器存在不能单独证明 `T[]()` 已实现。必须证明 `array_new(T[])` 从 IR 到 Backend/Runtime 的完整执行路径。

Backend 契约：

```text
array_new(T[], 0) -> 独立的零长度动态数组值
index_get(T[], int) -> T 或定义明确的越界失败
index_set(T[], int, T) -> 更新同一数组值或定义明确的扩容行为
```

Backend 必须拒绝元素类型不匹配的 IR；Runtime 错误不得被静默转换为另一种元素类型。越界、负索引、分配失败和扩容失败必须有明确失败结果。

本契约将以下运行时错误统一定义为不可恢复的 Runtime panic：

- 负索引或越界读取；
- 负索引写入；
- 数组扩容失败；
- 数组存储分配失败。

不得将上述情况转换为未定义行为、静默返回零值或继续执行。panic 的具体消息格式属于 Runtime 实现细节，但错误类别和终止行为必须稳定可测试。

Hosted 与 Standalone 必须都终止当前程序，不能只在一条路径返回错误值。本设计提出统一退出码 `1`，作为契约候选值；在 S 全局 Runtime 规范批准前仍属于设计提案。panic 不可恢复、不可被普通 S 代码捕获，且两条路径必须产生相同的终止类别和退出码。

## 6. 端到端契约表

| 边界 | 输入 | 输出 | 必须保持的不变量 | 失败条件 |
|---|---|---|---|---|
| Source → AST | `T[]()` | `CALL_EXPR(INDEX_EXPR)` 或等价构造节点 | 保留类型构造与普通索引调用的可消歧信息 | 语法结构不完整 |
| AST → Type | 构造 AST | `ArrayType(dynamic_array, T)` | `T` 必须是合法类型，参数数为零 | 非类型符号、带参数、未知类型 |
| Type → Typed IR | `ArrayType(T)` | `array_new(result_type=T[], element_type=T, length=0)` | 两个类型字段一致 | 类型丢失或字段不一致 |
| Typed IR → Verifier | `array_new`、索引、调用、返回 | 验证通过的 IR | 所有数组边界保持同一 `T[]` | 元素类型、参数或返回不匹配 |
| Verifier → Backend | 已验证 Typed IR | 原生数组操作 | Backend 不重新猜测类型 | 非法 IR、ABI 不支持 |
| Backend → Runtime | `array_new/index_get/index_set` | 正确数组值行为 | 独立性、复制、扩容和失败语义一致 | 越界、分配或扩容失败 |
| Runtime → Caller | 数组值/返回值 | 有效 `T[]` 逻辑值 | 无悬空引用、无错误别名覆盖 | 返回值传播失败 |

## 7. 验证计划

正例：

```s
func empty() int[] {
    return int[]()
}

func main() int {
    int[] values = int[]()
    return len(values)
}
```

负例：

```s
unknown[] values = unknown[]()
int[] values = int[](1)
int value = 0
int[] values = value[]()
```

边界与回归：

- `int[]` 与 `string[]` 类型不混淆；
- 函数参数和返回值保持数组元素类型；
- 数组索引读取和写入类型正确；
- 数组字面量路径继续工作；
- 普通函数调用不受 `CALL_EXPR(INDEX_EXPR)` 特判影响；
- `vec[T]` 不作为 S 数组语义依据；
- P1 行为测试继续通过；
- P2.1 SSA 表示与验证器测试在数组构造阻塞解除后重新运行。

### 7.1 第三版验收矩阵

| 测试 | 预期 |
|---|---|
| `int[]()` | 成功，静态类型为 `int[]`，长度为 0 |
| 同名类型和值绑定 | 按分离命名空间规则解析 |
| `a[i]()` 且元素不可调用 | 静态类型错误 |
| `a[i]()` 且元素为可调用值 | 按普通调用语义执行 |
| 数组赋值后修改副本 | 原数组不变 |
| 函数参数内修改数组 | 调用方数组不变 |
| 函数返回数组 | 返回值有效，无悬空引用或错误别名 |
| 越界读取/写入 | 确定性 Runtime panic |
| 扩容分配失败 | 确定性 Runtime panic |
| `int[]` 传给 `string[]` 参数 | 静态类型错误 |
| `T[N]` 与 `T[]` 互换 | 静态类型错误或明确拒绝 |
| `return a` 后可达路径读取 `a` | 静态 use-after-move 错误 |
| 返回语句后的代码 | 按既有不可达代码规则处理 |
| 嵌套数组复制后修改副本 | 原数组及嵌套元素不变 |
| 结构体数组递归复制 | 字段值独立且类型保持 |
| 字符串数组复制 | 可观察字符串值独立，允许不可变存储共享 |
| 类型名与局部值同名 | 类型构造使用类型命名空间 |
| `a[i]()` 的元素不可调用 | 静态不可调用错误，不回退为数组构造 |
| `a[i]()` 的元素可调用 | 仅在函数值/可调用对象属于语言能力时按普通调用执行 |
| Hosted 越界/分配失败 | 不可恢复 panic，非零终止 |
| Standalone 越界/分配失败 | 与 Hosted 相同的不可恢复 panic 语义 |

## 7.2 最小测试清单

实施前必须为以下测试准备独立输入、阶段、预期诊断或运行结果：

```text
TEST-01  return_move_valid
TEST-02  use_after_move_rejected
TEST-03  nested_array_deep_copy
TEST-04  struct_array_recursive_copy
TEST-05  string_array_copy
TEST-06  type_value_same_name
TEST-07  callable_index_result
TEST-08  noncallable_index_result
TEST-09  hosted_bounds_panic
TEST-10  standalone_bounds_panic
TEST-11  hosted_allocation_panic
TEST-12  standalone_allocation_panic
```

`TEST-07` 只有在现有 S 语言规范确认支持函数值或可调用对象时才要求通过；否则必须明确标记为不适用，并保留 `TEST-08` 的不可调用诊断验证。

### 7.3 独立可执行测试规格

| ID | 最小输入/操作 | 阶段 | 预期结果 |
|---|---|---|---|
| TEST-01 | `int[] a = int[](); return len(a)` | 编译+运行 | 编译成功，退出码 0 |
| TEST-02 | `int[] a = int[](); move(a); return len(a)` | Semantic | 可达 use-after-move 静态错误；若无显式 `move` 语法则 `NOT_APPLICABLE` |
| TEST-03 | `b = a; b[0] = 2` 后读取 `a[0]` | 编译+运行 | 原数组值不变 |
| TEST-04 | 嵌套 `int[]` 复制后修改内层 | 编译+运行 | 原数组内层值不变 |
| TEST-05 | `string[]` 复制后修改字符串元素 | 编译+运行 | 原数组可观察字符串值不变 |
| TEST-06 | 同名类型与局部值后执行 `T[]()` | Semantic | 类型上下文选类型绑定 |
| TEST-07 | 数组元素为函数值并执行 `a[i]()` | Semantic/运行 | 仅在函数值能力已批准时执行，否则 `NOT_APPLICABLE` |
| TEST-08 | `int[] a; a[i]()` | Semantic | 元素不可调用静态错误，不回退为构造 |
| TEST-09 | 读取 `a[len(a)]` | Hosted/Standalone 运行 | panic，退出码 1 |
| TEST-10 | 写入负索引或越界索引 | Hosted/Standalone 运行 | panic，退出码 1 |
| TEST-11 | 注入 Hosted 分配失败 | Hosted 运行 | panic，退出码 1 |
| TEST-12 | 注入 Standalone 分配失败 | Standalone 运行 | panic，退出码 1 |

每项测试必须记录源文件、编译命令、编译阶段、标准输出、标准错误、退出码及 Hosted/Standalone 适用性。没有显式 Move 或函数值能力时，必须记录能力审计证据并使用 `NOT_APPLICABLE`，不能记为 PASS。

## 8. 模块责任与实施边界

设计层面的责任划分：

```text
Parser       保留可区分的 T[]() AST 形状
Semantic     识别构造、规范化 T[]、完成类型检查
Typed IR     表示 array_new(T[]) 及其结果类型
Verifier     验证数组操作、调用和返回的类型一致性
Backend      消费 Typed IR，不猜测元素类型
Runtime      执行已验证的数组行为
```

可能涉及的实现文件目前只能列为候选，尚未授权：

```text
src/cmd/compile/seed/semantic/analyzer.c
src/cmd/compile/seed/intermediate/ir.c
src/cmd/compile/seed/intermediate/ir.h
src/cmd/compile/seed/code/*
src/cmd/compile/seed/runtime/runtime.c
```

当前明确禁止：

- 引入 `vec` 作为替代类型；
- 修改 `T[N]` 固定数组语义；
- 修改 P1 IR 设计；
- 修改 P2.1 SSA 实现；
- 通过 Runtime 无类型容器绕过静态检查；
- 在设计审查通过前实施任何代码变更。

## 9. 当前决策状态

```ini
P1                    = ACCEPTED
P2.1                  = BLOCKED
TYPED_ARRAY_CONTRACT  = SIXTH_DRAFT
ARRAY_CONSTRUCTOR_IR  = PROPOSED_ONLY
IMPLEMENTATION        = NOT_APPROVED
P2.2+                 = NOT_STARTED
P3-P6                 = FROZEN
SELFHOST              = NOT_PROVEN
```
