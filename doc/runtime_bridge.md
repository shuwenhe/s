# runtime bridge dispatch

version: draft 0.1  
status: working draft

## 1. purpose

本文档定义从 s 侧 intrinsic 调用到 python bridge 函数的最小映射层。

目标不是立即执行完整 s 程序，而是先固定一层稳定协议：

```text
s source
   intrinsic symbol in s code
   host-side intrinsiccall
   python bridge dispatch
   concrete host value
```

## 2. runtime files

当前相关文件：

- [python_bridge.py](/app/s/src/runtime/python_bridge.py)
- [intrinsic_dispatch.py](/app/s/src/runtime/intrinsic_dispatch.py)
- [intrinsics_manifest.json](/app/s/src/runtime/intrinsics_manifest.json)
- [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py)
- [check_bridge.py](/app/s/src/runtime/check_bridge.py)

## 3. call model

s 侧当前把 intrinsic 写成：

```s
extern "intrinsic" func __string_slice(string text, int32 start, int32 end) string
```

在宿主桥接层，这会映射为：

```python
intrinsiccall(
    symbol="__string_slice",
    args=("hello", 1, 4),
    type_args=(),
)
```

然后通过 dispatcher 调到：

```python
invoke_intrinsic("__string_slice", "hello", 1, 4)
```

## 4. symbol mapping

当前 dispatcher 采用“符号名直接映射”的策略：

- s 侧 intrinsic 名字
- python bridge registry key
- dispatcher `intrinsiccall.symbol`

三者必须一致。

the manifest is now the abi source of truth. the python bridge must switch it at
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

## 5. argument order

参数顺序采用“s 声明顺序即 host 调用顺序”的最小规则。

例如：

```s
extern "intrinsic" func __vec_array_set[t](array[t] array, int32 index, t value) ()
```

对应：

```python
invoke_intrinsic("__vec_array_set", array, index, value)
```

## 6. host value encoding

当前宿主值采用最小 python 编码：

- `string`  python `str`
- `int32`  python `int`
- `array[t]`  `hostarray`
- `()`  `none`

for the std-layer host intrinsics, the current bridge uses a success-path model:

- `__host_read_to_string`  python `str`
- `__host_make_temp_dir`  python `str`
- `__host_write_text_file`  `none`
- `__host_run_process`  `none`
- `__host_args`  python `list[str]`
- `__host_println` / `__host_eprintln`  `none`
- `__host_exit`  raises `runtimeexit`

s declarations currently expose these as `result[...]` for `std.fs` and
`std.process`, but the python prototype does not yet materialize a host-side
`result[t, e]` wrapper. instead, success returns the payload and failures raise
`runtimetrap`.

后续如需支持：

- `vec[t]`
- `option[t]`
- `result[t, e]`
- `box[t]`

可以继续引入更明确的 host wrapper 类型。

## 7. error model

桥接层错误统一抛出 `runtimetrap`。

包括：

- 未知 intrinsic
- 参数个数不匹配
- 字符串越界
- 数组越界
- unwrap 失败

## 8. current validation

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

现在已经不再直接走 python 原型 lexer，而是通过 [hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py) 中的 `hostedlexer` 真实产出并执行 `intrinsiccall`，再完成 `lex_dump` / `ast_dump` 的 golden 对比。

当前 parser 侧也已经开始接入这条链：

- `hostedparser._parse_pattern`
- `hostedparser._parse_use_path`
- `hostedparser._parse_path`
- `hostedparser._path_contains_dot`
- `hostedparser._starts_with_upper`
- `hostedparser._join_strings`
- `hostedparser._normalize_type_text`
- `hostedparser._parse_type_text`
- `hostedparser._parse_bracket_group`
- `hostedparser._expect_keyword`
- `hostedparser._expect_symbol`
- `hostedparser._expect_ident`

这些 helper 现在会通过 `__runtime_len` / `__string_char_at` / `__string_concat` / `__string_replace` 产出并执行显式 `intrinsiccall`，而不是直接依赖 python 原生字符串语义。

另外，command 边界现在也已经开始进入统一执行计划：

- `run_lex_dump` 通过 `__host_read_to_string` / `__host_println`
- `run_ast_dump` 通过 `__host_read_to_string` / `__host_println`

编译器后端当前也已经切到 std-layer host boundary：

- [main.s](/app/s/src/cmd/compile/internal/main.s) 通过 `std.fs.readtostring`
- [backend_elf64.s](/app/s/src/cmd/compile/internal/backend_elf64.s) 通过
  `std.fs.writetextfile` / `std.fs.maketempdir` / `std.process.runprocess`

命令入口 abi 也已经有了 s 侧包装：

- [env.s](/app/s/src/env/env.s) 通过 `__host_args`
- [process.s](/app/s/src/process/process.s) 通过 `__host_exit`
- [s.s](/app/s/src/cmd/s/main.s) 通过 `args() compiler.main(args) exit(code)`

这意味着 `executionplan` 已经不只记录 parser/lexer 内部 intrinsic，也开始覆盖宿主 io 边界。

## 9. next step

下一步最值得推进的是：

1. 让 parser 的更多辅助路径和后续 lowering 阶段也显式产出 `intrinsiccall`
2. 给 `vec`、`option`、`result` 增加 host wrapper
3. 让 `read_to_string` / `println` 这类宿主边界也进入统一执行计划
