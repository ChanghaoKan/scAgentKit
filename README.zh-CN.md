# scAgentKit

[English](README.md) · **简体中文**

scAgentKit 面向有生物学背景的研究者，帮助减少维护单细胞 RNA-seq 工作流的精力。
从 counts 与样本事实，或含 counts/Seurat 的 RDS 文件开始，在可保存、可审阅的项目中完成 QC、基础分析与注释。

你会得到包含 counts、样本 metadata、降维及已审阅标签的新 Seurat 对象，以及 marker 表、图、
决策证据与理由。QC、整合和分群仍需研究判断；默认值只是起点。FASTQ 处理在本流程上游；
研究特定的轨迹、细胞通讯及调控网络分析在下游，不会自动运行。

## 分析流程

<img src="docs/diagrams/project-analysis-flow.zh-CN.svg" alt="开发分支的 raw-count 流程：自动本地计算分别停在分析方案、实测分群及注释审批处，可选支路须明确选择" width="1000">

[English diagram](docs/diagrams/project-analysis-flow.svg) · [中文流程图](docs/diagrams/project-analysis-flow.zh-CN.svg) · [流程图生成源](docs/diagrams/generate_project_flow.py)

本图对应 **0.8.0**。历史 v0.6.0 请用[两次审批发布路径](docs/RELEASE_060_PROTOCOL.md)；其 tag 和资产保持不变。

### 哪些自动运行，哪里需要你决定

本地自动工作包括 counts/metadata 验证、QC 测量及证据准备。
分析方案经你批准后，程序执行该方案及常规分辨率扫描/簇关系树；
三个科学决策分别暂停并需要独立审批：

