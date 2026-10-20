# xAI / Grok 主矩阵资格记录

核实日期：2026-10-20。依据 xAI 官方文档、OpenAPI 和官方 SDK 源码；未读取 API key，未调用推理、tokenize 或账户 API。**官方能力已核实；scAgentKit 适配、真实冒烟和正式实验资格尚未完成。** 主矩阵按维护者决定为 DeepSeek + Grok，M1-xAI 优先；Anthropic/OpenAI 随后作为正式产品支持。费用只在运行后记录和比较。

## 具体候选和参数

| 项目 | 官方资料 | 资格边界 |
| --- | --- | --- |
| API model | `grok-4.7` | 未查到日期后缀快照，不能声称永不更新；记录请求/返回 model 和日期 |
| context | 500,000 tokens | 容量规格，不是费用上限 |
| 知识截止 | May 2026 | 官方 knowledge cutoff，不是训练数据清单或未见数据的证明 |
| 模态 | text/image 输入、text 输出 | 本项目只启用文本 |
| 工具 | custom function calling、structured outputs | 只连接四个本地只读工具，不启用服务端搜索/代码/MCP |
| reasoning | low、medium、high、xhigh，默认 high | 4.7 不能关闭 thinking；低 effort 仍可能产生推理 token |
| sampling | temperature 支持 0–2；官方建议 .7 和 top_p .95 | provider 专属设置在开发资格后冻结，不套用 DeepSeek temperature 0 |

