# Self-Hosted Runtime Intrinsics

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

This document narrows the minimal runtime intrinsic contract used during the
self-hosting bootstrap phase. The current scope covers:

- 字符串长度与切片
- 单字符访问
- 整数转字符串
- 通用 `len`
- `Vec` 底层数组分配与读写
- `Option` / `Result` 的 panic-style unwrap fallback
- `std.fs` / `std.process` / `std.io` 对应的 host IO bridge

These intrinsics are not yet the final public runtime API. They are the
bootstrap execution contract currently relied on by the self-hosted frontend,
compiler drivers, and backend prototype.

Current host bridge files:

- [runtime/README.md](/app/s/runtime/README.md)
- [python_bridge.py](/app/s/runtime/python_bridge.py)
- [validate_outputs.py](/app/s/runtime/validate_outputs.py)

## 2. String Intrinsics

Current [prelude.s](/app/s/std/prelude.s) declares:

```s
extern "intrinsic" func __runtime_len[T](value: T) -> i32
extern "intrinsic" func __int_to_string(value: i32) -> String
extern "intrinsic" func __string_char_at(text: String, index: i32) -> String
extern "intrinsic" func __string_slice(text: String, start: i32, end: i32) -> String
```

### `__runtime_len`

Requirements:

- 对 `String` 返回字符长度或当前 runtime 约定下的索引长度
- 对 `Vec[T]` 返回逻辑元素个数
- 对其他运行时支持的集合类型可扩展

Notes:

- 当前 lexer / parser 只要求这个长度能与 `char_at`、`slice` 的索引模型保持一致

### `__int_to_string`

Requirements:

- 支持 `i32 -> String`
- 至少正确处理 `0`、正数、负数

### `__string_char_at`

Requirements:

- 返回给定位置的单字符字符串
- 越界时的行为需要固定

Draft 0.1 recommendation:

- 运行时抛错，或者进入统一 trap 语义

### `__string_slice`

Requirements:

- 返回 `[start, end)` 半开区间
- `start == end` 时返回空字符串
- 与 `__string_char_at` 和 `__runtime_len` 的索引模型一致

## 3. Vec Intrinsics

Current [vec.s](/app/s/std/vec.s) declares:

```s
extern "intrinsic" func __vec_new_array[T](size: i32) -> Array[T]
extern "intrinsic" func __vec_array_get[T](array: Array[T], index: i32) -> T
extern "intrinsic" func __vec_array_set[T](array: Array[T], index: i32, value: T) -> ()
```

Requirements:

- `__vec_new_array` 创建固定容量的底层存储
- `__vec_array_get` 按索引读取
- `__vec_array_set` 按索引写入
- `Vec.push` 的扩容语义由上层 `ensure_capacity` 保证

The current intrinsic layer does not need to understand `Vec.length`. It only
needs to provide the backing array behavior.

## 4. Option / Result Panic Intrinsics

Current declarations:

```s
extern "intrinsic" func __option_panic_unwrap[T]() -> T
extern "intrinsic" func __result_panic_unwrap[T]() -> T
extern "intrinsic" func __result_panic_unwrap_err[E]() -> E
```

Purpose:

- 支撑 `unwrap()` / `unwrap_err()` 的最小语义
- 在还没有完整 panic/runtime error 模型之前，提供统一失败出口

Draft 0.1 recommendation:

- 这些 intrinsic 直接终止执行
- 后续可以统一收敛到标准 panic 机制

## 5. Host IO Intrinsics

The new std-layer host boundary is now:

- [fs.s](/app/s/std/fs.s)
- [process.s](/app/s/std/process.s)
- [io.s](/app/s/std/io.s)

Current declarations:

```s
extern "intrinsic" func __host_read_to_string(path: String) -> Result[String, FsError]
extern "intrinsic" func __host_write_text_file(path: String, contents: String) -> Result[(), FsError]
extern "intrinsic" func __host_make_temp_dir(prefix: String) -> Result[String, FsError]
extern "intrinsic" func __host_run_process(argv: Vec[String]) -> Result[(), ProcessError]
extern "intrinsic" func __host_println(text: String) -> ()
extern "intrinsic" func __host_eprintln(text: String) -> ()
```

Bridge behavior in the current Python prototype:

- success path returns the payload for `read_to_string` / `make_temp_dir`
- success path returns `None` for `write_text_file` / `run_process` / `println` / `eprintln`
- host IO failures raise `RuntimeTrap`

This means the bridge currently models the successful payload path plus trap
semantics. It does not yet materialize a host-side `Result[T, E]` wrapper.

## 6. Current Consumers

Code that currently depends on these contracts includes:

- [lexer.s](/app/s/frontend/lexer.s)
- [parser.s](/app/s/frontend/parser.s)
- [tokens.s](/app/s/frontend/tokens.s)
- [lex_dump.s](/app/s/cmd/lex_dump.s)
- [ast_dump.s](/app/s/cmd/ast_dump.s)
- [vec.s](/app/s/std/vec.s)
- [main.s](/app/s/compiler/main.s)
- [backend_elf64.s](/app/s/compiler/backend_elf64.s)
- [fs.s](/app/s/std/fs.s)
- [process.s](/app/s/std/process.s)
- [io.s](/app/s/std/io.s)

## 7. Next Step

The next valuable steps are:

1. 让 Python bridge 接到更明确的 S AST / intrinsic 调用层
2. 让 `lex_dump` 真正跑通 `sample.s -> sample.tokens`
3. 让 `ast_dump` 真正跑通 `sample.s -> sample.ast`
