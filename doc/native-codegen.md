# P0：函数级原生代码生成

当前 Linux/amd64 默认 `build` 已使用可执行的 S 前端 → 结构化函数 MIR →
结构化函数 SSA → amd64 指令 → ELF。程序行为不经过 `execute_source_main` 或
`execute_mir_graph` 预计算。旧模块仍保留，原有 C 编译能力通过显式 `build --legacy`
使用，Native 失败不会隐式回退。

## 支持的切片

- 每个函数一个直线块；保留全部函数、参数顺序、常量、直接调用和返回。
- `int` 为 signed int64；支持 `+ - * / %`、括号、负号、局部绑定和赋值。
- 前向调用、跨函数调用、整数或 void 返回；System V amd64 寄存器及栈参数。
- 生产入口 `main()` 或 `main(int input)`，返回 int 或 void。单参数入口从 argv[1]
  严格解析十进制 int64，支持负数和边界值。参数错误退出 2。
- 整数加减乘按 64 位环绕，除法向零截断；除零退出 86；INT64_MIN/-1 的商为
  INT64_MIN、余数为 0。

分支、循环、Phi 消除、聚合、字符串、浮点、全局变量、导入、外部链接、泛型和
多结果调用尚不支持；遇到这些输入会报错，未调用函数也必须属于支持范围。

## 使用与验收

```sh
make compiler
./bin/s build test/native-build/program.s -o /tmp/s-native-demo
/tmp/s-native-demo 7
# 退出状态 25
/tmp/s-native-demo 2
# 同一个文件，退出状态 10
./bin/s --emit-amd64 test/native-build/program.s /tmp/demo.s
./bin/s --emit-native-object test/native-build/program.s /tmp/demo.o
make native-codegen-check
make compiler-unit-check
make pipeline
```

`--emit-amd64` 输出 System V 函数汇编，导出 `s_native_entry`，没有 `_start`；
`--emit-native-object` 输出可重定位 ELF，可从独立 C ABI harness 调用。
Native `build` 添加 libc-free Linux `_start` 并链接可执行文件。int 返回值作为退出
状态，仅低 8 位可见；void 返回状态 0。

| 里程碑 | 实际验收 |
| --- | --- |
| P0.1 | MIR→SSA 测试验证全部函数、稀疏 ID、常量、参数位置、调用边和 void。另有多调用 MIR 元数据回归。 |
| P0.2 | 独立对象文件经 C ABI harness 运行；覆盖 7/8 参数、调用栈对齐、callee-saved、调用后活跃值、符号重定位、整数边界与错误 IR。 |
| P0.3 | `bin/s_compiler build` 和 `bin/s build` 均实际生成 Native ELF；禁用 CC 仍通过。对象输出也经独立 harness 执行。 |
| P0.4 | 同一文件输入 7、2、-2 得到退出状态 25、10、254，文件哈希不变；修改常量或被调用函数的运算会改变运行结果。 |

验收还覆盖不支持的源码、嵌入 NUL、保留字、错误目标、源文件别名、工具失败、
原产物保留和临时文件清理。Stage 22 gate 已执行 Native 产物，并拒绝固定行为和
legacy fallback。

## 实现边界

S 负责 MIR→SSA、指令选择、调用 ABI 和栈槽分配。GNU `as` 负责机器指令编码、
重定位及 ELF 对象输出；GNU `ld` 负责链接。第一版将 SSA 值保存到栈槽，使用
caller-saved 寄存器作为临时寄存器，尚未接入优化寄存器分配器。

当前编译器仍由 seed 托管。宿主运行时新增 argv 工具执行、同文件判断、临时目录、
原子安装和严格源码读取接口；它们只服务编译器，不链接进生成程序。

生产前端 `compiler/native_frontend.s` 复用现有 token scanner，直接构造结构化 MIR；
它没有宣称执行完整 canonical AST/Semantic 前端。`core/backend.s` 的 canonical
`build`/`build_object` 已改用 `lower_program_to_mir` 和同一 Native 后端，但该完整闭包
仍受 seed 不支持 enum payload/result 等语法的限制，未计入已运行的验收。

本轮不认定完整自举成立。完整语言支持、canonical 前端闭包、运行时 ABI/栈图、
编译器源码独立生成以及 stage2/stage3 收敛仍需单独验证。旧 22 阶段中的其他部分
仍主要检查证明报告或源码；不能把这些 PASS 扩大解释为完整语言 Native 编译。

## 本轮验证记录

2026-10-17 实际运行：

- `make native-codegen-check`：通过，完整日志 `/tmp/s-p0-full-check.log`。
- `make compiler-unit-check`：通过，日志 `/tmp/s-p0-unit-final.log`。
- `bash script/compile-pipeline-check.sh`：19 个 required gate 通过，3 个 optional
  gate 跳过；Stage 22 为真实 Native 动态执行，日志 `/tmp/s-p0-pipeline-final.log`。
- 显式 legacy Hello World 与 seed parser/semantic/IR C 测试通过。
- 两名独立审查者分别审查后端/ABI与前端/构建集成，发现项已修复并复查。

扩展的既有 `seed/testing/runtime_regression.c` 在本环境报出以下网络相关失败并在
30 秒超时（exit 124）。用 HEAD 中修改前的 runtime.c 重建对照，报错与超时一致，
所以这里没有把该套件记为通过，也没有将它计入 P0 验收：

- `test_runtime_host_socket_operations`
- `test_runtime_tcp_loopback`
- `test_runtime_udp_loopback`
- `test_runtime_socket_timeout`
- `test_runtime_network_poller`
- `test_runtime_dns_and_interfaces`
- `test_runtime_ipv6_loopback`
- `test_runtime_sendfile`
- `test_native_concurrent_loopback`

修改版运行器在 `/tmp/s-p0-seed-regression.GaY466`，对照版、日志和通过的 seed
parser/semantic/IR 运行器在 `/tmp/s-p0-baseline-regression.urqsIC`。网络套件的根因
不在本轮 P0 的已验证结论内。
