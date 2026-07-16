# S 原生编译器自举

日常编译器入口是 `src/cmd/compile/main.s`。`src/cmd/compile/seed` 是最小 C 可信根，只负责在没有 S 编译器的机器上生成第一个可执行编译器。

执行：

```sh
make selfhost-check
```

构建链如下：

1. 系统 C 编译器构建 `bin/s_seed`。
2. seed 编译 `src/cmd/compile/main.s`，生成 `stage1.ir` 和 `stage1`。
3. `stage1` 编译同一份 S 编译器源码，生成 `stage2.ir`。
4. `stage1` 从 `stage2.ir` 生成 `stage2`。
5. `stage2` 再次编译 S 编译器源码，生成 `stage3.ir`。
6. 字节比较 `stage2.ir` 与 `stage3.ir`，一致后将 `stage2` 安装为 `bin/s`。
7. 使用 `bin/s` 编译真实测试夹具。
8. 将 `src/cmd/compile/selfhost/lexer.s` 编译为 `bin/s_lexer`，并与 seed lexer 做逐字节 token golden 对比。

产物默认位于 `.bootstrap/selfhost/`。可通过 `SELFHOST_DIR` 修改：

```sh
make selfhost-check SELFHOST_DIR=/tmp/s-selfhost
```

## 当前边界

编译器命令入口和构建控制流已经由 S 源码提供，但 stage1 二进制仍嵌入 C seed 的 lexer、parser、semantic、IR 和 runtime 实现。因此这是可重复的 S-hosted 自举闭环，还不是完全移除 C 前端后的最终状态。

第一个真实迁移组件是 `src/cmd/compile/selfhost/lexer.s`。标识符、关键字、数字、字符串、注释、运算符、行列跟踪和 token 序列生成均在 S 中执行；C runtime 只提供文件读写、单字符读取和字符串切片 intrinsic。`make selfhost-lexer-check` 会生成 C/S 两份 token 文件并要求字节完全一致。

S Lexer 与 Parser 之间使用窄桥接协议：token 的 lexeme 使用十六进制编码，桥接层恢复 `token_vec` 后直接调用现有 Parser。设置下列环境变量即可让完整编译走 S Lexer：

```sh
S_LEXER_MODE=selfhost S_SELFHOST_LEXER=./bin/s_lexer ./bin/s input.s output.ir
```

`make selfhost-check` 会分别使用 seed lexer 和 S lexer 编译同一源码，并要求最终 IR 字节一致。覆盖用例包括小数、科学计数法、非法字符、未闭合字符串和未闭合块注释。

下一阶段应逐个让 `compile/internal/syntax`、`typecheck`、`ir` 和 backend 模块成为实际执行路径，并用相同输入的 IR golden test 验证与 seed 行为一致。C 最终只保留启动、系统调用和 CUDA/CANN C ABI shim。
