# S 编写的模块 MIR → C 消费端

运行：`bash test/mir-c-codegen/check.sh`。需要 GCC（构建现有 Seed 宿主）及可配置的
`CC`（编译生成的 C）。测试产物放在独立 `/tmp/s-mir-c-codegen.*` 目录，记录版本和输入哈希。

生产实现：`src/cmd/compile/internal/codegen/c_program.s`，入口
`emit_mir_program_c(mir_program) -> c_program_result {code, error}`。
它复用 `mir/program.s` 的类型和 `lower_mir_program` 验证器，不接受源码、AST 或预先计算的输出。
返回 C translation unit；公开函数 `s_mir_entry` 与 MIR 入口具有对应的整数参数/返回值。
测试 C runner 仅将运行期命令行参数传给这个入口并打印返回值。

已实现范围：单直线块；int64 常量、copy、add/sub/mul/div/mod；直接/前向函数调用；
零或一个整数返回值及 void 调用。整数加减乘采用 64 位回绕，除法向零截断；
INT64_MIN / -1 返回 INT64_MIN、对应余数为 0；除零退出 86。生成代码没有 C 有符号溢出 UB。
这些是本消费端的明确契约，不是对整个 S 语言规范完成度的声明。

不支持：CFG/条件分支、循环、多个返回值、泛型实例化、对象/数组布局、外部符号链接。
非法 MIR 或当前不支持的类型明确拒绝，失败时 code 为空；不尝试其他 Backend。
符号通过函数索引映射为 C 名称，避免包名碰撞或拼接为 C 语法。

验证包括运行期输入、跨函数调用、保持未调用函数、修改 IR 常量/操作后行为改变、
正负数除法与余数、整数边界/回绕、void 调用、除零，以及非法指令/值/类型/目标/终结器拒绝。
已验证模块也可被修改，因此消费端重新执行现有 MIR 验证器。

宿主边界：测试用现有 Seed hosted runner 执行真实 S 发射器；该宿主仍含 Seed 的 C runtime。
最终测试程序由发射出的普通 C 编译生成，不包含该解释器。不能把发射器宿主认定为可信 Stage0。
fixture 使用现有 `lower_mir_program` 构造、验证模块；没有声称执行了 Canonical Source Parser/
Semantic/`lower_source_program`。完整 Source → MIR → C Pipeline 仍待接入。

本轮还修复宿主的 record 别名生命周期错误：复制时分配有界的新身份，不再累加旧名字，
避免嵌套 MIR 字段名超出 runtime_values 的键长后被截断。MIR 发射集成测试会复现旧故障；
record_transfer.s 额外覆盖数组 record 多次传递。未扩展 Seed 的语言功能。

验收定位：这是 MIR → C → Host CC → Executable 的局部运行证据。
Driver/Pipeline Backend 接入、293 文件闭包编译、Stage0→Stage1 和 Self-host 仍未证明。
此前停止的 Seed 完整闭包路线不因这些测试自动重启。
