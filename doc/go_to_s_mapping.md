# go → s ast 映射草案

目标
- 将 go 语言的语法节点映射到 `s` 语言现有的 ast（`s/src/s/ast.s`）结构。
- 优先保持语义信息（名称、签名、类型文本、表达式结构），以便后续实现转换器或前端兼容层。

设计原则
- 保留原始 go 源的可重建信息：尽量把 go 节点中无法直接映射到 s 的部分以原始文本或 `type_text` 字段保留在 ast 中。
- 逐步增强：先实现表面语法（parse-only）映射，再逐步补充语义（types、methods、interfaces、channel 等）。
- 尽量复用 `s` ast 节点：如 `expr::call`、`expr::member`、`expr::index`、`stmt::var`、`functiondecl` 等。

概览（高层）
- go `file` → `sourcefile`
  - package name → `sourcefile.package`
  - import list → `sourcefile.uses`（映射为 `use`，as 保留到 alias）
  - top-level declarations → `sourcefile.items`

详细节点映射

1. 包与导入
- go: `ast.file.name` → s: `sourcefile.package`（字符串）
- go: `ast.importspec` → s: `usedecl { path, alias }`
  - 保留原始路径文字（去引号），若 `importspec.name` 非空则映射到 `alias`。

2. 类型声明
- go: `ast.typespec`：
  - `type t struct { ... }` → s: `structdecl { name: t, fields: [...] }`
    - 字段名/类型映射到 `field { name, type_name }`；若无命名字段（匿名嵌入）则用类型文本放到 `type_name`，字段名可设为 `_embed_n`。
  - `type t interface { ... }` → s: `traitdecl { name: t, methods: [...] }`（接口映射为 trait）
    - interface 方法签名映射为 `functionsig`（返回 `option[string] return_type`），保留参数名/类型文本。
  - 其他类型别名或自定义类型（例如 `type myint int`）→ 生成 `structdecl` 不合适，建议作为 `use`/`type_text` 的注记：在 ast 中以 `structdecl` 或 `enumdecl` 之外保留到 `impl`/注释，或扩展 ast（后续）。

3. 变量与常量
- go: `ast.valuespec` in top-level → s: `varstmt` 或 `constdecl`（s 当前 ast 有 `varstmt` 与 `constdecl` 位于 parser 层）
  - 多重声明（`var a, b = 1, 2`）可拆分为多个 `varstmt`。
  - 未显式类型时将类型留空，`type_text` 可用字符串保存（例如 `int`、`map[string]int`）。

4. 函数与方法
- go: `ast.funcdecl`
  - 非方法（receiver == nil）→ s: `functiondecl`：
    - `functionsig.name` = func name
    - `functionsig.params` = 参数名与 `type_name` 使用 `param { name, type_name }`（若无参数名，生成 `_argn`）
    - `functionsig.return_type` = 单一或多重返回：若多重返回，用 `type_text`（例如 `(int, error)`）或映射到一个 tuple 表示法保存在字符串
    - body → `option[blockexpr]`（若 `funcdecl.body == nil` 则 option::none）
  - 方法（有 receiver）→ s: `impldecl` with `methods` 包含该方法：
    - `target` = receiver type as string（如 `*t` 或 `t`）
    - 方法本体映射成 `functiondecl`，`is_public` 根据首字母大小写决定

5. 语句与表达式（逐项）
- 基础字面量：`basiclit`（int/string）→ `expr::int` / `expr::string`（保留文字）
- 标识符：`ident` → `expr::name`（`name` 字段）
- 二元/一元表达式：`binaryexpr` / `unaryexpr` → `expr::binary` / 以 `borrow` 表示的借用（若用 `&`）
- 函数调用：`callexpr` → `expr::call`（callee 映射，args 列表映射）
- 选择器表达式：`selectorexpr` (`x.y`) → `expr::member`（target: `x`，member: `y`）
- 索引/切片：`indexexpr` / `sliceexpr` → `expr::index` 或保留 `type_text`（切片语法）
- 赋值、短声明：`assignstmt` / `declstmt` → `stmt::assign` 或 `stmt::var`（short `:=` 映射为 `varstmt`）
- `if/for/switch/select`：
  - `if` → `expr::if`
  - go `for` 三类：
    - `for init; cond; post` → `stmt::cfor`（c-style for）
    - `for range` → `expr::for`（将 range target 映射到 `iterable`，`names` 为迭代变量）
    - `for {}`（无限循环）→ `expr::while` with `true` 或 `cfor` with empty clauses
  - `switch` → 首先映射为 `switch` 风格的 `expr::switch`（将 switch-case 转为 switch arms，case 表达式映射为 `pattern` 或 `expr`）
  - `select`（channels）→ 无直接对应，映射为 `switch` 或保留为 `expr::call` 带 `type_text` 注记（后续实现并发/通道需要扩展 runtime）

6. 类型表达式
- 所有类型文本（复杂类型）建议保存在 `type_text` 与 `param.type_name` / `field.type_name` 中，使用 `normalize_type_text` 风格处理空格与符号。
- 例如：`map[string][]*t` → `"map[string][]*t"` 放入 `type_name`。

7. 其他特殊
- goroutine (`go f()`)、defer、recover/panic：
  - `go` 调用映射为 `expr::call` 包装 `stmt::expr` 并用 `deferstmt` / 额外标记区分（建议在 `expr::call` 的 `callee` 名称或附加字段中保留 `go:` 前缀，或扩展 ast 增加 `gocall` 节点）。
- 标签与跳转（label/goto）: s 当前 ast 无直接支持；可将标签作为注解字符串或扩展 ast。

示例映射

go 源：

```go
package p
import "fmt"

func add(a int, b int) int { return a + b }

func (s *s) method(x int) {
    s.val = x
}
```

对应 s ast（伪表示）:

- `sourcefile.package` = "p"
- `sourcefile.uses` = [{ path: "fmt", alias: none }]
- `sourcefile.items` = [
  item::function(functiondecl{ sig: { name: "add", params: [{name: "a", type_name: "int"},{name: "b", type_name: "int"}], return_type: some("int") }, body: some(...) }),
  item::impl(impldecl{ target: "*s", methods: [ functiondecl{ sig: { name: "method", params: [{name: "x", type_name: "int"}] }, body: some(...) } ] })
]

实施建议（分阶段）
1. 编写 mapping 文档（当前文件）。
2. 从 go 源构建解析器输入：两种可选路径
   - 在 `s` 中集成一个 go 词法/语法解析器（难度高）；或
   - 使用现成的 `go/parser`（外部工具）生成 go ast，然后写一个转换器把 go ast 转为 s ast（推荐，先做 poc）。
3. 实现转换器模块：`s/src/tools/go2s/convert` 或 `s/src/cmd/compile/internal/go_import/`。
4. 为常见代码路径添加测试用例（包、struct、func、methods、for-range、if、switch）。

未决问题 / 需要你确认的点
- 是否接受使用外部 `go/parser`（go 工具链）生成 go ast，然后在 `s` 工具链中做转换？（我推荐此方案以节省实现工作）
- 对接口（go interface）映射到 s `trait` 的语义期待：仅保留签名还是需要实现动态分派支持？

下一步
- 如果你同意，我将实现一个 poc：使用 `go/parser` 在工作目录外生成 json 化的 go ast（`go/ast` → json），并在 `s` 中实现一个小转换器读取该 json，输出 `s` 的 `sourcefile`（以 `dump_source_file` 文本形式验证）。

---

文件位置：s/doc/go_to_s_mapping.md
