# Runtime Bridge Dispatch

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档定义从 S 侧 intrinsic 调用到 Python bridge 函数的最小映射层。

目标不是立即执行完整 S 程序，而是先固定一层稳定协议：

```text
S source
   intrinsic symbol in S code
   host-side IntrinsicCall
   Python bridge dispatch
   concrete host value
```

## 2. Runtime Files

当前相关文件：

- [python_bridge.py](/app/s/src/runtime/python_bridge.py)
- [intrinsic_dispatch.py](/app/s/src/runtime/intrinsic_dispatch.py)
- [intrinsics_manifest.json](/app/s/src/runtime/intrinsics_manifest.json)
- [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py)
- [check_bridge.py](/app/s/src/runtime/check_bridge.py)

## 3. Call Model

S 侧当前把 intrinsic 写成：

```s
extern "intrinsic" func __string_slice(String text, i32 start, i32 end) String
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

The manifest is now the ABI source of truth. The Python bridge must match it at
import time.

当前已接通的符号包括：

- `__runtime_len`
- `__int_to_string`
- `__string_concat`
- `__string_replace`
- `__string_char_at`
- `__string_slice`
- `__vec_new_array`
- `__vec_array_get`
- `__vec_array_set`
- `__host_read_to_string`
- `__host_write_text_file`
- `__host_make_temp_dir`
- `__host_run_process`
- `__host_args`
- `__host_exit`
- `__host_println`
- `__host_eprintln`
- `__option_panic_unwrap`
- `__result_panic_unwrap`
- `__result_panic_unwrap_err`

## 5. Argument Order

参数顺序采用“S 声明顺序即 host 调用顺序”的最小规则。

例如：

```s
extern "intrinsic" func __vec_array_set[T](Array[T] array, i32 index, T value) ()
```

对应：

```python
invoke_intrinsic("__vec_array_set", array, index, value)
```

## 6. Host Value Encoding

当前宿主值采用最小 Python 编码：

- `String`  Python `str`
- `i32`  Python `int`
- `Array[T]`  `HostArray`
- `()`  `None`

For the std-layer host intrinsics, the current bridge uses a success-path model:

- `__host_read_to_string`  Python `str`
- `__host_make_temp_dir`  Python `str`
- `__host_write_text_file`  `None`
- `__host_run_process`  `None`
- `__host_args`  Python `list[str]`
- `__host_println` / `__host_eprintln`  `None`
- `__host_exit`  raises `RuntimeExit`

S declarations currently expose these as `Result[...]` for `std.fs` and
`std.process`, but the Python prototype does not yet materialize a host-side
`Result[T, E]` wrapper. Instead, success returns the payload and failures raise
`RuntimeTrap`.

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
python3 /app/s/src/runtime/check_bridge.py
```

它会验证：

- 字符串长度
- `char_at`
- `slice`
- `vec` 底层数组读写
- `read_to_string`
- `write_text_file`
- `make_temp_dir`
- `run_process`
- `args`
- `exit`
- dispatcher 的符号调用路径

另外：

```bash
python3 /app/s/src/runtime/validate_outputs.py all
```

现在已经不再直接走 Python 原型 lexer，而是通过 [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py) 中的 `HostedLexer` 真实产出并执行 `IntrinsicCall`，再完成 `lex_dump` / `ast_dump` 的 golden 对比。

当前 parser 侧也已经开始接入这条链：

- `HostedParser._parse_pattern`
- `HostedParser._parse_use_path`
- `HostedParser._parse_path`
- `HostedParser._path_contains_dot`
- `HostedParser._starts_with_upper`
- `HostedParser._join_strings`
- `HostedParser._normalize_type_text`
- `HostedParser._parse_type_text`
- `HostedParser._parse_bracket_group`
- `HostedParser._expect_keyword`
- `HostedParser._expect_symbol`
- `HostedParser._expect_ident`

这些 helper 现在会通过 `__runtime_len` / `__string_char_at` / `__string_concat` / `__string_replace` 产出并执行显式 `IntrinsicCall`，而不是直接依赖 Python 原生字符串语义。

另外，command 边界现在也已经开始进入统一执行计划：

- `run_lex_dump` 通过 `__host_read_to_string` / `__host_println`
- `run_ast_dump` 通过 `__host_read_to_string` / `__host_println`

编译器后端当前也已经切到 std-layer host boundary：

- [main.s](/app/s/src/cmd/compiler/main.s) 通过 `std.fs.ReadToString`
- [backend_elf64.s](/app/s/src/cmd/compiler/backend_elf64.s) 通过
  `std.fs.WriteTextFile` / `std.fs.MakeTempDir` / `std.process.RunProcess`

命令入口 ABI 也已经有了 S 侧包装：

- [env.s](/app/s/src/env/env.s) 通过 `__host_args`
- [process.s](/app/s/src/process/process.s) 通过 `__host_exit`
- [s.s](/app/s/src/cmd/s/main.s) 通过 `Args() compiler.main(args) Exit(code)`

这意味着 `ExecutionPlan` 已经不只记录 parser/lexer 内部 intrinsic，也开始覆盖宿主 IO 边界。

## 9. Next Step

下一步最值得推进的是：

1. 让 parser 的更多辅助路径和后续 lowering 阶段也显式产出 `IntrinsicCall`
2. 给 `Vec`、`Option`、`Result` 增加 host wrapper
3. 让 `read_to_string` / `println` 这类宿主边界也进入统一执行计划
