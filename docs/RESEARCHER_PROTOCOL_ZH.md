# scAgentKit 研究者操作协议

本页描述在数据所在机器上使用当前开发源码构建的流程。[English operator guide](SCIENTIFIC_REVIEW_QUICKSTART.md)。
安装、1.0 前的兼容政策及[局限](../README.zh-CN.md#局限)统一见 README。

## 本源码构建的模型入口

在新项目 `sc_start()` 中配置 provider/model，并一次确认汇总数据传输；见
[README 入口](../README.zh-CN.md#分析步骤)及随包 `full-llm-workflow.R`。
只使用已有环境 key；缺 key 时进入人工路径。不使用项目级同意时，每个确切 payload 单独审批。
采纳候选或 Save 不等于科学审批。新启动流程默认事后记录实际用量，不设金额上限或额度预留。
默认查证、回退与离线重放见 [ReAct 用户指南](REACT_ZH.md)。

新草稿仅在各组所需指标完整且适用时使用保守 AND3；否则明确保留 keep-all。
细胞周期仅对物种和基因覆盖适用的输入尝试评分；自动 doublet 仅在合格 called-cell/capture 队列中标记，
其他输入保持未评估。逐项核实已保存理由，不把 condition 当技术批次；Harmony 设计保护仍有效。
实测分辨率必须从实际扫描网格中选择。

ACT 是默认本地参考，见[输入与来源](ACT_LOCAL_REFERENCE.md)；此版本随包保留固定快照，默认离线加载。
缺失/零匹配会明确提示。首轮 marker-only 注释后再比较参考，最多一次 guided 差异请求。
检查实际正向 marker 引用及不可变 PNG。CL 精确匹配不确定时保持缺失。
采纳候选保留人工编辑，每个完整科学提案仍须人工批准。

## 1. 先理解三个控件

| 控件 | 你做什么 | 接下来会发生什么 |
| --- | --- | --- |
| 编辑或采纳候选 | 修改本地草稿，再 Save | 页面重建方案及证据，供你阅读。 |
| 批准科学提案 | 阅读当前完整提案，填写审核人和理由 | Approve and continue 执行已批准的本地步骤，到下一复核点暂停。 |
| 可选模型请求 | 预览确切内容，同意发送，再 Request | 得到候选；编辑并保存后，再独立做科学审批。 |

保存事实或草稿与审批分开。每次编辑后阅读刷新的审阅。
Raw-count 路径依次停在初始方案、实测分群和注释三处。

## 2. 安装与版本确认

按 [README 安装](../README.zh-CN.md#安装)，运行其中的离线检查。
进入研究前核实包版本和 library 路径；R、Rscript、本地服务使用同一包环境。
支持 macOS/Linux；具体要求见[运行环境](LINUX_RUNTIME_SUPPORT.md)。

## 3. 用随包示例练习

在已加载 scAgentKit 的新 R 会话中运行：

```r
source(system.file("examples", "three-gate-analysis.R", package="scAgentKit"))
tutorial <- three_gate_analysis(tempfile("scagentkit-training-"))
tutorial$receipt
```

应看到 complete、80 个细胞、三次练习审批和零 provider 请求。
示例自带练习选择；接入自己的研究时另建目录，按下方步骤亲自决定。

## 4. 接入输入和样本信息

网页入口使用 10x MEX 目录、样本表或 RDS **文件路径**。
Counts 须为有限、非负整数，gene/cell ID 唯一。确认选定 RNA counts 层覆盖所有细胞；
同 assay 的 split counts 仅在精确覆盖及 counts 检查通过后合并；歧义层仍阻止进入。输入格式及 feature/metadata 匹配见 [10x 输入](TENX_INPUT.md)。

声明 species、tissue 和研究目标。sample、donor、capture、condition、batch 只映射到已核实的
metadata 列，且每个细胞都有值；未知角色省略。检查元数据角色草稿：单个安全候选可预填，多个候选须人工选择；缺分组事实时明确显示未评估。
以 RDS 为例：

```r
context <- list(species="human", tissue="Blood", research_goal="Study question")
service <- sc_start("input.rds", "new-review-project", context=context)
```

页面显示导入摘要与未审批方案。核对细胞数、特征名称和样本事实，再进入策略复核。
明确 provider="manual" 可选择本地人工路径；模型费用仅在调用后记录，不设金额上限。模型设置见第 6 节。

## 5. 复核方案和实测分群

### 5.1 Raw-count 分析

阅读各组 QC 分布、候选保留影响及完整方案。核对可选方法的前提；
选入的方法若不受支持，修订选择或将其关闭。保存修改，阅读刷新的审阅，再审批并继续。
随后会看到已计算 PC、扫描过的分辨率、簇关系树、marker 对照和样本组成。

选择实际扫描过的分辨率；修改后先保存、阅读新审阅，再次审批，然后进入注释工作表。
计算原理与图的解释见[方法附录](SCIENTIFIC_METHODS_APPENDIX.md)。

### 5.2 已有 processed Seurat：不重做基础计算

准备真实 counts、选定的 normalized layer、已有 clusters，以及复用已有处理的理由。
使用明确的 R 入口：

```r
processed <- sc_run("processed.rds", "new-annotation-project", context=context,
  start_stage="processed", processed_reason="Reuse documented QC, normalization and clusters.",
  assay="RNA", counts_layer="counts", normalized_layer="data",
  cluster_column="seurat_clusters", provider=NULL)
sc_open("new-annotation-project")
```

该入口复用所提供的处理与分群，准备 markers 后停在注释处。
若要重新分群，从 raw counts 另建项目。后续操作见[已处理对象示例](../dev/examples/server_processed.R)
及第 9 节的注释复核。

## 6. 可选模型辅助

打开网页前，在 `sc_start(provider=..., review=...)` 中直接配置**新**项目；provider、model、生成设置随后固定。
密钥通过实际运行进程的环境提供。`Rscript --vanilla` 需要继承的环境，不读取 `.Renviron`。
完整配置见[模型设置与发送同意](dev/UNIFIED_MODEL_REVIEW.md)。

先检查聚合类别和 provider，再决定是否给予创建时项目级同意；在其范围内，候选可按每个证据快照自动请求一次。没有项目级同意时，预览内容及目的地，同意确切传输，再明确请求。查看、采纳或编辑候选后 Save，
再独立批准科学方案。若请求结果不明确，先查看已保存 job 和用量记录，再决定是否重新请求。
页面未提供的 external-transfer 停点，按链接指南中的 R 操作处理。

配置后的模型建议若因缺少 key、坏 JSON 等失败，会自动保存本地规则草稿及理由，不批准、不重试。
完整且合格的分组 MAD 证据使用 conservative AND3；证据不足时 keep_all，并明确 QC 尚未完成评估。
已保存的人工修改优先保留，请查看实际生效草稿后再审批。有效模型注释不会被自动改成 Unknown；
分析者可另行作出有记录的人工修改。

首次外传前确认数据范围与 provider；调用后分别记录已知费用和费用未知的请求数。费用未知不记为零，也不阻止投递状态明确的新请求。详见[用量与费用记录](MODEL_BUDGET.md)。

## 7. 输入准备好后再选可选方法

| 选择 | 需要先准备什么 | 详细说明 |
| --- | --- | --- |
| Sample-consensus HVG | 至少 2 个已声明样本，每个至少 30 个保留细胞；设置 hvg_method=sample_consensus、hvg_column，保存并复核 | [HVG 与诊断](SCIENTIFIC_METHODS_APPENDIX.md) |
| Harmony | 已核实的技术 batch 列，以及满足检查的研究设计；复核完整方案 | [Harmony/PC](dev/HARMONY_PC_REVIEW.md) |
| Doublet 评分 | 适用的 droplet raw counts、明确 capture 单位和受支持运行版本 | [Doublet 前提](dev/DOUBLET_REVIEW.md) |
| Cell-cycle 选项 | 明确 species，测得且记录来源的 gene set；选择 keep/full/受支持的 difference | [Cell-cycle 复核](dev/CELL_CYCLE_REVIEW.md) |
| Ambient 校正 | 单独 R API；SoupX 需完整 capture、匹配的 raw/filtered counts、至少 20 个额外 droplets 和具名 clusters；decontX 需明确初步 clusters | [Ambient 输入与版本](SCIENTIFIC_METHODS_APPENDIX.md#ambient-estimation-and-correction) |

额外 PC sensitivity、重采样、分辨率扩展、sample-consensus HVG、实验性 OR 草稿比较、
跨样本/混合谱系扩展初始均关闭；需要时为新项目明确选择。
采用 ambient 校正结果时，先查看单独返回的 counts，再另建项目。

## 8. 同一项目的可选网页与服务器运行

在数据所在机器运行，R library/Rscript 保持一致。服务绑定 127.0.0.1，
用你已有的机构认可 SSH 访问转发端口。命令和作业设置见[远程访问](../workbench/README.md#remote-access)。
页面显示已保存项目；接下来从当前显示阶段继续复核。

## 9. 填写并批准注释

阅读每簇 marker 及已配置的参考候选。所有行填写标签或 Unknown、置信度、理由和提供的支持 marker。
未编辑行选择参考候选可复制标签/引用，解释由你补充；批量 Unknown 要求理由并保留已编辑行。
Save complete proposal，通看各群，再批准注释并继续。随后看到完成状态及结果页。
详细操作见[ACT 参考设置](ACT_LOCAL_REFERENCE.md)和 [marker 定义](SCIENTIFIC_METHODS_APPENDIX.md#main-annotation-marker-pool)。

## 10. 可选子分析和新的父对象输出

从已完成父项目开始。选择真实 cluster ID，查看选中细胞；child 当前至少需 21 个细胞及独立新目录。
复核其新 raw-count 方案及注释。完成后查看目标列和选中细胞，再明确 apply，将标签写入**新的**父 RDS。
范围外及 child QC 排除的细胞在新列为 NA，原父文件保留。
当前不支持 child 再创建 child，也不自动合并重叠 children。

背景编辑仅在停止的注释阶段、写回前提供。保存页面允许的编辑，阅读重新生成的提案并重新审批。
准确 R 调用、编辑前提及 undo 见[子群复核](SUBCLUSTER_REVIEW.md)和[背景控件](dev/PARAMETER_CONTEXT_CONTROLS.md)。

## 11. 输出、恢复与可复现记录

完成后检查并取得最终对象：

```r
project_dir <- "new-review-project"
saved <- sc_open(project_dir)
saved$view$output
result <- sc_result(project_dir)
sc_run_open(project_dir)
```

`sc_open()` 在 R 中显示已保存结果；`sc_run_open()` 打开只读网页。
完成前可用 `sc_result(project_dir, stage="analysis")` 读取暂定对象。
继续复核时，使用相同输入/选项及项目环境重复原 `sc_start()` 调用，省略 context 以复用保存的事实。
项目复用边界统一见 [README 局限](../README.zh-CN.md#局限)。

| 看到什么 | 下一步 |
| --- | --- |
| awaiting_configuration | 补齐人工方案/注释，或按配置好的模型步骤操作。 |
| awaiting_review | 阅读当前提案，保存编辑后再审批。 |
| job 忙或响应不明确 | 先看保存的 job/回执，等 worker 完成后再提交。 |
| 输入/layer 不符或项目环境改变 | 核对输入和记录的环境；使用原环境或另建项目。 |

完整备份复制回原路径后，目录身份会改变。若出现
`Saved local continuation belongs to a different project directory`，
含恢复命令的开发构建提供[显式终态作业恢复](../workbench/RUN_CONTINUE_RUNTIME.md#restore-a-complete-terminal-job-backup-unreleased)。
它保留原作业与科学记录，只重新绑定已结束作业的本地目录；不支持正在运行的备份或迁移到新路径。
恢复后仍须用原环境检查项目，不要手动修改状态、锁或校验值。

反馈时保留包/OS 版本、输入类型、当前阶段、准确错误及 job/回执。
分享前移除私密数据和凭据。
