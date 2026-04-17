# Go → S AST 映射草案

目标
- 将 Go 语言的语法节点映射到 `s` 语言现有的 AST（`s/src/s/ast.s`）结构。
- 优先保持语义信息（名称、签名、类型文本、表达式结构），以便后续实现转换器或前端兼容层。

设计原则
- 保留原始 Go 源的可重建信息：尽量把 Go 节点中无法直接映射到 S 的部分以原始文本或 `type_text` 字段保留在 AST 中。
- 逐步增强：先实现表面语法（parse-only）映射，再逐步补充语义（types、methods、interfaces、channel 等）。
- 尽量复用 `s` AST 节点：如 `Expr::Call`、`Expr::Member`、`Expr::Index`、`Stmt::Var`、`FunctionDecl` 等。

概览（高层）
- Go `File` → `SourceFile`
  - package name → `SourceFile.package`
  - import list → `SourceFile.uses`（映射为 `use`，as 保留到 alias）
  - top-level declarations → `SourceFile.items`

详细节点映射

1. 包与导入
- Go: `ast.File.Name` → S: `SourceFile.package`（字符串）
- Go: `ast.ImportSpec` → S: `UseDecl { path, alias }`
  - 保留原始路径文字（去引号），若 `ImportSpec.Name` 非空则映射到 `alias`。

2. 类型声明
- Go: `ast.TypeSpec`：
  - `type T struct { ... }` → S: `StructDecl { name: T, fields: [...] }`
    - 字段名/类型映射到 `Field { name, type_name }`；若无命名字段（匿名嵌入）则用类型文本放到 `type_name`，字段名可设为 `_embed_N`。
  - `type T interface { ... }` → S: `TraitDecl { name: T, methods: [...] }`（接口映射为 trait）
    - interface 方法签名映射为 `FunctionSig`（返回 `Option[string] return_type`），保留参数名/类型文本。
  - 其他类型别名或自定义类型（例如 `type MyInt int`）→ 生成 `StructDecl` 不合适，建议作为 `use`/`type_text` 的注记：在 AST 中以 `StructDecl` 或 `EnumDecl` 之外保留到 `impl`/注释，或扩展 AST（后续）。

3. 变量与常量
- Go: `ast.ValueSpec` in top-level → S: `VarStmt` 或 `ConstDecl`（S 当前 AST 有 `VarStmt` 与 `ConstDecl` 位于 parser 层）
  - 多重声明（`var a, b = 1, 2`）可拆分为多个 `VarStmt`。
  - 未显式类型时将类型留空，`type_text` 可用字符串保存（例如 `int`、`map[string]int`）。

4. 函数与方法
- Go: `ast.FuncDecl`
  - 非方法（Receiver == nil）→ S: `FunctionDecl`：
    - `FunctionSig.name` = func name
    - `FunctionSig.params` = 参数名与 `type_name` 使用 `Param { name, type_name }`（若无参数名，生成 `_argN`）
    - `FunctionSig.return_type` = 单一或多重返回：若多重返回，用 `type_text`（例如 `(int, error)`）或映射到一个 tuple 表示法保存在字符串
    - body → `Option[BlockExpr]`（若 `FuncDecl.Body == nil` 则 Option::None）
  - 方法（有 Receiver）→ S: `ImplDecl` with `methods` 包含该方法：
    - `target` = receiver type as string（如 `*T` 或 `T`）
    - 方法本体映射成 `FunctionDecl`，`is_public` 根据首字母大小写决定

