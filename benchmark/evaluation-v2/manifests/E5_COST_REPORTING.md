# E5 运行后用量与费用报告

2026-10-20。这是结果字段与汇总口径，不是发送前报价单。主矩阵为 DeepSeek + Grok；不要求先估算总费用，不新增 token 计数、余量、费用封顶或预留系统。当前没有真实运行金额。协议见[provider 型号与用量契约](../../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md)。

## 记录单位

每次实际请求绑定 `run_id + dataset_id + input_hash + method + config_hash + replicate_id + stage + request_id`。复用已有 ledger/event，结果表仅投影，不建另一账本。至少保存：

| 字段组 | 内容 |
| --- | --- |
| 请求身份 | provider、请求/返回 model、endpoint、时间、阶段/簇、payload/response hash、投递/完成/失败状态 |
| 用量 | 原始 usage；可映射的输入、缓存、输出、推理及 total；各字段是否包含其他项的 provider 口径；缺失为 null |
| 金额 | 服务报告金额与原始单位；没有报告金额时可按实际 usage 事后折算，附价格来源/日期、币种及适用档位；无法确定为 unknown |
| 时间与结果 | 耗时、超时、拒绝、回退原因、工具调用数/turn 数；未发送与发送后失败分开 |
| 证据 | 记录来源、对应 ledger/event；后补账单 receipt 与原请求关联，保留原始记录 |

服务报告金额和按用量折算金额是同一请求的替代估价来源，不能相加。推理 token 与 output 的包含关系依 provider 核实，不能重复计费。xAI 优先使用 `usage.cost_in_usd_ticks / 10^10`，保留原始 ticks；缺失不推断免费。某些生成前违规拒绝可收费 $0.05，不能把所有 refusal 一律记 $0.05 或零。来源见[xAI 资格记录](xai-qualification.md)。

## 汇总与模型比较

按数据集、split、方法、冻结配置和实际模型分别汇总。主实验每配置 N=5；开发与其他 provider 可用性验证 N=3 单列。重复次数不等于成功次数，报告计划、尝试、完成、失败数量。未运行项目的数值保持 null/not_run，不填零。

- scAgentKit 全流程分第一关、第二关、第三关 baseline 和额外 ReAct；单次注释表也分别列 baseline/额外 ReAct。工具本地耗时与 API 费用分开。
- CASSIA 的 annotation、validator、formatter 及显式启用的额外 agent 都计入；实际 retries/预检同样计入，不能用一次调用价格代表整个方法。
- 每次运行报告已知金额总和、来源覆盖率、费用未知的请求数、tokens 和耗时；跨重复报告均值/范围及有效分母。缺费用时称“已知部分费用”，不能作完整总价或据此断言哪个模型更便宜。
- on/off 和其他消融用冻结的配对配置比较；共用控制组只计一次，列明 run IDs。对照共享的预处理记录成本归属，避免漏算或重复计入。
- 公开开发、公开基准、维护者留出和其他 provider 产品验证分别汇总。留出不用于开发估价；由维护者正式运行后提交真实记录。

费用只是运行后的比较指标，不作为模型选择或阶段启动的报价门槛。步数、时间、隐私、科学审批和投递不明不重发仍有效。真实实验仍需满足协议的数据/代码/preset 冻结与执行授权；本文件不授权真实 API 调用。单次请求和结构化 turn 均不设金额上限。
