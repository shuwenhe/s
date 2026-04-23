# IR 设计草案（AST / Types / MIR）

目的：为将 `s` 编译器对齐到 Go 编译器的分层管线，定义统一的中间表示（IR）边界与数据结构草案，作为后续实现 `noder`、`mir->ssa` 降级与后端生成的参考。

基本原则：
- 明确分层：Syntax -> Typed AST -> MIR -> SSA/Backend
- 保持简单可验证：每一层应支持序列化/打印与单元测试（便于逐步替换旧实现）
- 可扩展性：支持增加 borrow/ownership 标注以及架构特定指令/约束

建议文件布局：
- `internal/syntax/`：现有解析器，输出原生 syntax AST（保留）
- `internal/ir/ast.s`：Typed AST（统一节点，包含类型注释）
- `internal/ir/types.s`：编译器内部类型表示（Size/Ptr/泛型占位）
- `internal/ir/mir.s`：函数级中间表示（控制流图、局部槽、终结器）

核心数据结构草案（概要）
- program_ir: 包含若干 `package_ir`（或单一文件包）
- package_ir: 名称、文件列表、Top-level decls
- decl_ir: `func_decl` | `type_decl` | `const_decl` | `var_decl` | `impl_decl`
- func_decl: 名称、签名（params, returns, generics）、Typed Body (`block_ir`)
- expr_ir: 各种表达式节点，且每个 expr 有 `type: type` 字段
- stmt_ir / block_ir: 语句序列 + 最终表达式

Types（概要）
- Primitive: Int32/Bool/String/Unit
- Pointer/Ref: `&T` / `&mut T`
- Slice: `[]T`
- Named/Generic: 标记基础名与参数
- TypeUtilities: `SameType`, `IsCopy`, `BaseType` 等

MIR（概要）
- Function MIR: list of BasicBlocks, locals (slots), entry/exit
- BasicBlock: id, statements[], terminator
- Statement kinds: assign, move, copy, drop, eval (calls/ops)
- Terminator: return, branch(cond, then, else), jump(target)

接口约定
- Parser -> `internal/ir/ast.s`: 提供 `from_syntax(syntax.file) -> ir.package_ir` 的转换
- `semantic`（类型检查）为 Typed AST 注入 `type` 字段并返回错误列表
- `mir` 接受 Typed AST 并生成 `mir.function`（可打印/序列化），便于单元测试
- 后端实现逐步消费 MIR：先实现简单直接生成 asm，再逐步引入 SSA 降级与优化

下一步
- 在 `internal/ir/` 下添加 `ast.s`、`types.s` 骨架并实现基本构造与打印函数（已开始）
