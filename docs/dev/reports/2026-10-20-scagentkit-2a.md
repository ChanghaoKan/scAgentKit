# scAgentKit 2A 与工作流修订阶段报告

日期：2026-10-20（Asia/Taipei）。状态：**2A 实现和计划修订已提交，尚待 CI 与合并；ReAct 循环尚未实现。** 本报告记录实际完成的单轮运输、会话授权和恢复基础，不把它称为正式可用的 ReAct 功能。

## PR 与 commit 范围

| 交付 | PR 与范围 | 当前状态 |
| --- | --- | --- |
| scAgentKit 2A | [#17](https://github.com/ChanghaoKan/scAgentKit/pull/17)，`b5bfbb668c581b043449199343af355249c19fa6..141d7a90697d26579a83ebac104172d38269691e`；实现 commit `7580447027c74a3628811b28ee7c4403db620661`，随后仅收紧注释/帮助文案 | Draft；CI 运行中，未合并 |
| 协议、路线与资格清单修订 | [#18](https://github.com/ChanghaoKan/scAgentKit/pull/18)，实质协议范围 `b5bfbb668c581b043449199343af355249c19fa6..9d32bd3f94f01cd7eefdae0ca9176314bf9defb7` | Draft；本报告作为后续 receipt 提交 |
| Core 兼容说明 | [agentomicsCore #3](https://github.com/ChanghaoKan/agentomicsCore/pull/3)，`d9348c128609857ae4a722a26aa011c95f4aac5d..8416a4499a8c05fd19146550a4a0ea31d4866efc` | NEWS 说明结构化响应需要 assistant role；CI 成功，未合并 |
| E0 已确认交付 | [#16](https://github.com/ChanghaoKan/scAgentKit/pull/16)，工程协议 commit `a7bb0c1507b3381f6977ac8f007d657fb0c11437`，审阅 head `e4ba9333319b8fb7cd5cab56d093ba67837ab234` | 指定 CI 通过后已合并为 `b5bfbb668c581b043449199343af355249c19fa6` |

Core [v0.2.0](https://github.com/ChanghaoKan/agentomicsCore/releases/tag/v0.2.0) 已发布，tag 仍指向 `d9348c128609857ae4a722a26aa011c95f4aac5d`，没有为 NEWS 修改已发布 tag。scAgentKit 的 Imports/Remotes 已在 #17 更新。工程协议的新修订 commit 是 `9d32bd3f94f01cd7eefdae0ca9176314bf9defb7`；E5 的正式实验冻结仍为 `not_frozen`。

## 本阶段实现与复用

2A 新增内部单轮接口及保存于检查点的会话范围，绑定科学输入、簇成员、provider/model、prompt、工具 schema、允许工具和限制。创建时的一次性外发确认包含只读查证范围；严格模式必须有已保存的准确 payload 审批事件，不能拿调用者自己计算的 hash 充当授权。所有外发消息、参数、工具结果和错误接受隐私与大小检查。

按簇保留完整历史，只允许追加，另有全局轮次链和步数检查。发送前记录投递；完成后先写不可变结果检查点，再追加 state event，最后投影到账本。完成事件之后崩溃可恢复已保存结果，之前无法确认投递时不自动重发。缓存读取重新验证权威 receipt、响应和输出限制。模型没有执行工具或批准科学决策的入口。

新增抽象限于会话/能力范围、单轮请求与结果、完成 receipt 和恢复投影。复用现有项目锁、`.sc_run_put`、state/history、外发授权、provider 账本及费用函数；没有第二套审批、账本、event 服务或通用 agent 框架。实现 hash 会改变，旧批准和科学身份不会被重写迁移。

按最新决定，结构化 turn 只记录调用后的 usage 和可得费用；删除新增 token 计数、估算、系数与预留工作，不设金额停止条件。未知用量/费用明确为 unknown，收到响应后的费用缺项不阻断后续调用。旧一次性接口的预算语义为兼容保留，且不把新 turn 的金额计入它的余额。投递不确定与费用不确定是不同状态，补记账单不能解除结构化会话的交付不确定。

## 1.0 验收状态变化

本阶段没有使新的整条 1.0 标准达到“已满足”。原审计是历史快照；下表按当前范围说明增量。

| 标准 | 本次变化与仍缺内容 |
| --- | --- |
| 1、3 启动与一次授权 | 增加受限会话范围的显示和保存，仍为部分满足。标准 3 原有“启动前费用估算”已按维护者决定取消；耗时说明和完整一行体验仍属后续工作。 |
| 4 失败可继续 | 完成单轮投递/缓存/恢复基础和明确状态；全流程 baseline 回退及界面仍需 2B/3，保持部分满足。 |
| 7 第三关证据 | 四工具已有，2A 运输已提交；循环、工具引用校验、第三关外层风险字段和最终 UI 均未完成，保持部分满足。 |
| 8 草稿与批准分离 | 已满足的边界保持；新会话只授权外发，不授予科学批准。 |
| 11、12 评估与重放 | 保存可供后续消费的会话/响应记录，明确同型号对照的资格差异；`sc_react_eval` 和 `sc_react_replay` 尚未实现。11 仍部分满足，12 的用户功能仍未开始。 |
| 13 固定三关 mock 验收 | 本次是单轮与相关回归，不是三关均采纳草稿的 ReAct all 端到端验收，保持部分满足。 |
| 16 项目兼容 | 继续严格科学身份绑定；没有环境等价迁移或旧批准放行，保持部分满足。 |
| 其余 2、5、6、9、10、14、15、17、18 | 状态未提升。安装局部检查、文档计划与离线探针均不能替代对应产品或生物学验收。 |

## 测试与 CI

本次本地实际执行均没有真实 provider 调用：

- R 相关回归 11 个文件、94 个案例：886 条断言通过，0 失败、错误或警告；4 项 Core 0.1.1 专用检查在 0.2.0 下跳过。新单轮文件贡献 142 条，其余 744 条，不重复计数。
- 生产前端源码的离线 DOM 测试 91/91 通过；使用模拟 HTTP，没有浏览器、实际 R 桥接、API 或 key 访问。
- `R CMD build --no-build-vignettes --no-manual` 成功；归档未包含本机路径或已移除的 tokenizer/估算资产；安装到新包目录成功。安装版再执行单轮测试 142 条与 runtime manifest 测试 9 条，均通过。
- 独立复核促成修复交付状态篡改与缓存读取绕过输出上限两处问题；修复后复验通过。三处中断位置均无自动重发；另有 7 个精选案例、28 条断言通过。以上是补充复核，不能累加为独立覆盖范围。
- 完整本地 vignette 构建因缺少 Pandoc 未完成；该限制如实留给配置了 Pandoc 的 CI 验证。安装版检查使用实现 commit，后续 commit 仅修改注释和说明。
- 协议/资格附件验证：75 个相对链接、3 个 JSON 文档/示例、Python AST 和差异检查通过。CASSIA 离线探针在实际 SDK/内存 HTTP 下重新执行 5 个场景、31 次模拟请求，完整结果与保存记录一致；来源和附件 hash 可复查。它不证明真实 API 可用、完整 CASSIA 安装或生物学性能。

#17 当前 CI 运行记录：

- [R-CMD-check](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39411293152)
- [release-archive](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39411293148)
- [installed-runtime-contract](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39411293171)
- [workbench-tests](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39411293202)

上述 CI 在报告时尚未全部完成，不能用本地通过代替。Core #3 的 [R-CMD-check](https://github.com/ChanghaoKan/agentomicsCore/actions/runs/39406274674) 成功。E0 #16 的 [R-CMD-check](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39404216711) 和 [release-archive](https://github.com/ChanghaoKan/scAgentKit/actions/runs/39404216604) 成功后才合并；历史 E0 报告保持原样。

## 论文里程碑进度

已合并阶段 1、Core 2A 和 E0；Core 已发布；scAgentKit 2A 已提交。当前关键项是 **2B 主循环**，同时推进 M1-xAI 资格与适配，E1–E3 可并行开发。

**2B 合并后分为两支并行：UI/评估/重放/文档，以及 B1/B2。** B2 集成需共享诊断可用；E3 的第一关发现率验收需 B1/B2，第三关需 2B。主发现率必须读取生产校验器接受的枚举字段，包括 `doublet_risk`、`ambient_suspected` 等；关键词只作辅助。未就绪能力标 unsupported，不能由 evaluator 模拟生产行为。

两支与 E1–E4、主矩阵适配均完成并冻结后，才进入 E5 正式公开与留出实验。论文主矩阵仍为 DeepSeek + Grok；Anthropic/OpenAI 随后作为正式产品支持，不阻塞论文。`grok-4.7` + Responses 及 CASSIA exact-ID 目前分别有官方资料和离线请求证据，尚无真实冒烟结论，不能标为正式支持。

定位中“用什么证明”的变化：

| 要证明的能力 | 当前进展 |
| --- | --- |
| 生物学上合理的决策 | B1/B2 提前并行，功能与错误注入结果仍未完成。 |
| 显式决策与可复现 | 增加授权、完整历史、交付恢复与缓存完整性测试；完整离线重放仍待 4E。 |
| 证据可核对 | 运输和来源绑定基础已有；工具引用准入和风险字段生产校验待 2B。 |
| LLM、ReAct、ACT 的价值 | 消融契约保持，尚无价值或准确率结果。 |
| 同模型注释比较 | CASSIA exact-ID 离线证据已补齐；Flash thinking、Grok effort/endpoint 差异仍需冻结前处理。 |
| 长期真实使用 | 本次没有增加作者案例、外部验证者或真人使用证据。 |

## 限制与计划调整

步数、单次请求超时和大小限制已有；累计每簇 180 秒、常驻 worker、工具执行、最终核验与回退由 2B 完成。单轮测试不能替代 50k 会话性能或公开 50k 全流程验收。

费用从前置预算工程收缩为事后指标，B1/B2 从全部 ReAct 完成后提前到 2B 合并后并行，均为维护者明确决定。第三关五项风险枚举继续放在版本化草稿外层，保留 annotation.v1。完整性损坏仍阻断，不能用 baseline 回退隐藏。

Grok 与 CASSIA 的型号、生成参数和接口必须在真实冒烟时核实；同型号不等于同推理设置或同历史协议。现有 CASSIA Flash 请求未关闭 thinking，Grok 请求未显式透传 effort；不能据此暗改产品默认或提前声称严格同配置比较成立。具体处理见[资格记录](../../../benchmark/evaluation-v2/manifests/model-qualification.md)。

本次没有访问维护者留出数据，没有运行正式实验，也没有新增自动批准能力。
