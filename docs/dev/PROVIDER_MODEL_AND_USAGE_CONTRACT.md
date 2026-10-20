# Provider 型号、协议与用量契约

2026-10-20。按维护者最新决定修订：论文主矩阵是 **DeepSeek + Grok**；费用只在运行后记录并比较。本文件是实现契约和来源核实，不是已实现适配器或真实 API 验证报告。E0 历史阶段报告保留原样。科学定义见[协议 v2](EVALUATION_PROTOCOL_V2.md)，顺序见[论文里程碑](PAPER_MILESTONE_PLAN.md)。

## 支持范围与实施顺序

产品正式支持目标是 DeepSeek、xAI Grok、Anthropic Claude、OpenAI，由用户选择。每家分别提交 M1 PR，型号逐个验收。先做论文需要的 **M1-xAI：原生 Responses**；Anthropic/OpenAI 的正式支持随后实现，可在论文之后。其他届时已支持 provider 各做公开开发集 N=3 `accept_drafts` 可用性验证，与论文主准确率/稳定性实验分开，不阻塞主矩阵。

DeepSeek 初始产品配置仍为 Flash、thinking disabled、temperature 0。Grok 推荐候选 `grok-4.7`：官方自定义工具能力已核实，Core 与 scAgentKit 引擎的合成 live smoke 已通过，公开真实数据产品验证仍未完成。精确型号和生成设置须与对照 preset 一起冻结；不根据报价选型或增加总费用估算门槛。

CASSIA 1.4.0 的实际 SDK/内存 HTTP 探针验证了 Flash、V4 Pro、Grok4.7 在三个 agent 中的精确型号透传；Flash 的 requested none 没有关闭 thinking，Grok 的 requested effort 没有传入。V4 Pro non-thinking/temperature 0 与 Grok4.7 默认 high/temperature .7 是无补丁匹配候选，尚未成为正式实验配置。修复传输参数或调整受影响 arm 必须在冻结前记录；不因此暗改产品默认，也不把同型号等同于同协议。见[对照资格](../../benchmark/evaluation-v2/manifests/model-qualification.md)。

## 费用只在运行后报告

新结构化 turn **没有金额上限**，复用现有账本逐次保存服务返回的 usage、可得费用、时间和状态。没有新增计数 API、本地 tokenizer、输入估算、安全系数、复杂预留或通用费用模式。价格或费用字段未知不成为新 turn 的发送阻塞条件。历史一次性文本接口的预算行为为兼容保留，历史账本/授权/hash 不重写；不把旧预算机制扩展成新 turn 的金额上限。

优先保存服务报告的实际收费；只有实际 usage 和适用单价时，运行后折算并明确标“按用量折算”，附币种、价格来源/日期、缓存和推理字段口径。无法计算时为 unknown，不记零。费用报告分别列已知金额、按用量折算金额和费用未知的请求数，不把缺项的总和称为完整总花费。模型比较在完成运行后按相同数据、方法和重复范围汇总；具体字段见[E5 费用报告](../../benchmark/evaluation-v2/manifests/E5_COST_REPORTING.md)。

不确定交付仍不得自动重发。即使没有合法草稿，也要保存收到的 usage/拒绝/失败状态；超时不意味着服务没有计费。后续拿到账单证据时追加 receipt，不改写原事件。不因为费用超出某个估计停止新 turn，因为新 turn 没有此估计或金额门槛。

## 授权、只读和审批保持

创建项目时的一次性会话授权包含默认 ReAct；严格模式仍逐次确认准确 payload。全外发历史、工具定义、参数、结果和错误都通过既有隐私/大小检查。每轮保存 payload hash、response hash、投递状态和 event；state/ledger/checkpoint 仍是权威，不新增账本或会话状态库。

工具只读，只返回汇总统计。每簇 6 turn、每次注释 60 turn、每簇 180 秒、每工具 60 秒的默认边界不变；厂商建议更长请求超时不会自动扩大这些限制。模型/工具/格式/时间失败按合法 baseline 回退，无 baseline 标 `baseline_unavailable`；完整性损坏阻断。保存仍不等于批准，模型永远不能批准。

## M1-xAI 协议要点

使用 `POST https://api.x.ai/v1/responses`，`store=false`，显式 `include=["reasoning.encrypted_content"]`，`tool_choice="auto"`、`parallel_tool_calls=false`。保存并按原顺序续传完整 `response.output`，追加配对的 `function_call_output`。不把历史压成纯文本，不依赖仅远端 response ID 才可恢复的状态。`store=false` 不能被表述为对服务全部日志的零保留承诺。

必要的 encrypted reasoning 作为版本化 provider envelope 的私有协议原件保存，绑定当前会话及响应 hash；不解密、不当作生物学证据或公开预览。未知 item 类型不能静默丢弃。明文仍接受完整隐私检查。这个兼容扩展复用 Core turn 与既有审计，不引入新执行框架。

Grok4.7 不能关闭 reasoning，默认 effort high；其他 effort 是否用于实验须连同 CASSIA preset 核实。可见输出长度字段不覆盖全部推理和函数调用 token，不能称费用上限。工具 `strict` 在官方 OpenAPI 标为兼容但不支持，R 参数校验继续负责确定性检查。详细来源、模型限制和当前价格见[xAI 资格记录](../../benchmark/evaluation-v2/manifests/xai-qualification.md)。

不启用服务端 web/X/code 工具、自动 context compaction、后台 agent 或未审查的模型切换。CASSIA 的 legacy Chat 路径可作为同型号的方法对照，但必须披露其不保留 Responses 的 encrypted reasoning；ReAct on/off 的单因素结论来自 scAgentKit 内部配对消融。

## 型号清单与验收

清单保存 provider、精确 API ID、返回 model、endpoint、日期/别名语义、支持参数、工具能力、source/offline/live 状态及来源。官方文档、离线 mock、真实开发冒烟、完整 preset 分列，只有相应验收完成才称产品已验证。用户可填写清单外型号并明确标 `unverified`；未实现 provider 返回 unsupported。未知价格不禁止发送，未知工具协议不能伪称已支持。

验收复用现有测试机制：完整工具历史和 opaque item 顺序、参数/大小/隐私、投递不明不重发、拒绝/缺 usage、实际用量字段映射、离线重放。真实冒烟在 CI 外执行并记录结果；本次没有调用任何 provider API，也没有真实费用或准确率结果。


M1-xAI 当前原生 Responses 适配覆盖结构化 ReAct turns。原有一次性草稿
仍沿用既有文本 provider 路径；本阶段没有把三个审批的所有调用都迁移为
Responses，也不据此宣布完整产品支持。会话能力记录写入合成冒烟验证日期和
`formal_support=false`；正式资格仍以完整产品/公开数据验收为准。
