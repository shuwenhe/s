**完整原生自举尚未完成。新的完整原生 Stage1 已通过 canonical enum 编译和执行，Stage1 → Stage2 当前失败于真实 canonical Parser 的 `struct` 解析。**

本次结果来自共享工作区 `/app/shuwen/s`，单 Agent 执行，原生类型、借用、schema、MIR、SSA 和 ELF 门禁保持开启。没有调用 Seed/C 代替 Stage1 生成 Stage2，也没有丢弃不支持的声明。

| 验收项 | 最新结果 |
| --- | --- |
| `make compiler` | PASS，95 模块，输出原生 ELF `bin/s_compiler` |
| `make selfhost-canonical-production-check` | PASS，8 个专项脚本，包括语义正反例、enum MIR 身份校验和原生执行 |
| 完整源码闭包 → Seed IR | PASS，264 个 S 模块 |
| Seed → 完整原生 Stage1 | PASS |
| 完整 Stage1 ELF 校验 | PASS |
| 完整 Stage1 → canonical enum 程序 ELF | PASS，输入 2 → 42、7 → 47；标签 40 改为 41 后 2 → 43 |
| 完整 Stage1 的 Public MIR、语义正反例 | 已执行，见对应日志 |
| Stage1 → 完整 Stage2 | FAIL：`canonical parser:16: unsupported top-level declaration: struct` |
| Stage2 → Stage3 | NOT RUN |
| Stage2 / Stage3 汇编、二进制字节一致 | NOT PROVEN |

`make selfhost` 实际退出码为 2；`.bootstrap/native-imports/.complete`、Stage2 ELF、Stage3 ELF 均不存在。完整 Stage1 SHA-256：`6ae92caff9d6ad61b59f22d42fed590eedbecbcb22eeebbc00054787834e53d2`。

真实生产调用链：

```text
compiler_main → handle_compile_unit → canonical_source_to_mir
  → compile.internal.syntax.parse_source → canonical_parse → shared AST
  → compile.internal.semantic.check_source_file
  → compile.internal.ir.lower.lower_source_program → typed MIR
  → native_program_assembly → lower_function_mir_to_ssa
  → emit_function_ssa_amd64 → S-NATIVE-AMD64-V1 assembly
--emit-bin → as / ld → static native ELF
```

`compiler/main.s`、`compiler/bridge.s`、`core/native_build.s` 的实际生产入口均接入同一个 canonical producer；`native_source_to_mir` 仅保留在旧实现文件中，没有生产调用点。`make compiler` 已使用 `--compile-native-unit` 和 `--emit-standalone-amd64` 构建，不再将 hosted runner 作为生产 `s_compiler`。这不改变完整自举的 Seed → Stage1 → Stage2 → Stage3 验收拓扑。

最小程序没有跳过 enum：共享 AST 保留完整声明、variant 和显式标签，Semantic 检查声明与表达式类型，MIR 携带 `main.Code` 名义类型、`main.Code.answer` 符号和标签 40。MIR 复验调用参数身份和声明标签后，SSA 才将 enum 表示降为整数。伪造标签、错用另一种 enum、缺失声明的 MIR 都被独立回归拒绝。缺失 variant、重复 variant、直接 enum + int 的源码均在真实 Semantic 阶段拒绝并保留原输出文件。

完整 Stage1 的 enum 实测命令与保留产物：

```sh
S_CANONICAL_ENUM_WORK="$PWD/.bootstrap/canonical-production/full-stage1-enum" \
  bash test/native-bootstrap-diagnostic/canonical_enum_production_check.sh \
  "$PWD/.bootstrap/native-imports/stage1"
```

