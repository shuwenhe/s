# Runtime Bridge Dispatch

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义从 S 侧 intrinsic 调用到 Python bridge 函数的最小映射层。

目标不是立即执行完整 S 程序，而是先固定一层稳定协议：

```text
S source
  -> intrinsic symbol in S code
  -> host-side IntrinsicCall
  -> Python bridge dispatch
  -> concrete host value
```

## 2. Runtime Files

当前相关文件：

- [python_bridge.py](/app/s/runtime/python_bridge.py)
- [intrinsic_dispatch.py](/app/s/runtime/intrinsic_dispatch.py)
- [hosted_frontend.py](/app/s/runtime/hosted_frontend.py)
- [check_bridge.py](/app/s/runtime/check_bridge.py)

## 3. Call Model

S 侧当前把 intrinsic 写成：

```s
extern "intrinsic" fn __string_slice(text: String, start: i32, end: i32) -> String
```

在宿主桥接层，这会映射为：

```python
IntrinsicCall(
    symbol="__string_slice",
    args=("hello", 1, 4),
    type_args=(),
)
```

然后通过 dispatcher 调到：

```python
invoke_intrinsic("__string_slice", "hello", 1, 4)
```

## 4. Symbol Mapping

当前 dispatcher 采用“符号名直接映射”的策略：

- S 侧 intrinsic 名字
- Python bridge registry key
- dispatcher `IntrinsicCall.symbol`

三者必须一致。

当前已接通的符号包括：

- `__runtime_len`
- `__int_to_string`
- `__string_char_at`
- `__string_slice`
- `__vec_new_array`
- `__vec_array_get`
- `__vec_array_set`
- `__option_panic_unwrap`
- `__result_panic_unwrap`
- `__result_panic_unwrap_err`

## 5. Argument Order

参数顺序采用“S 声明顺序即 host 调用顺序”的最小规则。

例如：

```s
extern "intrinsic" fn __vec_array_set[T](array: Array[T], index: i32, value: T) -> ()
```

对应：

```python
invoke_intrinsic("__vec_array_set", array, index, value)
```

## 6. Host Value Encoding

当前宿主值采用最小 Python 编码：

- `String` -> Python `str`
- `i32` -> Python `int`
- `Array[T]` -> `HostArray`
- `()` -> `None`

后续如需支持：

- `Vec[T]`
- `Option[T]`
- `Result[T, E]`
- `Box[T]`

可以继续引入更明确的 host wrapper 类型。

## 7. Error Model

桥接层错误统一抛出 `RuntimeTrap`。

包括：

- 未知 intrinsic
- 参数个数不匹配
- 字符串越界
- 数组越界
- unwrap 失败

## 8. Current Validation

当前可直接运行：

```bash
python3 /app/s/runtime/check_bridge.py
```

它会验证：

- 字符串长度
- `char_at`
- `slice`
- `vec` 底层数组读写
- dispatcher 的符号调用路径

另外：

```bash
python3 /app/s/runtime/validate_outputs.py all
```

现在已经不再直接走 Python 原型 lexer，而是通过 [hosted_frontend.py](/app/s/runtime/hosted_frontend.py) 中的 `HostedLexer` 真实产出并执行 `IntrinsicCall`，再完成 `lex_dump` / `ast_dump` 的 golden 对比。

当前 parser 侧也已经开始接入这条链：

- `HostedParser._parse_pattern`
- `HostedParser._path_contains_dot`
- `HostedParser._starts_with_upper`

这些 helper 现在会通过 `__runtime_len` / `__string_char_at` 产出并执行显式 `IntrinsicCall`，而不是直接依赖 Python 原生字符串语义。

## 9. Next Step

下一步最值得推进的是：

1. 让 parser 的更多辅助路径和后续 lowering 阶段也显式产出 `IntrinsicCall`
2. 给 `Vec`、`Option`、`Result` 增加 host wrapper
3. 让 `read_to_string` / `println` 这类宿主边界也进入统一执行计划
