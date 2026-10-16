# Seed → 固定闭包可行性验证：提前停止

决策日期：2026-10-16。用户已批准在第二轮后提前停止；不等待第三个工作日。
本记录为此路线的最终决策，取代此前继续验证或扩展 Seed 的建议。

```ini
FEASIBILITY_ROUND = 2
FEASIBILITY_STATUS = STOPPED_EARLY
STAGE0_BUILD = PASS
PARSER_ACCEPTED = 250/293
PARSER_REJECTED = 43/293
STAGE1 = NOT_GENERATED
REMAINING_WORK_BOUND = UNKNOWN
CURRENT_ROUTE = NO_GO
SELFHOST = NOT_PROVEN
```

S 基线 commit：99aa95298e01f68fcbeb2c504227e49b25406f30。
GCC 11.5.0 从该版本 Seed C 源码独立构建 Stage0；执行文件的原始 SHA-256 已保存。
入口候选闭包为 293 文件，Manifest SHA-256 为
bb23149b253207518bce0ba15cc2a3aace5ba58aacbbab761191f93634dfecea。

第一轮完整候选闭包编译失败于 assembler.s:50，合并源码位置为 1995:11：
`expected {, got :=`。未生成 Stage1 可执行文件，未运行 Stage1 能力测试。
第二轮逐文件 Parser 检查接受 250、拒绝 43；85.3% 仅是文件语法接受比例，
不是功能完成率，不能预测工作量。每个失败文件只提供首个错误；后续语义、IR、运行时和代码生成仍未闭合。
两轮源码哈希一致。停止后不得自动修复 for 语法、增加 Backend 输入或继续扩展 Seed。

## 证据归档

[归档目录](evidence/stage0-feasibility-2026-10-16/) 保存源码/工具链身份、
构建命令与日志、源码哈希、闭包 Manifest、依赖图、293 项 Parser 结果与逐文件日志。
未归档二进制、空/失败 IR 或 AST dump；执行文件身份由原始哈希记录。
原始二进制仍在 /tmp/s-stage0-feasibility.0sE4Tj，临时目录可能被清理。
命令中的原始绝对路径保留，复现时需调整输出目录；重跑必须取得新的授权。

第二轮命令模板为：对 canonical-closure.txt 每个路径，以相同 Stage0 执行
`timeout 5s stage0 --dump-ast INPUT OUTPUT.ast`，保存退出码和 stderr。
归档不证明新机器或工具链生成相同二进制；它保存的是本次执行证据。

## 重启门槛

仅当出现新的可执行 Stage0 候选、明显缩小且功能完整的源码闭包，或明确增加资源预算时，
才可提交重新评估建议；仍需用户授权，不能自行推翻 NO_GO。
不启动第三条路线，不重复全仓库审计。

本次是否推进 M0–M5 功能验收：NO。
本次是否消除下一里程碑实现能力缺口：NO。
交付为可行性证据归档与正式停止决定，不计为自举功能完成。