5. 语句与表达式（逐项）
- 基础字面量：`BasicLit`（INT/STRING）→ `Expr::Int` / `Expr::string`（保留文字）
- 标识符：`Ident` → `Expr::Name`（`name` 字段）
- 二元/一元表达式：`BinaryExpr` / `UnaryExpr` → `Expr::Binary` / 以 `Borrow` 表示的借用（若用 `&`）
- 函数调用：`CallExpr` → `Expr::Call`（callee 映射，args 列表映射）
- 选择器表达式：`SelectorExpr` (`x.y`) → `Expr::Member`（target: `x`，member: `y`）
- 索引/切片：`IndexExpr` / `SliceExpr` → `Expr::Index` 或保留 `type_text`（切片语法）
- 赋值、短声明：`AssignStmt` / `DeclStmt` → `Stmt::Assign` 或 `Stmt::Var`（short `:=` 映射为 `VarStmt`）
- `if/for/switch/select`：
  - `if` → `Expr::If`
  - Go `for` 三类：
    - `for init; cond; post` → `Stmt::CFor`（C-style for）
    - `for range` → `Expr::For`（将 range target 映射到 `iterable`，`names` 为迭代变量）
    - `for {}`（无限循环）→ `Expr::While` with `true` 或 `CFor` with empty clauses
  - `switch` → 首先映射为 `match` 风格的 `Expr::Match`（将 switch-case 转为 match arms，case 表达式映射为 `Pattern` 或 `Expr`）
  - `select`（channels）→ 无直接对应，映射为 `match` 或保留为 `Expr::Call` 带 `type_text` 注记（后续实现并发/通道需要扩展 runtime）

6. 类型表达式
- 所有类型文本（复杂类型）建议保存在 `type_text` 与 `Param.type_name` / `Field.type_name` 中，使用 `normalize_type_text` 风格处理空格与符号。
- 例如：`map[string][]*T` → `"map[string][]*T"` 放入 `type_name`。

7. 其他特殊
- goroutine (`go f()`)、defer、recover/panic：
  - `go` 调用映射为 `Expr::Call` 包装 `Stmt::Expr` 并用 `DeferStmt` / 额外标记区分（建议在 `Expr::Call` 的 `callee` 名称或附加字段中保留 `go:` 前缀，或扩展 AST 增加 `GoCall` 节点）。
- 标签与跳转（label/goto）: S 当前 AST 无直接支持；可将标签作为注解字符串或扩展 AST。

示例映射

Go 源：

```go
package p
import "fmt"

func add(a int, b int) int { return a + b }

func (s *S) Method(x int) {
    s.val = x
}
```

对应 S AST（伪表示）:

- `SourceFile.package` = "p"
- `SourceFile.uses` = [{ path: "fmt", alias: None }]
- `SourceFile.items` = [
  Item::Function(FunctionDecl{ sig: { name: "add", params: [{name: "a", type_name: "int"},{name: "b", type_name: "int"}], return_type: Some("int") }, body: Some(...) }),
  Item::Impl(ImplDecl{ target: "*S", methods: [ FunctionDecl{ sig: { name: "Method", params: [{name: "x", type_name: "int"}] }, body: Some(...) } ] })
]

实施建议（分阶段）
1. 编写 mapping 文档（当前文件）。
2. 从 Go 源构建解析器输入：两种可选路径
   - 在 `s` 中集成一个 Go 词法/语法解析器（难度高）；或
   - 使用现成的 `go/parser`（外部工具）生成 Go AST，然后写一个转换器把 Go AST 转为 S AST（推荐，先做 PoC）。
3. 实现转换器模块：`s/src/tools/go2s/convert` 或 `s/src/cmd/compile/internal/go_import/`。
4. 为常见代码路径添加测试用例（包、struct、func、methods、for-range、if、switch）。

未决问题 / 需要你确认的点
- 是否接受使用外部 `go/parser`（Go 工具链）生成 Go AST，然后在 `s` 工具链中做转换？（我推荐此方案以节省实现工作）
- 对接口（Go interface）映射到 S `trait` 的语义期待：仅保留签名还是需要实现动态分派支持？

下一步
- 如果你同意，我将实现一个 PoC：使用 `go/parser` 在工作目录外生成 JSON 化的 Go AST（`go/ast` → JSON），并在 `s` 中实现一个小转换器读取该 JSON，输出 `s` 的 `SourceFile`（以 `dump_source_file` 文本形式验证）。

---

文件位置：s/doc/go_to_s_mapping.md
