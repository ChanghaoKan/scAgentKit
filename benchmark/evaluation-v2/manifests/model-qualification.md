# E0：主矩阵模型与注释对照资格核实

核实日期：2026-10-20。范围为官方仓库源码、许可证、供应商文档，以及一个隔离的离线请求形状探针。没有访问 API key，没有付费 API 调用，没有下载生物学数据，也没有运行完整对照工具。以下“源码符合”不等于真实服务冒烟通过。

## 建议

主矩阵采用 **DeepSeek + Anthropic**；前沿模型候选固定为 **`claude-opus-5-5`**，主要同模型注释对照采用 **CASSIA 1.4.0、commit `c01f573caf25c5ef471e8afefd035c05becfab08`**。先实施 M1-Anthropic；OpenAI、xAI 各自单独 PR，作为扩展矩阵，不阻塞正式实验。ReAct v1 的 DeepSeek 产品支持范围保持原计划。

选择依据是可审查的接口路径与版本稳定性，**不是已经证明 Claude 的单细胞准确率更好**：

- CASSIA 的精确模型名可直接透传；Anthropic 注释、验证、格式化 agent 使用传入的同一模型和 provider。原生 Messages 调用对 Claude Opus 5 系列省略 temperature，并可传入 `output_config.effort`，提取文本时跳过典型的 thinking 块。[模型名解析](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/model_settings.py#L115-L176)、[原生调用](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/llm_utils.py#L580-L671)、[三个 agent 的模型传递](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/engine/main_function_code.py#L506-L545)。
- Anthropic 当前官方文档列出 `claude-opus-5-5`，支持工具使用；该模型的 adaptive thinking 不能关闭。官方版本说明把 4.6 及以后没有日期后缀的模型 ID 定义为固定模型快照，同时说明服务基础设施变化仍可能改变可观察行为。因此记录模型 ID、返回的 model、请求日期、实际参数和完整响应，不能承诺重新请求逐字一致。[模型说明](https://platform.claude.com/docs/en/models/opus-5-5/overview)、[版本语义](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)。
- CASSIA 的 R/Python 声明版本均为 1.4.0，仓库使用 MIT 许可；README 展示的版本/模型名可能落后于当前源码，应以本次锁定 commit 为准。[R 版本](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_R/DESCRIPTION)、[Python 版本](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/setup.py)、[许可证](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/LICENSE)。

**资格状态：仓库、许可、精确模型透传路径和离线请求形状已核实；完整安装、真实 API 可用性、完整 CASSIA preset 输出、预算覆盖和 scAgentKit M1 接入未核实。** 主矩阵正式执行仍受这些剩余项阻塞。不要在协议中把本次核实写成“同模型对照已跑通”。

## 其他对照工具

| 工具与锁定版本 | 证据和角色 | 当前限制 |
|---|---|---|
| GPTCelltype 1.0.1；`3d2785aa96ab5f260dd075b688a9fa51654cdf0d`；DESCRIPTION 声明 MIT | `gptcelltype(..., model=)` 把模型名传入 `openai::create_chat_completion()`；适合 OpenAI 扩展矩阵中的一次性注释对照。[源码](https://github.com/Winnie09/GPTCelltype/blob/3d2785aa96ab5f260dd075b688a9fa51654cdf0d/R/gptcelltype.R)、[版本及许可声明](https://github.com/Winnie09/GPTCelltype/blob/3d2785aa96ab5f260dd075b688a9fa51654cdf0d/DESCRIPTION) | 模型可传不等于当前前沿型号已兼容；旧 R 客户端和返回解析需冒烟核实。源码对返回行数不匹配使用无上限 while 重试，须在外部运行器设置超时/费用硬限，不能让它无界消耗。该保护不改变注释 prompt。 |
| mLLMCelltype R 2.0.8 / Python 2.0.9；`26bda564459257a47dd75f8ed321ad81cb306bca`；MIT | Python 原生 provider 模块涵盖 OpenAI、Anthropic、DeepSeek、Grok；可作为扩展多模型对照。正式比较必须区分单 provider 配置和多模型共识配置。[R 版本](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/R/DESCRIPTION)、[Python 版本](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/python/pyproject.toml)、[providers](https://github.com/cafferychen777/mLLMCelltype/tree/26bda564459257a47dd75f8ed321ad81cb306bca/python/mllmcelltype/providers)、[MIT](https://github.com/cafferychen777/mLLMCelltype/blob/26bda564459257a47dd75f8ed321ad81cb306bca/LICENSE) | `latest` 别名在源码中可能映射到旧型号，必须传明确 ID；其具体最新模型和完整共识流程尚未做真实调用。Python 原生 Anthropic 路径的输出限额为 4096，默认重试和超时也需记录。 |
| 论文对应 CellTypeAgent；`da9c31dbca44d1b2eb6bdde1cecf077987f28d42`；未发现仓库 LICENSE，包版本 unknown | 原论文链接的是 **jianghao-zhang/CellTypeAgent**，不是其他同名 celltype-agent 项目。README 写明 OpenAI/Anthropic/DeepSeek，并要求 CELLxGENE 表达参考。[仓库](https://github.com/jianghao-zhang/CellTypeAgent/tree/da9c31dbca44d1b2eb6bdde1cecf077987f28d42)、[论文](https://pmc.ncbi.nlm.nih.gov/articles/PMC12133089/)、[调用代码](https://github.com/jianghao-zhang/CellTypeAgent/blob/da9c31dbca44d1b2eb6bdde1cecf077987f28d42/CellTypeAgent/LLM.py#L75-L146) | 调用代码面向旧型号：Claude 无条件发送 temperature，OpenAI 对 gpt-5/6 会走非旧 GPT chat 分支，不能据此认定当前前沿型号可直接运行。API 文件夹用于用户自备密钥；没有下载或读取任何真实密钥。代码许可不能用论文 CC BY 替代。当前列为待维护者资格确认，不能作为主矩阵唯一对照。 |

这里的注释工具均用于注释比较；描述范围差异时使用“未将 QC、批次等作为显式、可审阅的决策”，不推断它们“不考虑”这些因素。

## 请求参数与公平比较

1. DeepSeek 延续 v1 的 thinking disabled、temperature 0。CASSIA 原生 DeepSeek 自定义 endpoint 的调用代码可以在 `reasoning={"effort":"none"}` 下生成 `thinking={"type":"disabled"}`。实际使用的 model 和价格仍需在正式 manifest 冻结；不要沿用陈旧别名并假定底座未变。[CASSIA 路由](https://github.com/ElliotXie/CASSIA/blob/c01f573caf25c5ef471e8afefd035c05becfab08/CASSIA_python/CASSIA/core/llm_utils.py#L19-L60)、[DeepSeek 官方当前入口](https://api-docs.deepseek.com/)。
2. 对 Anthropic，建议两方法都使用 `claude-opus-5-5`、adaptive thinking、`effort="medium"`，省略不支持的 temperature 字段；预算包含计费的推理输出。该参数候选需在 M1 的模型能力核实与开发集冒烟时冻结。**不能把“temperature 0、thinking off”宣称为所有模型的统一设置。** 不要求查看或公开模型隐藏推理文本；保存 API 返回中重放协议所必需的 opaque blocks/signatures 时仍应用隐私及安全边界。
3. CASSIA 使用固定的公开 annotation preset，所有 annotation/validator/formatter 模型一致；若加 score/boost/merge，它们也必须使用同一底座，并预先把 preset 名称、预算、额外信息来源冻结。不能将默认的混合模型 pipeline 写成同模型比较。
4. 方法之间固定底座、输入/组织/物种上下文和预处理底座；保留各方法自身算法和提示。主注释比较与端到端比较分开。提示长度、工具信息量和费用不是天然相同，应报告，不通过暗中删改对照方法消除差异。
5. xAI 已在官方文档中说明模型版本/别名和函数调用能力，但不据此推断旧版对照 adapter 已支持最新 Grok；扩展矩阵须单独核实模型 ID、接口类型、token 计费和响应重放。[xAI 模型文档](https://docs.x.ai/developers/models)。
6. 公开数据晚于训练截止日期是优先项，不是硬准入；主要“模型未见原始数据”证据由未公开的维护者留出集、冻结 hash/时间记录和隔离规则承担。即使原始数据未公开，也不能推断模型从未见过相似 marker 知识或相关论文。分别记录公开数据发布日期、模型公开训练截止说明、unknown 项和已知泄漏风险。

## 本次离线探针

阶段 0 核实中，从锁定 CASSIA 源码的 AST 只加载 `call_llm` 和文本提取函数，替换 Anthropic SDK 为假客户端并阻断 socket。断言通过：精确 `claude-opus-5-5` 透传、effort 传递、temperature 省略、文本块提取、usage hook 调用。API 调用数为 0。

上游被核实文件 SHA256：`3d644ca2fb7f494d1b1e8488cd87a1b8cdb49c33186e4a0c2fbf53fdcf08ed7d`。这个探针只证明隔离的请求构造路径，**不证明**完整依赖安装、SDK 最新兼容性、真实响应或科学准确性。
