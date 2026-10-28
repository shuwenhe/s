# continue 原生全链路验证（2026-10-28）

## 结果

Canonical `continue` 已贯通 Parser、共享 AST、Semantic、MIR/SSA 和原生 amd64 跳转。完整 Stage1 构建及原生验证通过；Stage2 仍未生成，Stage3 未运行，固定点未证明。

## 实现

- 独立 `continue_stmt` / `stmt.continue` 节点。块、普通 switch arm、传统 case body 均保留该节点。
- Semantic 和注解上下文跟踪词法循环深度；循环外报 e3070。continue 的块路径标记为 never，现有 switch 分支类型合并规则继续成立。
- 每个循环分配独立继续汇合块。continue 与正常循环尾部携带绑定值进入该块；Phi 按前驱块 ID 排序。while 回到条件检查；C-for 先执行 post，再回条件。嵌套循环恢复外层目标。
- 复用现有 MIR jump/Phi、SSA 验证和 amd64 生成；没有新解释器路径、C fallback、GC 或固化结果。终止路径之后的不可达代码不生成。
- 类型展开、单态化、标识符与所有权访问器保留/识别该叶节点。辅助旧后端同步控制标记，不参与原生自举路径。

## 验证

`test/native-bootstrap-diagnostic/canonical_continue_production_check.sh`：

- 9 个真实原生程序执行 42：while、条件 for、无限 for、C-for post、嵌套循环、普通 switch、传统 case、所有分支 continue、数组跨继续路径的值及独立快照。
- 同一个动态输入 ELF 在输入 0/6/10/13 时返回 0/9/25/36。
- 3 个循环外 continue 反例均报 e3070，原有输出文件不被替换。
- 上述测试使用新完整 268 文件 Stage1 通过，不仅使用组件编译器。
- 八组生产回归（semantic、external contract、record、array、bool、CFG、store、tuple）和三包 nominal-scope 程序通过。
- 10 组 parser 回归、包含泛型遮蔽/枚举载荷作用域/switch 合并的 semantic diagnostics 通过。
- 全局临时区、参数回收、只读参数快照回归再通过；2000 次只读调用仍为 5 次快照。跨 continue 的数组更新后，旧快照保持独立。

独立静态审查发现传统 case 以 continue 开头时分派顺序错误；已先复现解析失败，再修复并添加原生回归。未发现新的 Phi 顺序或嵌套目标问题。

## 完整构建与实测

冻结输入：`.bootstrap/selfhost-continue-v2/source/`，268 文件及逐文件 SHA-256 清单已复核。

Stage1 SHA-256：`f2b10a292366ef4dd4946fa247eaa2e6dfdad480c1a0566095bc034f10a5b0e2`。

| 项目 | 耗时 | 峰值 RSS | 结果 |
| --- | ---: | ---: | --- |
| Seed → Stage1 IR | 158.76 s | 678028 KiB | PASS |
| 原生 Stage1 生成 | 211.89 s | 716176 KiB | PASS |
| Stage1 → Stage2 | 47.930 s | 1042676 KiB（1018.2 MiB） | exit 1，e3004 |

Parser 完成于 22.815 s；语义检查在 47.880 s 返回拒绝。与上一轮 46.562 s / 1009.4 MiB 的拒绝相比，当前处理到了更后的函数，内存仍约 1 GiB。此耗时是拒绝耗时，不是成功编译耗时。

原始数据：`.bootstrap/selfhost-continue-v2/after-measurements.json`；原生回归：`production.log`；构建：`build.log`。

构建期间曾发现新增辅助后端代码中 `value` 参数遮蔽枚举构造器（backend.s:4045，execute_c_for，exit 1，10.99 s，101976 KiB）；已使用限定名称修复，失败快照保存在 `.bootstrap/selfhost-continue-final/`，没有覆盖该证据。

## 下一处 FIRST RED

- 文件：`src/cmd/compile/internal/base/mapfile_mmap.s`。
- 函数：`compile.internal.base.map_file_mmap`；声明第 2 行，尾调用第 3 行。
- 错误：e3004，function return type mismatch。
- 完整 Stage2：exit 1，47.930 s，1042676 KiB。
- 同源完整输入的语义组件：exit 1，33.72 s，1042176 KiB；打印的失败函数及锚点均为 map_file_mmap。
- 最小复现：`test/selfhost/tuple-tail-return/main.s`。Seed 编译、原生执行 42；新完整 Stage1 拒绝 relay 的元组尾返回（exit 1，<0.01 s，2384 KiB）。

关键形式：

```s
func pair() (string,string) { return "a", "b" }
func relay() (string,string) { pair() }
```

这是当前独立、可复现的正确性阻塞。本轮未扩大为类型系统重构。既有 C-for 不可达除零反例与 option[expr] fixture 继续独立跟踪。

没有 Stage2 ELF、Stage3 ELF 或 convergence completion marker。
