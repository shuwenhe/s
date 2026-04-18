# self-hosted `lex_dump` driver

version: draft 0.1  
status: working draft

## 1. purpose

本文档说明自举阶段最小 driver [lex_dump.s](/app/s/src/cmd/lex_dump/main.s) 的职责、调用路径，以及它当前依赖的 `std.fs` / `std.io` 接口假设。

`lex_dump` 的目标很简单：

```text
source file
   read source text
   self-hosted lexer
   token stream
   textual dump
```

它不是完整的 `s check` cli，只是自举前端的最小验证入口。

## 2. current flow

当前路径如下：

1. `main(args)` 读取命令行参数
2. `parse_path(args)` 提取输入文件路径
3. `read_source(path)` 调用 `std.fs.read_to_string`
4. `lex_source(source)` 调用 [lexer.s](/app/s/src/s/lexer.s)
5. `dump_tokens(tokens)` 生成与 python 版接近的 token dump 文本
6. `println(...)` 输出到标准输出

涉及文件：

- [lex_dump.s](/app/s/src/cmd/lex_dump/main.s)
- [lexer.s](/app/s/src/s/lexer.s)
- [tokens.s](/app/s/src/s/tokens.s)

## 3. `std.fs` assumptions

`lex_dump.s` 当前假设标准库存在如下接口：

```s
use std.fs.read_to_string

func read_to_string(string path) result[string, fserror]
```

当前自举阶段对这个接口的约束只有这些：

- 输入是拥有型 `string` 路径
- 成功时返回完整源码文本
- 失败时返回某种错误值
- `lex_dump` 当前不会依赖 `fserror` 的具体结构，只关心成功或失败

这意味着：

- 后续可以把 `fserror` 替换成更正式的 `ioerror`
- 也可以把 `string` 路径升级成 `path` / `pathbuf`
- 只要调用形状兼容，`lex_dump` 代码不需要大改

## 4. `std.io` assumptions

`lex_dump.s` 当前假设标准库存在如下接口：

```s
use std.io.println
use std.io.eprintln

func println(string text) ()
func eprintln(string text) ()
```

当前约束：

- `println` 输出正常 token dump
- `eprintln` 输出错误信息
- 暂不要求 writer trait、buffering 或格式化参数系统

也就是说，现阶段只需要“把字符串打到 stdout/stderr”的最小能力。

## 5. cli assumptions

`lex_dump` 当前还假设运行时能把命令行参数以如下形式交给入口：

```s
func main(vec[string] args) int32
```

约定：

- `args[0]` 是程序名
- `args[1]` 是待词法分析的源码路径

最小调用形状：

```text
lex_dump path/to/file.s
```

## 6. error model

当前 driver 使用本地错误类型：

```s
struct clierror {
    string message
}
```

设计意图：

- 先把 cli 层错误与 lexer 错误隔离
- 暂时不强依赖统一的 `std.error.error` trait
- 等标准库错误模型稳定后再统一

## 7. known gaps

当前 `lex_dump` 仍然只是自举骨架，已知缺口包括：

- `std.fs` / `std.io` 还没有真实 s 实现
- 命令行参数注入机制还只是接口约定
- `dump_tokens` 依赖 `to_string`、`len` 等基础库能力，这些也还没有真正落地
- 还没有 golden test runner 去自动比对 [sample.tokens](/app/s/src/cmd/compile/internal/tests/fixtures/sample.tokens)

## 8. next step

`lex_dump` 下一步最值得做的事情：

1. 给自举 runtime 补最小 `std.fs.read_to_string`
2. 给自举 runtime 补最小 `std.io.println` / `std.io.eprintln`
3. 用 [sample.s](/app/s/src/cmd/compile/internal/tests/fixtures/sample.s) 跑出和 [sample.tokens](/app/s/src/cmd/compile/internal/tests/fixtures/sample.tokens) 对齐的输出
4. 把 parser 接到 `token stream  ast` 路径上
