# scAgentKit 论文里程碑与 1.0 PR 计划

2026-10-20，维护者已确认。论文里程碑暂定 **0.10**；版本号不是提前的发布或生物学验证声明。当前 E0 只落实协议与计划，正式实验仍需完成 [协议 v2](EVALUATION_PROTOCOL_V2.md) 的冻结门槛。以 [定位 v2](SCAGENTKIT_POSITIONING_V2.md) 为对外叙述边界。

每个 PR 都写明基线 commit、改动文件、新增抽象、能否复用 checkpoint/ledger/event，以及实际测试和限制。能复用的必须复用；不建立平行状态库、账本、事件机制或自动批准 API。每个阶段报告沿用 PR/commit、1.0 验收变化、定位证据变化、测试/CI、限制和偏离栏目，并增加“论文里程碑进度”。

## 已提交 PR 的处理

- [agentomicsCore #2](https://github.com/ChanghaoKan/agentomicsCore/pull/2)，审阅 head `cab2b4002fbdb361f2cbed858f0cda08a100e270`：已合并，merge commit `d9348c128609857ae4a722a26aa011c95f4aac5d`，[v0.2.0 已发布](https://github.com/ChanghaoKan/agentomicsCore/releases/tag/v0.2.0)（2026-10-20 核实）。scAgentKit 2A 的依赖升级前置已满足。
- [scAgentKit #15](https://github.com/ChanghaoKan/scAgentKit/pull/15)，审阅 head `703309b`：R-CMD-check、release-archive 及其余两项 CI 均通过后，已标 Ready 并合并，merge commit `7507f2d081a5a9a0af809921d47778da038cf03a`。阶段 1 基线为 #14 合并后的 `1936bb6cc244a24c4ff04775ca2e76f7b30f2ee7`。已完成的 50k 合成四工具性能测量不等于公开 50k 全流程验证。
- E0 [#16](https://github.com/ChanghaoKan/scAgentKit/pull/16) 基于 `7507f2d081a5a9a0af809921d47778da038cf03a`；工程协议 commit 为 `a7bb0c1507b3381f6977ac8f007d657fb0c11437`。指定 CI 通过后已合并，merge commit `b5bfbb668c581b043449199343af355249c19fa6`。本次修订更新后续决定，保留原阶段报告；正式实验仍未冻结。
- scAgentKit 2A [#17](https://github.com/ChanghaoKan/scAgentKit/pull/17) 已提交，基线为 `b5bfbb668c581b043449199343af355249c19fa6`，head `141d7a90697d26579a83ebac104172d38269691e`；只完成结构化单轮运输与会话绑定，未接循环。CI 尚未完成，不能称已合并或 ReAct 已可用。
- Core [#3](https://github.com/ChanghaoKan/agentomicsCore/pull/3) 补充 v0.2.0 响应 `assistant` role 与旧 mock 的兼容说明；head `8416a4499a8c05fd19146550a4a0ea31d4866efc`，CI 通过，尚未合并。已发布 tag 保持不变。

## 论文里程碑的 ReAct v1

| PR/阶段 | 范围与预计文件 | 抽象与复用 | 完成条件 |
| --- | --- | --- | --- |
| 阶段 1 / #15 | 四工具、dispatcher、严格参数/隐私/大小限制、cache、worker、测试和 50k 合成性能记录；`R/run-react-tools.R`、`run-react-dispatch.R`、`run.R`、DESCRIPTION、测试及开发文档 | registry/context/dispatcher；复用 state、SHA、原子写入、实现指纹；未接 LLM loop | 两项指定 CI 通过、Ready、合并；报告审阅与最终 commit |
| Core 2A / Core #2 | 结构化 turn、请求预览、tool_calls/usage/投递状态；`R/chat-turn.R`、旧 factory 兼容、导出/help、tests、版本/NEWS | 单 turn 协议，保留旧文本接口和 token 记录，无工具执行/审批 | 合并并发布 v0.2.0 |
| scAgentKit 2A | DESCRIPTION Remotes/Imports；provider/start/transfer/suggest、账本与授权 tests | 受限多轮会话和 turn 绑定；复用 ledger/consent/event | Core 已发布；全消息隐私；单次请求和结构化 turn 只记录调用后的 usage/费用，无金额上限或发送前费用估算；不确定投递不重发 |
| 2B | `R/run-react.R`、外层引用/风险记录、`inst/prompts/`、annotation prepare/review/history、配置/hash、mock tests；更新现有 dispatcher | 顺序 loop；保留 annotation.v1；第三关外层五项风险枚举及生产格式校验必须在 2B 交付；会话常驻 worker 复用既有进程机制 | baseline→auto/all/off；6 turn/簇、60/session、3 分钟/簇；白名单/ACT 消融与逐簇恢复；开始/结束完整 SHA、同字节加载、中途 stat 报警；重测热缓存/全会话性能 |
| 3 | 现有 audit 投影、workbench 前端/桥接、R/DOM tests、runtime manifest | state 权威，JSON 投影；不新增状态库 | 查证折叠区、引用跳转、费用/回退统计；人工编辑保留 `(簇,基因)` 来源；审批流程不变 |
| 4E | `R/react-eval.R`、`R/react-replay.R`（暂定）、导出/help/tests；扩展 v1 共用评分 | 公开 eval/replay；一个 CL 映射/评分实现；复用生产工具/引用 validator | 全簇/难簇；CL 距离≤3；簇真值 80/80；主版/严格版准确率并列；外部 CSV、费用/token/步骤/回退；无 key 重放与差异报告 |
| 4 | start API/透传、README、双语指南、示例、mock E2E、`dev/smoke/react-real.R`、ACT manifest、NEWS | 复用启动/UI，无新增弹窗或批准层 | `sc_start(...,react="auto")`；三关 mock 草稿直接采纳 + react all；ACT 来源无空项；手动真实 PBMC3k 脚本及实测状态 |

第一版四工具是 `cluster_markers`、`gene_expression`、`act_lookup`、`cluster_context`。工具引用只能来自本次会话同簇的合法 cluster_markers 保存行（padj<.05、FC>0、pct1>pct2、非排除基因）；gene_expression 是未检验背景证据。人工改 label/置信度/理由保留已验证来源，删除引用即删除来源，新增人工引用遵循原 pool 规则。

有合法 baseline 时，模型能力、步数、时间或结果校验失败逐簇回退；没有 baseline 标 `baseline_unavailable`。完整性错误继续阻断。会话性能优化不改变这条边界，缓存和固定内存必须具有同一已验证科学身份。第三关风险枚举进入版本化草稿外层，annotation.v1 内层不变，旧/人工记录缺项显式未评估。

## 论文里程碑的评估与生物学功能

| PR | 范围与预计文件 | 新抽象及复用要求 | 依赖和验收 |
| --- | --- | --- | --- |
| **E0 协议与定位** | 本协议、定位、本文、benchmark README、外部说明、清单字段/示例文档，归档旧提案 | 仅文档；不引入可执行框架或改变包 hash | 先提交 E0；阶段报告记录工程协议 commit。精确模型和经验参数尚未实验冻结 |
| E1 运行器 A | `benchmark/evaluation-v2/run_pipeline.R`、汇总投影、fixtures/tests；复用 v1 counts-only 准备和运行 helper | 一个 policy 配置和 run_summary 投影，调用既有公开 suggestion/sc_review、checkpoint/ledger/event | E0 后与 ReAct 并行；mock 三关 accept/rules/fixed、失败/恢复、unsupported 开关和真值隔离；reviewer=`benchmark-policy:<策略>` |
| E2 稳定性 B / 外部导入 | stability、外部 CSV/JSON adapter、tests；扩展 v1 评分版本 | 共用 label-map/CL/分母，不另写一套评分 | E1；N 次仅改 replicate ID；手算 Jaccard/ARI/标签层级指标、缺失和 ID 错配；CellAgent 官方版本/命令核实后维护者运行 |
| E3 注入 C | 稀疏整数注入器、参数/风险字段映射、score/tests | 包外固定注入 registry，共用整数/ID/hash 检查，不成为模型工具 | E1/E2；十类机制、小型 fixtures；低 RNA 为真实选集；未知类型为可见参考留出；主发现率读取生产校验后的结构化风险字段；第一关依赖 B1/B2，第三关依赖 2B，未就绪部分标 unsupported |
| **M1-xAI（主矩阵，优先）** | Core 原生 Responses adapter、完整 output items/工具/usage tests；scAgentKit capability/授权/账本、型号清单 | 扩展既有版本化 provider envelope 保存 opaque items，复用 turn/ledger/隐私，不另建会话库 | grok-4.7 官方能力与 CASSIA exact ID 离线透传已核实；完整 preset/真实冒烟仍 pending；保持 180 秒/簇；费用仅事后记录 |
| M1-OpenAI（正式产品支持） | 独立 provider PR，范围同上 | 复用上述契约；实际型号逐项核实 | 用户可选 provider、验证型号清单、公开开发集 N=3 accept_drafts 可用性验证；可论文后，不阻塞主矩阵 |
| M1-Anthropic（正式产品支持） | 独立原生 Messages provider PR、tool use/完整响应/usage tests | 复用上述契约，按实际 Claude 型号核实参数及 opaque blocks | 用户可选 provider、验证型号清单、公开开发集 N=3 accept_drafts 可用性验证；可论文后，不阻塞主矩阵 |
| E4 证据指标 D / 开发试跑 | trace adapter、证据/校准/消融评分、共享 tests、开发结果 manifest/CSV/report | 消费 4E 的生产校验和稳定轨迹，不再造 validator | ReAct 2B/3/4E；原始引用分母、ACT/LLM/ReAct 对照；开发集 N=3 accept_drafts，mock 与已验证真实 provider；其他已支持 provider 同样做 N=3 可用性验证，与主科学结论分开 |
| **B1 诊断簇 QC** | 诊断 checkpoint、typed QC 替换、MAD/preview/strategy/schema/UI/tests、方法附录、NEWS | 只读诊断与 `(簇,指标)` 替换；复用审批、失效、MAD、选择器；第一关风险外层 | 2B 合并后与 UI/4E/文档并行，不等 ReAct 全部完成；审批前诊断标识、批准后重算；top5 正 marker 中非 MT/ribo/stress 至少 N 才可放宽（N=3 开发确认）；有效阈值/保留差；冲突拒绝、成员变更失效 |
| **B2 批次必要性** | Harmony/recommend/B1 诊断、策略 schema、第二关 UI、tests/NEWS | 复用设计秩、nested_biology、kNN/Harmony；无新增包依赖；batch_status 枚举 | 2B 合并后并行开发，集成需 B1 共享诊断；same-batch 超额混合、固定簇邻域纯度、≥2 样本/条件的类型内条件信号；技术/生物学指标分报；无效应/完全混杂默认不校正 |
| **E5 正式冻结、公开与最终留出实验** | freeze receipt、数据/模型/对照工具清单、结果与报告；双人工标签/CL/mask 与导入 | 同一评分器和审计产物；没有额外科学语义 | ReAct v1+B1+B2+E1–E4+主矩阵 M1 完成；≥3 合格公开集、N=5、适用消融；主矩阵 DeepSeek+Grok 及对照 preset 资格通过后冻结；按 dataset×repeat×method 事后汇总实际用量/费用；留出主结果同阶段完成 |

E1–E3 可以并行开发；2B 合并后 B1/B2 与 UI、4E 评估重放、文档并行。E3 的生成器不必等待全部风险字段，但第一关发现率验收必须等 B1/B2，第三关必须等 2B；相应能力尚未实现时明确返回 unsupported，不能在 evaluator 模拟科学行为。E 类 PR 不偷带包内科学改动。B1/B2 和 2B 的风险字段由生产校验器检查格式，主发现率以这些结构化字段计，关键词只作辅助。

B1/B2 的规则兜底、最小预筛、用户批准是强制边界。B1 放宽资格不等于健康认证；每项收紧或放宽均需理由，其他 baseline 指标继续生效。B2 不将 RNA 不变当无过度校正证据，包外另用 scIB 风格真值 ARI/NMI/类型保留评价。

论文主矩阵为 **DeepSeek + Grok**，M1-xAI 优先使用 Responses，`grok-4.7` 为官方能力已核实的具体候选。CASSIA exact ID 已离线核实，但 Flash thinking 参数、Grok effort 和 endpoint 差异必须按[资格记录](../../benchmark/evaluation-v2/manifests/model-qualification.md)处理，完整 preset 和真实 API 仍 pending；不暗改产品 Flash 默认。**四家均是正式产品目标，由用户选择**；Anthropic/OpenAI 后续独立 PR，可论文后完成。其他已支持 provider 在公开开发集 N=3 accept_drafts 验证可用性，不作为主科学结论、不阻塞论文。[型号与用量契约](PROVIDER_MODEL_AND_USAGE_CONTRACT.md)和[E5 费用报告](../../benchmark/evaluation-v2/manifests/E5_COST_REPORTING.md)只要求运行后记录和比较，不再有选型报价或发送前金额门槛。

公开数据训练后首次发布改为优先项；未公开最终留出及其证据记录承担主要“模型未见数据”支持，不能声称模型未见过相同细胞知识。留出不参与开发/调参/prompt 设计，真值、CL 映射和一致 mask 在首次运行前冻结；维护者按 accept_drafts/rules 执行，不手工改决策。原 E6 的操作与结果并入 E5，不存在“论文完成后才验证最终留出”的依赖。

## 论文之后的 1.0 工作

以下均仍是 1.0 计划中的必需工作，但不阻塞论文里程碑。必须如实限制论文版本的产品承诺，不能提前称已满足全部 1.0 验收。

| 工作 | 最小范围与主要复用 | 完成门槛 |
| --- | --- | --- |
| M1-Anthropic / M1-OpenAI | 四家产品支持余下 provider 的独立正式适配；型号清单、协议/usage 测试，复用 Core/ledger/consent | 用户可选，清单外标 unverified；公开开发集 N=3 accept_drafts 可用性验证；费用仅事后报告 |
| U1 输入与启动 | 样本列结构化确认、MEX 声明体验、一次授权、输入检查和耗时说明，start/metadata/tenx/UI | 说明有实测依据；按后续决定取消新增发送前费用估算 |
| U2 三关理由证据 | 第一关各项理由绑定具体证据、完整 HVG、第二关证据跳转 | 复用 v1 证据身份，不用第二个 LLM 校验 |
| O1 便携结果 | `@misc$scAgentKit` 审计投影、最终图表、研究者 report、可选 h5ad | RDS 离开项目后仍可读；审计只新增 |
| C1 项目补丁兼容 | 已证明科学等价的变更分类、差异确认 receipt、迁移回归 fixtures | 原 hash/批准保持；完整性破坏和科学代码变化阻断；依赖小版本号不能单独证明等价 |
| P1 API/安装/文档 | `inst/api-contract.json`、语义版本 tests、正式便捷安装、全新环境 CI、一屏开始 | macOS/Linux 实测；API 稳定后冻结 |
| V1 公开 50k 全流程 | 来源、三关、每阶段耗时和进程树内存、失败/等待记录 | 与已完成四工具合成 benchmark 分开 |
| V2 1.0 就绪报告 | 更新 18 项证据、PR/commit、CI、结果与限制、安装/兼容状态 | 全部必需验收完成才能称 1.0 就绪 |
| R2 第二关 ReAct | 复用扫描/adjacent_splits/registry/loop；compare_clusters 差异计算缓存与测试，cl_lookup 可独立 | 不新增审批，不重做扫描；满足标准 6 的新增检索部分 |

## 关键路径与阶段报告

论文关键路径先到 **Core v0.2.0 → scAgentKit 2A → 2B 合并**，随后分为并行两支：**3（UI）/4E（评估重放）/4（文档与发布验收）**，以及 **B1/B2（共享诊断与风险字段）**；两支均完成后汇入 **E5 冻结/主实验/留出主结果 → 论文里程碑**。B2 集成需共享诊断可用，阶段 4 最终发布验收仍需相应前置完成，但它们不阻塞 B1/B2 开发。阶段 1 合并是 2B 的另一前置；E0→E1/E2/E3 与 ReAct 并行，E3 发现率集成等待 2B/B1/B2 风险字段，E4 在轨迹/4E 可用后完成。数据/对照工具资格和 M1-xAI 同时推进，也是 E5 的阻塞路径。非主矩阵 provider 的正式产品适配及其可用性验证不在论文关键路径；四家产品目标没有被缩减。

每个阶段报告必须列出：

1. PR 链接及基线→head/合并 commit 范围；E0 的协议 commit，E5 的 experiment-freeze receipt。
2. 18 项 1.0 验收状态变化；未推进的不能因计划获批改为已满足。
3. 定位各项“用什么证明”的进展：生物学决策、显式/复现、引用、LLM、ACT、同模型注释、长期使用。
4. 实际运行的测试、CI 和试验；mock、开发、正式、静态核查分别记录。
5. **论文里程碑进度**：本阶段完成项、关键路径下一项、主矩阵候选/已冻结状态、四家产品支持与可用性验证状态。
6. 已知限制、原计划偏离及原因。

脚本 accept_drafts 不是真人采纳率；N=3 开发试跑不是正式稳定性证据；代码合并不是生物学验证。外部长期案例和真人用户研究可在独立协议下补充，论文若未完成这些证据就保留相应限制。

## 启动整合候选状态（2026-10-21）

阶段 4 的启动/示例/三关 mock 验收在 #22–24 的本地整合基线上实现，
详见 `reports/REACT_START_STAGE_REPORT.md`。新 `sc_start` 默认 ReAct auto、
启用诊断证据、一次外发确认，并对一次性草稿和 ReAct 统一事后记账。
正式发布所需的真实 PBMC3k 手动冒烟、
ACT 清单复核和完整 CI 仍需独立验收；此候选不宣告整个阶段 4 或论文里程碑完成。
