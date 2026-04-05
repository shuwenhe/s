# Self-Hosted Runtime Intrinsics

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档收紧自举阶段最小 runtime intrinsic 的接口约定，重点覆盖：

- 字符串长度与切片
- 单字符访问
- 整数转字符串
- 通用 `len`
- `Vec` 底层数组分配与读写
- `Option` / `Result` 的 panic-style unwrap fallback

这些 intrinsic 目前还不是“标准库公开 API”，而是 self-hosted 前端在真正 runtime 落地前所依赖的最小执行契约。

当前宿主桥接原型位于：

- [runtime/README.md](/app/s/runtime/README.md)
- [python_bridge.py](/app/s/runtime/python_bridge.py)
- [validate_outputs.py](/app/s/runtime/validate_outputs.py)

## 2. String Intrinsics

当前 [prelude.s](/app/s/std/prelude.s) 约定如下 intrinsic：

```s
extern "intrinsic" func __runtime_len[T](value: T) -> i32
extern "intrinsic" func __int_to_string(value: i32) -> String
extern "intrinsic" func __string_char_at(text: String, index: i32) -> String
extern "intrinsic" func __string_slice(text: String, start: i32, end: i32) -> String
```

### `__runtime_len`

要求：

- 对 `String` 返回字符长度或当前 runtime 约定下的索引长度
- 对 `Vec[T]` 返回逻辑元素个数
- 对其他运行时支持的集合类型可扩展

注意：

- 当前 lexer / parser 只要求这个长度能与 `char_at`、`slice` 的索引模型保持一致

### `__int_to_string`

要求：

- 支持 `i32 -> String`
- 至少正确处理 `0`、正数、负数

### `__string_char_at`

要求：

- 返回给定位置的单字符字符串
- 越界时的行为需要固定

Draft 0.1 推荐：

- 运行时抛错，或者进入统一 trap 语义

### `__string_slice`

要求：

- 返回 `[start, end)` 半开区间
- `start == end` 时返回空字符串
- 与 `__string_char_at` 和 `__runtime_len` 的索引模型一致

## 3. Vec Intrinsics

当前 [vec.s](/app/s/std/vec.s) 约定如下 intrinsic：

```s
extern "intrinsic" func __vec_new_array[T](size: i32) -> Array[T]
extern "intrinsic" func __vec_array_get[T](array: Array[T], index: i32) -> T
extern "intrinsic" func __vec_array_set[T](array: Array[T], index: i32, value: T) -> ()
```

要求：

- `__vec_new_array` 创建固定容量的底层存储
- `__vec_array_get` 按索引读取
- `__vec_array_set` 按索引写入
- `Vec.push` 的扩容语义由上层 `ensure_capacity` 保证

也就是说，当前 intrinsic 层不需要自己知道 `Vec` 的 `length`，只负责底层 array 行为。

## 4. Option / Result Panic Intrinsics

当前约定如下 intrinsic：

```s
extern "intrinsic" func __option_panic_unwrap[T]() -> T
extern "intrinsic" func __result_panic_unwrap[T]() -> T
extern "intrinsic" func __result_panic_unwrap_err[E]() -> E
```

用途：

- 支撑 `unwrap()` / `unwrap_err()` 的最小语义
- 在还没有完整 panic/runtime error 模型之前，提供统一失败出口

Draft 0.1 推荐：

- 这些 intrinsic 直接终止执行
- 后续可以统一收敛到标准 panic 机制

## 5. Current Consumers

当前直接依赖这些约定的代码包括：

- [lexer.s](/app/s/frontend/lexer.s)
- [parser.s](/app/s/frontend/parser.s)
- [tokens.s](/app/s/frontend/tokens.s)
- [lex_dump.s](/app/s/cmd/lex_dump.s)
- [ast_dump.s](/app/s/cmd/ast_dump.s)
- [vec.s](/app/s/std/vec.s)

## 6. Next Step

接下来最值得推进的是：

1. 让 Python bridge 接到更明确的 S AST / intrinsic 调用层
2. 让 `lex_dump` 真正跑通 `sample.s -> sample.tokens`
3. 让 `ast_dump` 真正跑通 `sample.s -> sample.ast`
