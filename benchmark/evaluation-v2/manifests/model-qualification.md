# CASSIA 同模型对照资格核实：DeepSeek 与 Grok

核实日期：2026-10-20。范围：官方源码、官方 API 文档、离线 SDK/HTTP 请求探针；**未读取真实 key、未调用 provider API、未运行真实注释实验**。主矩阵按维护者最新决定为 DeepSeek + Grok；M1-xAI 先实现，Anthropic/OpenAI 的正式产品支持随后完成。费用仅在运行后比较，费用估算/预留不是本资格核实的准入条件。

本报告修正此前资格记录中过宽的说法：CASSIA 的 DeepSeek thinking 控制依赖型号名包含 `deepseek-v4`，并非适用于所有 DeepSeek 型号。旧的 Anthropic 主矩阵建议也已被维护者后续决定替代。

## 结论

**CASSIA 1.4.0 可以作为主矩阵的同型号注释对照候选。离线实际 SDK 请求已证明 `deepseek-flash`、`deepseek-v4-pro`、`grok-4.7` 在注释、验证、格式化三个角色中均原样透传，没有改成默认型号或 OpenRouter 别名。但同型号不代表同推理配置。**

| 候选 | exact model 透传 | 与 scAgentKit 预期配置的关系 | 资格判断 |
|---|---|---|---|
| `deepseek-v4-pro`，官方 DeepSeek URL | 三个角色均通过 | `reasoning="none"` 真正生成 `thinking.type="disabled"`；temperature 0 原样发送；CASSIA 输出参数固定 16384 | 最直接的未修改 CASSIA 主矩阵候选。需要冻结 scAgentKit 同型号和生成配置、完成真实开发集冒烟后才能标为运行资格通过 |
| `deepseek-flash`，官方 DeepSeek URL | 三个角色均通过 | `reasoning="none"` **没有**生成 thinking 字段；官方当前默认 thinking enabled/high，因此也不能把发送的 temperature 0 当成生效的非思考温度配置 | 保留原生 preset 时可作同型号、不同推理配置的描述性对照；**不能冒充 thinking-off 的受控对照**。若坚持主矩阵 Flash，应先明确冻结一个最小传输兼容补丁，把 `thinking.disabled` 传到真实请求，保留全部科学 prompt/agent 流程，并重新验证 |
| `grok-4.7`，官方 xAI URL | 三个角色均通过 | CASSIA 使用 Chat Completions；`reasoning="medium"` 与 `"high"` 都被忽略；有效配置依赖官方当前默认 high。temperature .7 原样发送，输出参数固定 4096 | 可以作为同型号主矩阵候选，建议冻结 **high**，并记录请求未显式发送 effort、官方默认核实日期和 endpoint 差异。若 scAgentKit 选择 medium，则不是同 effort 的受控对照，需显式传输补丁或将其作为不同 preset 的描述性结果 |

本次没有要求所有方法使用同一 endpoint。Grok 的 CASSIA Chat Completions 与 scAgentKit 拟用 Responses 可以进行**同底座模型的方法比较**，但不能称为多轮协议等价，也不能单凭这个对照把所有差异归因于 ReAct。ReAct on/off 的因果消融应在 scAgentKit 内固定 provider、型号、生成配置和其他方案。当前正式实验剩余条件是完整安装、真实 provider 接受请求、冻结 preset、完整结果与失败处理；没有把它们写成已完成。

## 固定来源与路由

CASSIA 固定 commit：`c01f573caf25c5ef471e8afefd035c05becfab08`。R/Python 均声明 1.4.0，MIT 许可；不是根据 README 的型号示例猜测兼容性。[R DESCRIPTION](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_R/DESCRIPTION)、[Python setup](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/setup.py)、[LICENSE](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/LICENSE)。

