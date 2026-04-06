# Python Migration Checklist

Version: Draft 0.1  
Status: Working Draft

## 1. Purpose

本文档列出 `/app/s` 仓库中当前所有 `.py` 文件的迁移状态，并给出推荐的替换顺序。

目标不是机械地把扩展名全部改成 `.s`，而是优先迁移那些已经具备明确 S 对应实现空间、且不会立即切断宿主验证链的模块。

## 2. Classification

### Group A: Ready To Replace First

这些文件要么已经有清晰的 S 版目标，要么逻辑足够独立，适合第一批开始替换：

- [compiler/typesys.py](/app/s/src/compiler/typesys.py)
- [compiler/ownership.py](/app/s/src/compiler/ownership.py)
- [compiler/ast.py](/app/s/src/compiler/ast.py)
- [compiler/lexer/tokens.py](/app/s/src/compiler/lexer/tokens.py)
- [compiler/lexer/lexer.py](/app/s/src/compiler/lexer/lexer.py)
- [compiler/parser/parser.py](/app/s/src/compiler/parser/parser.py)

当前状态：

- `ast.py` 已有对应 S 版 [frontend/ast.s](/app/s/src/s/ast.s)
- `tokens.py` 已有对应 S 版 [frontend/tokens.s](/app/s/src/s/tokens.s)
- `lexer.py` 已有对应 S 版 [frontend/lexer.s](/app/s/src/s/lexer.s)
- `parser.py` 已有对应 S 版 [frontend/parser.s](/app/s/src/s/parser.s)
- 本次新增 `typesys.py` 对应的 [compiler/typesys.s](/app/s/src/compiler/typesys.s)
- 本次新增 `ownership.py` 对应的 [compiler/ownership.s](/app/s/src/compiler/ownership.s)
- 本次新增最小 golden 验证入口 [compiler/golden.s](/app/s/src/compiler/golden.s)

### Group B: Replace After Core Frontend Stabilizes

这些文件依赖较多，但一旦前端和类型层稳定，就值得逐步替换：

- [compiler/prelude.py](/app/s/src/compiler/prelude.py)
- [compiler/semantic.py](/app/s/src/compiler/semantic.py)
- [compiler/mir.py](/app/s/src/compiler/mir.py)
- [compiler/borrow.py](/app/s/src/compiler/borrow.py)
- [compiler/__main__.py](/app/s/src/compiler/__main__.py)

当前状态：

- `prelude.py` 已有最小 S 版 [compiler/prelude.s](/app/s/src/compiler/prelude.s)
- `__main__.py` 已有最小 S 版 [compiler/main.s](/app/s/src/compiler/main.s)
- `semantic.py` 已有最小 S 版 [compiler/semantic.s](/app/s/src/compiler/semantic.s)
- `mir.py` 已有最小 S 版 [compiler/mir.s](/app/s/src/compiler/mir.s)
- `borrow.py` 已有最小 S 版 [compiler/borrow.s](/app/s/src/compiler/borrow.s)

### Group C: Python Packaging / Test Glue

这些文件主要是 Python 包装、导出或测试 glue，不是最先应该逐个“翻译成 S”的对象：

- [compiler/__init__.py](/app/s/src/compiler/__init__.py)
- [compiler/lexer/__init__.py](/app/s/src/compiler/lexer/__init__.py)
- [compiler/parser/__init__.py](/app/s/src/compiler/parser/__init__.py)
- [compiler/tests/__init__.py](/app/s/src/compiler/tests/__init__.py)
- [compiler/tests/golden.py](/app/s/src/compiler/tests/golden.py)
- [compiler/tests/test_golden.py](/app/s/src/compiler/tests/test_golden.py)
- [compiler/tests/test_mir.py](/app/s/src/compiler/tests/test_mir.py)
- [compiler/tests/test_semantic.py](/app/s/src/compiler/tests/test_semantic.py)

推荐做法：

- 先保留它们，直到 S 版测试入口和 CLI 更成熟
- 后续再把验证逻辑迁到 S 侧或 host bridge 新层

当前状态：

- `golden.py` 已有最小 S 版对应物 [compiler/golden.s](/app/s/src/compiler/golden.s)
- `test_golden.py` 已有对应入口 [compiler/tests/test_golden.s](/app/s/src/compiler/tests/test_golden.s)
- `test_semantic.py` 已有对应入口 [compiler/tests/test_semantic.s](/app/s/src/compiler/tests/test_semantic.s)
- `test_mir.py` 已有对应入口 [compiler/tests/test_mir.s](/app/s/src/compiler/tests/test_mir.s)
- 新增统一 S 侧测试入口 [test_compiler.s](/app/s/src/cmd/test_compiler.s)
- Python 测试文件仍保留，继续作为宿主验证入口

### Group D: Host Bridge Must Stay For Now

这些文件当前是 self-hosted 原型可以“跑起来”和“验证起来”的宿主层，不适合马上删除：

- [runtime/python_bridge.py](/app/s/src/runtime/python_bridge.py)
- [runtime/intrinsic_dispatch.py](/app/s/src/runtime/intrinsic_dispatch.py)
- [runtime/hosted_frontend.py](/app/s/src/runtime/hosted_frontend.py)
- [runtime/check_bridge.py](/app/s/src/runtime/check_bridge.py)
- [runtime/validate_outputs.py](/app/s/src/runtime/validate_outputs.py)
- [scripts/auto_commit_push.py](/app/s/misc/scripts/auto_commit_push.py)

## 3. First Batch

第一批替换建议包含：

1. `typesys.py`
2. `ownership.py`

原因：

- 依赖少
- 易于验证
- 能给 semantic / MIR / borrow 的后续迁移提供稳定基础

## 4. Definition of Replacement

本文档中的“替换”采用渐进式定义：

1. 先新增对应 `.s` 文件
2. 让新文件覆盖 Python 版的核心职责
3. 通过文档或宿主验证确认行为边界
4. 当上层调用链不再依赖 Python 版时，再删除原 `.py`

也就是说，第一阶段不是“立刻删掉 Python 文件”，而是“先让 `.s` 版本成为真实替代物”。

## 5. Next Batch

在第一批之后，最自然的下一批是：

1. `prelude.py`
2. `semantic.py` 的局部子集
3. `__main__.py` 对应的最小 S 版 CLI 入口

当前推进情况：

1. `prelude.py` 的最小 S 版已落地
2. `__main__.py` 的最小 S 版 CLI 入口已落地
3. `golden.py` 已有最小 S 版验证入口
4. `semantic.py`、`mir.py`、`borrow.py` 已有最小 S 版主链替代物
5. 下一步建议继续清理 Python 测试 glue，并逐步缩小 runtime 宿主层
