# self-hosted `ast_dump` driver

version: draft 0.1  
status: working draft

## 1. purpose

本文档说明最小 ast driver [ast_dump.s](/app/s/src/cmd/ast_dump/main.s) 的职责、调用路径，以及它当前依赖的 `std.fs` / `std.io` / parser 接口假设。

`ast_dump` 的目标是：

```text
source file
   read source text
   self-hosted parser
   ast
   textual dump
```

它是 `lex_dump` 的下一层，不做类型检查，也不做 codegen。

## 2. current flow

当前路径如下：

1. `main(args)` 读取命令行参数
2. `parse_path(args)` 提取输入文件路径
3. `read_source(path)` 调用 `std.fs.read_to_string`
4. `parse_ast(source)` 调用 [parser.s](/app/s/src/s/parser.s)
5. `dump_source_file(ast)` 调用 [ast.s](/app/s/src/s/ast.s) 里的 dump helper
6. `println(...)` 输出 ast dump 文本

涉及文件：

- [ast_dump.s](/app/s/src/cmd/ast_dump/main.s)
- [parser.s](/app/s/src/s/parser.s)
- [ast.s](/app/s/src/s/ast.s)

## 3. `std.fs` assumptions

`ast_dump.s` 当前假设标准库存在如下接口：

```s
use std.fs.read_to_string

func read_to_string(string path) result[string, fserror]
```

当前只依赖这些性质：

- 输入是拥有型 `string`
- 成功时返回完整源码文本
- 失败时返回某种错误值
- driver 只关心成功或失败，不依赖 `fserror` 的详细字段

## 4. `std.io` assumptions

`ast_dump.s` 当前假设标准库存在如下接口：

```s
use std.io.println
use std.io.eprintln

func println(string text) ()
func eprintln(string text) ()
```

当前要求仍然只是最小输出能力：

- `println` 输出 ast dump
- `eprintln` 输出错误信息

## 5. parser assumptions

`ast_dump` 当前假设 parser 提供如下最小接口：

```s
func parse_source(string source) result[sourcefile, parseerror]
```

以及如下最小错误形状：

```s
struct parseerror {
    string message
    int32 line
    int32 column
}
```

也就是说，driver 需要 parser 至少提供：

- 完整源码字符串输入
- `sourcefile` 级别输出
- 位置化错误信息

## 6. cli assumptions

当前入口约定如下：

```s
func main(vec[string] args) int32
```

最小调用形状：

```text
ast_dump path/to/file.s
```

约定：

- `args[0]` 是程序名
- `args[1]` 是待解析源码路径

## 7. known gaps

当前 `ast_dump` 仍然只是自举骨架，已知缺口包括：

- `std.fs` / `std.io` 还没有真实后端实现
- parser 仍处于 skeleton 阶段
- ast dump 还没有 golden test runner 自动比对 [sample.ast](/app/s/src/cmd/compile/internal/tests/fixtures/sample.ast)
- `vec` / 字符串 / intrinsic 仍然只是最小 runtime 约定

## 8. next step

`ast_dump` 下一步最值得做的事情：

1. 继续收紧 parser 与 python 版的行为差异
2. 补一个最小 ast golden 对比入口
3. 给 runtime 的字符串和 `vec` intrinsic 提供更具体的执行模型
