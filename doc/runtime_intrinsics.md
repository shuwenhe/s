# self-hosted runtime intrinsics

version: draft 0.1  
status: working draft

## 1. purpose

this document narrows the minimal runtime intrinsic contract used during the
self-hosting bootstrap phase. the current scope covers:

- 字符串长度与切片
- 单字符访问
- 整数转字符串
- 通用 `len`
- `vec` 底层数组分配与读写
- `option` / `result` 的 panic-style unwrap fallback
- `std.fs` / `std.process` / `std.io` 对应的 host io bridge
- `std.env` / `std.process` 对应的 process entry bridge

these intrinsics are not yet the final public runtime api. they are the
bootstrap execution contract currently relied on by the self-hosted frontend,
compiler drivers, and backend prototype.

current host bridge files:

- [runtime/readme.md](/app/s/src/runtime/readme.md)
- [python_bridge.py](/app/s/src/runtime/python_bridge.py)
- [validate_outputs.py](/app/s/src/runtime/validate_outputs.py)

## 2. string intrinsics

current [prelude.s](/app/s/src/prelude/prelude.s) declares:

```s
extern "intrinsic" func __runtime_len[t](t value) int32
extern "intrinsic" func __int_to_string(int32 value) string
extern "intrinsic" func __string_char_at(string text, int32 index) string
extern "intrinsic" func __string_slice(string text, int32 start, int32 end) string
```

### `__runtime_len`

requirements:

- 对 `string` 返回字符长度或当前 runtime 约定下的索引长度
- 对 `vec[t]` 返回逻辑元素个数
- 对其他运行时支持的集合类型可扩展

notes:

- 当前 lexer / parser 只要求这个长度能与 `char_at`、`slice` 的索引模型保持一致

### `__int_to_string`

requirements:

- 支持 `int32  string`
- 至少正确处理 `0`、正数、负数

### `__string_char_at`

requirements:

- 返回给定位置的单字符字符串
- 越界时的行为需要固定

draft 0.1 recommendation:

- 运行时抛错，或者进入统一 trap 语义

### `__string_slice`

requirements:

- 返回 `[start, end)` 半开区间
- `start == end` 时返回空字符串
- 与 `__string_char_at` 和 `__runtime_len` 的索引模型一致

## 3. vec intrinsics

current [vec.s](/app/s/src/vec/vec.s) declares:

```s
extern "intrinsic" func __vec_new_array[t](int32 size) array[t]
extern "intrinsic" func __vec_array_get[t](array[t] array, int32 index) t
extern "intrinsic" func __vec_array_set[t](array[t] array, int32 index, t value) ()
```

requirements:

- `__vec_new_array` 创建固定容量的底层存储
- `__vec_array_get` 按索引读取
- `__vec_array_set` 按索引写入
- `vec.push` 的扩容语义由上层 `ensure_capacity` 保证

the current intrinsic layer does not need to understand `vec.length`. it only
needs to provide the backing array behavior.

## 4. option / result panic intrinsics

current declarations:

```s
extern "intrinsic" func __option_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap[t]() t
extern "intrinsic" func __result_panic_unwrap_err[e]() e
```

purpose:

- 支撑 `unwrap()` / `unwrap_err()` 的最小语义
- 在还没有完整 panic/runtime error 模型之前，提供统一失败出口

draft 0.1 recommendation:

- 这些 intrinsic 直接终止执行
- 后续可以统一收敛到标准 panic 机制

## 5. host io intrinsics

the new std-layer host boundary is now:

- [fs.s](/app/s/src/fs/fs.s)
- [process.s](/app/s/src/process/process.s)
- [io.s](/app/s/src/io/io.s)
- [env.s](/app/s/src/env/env.s)

current declarations:

```s
extern "intrinsic" func __host_read_to_string(string path) result[string, fserror]
extern "intrinsic" func __host_write_text_file(string path, string contents) result[(), fserror]
extern "intrinsic" func __host_make_temp_dir(string prefix) result[string, fserror]
extern "intrinsic" func __host_run_process(vec[string] argv) result[(), processerror]
extern "intrinsic" func __host_args() vec[string]
extern "intrinsic" func __host_exit(int code) ()
extern "intrinsic" func __host_println(string text) ()
extern "intrinsic" func __host_eprintln(string text) ()
```

bridge behavior in the current python prototype:

- success path returns the payload for `read_to_string` / `make_temp_dir`
- success path returns the payload for `args`
- success path returns `none` for `write_text_file` / `run_process` / `println` / `eprintln`
- `exit` terminates through a dedicated host boundary
- host io failures raise `runtimetrap`

this means the bridge currently models the successful payload path plus trap
semantics. it does not yet materialize a host-side `result[t, e]` wrapper.

## 6. current consumers

code that currently depends on these contracts includes:

- [lexer.s](/app/s/src/s/lexer.s)
- [parser.s](/app/s/src/s/parser.s)
- [tokens.s](/app/s/src/s/tokens.s)
- [lex_dump.s](/app/s/src/cmd/lex_dump/main.s)
- [ast_dump.s](/app/s/src/cmd/ast_dump/main.s)
- [vec.s](/app/s/src/vec/vec.s)
- [main.s](/app/s/src/cmd/compile/internal/main.s)
- [backend_elf64.s](/app/s/src/cmd/compile/internal/backend_elf64.s)
- [fs.s](/app/s/src/fs/fs.s)
- [process.s](/app/s/src/process/process.s)
- [io.s](/app/s/src/io/io.s)
- [env.s](/app/s/src/env/env.s)

## 7. next step

the next valuable steps are:

1. 让 python bridge 接到更明确的 s ast / intrinsic 调用层
2. 让 `lex_dump` 真正跑通 `sample.s  sample.tokens`
3. 让 `ast_dump` 真正跑通 `sample.s  sample.ast`