- 用户入口 `runCASSIA(..., provider=<完整 HTTPS base URL>, model=<exact ID>, temperature=<显式数值>, use_reference=FALSE)`；不要把 `provider="deepseek"` 或 `"grok"` 当成支持的标准 provider。内部 `_run_core_analysis()` 将 URL、型号和 reasoning 交给 custom wrapper。custom wrapper 的注释、验证、格式化三个 agent 使用同一型号与 URL。[tools_function.py:222–265、346–429](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L222-L265)、[main_function_code.py:588–632](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L588-L632)。
- resolver 对 HTTP provider 仍检查全局 alias，再走 exact ID passthrough。因此必须运行真实 resolver 验证，不能仅依据“pass through”的代码注释。此次三种 exact ID 均未改变。[model_settings.py:115–176](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/model_settings.py#L115-L176)、[冻结 alias 配置](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/data/model_settings.json)。
- custom route 创建 `openai.OpenAI(base_url=provider)` 并调用 `chat.completions.create(model=model, ...)`。仅 DeepSeek 官方 endpoint 且型号名包含 `deepseek-v4` 才调用 thinking 转换函数。这就是 canonical Flash 的配置缺口。Grok custom route 没有 effort 转换。[llm_utils.py:519–579](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/llm_utils.py#L519-L579)。
- DeepSeek 当前文档把 `deepseek-flash` 指向 DeepSeek-V4.1-Flash-1017，`deepseek-v4-pro` 指向 DeepSeek-V4-Pro-0813；旧 Flash 名称已经重定向。不能为了触发 CASSIA 字符串判断而悄悄改用旧 alias。冻结 manifest 要同时保留请求 ID、官方对应版本、请求日期和响应 model。[官方型号说明](https://api-docs.deepseek.com/quick_start/pricing/)、[thinking 默认及参数语义](https://api-docs.deepseek.com/guides/thinking_mode/)。
- Grok 当前 exact ID 为 `grok-4.7`，官方默认 effort high。Responses 返回并支持延续 encrypted reasoning；CASSIA legacy Chat 路径仅保存文本历史。这项方法差异必须在主结果说明，不能记成相同多轮记忆机制。[Grok 4.7](https://docs.x.ai/developers/grok-4-7)、[legacy Chat Completions](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions)、[reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning)。

## 实际离线探针

可复查附件包含[原始脚本、结果、依赖版本和五份固定源码的下载/hash 清单](cassia-offline-probe/README.md)。脚本和结果按已执行版本原样保留，第三方源码/依赖不打包；复跑在 scratch 目录完成，不覆盖提交的结果。

离线探针运行环境：Python 3.9.6，OpenAI SDK **2.48.0**（满足 CASSIA `openai>=2.0.0`），httpx **0.28.1**。

从冻结源码通过 AST 加载真实 ModelSettings、alias JSON、`call_llm`、annotation/validator/formatter、`_run_core_analysis` 和 usage 代码；跳过模块的第三方导入及初始化。真实 SDK 完成请求 JSON 序列化，httpx MockTransport 在内存中接收并返回固定响应；socket 禁用、使用合成 key，未读取真实凭据。HTTP mock 的合成响应不能证明服务端接受该请求。

| 实际执行的情景 | 内存 HTTP 请求数 | 检查结果 |
|---|---:|---|
| Flash + requested none | 3 | 全部 exact Flash；thinking 字段缺失；max_tokens=4096 |
| V4 Pro + requested none | 3 | 全部 exact Pro；thinking.disabled；max_tokens=16384 |
| Grok 4.7 + requested medium | 3 | 全部 exact Grok；effort 字段缺失；max_tokens=4096 |
| Grok 4.7 + requested high | 3 | 与 medium 情景的三个请求 body hash **逐一相同**，直接证明该参数未传入 |
| Grok 无完成短语、验证不通过 | 19 | 三次 outer iteration 后格式化；全部 exact Grok；三个角色没有切换型号 |

以上断言全部通过。实际 provider 请求 **0**；没有实付费用或真实准确率结果。探针记录了源码 SHA256 和每次完整请求体 hash；探针中 SDK retries=0 仅为测试隔离，不能据此声称原始 CASSIA 禁用了 retries。

## 应冻结的 CASSIA preset 与界限

建议命名 `cassia-1.4.0-annotation-validator-v1-no-reference`，采用公开 `runCASSIA` 的注释 + validator v1 + formatter 流程；同一份已冻结的 marker 输入、物种/组织和允许的研究背景。`use_reference=FALSE`、无 proxy、完整 direct URL、exact model、显式 temperature；不调用混合模型的 pipeline 默认项，不加入 score/annotationboost/merge，不借用 ACT 或真值。若要比较这些额外能力，应另立冻结的 preset，所有参与模型和外部证据分别记录。[pipeline defaults](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/pipeline/pipeline.py#L134-L160)。

这**不是一次性单调用基线**：正常合成流程 3 次；源码每次 annotation 至多 5 次、validator 外循环至多 3 次，最后 formatter 1 次，单次核心分析至多 **19 次逻辑调用**。SDK 自动重试、batch retry、API key 预检都是额外调用，不计在 19 中。[循环](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L161-L185)、[outer loop](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L400-L454)。

batch 默认 n_genes=50、max_workers=10、max_retries=1（初次 + 最多一次整簇重试）、运行前 API 验证开启、gene ID 自动转换开启。正式适配必须显式冻结这些参数，最好复用已有 marker/label-map 准备，避免自动转换和默认 marker 数改变输入。外部运行器设置次数/时间边界、记录每个重试及失败；费用和 token 在运行后汇总，未知 usage 保留 unknown。源码未自设 SDK timeout/retries；所测 SDK 默认 retries=2、读超时600秒。这些不是本次真实 provider 测量结果。[batch 参数](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L557-L625)、[batch retry](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/tools_function.py#L895-L968)。

本报告不宣称 CASSIA 的 LLM validator 是确定性证据校验器。对照仍统一由 scAgentKit evaluator 的 CL 映射、层级指标和分母规则计分。

## 备选工具的边界

mLLMCelltype 固定 `26bda564459257a47dd75f8ed321ad81cb306bca`（R 2.0.8 / Python 2.0.9，MIT）具有 DeepSeek 和 Grok 模块。DeepSeek 模块显式关闭 thinking，但硬编码 temperature .7；Grok 模块走原生 Chat 接口并传入 model。它可以作为后续候选，**此次没有完成其公共入口/共识模型选择/实际 SDK 请求探针**，不把 provider 函数的静态审阅写成完整对照资格。使用多模型共识时也不能称为单底座控制。[DeepSeek 模块](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/python/mllmcelltype/providers/deepseek.py)、[Grok 模块](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/python/mllmcelltype/providers/grok.py)。

## 后续资格与计划

1. 主矩阵保留 DeepSeek + Grok4.7，M1-xAI 先做，成本仅事后比较。
2. 原样 CASSIA 最清楚的受控候选是 **DeepSeek V4 Pro non-thinking / temperature 0 + Grok4.7 high**；模型最终选择仍由维护者确定，不因本核实暗改项目默认 Flash。
3. 如保留 Flash，增加显式、单独记录的最小传输兼容修复再冻结 preset；修复前 Flash native preset 的差异应明确标注，不能称同 thinking 配置。Grok 如要求 medium，也遵循同样规则。
4. 正式实验前需完成真实开发集小规模冒烟和完整 CASSIA 安装/结果导出验证；没有实测结果就保持 pending。不需要先计算费用上界或建立 token 预估系统。

费用仅按[E5 费用报告](E5_COST_REPORTING.md)事后汇总；发送与型号状态遵循[provider 契约](../../../docs/dev/PROVIDER_MODEL_AND_USAGE_CONTRACT.md)。xAI 官方能力、协议和用量口径见[xAI 资格记录](xai-qualification.md)。历史 E0 阶段报告保持原样。
