# Published v0.6.0 protocol / 已发布 v0.6.0 操作路径

Use the published archive and checksum instructions in the
[English README](../README.md#installation) or [中文 README](../README.zh-CN.md#安装).
The installed package version alone does not identify a development build;
record the archive checksum and dependency environment. The default v0.6.0
plan sets `diagnostic_resolutions=NULL`: two scientific approvals cover the
initial strategy and annotation. It does not include the preview's default
measured-clustering gate, recommendations or fact editor.

按 README 安装已发布归档并校验 checksum；同时保留依赖环境。默认 v0.6.0 的
`diagnostic_resolutions=NULL`，需两次科学审批：初始方案和注释；不包含开发预览的
默认实测分群审批、新推荐及事实编辑。包版本号相同不能证明代码来源相同。

Before the first call, choose manual or model-assisted initialization. The
following creates a manual project: no provider, no model request, zero budget.
`sc_start()` accepts an RDS **file path** containing raw counts/Seurat, a 10x
MEX path or a declared sample table; it does not accept an in-memory Seurat.
For a model project, initialize the provider/model/settings/budget with
`sc_analyze()`/`sc_run()` before reopening the same input via `sc_start()`.
Those settings are immutable; see [configuration and consent](UNIFIED_MODEL_REVIEW.md).

首次调用前先决定人工或模型辅助初始化。下例是人工项目；标签和置信度由用户提供。
`sc_start()` 的 RDS 输入是含原始 counts/Seurat 的**文件路径**，也支持 MEX 路径或
声明清楚的样本表，不直接接受内存 Seurat。模型项目先用 R 初始化 provider、model、
设置和预算；这些配置不能在后续网页中补加或更换。

```r
library(scAgentKit)
service <- sc_start("input.rds", "new-release-project",
  context=list(species="human", tissue="Actual tissue", research_goal="Actual study question"))
```

1. Inspect input facts, QC distributions and projected retention. Save the full
   strategy after edits; inspect it again, approve, and continue locally.
2. At annotation, prepare the worksheet. Review the actual supplied cluster
   markers and any configured local reference candidates. Supply labels or
   Unknown, qualitative confidence, rationale and same-cluster citations. Save
   the complete proposal; inspect, approve and continue.
3. Read `sc_result("new-release-project")` in the same library environment.
   `sc_open()` inspects/reopens; it does not execute analysis or request a model.

1. 审查输入事实、QC 分布及保留影响。编辑后保存完整方案，再审查、审批并继续。
2. 注释处准备表格，查看实测 marker 和已配置的本地参考候选；用户填写标签或 Unknown、
   定性置信度、理由及同簇引用。保存完整提案后，审查、审批并继续。
3. 在同一包环境用 `sc_result("new-release-project")` 读取结果；重开不自动执行或请求模型。

The [offline installation check](../README.md#offline-installation-check) uses
public `pbmc_small` and explicit software-control approvals. It tests installation
and abstains with Unknown; it is not biological validation. For preview code,
install its fixed commit separately and follow its three-gate protocol instead.

README 的离线检查使用公开 `pbmc_small`、明确的软件测试审批及 Unknown；只验证安装
路径，不验证生物学结论。开发预览须另装固定提交并使用对应三次审批教程。