| 决策点 | 看什么图与证据 | 需要你做什么 |
| --- | --- | --- |
| [**1. 初始分析方案**](#gate-strategy) | QC 分布、样本/分组比较、候选筛选的细胞保留影响及拟用 PC/方法规则。此时 PCA 尚未计算。 | 选择 QC 与完整分析方案；先 **Save**，看重建后的审阅，再 **Approve and continue**。 |
| [**2. 实测分群**](#gate-clustering) | 已算的 PC 曲线/阈值、簇关系树、marker 对照及样本组成。树的边表示共享细胞，不是谱系。 | 选择**实际扫描过的分辨率**。编辑后先保存、审阅，再独立审批，最终成员与 marker 才绑定该选择。 |
| [**3. 注释**](#gate-annotation) | 各簇 marker、适用的 mean/pct 面板、参考支持/来源、冲突及缺失证据。 | 为各群提供标签或 **Unknown**、定性置信度和理由。**Save complete proposal** 后通看各群，再 **Approve annotation and continue**。 |

第三次审批后，项目写出新 Seurat 对象及导出文件。保存草稿、改正事实或重新打开项目均不授予审批。
自动化执行的是已记录的选择，不能据此确认生物学结论正确。

可选方法须主动选择且输入适用。PC k±5、重采样、额外分辨率扩展、sample-consensus HVG 和
实验性 QC 草稿自动预选默认关闭；常规扫描/簇关系树仍是 raw 路径的一部分。
模型请求还需针对实际传输内容单独同意。SoupX/decontX 是**单独的 R-only API**，
输出供新项目使用的校正 counts，没有网页校正操作，也不替换原 counts/checkpoints。
方法细节见[方法及限制](docs/SCIENTIFIC_METHODS_APPENDIX.md)及[一页操作指南](docs/SCIENTIFIC_REVIEW_QUICKSTART_ZH.md)。

## 安装

需要 R ≥ 4.2、Seurat ≥ 5，以及浏览器入口使用的既有 Python ≥ 3.9。
浏览器资源随 R 包提供。版本 `0.8.0` 为实验性版本。

公开 Release 下载无需凭据。GitHub 依赖解析可能触及未认证 API 配额；这种情况下
`remotes` 支持既有 `GITHUB_PAT`。CI 使用既有只读 job token，不生成新凭据。

从 [v0.8.0 Release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.8.0)
下载 [scAgentKit_0.8.0.tar.gz](https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/scAgentKit_0.8.0.tar.gz)，
再安装到自己的 R library。文件仅在 release 发布后可用；准备好归档或 CI 成功不会自动发布它。
见[发布门槛](docs/RELEASE_PLAN.md)。

下载两个文件，并在安装前核对归档：

```sh
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o scAgentKit_0.8.0.tar.gz https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/scAgentKit_0.8.0.tar.gz
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o SHA256SUMS https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/SHA256SUMS
shasum -a 256 -c SHA256SUMS  # macOS; on Linux use: sha256sum -c SHA256SUMS
```

校验失败则停止。在新的 R 会话中，为大依赖下载留足时间，并确认加载的是预期私有库中的安装：

```r
options(timeout=max(1800, getOption("timeout", 60)))
lib <- path.expand("~/R/scagentkit-library")
dir.create(lib, recursive=TRUE, showWarnings=FALSE)
.libPaths(c(lib, .libPaths()))
if (!requireNamespace("remotes", quietly=TRUE))
  install.packages("remotes", repos="https://cloud.r-project.org")
remotes::install_local("scAgentKit_0.8.0.tar.gz", lib=lib,
  dependencies=c("Depends", "Imports"), upgrade="never", build=FALSE)
library(scAgentKit, lib.loc=lib)
stopifnot(as.character(packageVersion("scAgentKit")) == "0.8.0",
  identical(normalizePath(find.package("scAgentKit")),
    normalizePath(file.path(lib, "scAgentKit"))))
packageVersion("scAgentKit")
```

在下载归档所在目录执行，或提供完整路径。安装日志包含 `ERROR` 不算成功：
运行离线检查前，显式加载、版本及 library 路径断言都必须通过。
上述命令安装必需依赖，包括声明的 `ChanghaoKan/agentomicsCore@v0.1.1`。
记录归档 SHA256、包版本和 `sessionInfo()`。不要替换为可变的 `main` 或更旧 tag。
可选方法有各自核验的版本约定，见[安装与运行时支持](docs/LINUX_RUNTIME_SUPPORT.md)。

## 离线安装检查

安装后，在新项目中运行随包提供的公开数据软件示例：

```r
source(system.file("examples", "simple-analysis.R", package="scAgentKit"))
result <- simple_analysis_after(tempfile("scagentkit-offline-"))
stopifnot(inherits(result, "Seurat"), ncol(result) > 0)
```

示例使用 `pbmc_small`、明确的软件控制审批及 Unknown 标签。
它不调用 provider，也不验证生物学身份。发布验收在 package libraries 为空的新
`rocker/r-ver` 容器中执行上述安装命令，再运行该示例；完整依赖安装及示例日志保存在对应 CI run。

### 已有保存项目

执行及审批要求保存的实现 hash 与正在运行的函数、被纳入指纹的依赖版本一致。
旧项目的 hash 不同，就不能在此版本下继续。保留原项目、输入、包构建及依赖环境；
恢复准确的原环境后继续，或从原输入另建项目并重新审阅。
不要修改保存的 hashes、审批或 checkpoints 来强行 resume。
见[兼容性与弃用说明](NEWS.md)。作者标签 metadata prior 默认关闭，使用时须明确开启。
[v0.6.0 源码环境配方及恢复边界](docs/ENVIRONMENT_RESTORE.md)固定发布时的 R 环境和包来源。
应匹配原归档与实现，而不只是版本号；这不是自动的跨版本项目迁移。

## 一个项目工作流

0.8.0 删除旧直接编排入口及 AgentSeurat 类。请使用审批项目工作流或保留的 Seurat/表格工具；
完整变化见 [API 与对象类型说明](docs/API_CONSOLIDATION.md)。保留旧证据，以原始输入另建开发项目并重新审批。
这是不兼容的实验性版本，不提供跨版本 resume 或旧接口兼容 facade。

## 分析步骤

本节对应上方安装的 0.8.0，包含三次独立科学审批。

首次 `sc_start()` 前先决定人工或模型辅助初始化。默认创建人工项目：无 provider、模型预算为零，
标签和置信度由用户填写。若需模型，先按[配置与传输同意](docs/UNIFIED_MODEL_REVIEW.md#what-remains-in-the-starting-r-call)
用 `sc_analyze()` 或 `sc_run()` 初始化 provider、model、设置及预算，再用
`sc_start(..., model_suggestions="configured")` 重开相同输入。配置不可变；网页不能给人工项目后加 provider。

### 1. 选择 counts，声明样本事实

单个 10x MEX 目录需要唯一 sample ID，并明确原矩阵是 raw 还是 filtered：

```r
input <- "filtered_feature_bc_matrix"
project_dir <- "analysis"
context <- list(species="human", tissue="Actual tissue",
  research_goal="Actual study question")
service <- sc_start(input, project_dir, context=context,
  sample_id="S1", matrix_kind="filtered")
```

本地审阅页打开后，R 返回控制。初始状态应是导入摘要和未审批的策略。
Raw 输入保留所有提供的条码；导入不执行 empty-droplet calling。
继续前核对来源类别、细胞数、特征 key 变化及 metadata 对齐。

多样本时，用同时包含路径与研究事实的样本表替换上面的调用：

```r
input <- data.frame(sample_id=c("S1", "S2"),
  path=c("counts/control", "counts/treated"),
  matrix_kind=c("filtered", "filtered"),
  donor=c("D1", "D2"), condition=c("control", "treated"))
service <- sc_start(input, project_dir, context=context)
```

细胞 ID 为 `sample_id::barcode`，因此不同样本的重复条码不会混淆。
可选 cell metadata 按准确的 sample/barcode key 连接。
不同样本的 Gene Expression feature ID 集合必须相同；不取特征交集，也不合并特征。
文件/表格式、原始特征身份及对齐细节见[10x 输入与样本表](docs/TENX_INPUT.md)。

若使用含原始 counts 矩阵或 Seurat 对象的 RDS 文件，传入文件路径：

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

这里传 RDS 文件路径，文件内可含原始 counts 或 Seurat；`sc_start()` 不直接接受内存 Seurat。

每次新分析使用新的 `project_dir`。从 counts 启动会重新运行基础分析；
[已处理对象的显式复用](workbench/README.md)是另一条入口。

新的 raw strategy 项目保留常规 normalization / 全局 vst HVG / PCA、内部80% PC规则及
常规分辨率扫描/簇关系树。PC k±5、80%重采样、额外分辨率扩展、sample-consensus HVG 和
QC草稿自动预选须明确开启。适用的样本QC、肘部、引用方向及Fisher/BH证据保留。
经典 mean/pct 面板按明确的人类 blood/PBMC 或 pancreas 声明选择；
不适用的声明及缺失基因标为不可用/缺失，不猜测。
跨样本/混合谱系表达扩展仍须主动开启；SoupX/decontX 保持单独可选 R-only 调用。
见[默认策略与可选方法指南](docs/SCIENTIFIC_REVIEW_QUICKSTART_ZH.md)。

### 2. 审查策略并运行基础分析

<a id="gate-strategy"></a>

在**决策点1**核对研究事实、实测QC分布及预计保留细胞；有声明时按sample/QC角色分组，
缺失角色保持pooled或不可用。初始keep-all不表示QC已合格；`nCount >= 1`只排除全零输入。
高counts、核糖体或血红蛋白表达不授权自动删细胞，raw MEX导入也不是empty-droplet calling。

**Use candidate in local draft**只改本地草稿。保存完整方案、查看重建证据，再审批。
保存事实同样不是科学审批。可选doublet/batch事实或依赖缺失时，该路径未执行且明确披露；
已经选入方案但不受支持的方法需要修订。

<a id="gate-clustering"></a>

经审批的基础分析在本地运行，随后常规分辨率扫描在**决策点2**暂停。
查看已计算PC证据、簇关系树、marker对照与样本组成；选择实际扫描过的分辨率，保存改动后
审批实测方案。PC规则或分辨率比较都不提供生物学最优值。
模型辅助是可选项，默认不发出模型请求；可以关页后重开同一项目。
方法定义及边界见[分析策略支持](docs/ANALYSIS_STRATEGY_SUPPORT.md)和[方法附录](docs/SCIENTIFIC_METHODS_APPENDIX.md)。

### 3. 准备并审阅注释

<a id="gate-annotation"></a>

打开注释工作表。每行显示保存簇的marker及已配置的本地参考候选；
冲突与缺失证据会标记，详细统计和来源可展开。

为每群输入标签、定性置信度、基于证据的理由及所提供的支持marker。
明确选择参考候选可把标签和同簇引用复制到未编辑行，置信度与解释仍由你决定。
Coverage是重叠，不是概率。证据不足时用粗标签或**Unknown**；批量Unknown需要输入理由，并保留已编辑行。

选择**Save complete proposal**，通看所有群后，再**Approve annotation and continue**。
保存草稿不会应用标签；审批后应进入完成状态与结果页。
模型可选，纯人工路径无需provider。见[注释辅助](docs/ANNOTATION_ASSISTANCE.md)及[配置模型请求](docs/UNIFIED_MODEL_REVIEW.md)。

### 4. 取得结果

在同一个 R library 环境中：

```r
result <- sc_result(project_dir)
Seurat::DimPlot(result, reduction="umap", group.by="sc_annotation", label=TRUE)
table(result$sc_annotation)
sc_open(project_dir)$view$output
```

`result`是通过已记录文件完整性校验后读取的最终Seurat对象，可继续做研究特定分析。
项目目录也包含markers、metadata、参数、图和决策记录。
注释未完成时，`sc_result(project_dir, stage="analysis")`显式返回暂定分析对象。

### 5. 重开并继续

使用相同包/依赖环境，以相同项目和原始输入/选项再次调用对应入口；省略context以复用保存事实：

```r
# For the single-directory example:
sc_start("filtered_feature_bc_matrix", project_dir,
  sample_id="S1", matrix_kind="filtered")
# For the sample-table example: sc_start(input, project_dir)
# For the RDS example: sc_start("a.rds", project_dir)
```

页面显示已保存阶段；重开不会审批或重跑。此入口保留原输入绑定不变。
若需不依赖原来源位置查看保存结果，可用`sc_open(project_dir)`、`sc_result(project_dir)`，
或只读浏览器入口`sc_run_open(project_dir)`。

## 更多资料

- [中文操作指南](docs/SCIENTIFIC_REVIEW_QUICKSTART_ZH.md)
- [匹配的 v0.6.0 发布路径](docs/RELEASE_060_PROTOCOL.md)
- [公开PBMC3k的R-only预览步骤](docs/R_ANALYSIS_PROTOCOL.md)
- [10x MEX、样本表与keyed cell metadata](docs/TENX_INPUT.md)
- [分析策略及受支持方法](docs/ANALYSIS_STRATEGY_SUPPORT.md)
- [注释证据与决策](docs/ANNOTATION_REVIEW.md)
- [浏览器及远程服务器配置](workbench/README.md)
- [研究者协议—中文](docs/RESEARCHER_PROTOCOL_ZH.md)
- [文档索引](docs/README.md)

R帮助：`?sc_start`、`?sc_analyze`、`help(package="scAgentKit")`。

[版本记录](NEWS.md) · [许可证](LICENSE.md)