型号和日期依据：[Developer Guide](https://docs.x.ai/developers/grok-4-7)、[型号页](https://docs.x.ai/developers/models/grok-4.7)；生成设置依据：[Reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning)、[最佳实践](https://docs.x.ai/developers/model-capabilities/text/best-practices)。官方 API 目前没有公开 `grok-4.7-fast`；不从其他产品的 fast 名称推导可调用 ID。

原样 CASSIA 的 Grok 请求没有传入 effort，依赖官方默认 high，temperature .7 已在离线 HTTP 请求中核实。因此 high 是无补丁匹配候选；low/medium 可用于开发延迟评估，但正式 preset 须同时核实对照，不能擅自定为已冻结参数。详情见[同型号对照记录](model-qualification.md)。

厂商建议长请求超时及流式调用，但项目已有**每簇 180 秒**边界保持。开发试跑报告实际超时率；不自动放宽、不因一般重试建议覆盖“不确定交付不重发”。

## 推荐 Responses；完整保存协议历史

采用 `POST https://api.x.ai/v1/responses`。Chat Completions 已标 legacy，不能继续作为新 M1-xAI 的默认协议。官方 native SDK/gRPC 也能处理加密历史，但当前没有必要增加该依赖；R/Core 可用原生 REST。依据：[接口比较](https://docs.x.ai/developers/model-capabilities/text/comparison)、[legacy Chat](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions)。

请求明确 `store=false`、`include=["reasoning.encrypted_content"]`；4.7 当前即使不指定 include 也返回 encrypted reasoning，仍显式写入以固定意图。`store=false` 避免以服务保存的 response ID 作为续接依赖，不代表对全部服务日志的零保留承诺。[Responses 参考](https://docs.x.ai/developers/rest-api-reference/inference/responses.md)、[加密 reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning)。

每轮保存完整 `response.output`，下一轮保持全部 item 的内容和顺序，再追加配对的 `function_call_output`。reasoning、message、function-call 项不能缩写成 assistant 文本。每个 call_id 对应一个结果；`parallel_tool_calls=false`，仍校验意外多调用。未知 item 不静默丢弃。固定会话 `prompt_cache_key` 可帮助服务路由，但不预先认定缓存命中。

opaque reasoning 只能是来自本会话的原始协议记录，保存来源、hash、大小及前序响应绑定；不解密、不公开作生物学证据，不接受任意伪造密文。明文仍通过完整外发隐私/大小检查。Core 需要兼容扩展版本化 provider envelope，保留旧 turn/文本接口；复用既有 ledger/state/checkpoint，无新执行框架。不用远端历史、自动 compaction 或后台 agent 来省略本地审计。

## 工具形状与确定性检查

Responses 的工具定义为 `{type:"function", name, description, parameters}`；模型调用是 `{type:"function_call", call_id, name, arguments,...}`；本地结果是 `{type:"function_call_output", call_id, output}`。第一版用 `tool_choice="auto"`；官方指定工具的示例与 OpenAPI 对 name 嵌套位置并不完全一致，不采用尚未资格验证的强制分支。[Function Calling](https://docs.x.ai/developers/tools/function-calling)。

OpenAPI 的 `FunctionDefinition.strict` 标为兼容字段、不支持；对象 schema 的 grammar 说明也不能替代本地严格校验。四个工具的参数、只读权限、汇总隐私和返回大小仍由 R 校验器执行。来源：[官方 OpenAPI](https://docs.x.ai/openapi.json)。

## 用量与费用：调用后记录

Responses 的 `max_output_tokens` 以及 legacy Chat 的 `max_completion_tokens` 只限制可见输出，排除 reasoning 和 function-call tokens。不能将其称全部 token 或费用上限；thinking 不能关闭不再阻塞接入，因为新 turn 没有金额封顶。保留输出长度、步数和时间控制即可。[Responses 参数](https://docs.x.ai/developers/rest-api-reference/inference/responses.md)、[Chat 参数](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions.md)。

核实日全球标准渠道的 USD/百万 token：

| prompt 范围 | 普通输入 | 缓存输入 | 输出 |
| --- | ---: | ---: | ---: |
| <200,000 | 2.00 | 0.50 | 6.00 |
| ≥200,000 | 4.00 | 1.00 | 12.00 |

跨阈值时整次请求使用对应档位；US 区域接口有 10% 溢价，不隐式切换渠道。推理和生成工具调用文本计费，本地工具执行本身没有服务端工具调用费。部分生成前违规拒绝可能收 $0.05/request，生成后拒绝仍可收生成费用；不是全部 refusal 都固定收费或免费。来源：[价格](https://docs.x.ai/developers/pricing)、[区域接口](https://docs.x.ai/developers/advanced-api-usage/regions)。这些单价用于理解运行后记录，不是发送或选择模型的前置门槛。

优先使用服务返回的 `usage.cost_in_usd_ticks / 10^10`；保留原始整数单位，不能混用另一个 `cost_in_nano_usd` 字段或丢失精度。官方定义该金额包括适用折扣和工具费。缺失时按实际 usage 与可核实单价事后折算，仍不足就标 unknown。[Cost Tracking](https://docs.x.ai/developers/cost-tracking)。

保留原始 usage 再作 provider 映射，不能假定 output 总包含 reasoning，或机械使用 input+output=total。官方 Responses 示例的 input=32、output=9、reasoning=110、total=151 提示必须核对字段关系；`context_details` 是上下文信息，不是账单。真实 4.7 字段关系仍需 live smoke 验证。[Responses 返回结构](https://docs.x.ai/developers/rest-api-reference/inference/responses.md)。

不新增计数 API、本地 tokenizer、输入估算、系数或预留前置；价格/usage 未知不阻止新结构化请求。已知费用和未知请求数分报，不能把缺项总和称完整花费。超时不证明免费，投递不确定仍不重发。详见[E5 费用报告](E5_COST_REPORTING.md)。

## 后续资格和来源固定

M1-xAI 的 mock 验收覆盖完整 item 顺序/续传、call_id、非法参数、未知 item、usage 变体/ticks、拒绝、截断/断流、投递不明、完整历史隐私/大小限制、无需远端历史的离线重放。真实资格还须验证账号型号可用性、至少两轮工具调用和合法 final JSON、实际 usage/收费字段、固定工作量的耗时/超时率。真实调用不进 CI；本次均未执行。

公开 OpenAPI 快照 SHA256：`ee418da1de9d6b66648250e1ecb9fdd98cef472dde7b05c66cc9d0db8dad7f1f`。官方 SDK 查阅 commit：`1d9e1dffc9a0521ede0e6bc7f2b906177b940d34`，[chat.py 固定来源](https://github.com/xai-org/xai-sdk-python/blob/1d9e1dffc9a0521ede0e6bc7f2b906177b940d34/src/xai_sdk/chat.py)。这些证明查阅来源与接口声明，不证明 live 服务或单细胞性能。产品清单和正式实验记录须继续区分 source、offline、live 和完整 preset 状态。

## 2026-10-20 后续实现与协议冒烟记录

前文是 E0 的离线资格记录，保留其时间边界。其后 Core #4 实现了原生
Responses，`bc349db` 离线 238 条断言及完整 R-CMD-check 通过。维护者授权的
两轮合成汇总数据协议冒烟在 `8a48825` 上通过：grok-4.7、temperature 0、
effort high、每轮可见输出上限 512、timeout 60 秒，工具调用后返回合法 JSON，
完整 output / encrypted reasoning 原样续传。耗时 6.107 秒，input 2928、
output 165、total 3093、reasoning 134（不重复加到 total），费用由服务 ticks
返回为 $0.003198。没有私有数据、留出集或生物学效果实验。

scAgentKit M1 原生会话与 2B 集成仍为独立草稿；完整公开数据验收和 CASSIA
真实 preset 尚未完成，不标为产品正式支持，也不将开发参数写成正式实验冻结值。