- `.bootstrap/canonical-production/full-stage1-enum/main.s`、`main.mir`、`main.sasm`、`main`：真实输入、IR、目标汇编和 ELF。
- `.bootstrap/canonical-production/full-stage1-enum/changed.s`、`changed.sasm`、`changed`、`results.txt`：源码变化和动态执行结果。
- `.bootstrap/canonical-production/full-stage1-enum/{missing,duplicate,wrongtype}.log`：Semantic 拒绝证据。
- `.bootstrap/canonical-production/full-stage1-boundaries.log`：完整 Stage1 实际 Parser / Semantic / MIR 边界跟踪。
- `.bootstrap/canonical-production/full-stage1-public.log`、`full-stage1-semantic.log`：完整 Stage1 的额外验证。
- `.bootstrap/canonical-production/production-check.log`：原生生产构建和 8 项专项门禁，退出码 0。
- `.bootstrap/canonical-production/selfhost-final.log` 与 `.bootstrap/native-imports/stage{1,2}-*.log`：完整自举实际结果。
- `.bootstrap/canonical-production/verification.json`、`source-hashes.txt`、`review-snapshot/`：结果摘要、源码身份和共享工作区快照。

当前 FIRST RED 对应生产闭包首个文件 `src/cmd/compile/internal/lexer/token/token.s:16` 的 `struct token`。它前面的 scalar `enum token_kind` 已被真实解析。Parser 当前没有完整 struct/receiver/控制流语法实现，后端也仍对 record、字符串/数组、CFG 和泛型 payload enum 缺少完整的生产 lowering；仅增加一个接受 `struct` 的分支或跳过声明不能生成合法 Stage2。generic/payload enum 声明不会被悄悄擦除，尚未实现的 monomorphization/layout 会明确拒绝。

接入过程中修复的真实问题及回归：

- 类型解析 `parse_type → is_builtin_primitive → parse_type` 无限递归，以及类型一致性门禁所需的 tuple/array/reference 形状：`canonical_typesys_check.sh`。
- `infer_expr`、`check_stmt` 丢弃 switch 分支结果，显式 return 被当作 unit fallthrough：`canonical_semantic_ast_check.sh`、`canonical_semantic_production_check.sh`。
- `sort_diagnostics` 调用空的 `insert_diagnostic` 丢失全部错误：补齐真实排序与返回状态，`canonical_diagnostics_check.sh`。
- 完整闭包中 `param[]` 构造名称歧义：使用明确的 canonical AST 类型；完整 Stage1 重新生成通过。
- 原生验证同时覆盖合法程序通过和非法程序拒绝，不能将之前错误被吞掉的结果作为当前语义门禁证据。

此前的 hosted 诊断 runner 在执行新的真实 AST Parser 时仍有内存耗尽问题，未计为通过；它不进入现在的生产编译或原生自举路径。

此前里程碑与独立失败记录保留如下；这些旧模块数和旧诊断不代表最新自举结果。

本轮修复已越过 discard、声明种类、字符串 contains、AST 字段/box 接口、具体 option 类型、限定数组字面量、二值返回、缺失 IR 语句构造、Stage5 编译闭包及 AST 访问、stdout 桥接、SSA ID 比较等阻塞。两个旧占位映射已移除：逃逸点估算调用真实 S 实现，借用报告调用现有 S `analyze_function`；没有添加成功 stub 或改用 C/解释器生成 Stage2。

独立失败保留：

- `native_import_return_check.sh`：综合 record 门禁本轮仍复现“accepted unimported function return type”，日志 `.bootstrap/shared-contains/record-ir-stmt.log`；没有归因于本轮借用修复。
- `test_semantic_qualified_module_call_success`：保留先前独立失败记录，本轮未宣称修复或重新验证该 C 单元用例。
- MIR 所有权语句构造函数对按值数组参数的追加没有传回调用方：新增独立复现位于 `.bootstrap/shared-contains/ownership-array-mutation-repro.sh`，日志 `.bootstrap/shared-contains/ownership-array-mutation.log`；原生程序实际返回 20（调用方语句数量为零），脚本退出 1。该问题尚未修复，未被计为通过。
