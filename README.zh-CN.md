# scAgentKit

[English](README.md) · **简体中文**

scAgentKit 帮助研究者从单细胞 counts 和样本信息开始，完成 QC、基础分析、分群与注释复核。
保存的项目包含新的 Seurat 对象、marker 表、图和你的决策记录。

## 分析流程

<img src="docs/diagrams/project-analysis-flow.zh-CN.svg" alt="三次复核决定：初始方案、实测分群和注释" width="1000">

[English diagram](docs/diagrams/project-analysis-flow.svg) · [中文流程图](docs/diagrams/project-analysis-flow.zh-CN.svg) · [流程图生成源](docs/diagrams/generate_project_flow.py)

当前源码工作流分别停在三次审批：分析方案、实测分群选择、注释提案。
按下方步骤操作；可选方法见[操作指南](docs/RESEARCHER_PROTOCOL_ZH.md)。
历史 v0.6.0 请用[对应版本的协议](docs/dev/RELEASE_060_PROTOCOL.md)。

| 复核 1 | 复核 2 | 复核 3 |
| --- | --- | --- |
| [初始方案](#gate-strategy) | [实测分群](#gate-clustering) | [注释](#gate-annotation) |

## 安装

需要 R ≥ 4.2、Seurat ≥ 5，网页另需 Python ≥ 3.9。
网页资源已包含在 R 包中。
支持 **macOS 和 Linux**，**不支持 Windows**：本地服务和后台计算进程使用
[Unix `fcntl` 文件锁](https://docs.python.org/3/library/fcntl.html)。

本分支包含尚未发布的修改；历史 v0.8.0 归档不能证明这些修改已安装。
使用本源码时，在匹配 checkout 中运行 `R CMD build .`，记录 SHA256，再按下方方式安装本地归档。
历史版本可从 [Release](https://github.com/ChanghaoKan/scAgentKit/releases/tag/v0.8.0)
下载 [v0.8.0 归档](https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/scAgentKit_0.8.0.tar.gz)
及校验文件，核对下载内容：

```sh
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o scAgentKit_0.8.0.tar.gz https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/scAgentKit_0.8.0.tar.gz
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 -o SHA256SUMS https://github.com/ChanghaoKan/scAgentKit/releases/download/v0.8.0/SHA256SUMS
shasum -a 256 -c SHA256SUMS  # macOS; on Linux use: sha256sum -c SHA256SUMS
```

校验通过后，在归档所在目录的新 R 会话中安装包及必要依赖：

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

应从你的私有 library 读到版本 `0.8.0`。记录归档校验值、包版本和 `sessionInfo()`。
可选方法的依赖与版本要求见[运行环境支持](docs/LINUX_RUNTIME_SUPPORT.md)。
若 GitHub 依赖下载达到 API 配额，`remotes` 可使用已有的 `GITHUB_PAT`。

## 离线安装检查

在新项目中运行随包的小数据示例：

```r
source(system.file("examples", "simple-analysis.R", package="scAgentKit"))
result <- simple_analysis_after(tempfile("scagentkit-offline-"))
stopifnot(inherits(result, "Seurat"), ncol(result) > 0)
```

应得到含 80 个细胞、Unknown 标签的 Seurat 对象，然后再接入自己的输入。
[发布检查](docs/dev/RELEASE_PLAN.md)保留安装与示例运行日志。

<a id="一个项目工作流"></a>

## 分析步骤

在新项目创建前决定模型策略。已有 key 只放在分析机器的环境变量
`DEEPSEEK_API_KEY` 或 `XAI_API_KEY` 中，不写进代码、研究备注、网页或项目文件。
`sc_start()` 直接接收 provider，不需另行初始化。缺少可用 key 时进入人工路径；
检测到两个 provider key 时须明确选择。默认预算为 **USD 0**，尚未用真实模型校准付费默认值。

需要模型辅助时，先 source 下方 helper，检查实际研究信息、聚合类别、provider/model、
已核实价格和自行选择的 USD 上限，再在调用中确认 `confirmed=TRUE`。
Source 本身不会发送内容；下方零预算示例不能产生付费请求。

```r
source(system.file("examples", "full-llm-workflow.R", package="scAgentKit"))
service <- full_llm_start("input.rds", "new-project",
  context=list(species="human", tissue="Actual tissue", research_goal="Actual question"),
  provider=list(name="deepseek", model="deepseek-flash"), budget=0,
  reviewer="Your name", reason="Reviewed aggregate transfer scope and USD cap",
  categories=c("study_context", "aggregate_qc", "aggregate_markers",
    "aggregate_design", "aggregate_expression"), confirmed=FALSE)
```

`confirmed=FALSE` 会要求先检查配置。项目级同意只允许在已保存类别、provider/model 和预算内
自动准备候选，确切 payload 仍可查看。若要逐次同意确切 payload，使用
`sc_start(..., provider=..., budget=..., review=list(allow_external=TRUE))`，省略项目级同意。
两种方式均保留下面三次科学审批。人工路径使用 `provider="manual"`、省略同意并保持零预算。
详见[模型契约](docs/dev/UNIFIED_MODEL_REVIEW.md)。

### 1. 选择输入，声明样本事实

选择新的项目目录。单个 10x MEX 目录需要样本 ID，并声明矩阵是 raw 还是 filtered：

```r
input <- "filtered_feature_bc_matrix"
project_dir <- "analysis"
context <- list(species="human", tissue="Actual tissue",
  research_goal="Actual study question")
service <- sc_start(input, project_dir, context=context,
  sample_id="S1", matrix_kind="filtered")
```

页面显示导入摘要和未审批方案。检查导入细胞、特征名称和样本信息，再进入第 2 步。

多个样本改用包含路径和研究事实的表：

```r
input <- data.frame(sample_id=c("S1", "S2"),
  path=c("counts/control", "counts/treated"),
  matrix_kind=c("filtered", "filtered"),
  donor=c("D1", "D2"), condition=c("control", "treated"))
service <- sc_start(input, project_dir, context=context)
```

样本 ID 必须唯一，各样本 Gene Expression 的 feature ID 集合须相同。
页面中的细胞 ID 为 `sample_id::barcode`。详细格式见[输入与 metadata 匹配](docs/TENX_INPUT.md)。

RDS 内可以是 raw counts 或 Seurat 对象；传入的是**文件路径**，
`sc_start()` 不接收内存中的 Seurat 对象：

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

只用真实存在的 metadata 列声明已经核实的 sample、donor、capture、condition 角色；未知项留空。
counts/layer 检查及明确复用已处理对象的步骤见[操作指南](docs/RESEARCHER_PROTOCOL_ZH.md)。

### 2. 复核方案，再复核实测分群

<a id="gate-strategy"></a>

查看 QC 分布、样本对比、预计保留细胞及完整分析方案。
**Use candidate in local draft** 修改草稿；先 **Save**，阅读更新后的方案和证据，再 **Approve and continue**。
获批的本地分析运行后，页面停在实测分群复核。

<a id="gate-clustering"></a>

查看已计算 PC 曲线、簇关系树、marker 对照和样本组成，选择**实际扫描过的分辨率**。
保存修改、阅读更新后的审阅，再审批；随后进入注释工作表。
若选入的方法尚未 ready，修订选择或补足它列出的前提。
图的含义与 PC 规则见[方法附录](docs/SCIENTIFIC_METHODS_APPENDIX.md)。

### 3. 复核注释

查看 marker 及 DotPlot/FeaturePlot 证据。此版本为新项目离线加载固定 ACT 快照；
[快照来源与用法](docs/ACT_LOCAL_REFERENCE.md)，明确物种/组织并保留原 PMID。
缺失或零匹配会显示 unavailable，仍可按 marker/Unknown 人工复核。首轮模型注释仅看 marker；
其后最多一次另计预算的参考差异复核。CLID 使用固定版本的精确名称/同义词字典；歧义或未映射者保持缺失。

<a id="gate-annotation"></a>

打开工作表，阅读每簇 marker 和参考候选。每行填写标签或 **Unknown**、置信度、理由及提供的支持 marker。
在未编辑行选择参考候选，可复制其标签和引用；置信度与解释由你填写。
批量 Unknown 需输入理由，并保留已编辑行。

选择 **Save complete proposal**，通看各群，再 **Approve annotation and continue**。
页面应进入完成状态与结果页。请求及编辑控件见[注释辅助](docs/dev/ANNOTATION_ASSISTANCE.md)。

### 4. 取得结果

完成后使用相同的 R 包环境。下方绘图行要求分析方案中已运行 UMAP：

```r
result <- sc_result(project_dir)
Seurat::DimPlot(result, reduction="umap", group.by="sc_annotation", label=TRUE)
table(result$sc_annotation)
sc_open(project_dir)$view$output
```

项目还保存 marker 表、metadata、参数、图和审批记录。
注释完成前，`sc_result(project_dir, stage="analysis")` 可读取保存的暂定分析对象。
取得最终 Seurat 对象后，继续研究所需的下游分析。

### 5. 重开已保存项目

使用原包环境、原输入和原选项重复相应入口；省略 context，以读取已保存的研究事实：

```r
# For the single-directory example:
sc_start("filtered_feature_bc_matrix", project_dir,
  sample_id="S1", matrix_kind="filtered")
# For the sample-table example: sc_start(input, project_dir)
# For the RDS example: sc_start("a.rds", project_dir)
```

页面显示保存的阶段。不依赖原输入位置查看结果时，在 R 中用 `sc_open(project_dir)`，
只读网页用 `sc_run_open(project_dir)`。见[重开与错误处理](docs/RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录)。

## 局限

- 1.0 前任何版本都可能破坏兼容性，不保证弃用期，不支持跨版本恢复项目。
- 这套实验性流程执行你复核后的选择；运行完成不证明生物学准确率、QC/PC/分辨率最优或节省时间。
  Keep-all 是起始选择；`nCount >= 1` 只排除全零输入。小数据示例和 Unknown 标签用于检查软件流程。
- 80% PC 规则是项目经验规则；簇关系树的边表示共享细胞，不是谱系。
  参考重叠和定性置信度不是校准概率。缺失基因或评估不等于实测零值或检查完成。
  解释与分母见[方法附录](docs/SCIENTIFIC_METHODS_APPENDIX.md)。
- Raw MEX 导入保留所提供的 barcodes，不做 empty-droplet calling。
  FASTQ 处理及研究特定的轨迹、通讯、调控分析在本流程之外。
  可选诊断须输入适用并明确选择，见[操作指南](docs/RESEARCHER_PROTOCOL_ZH.md)。
- 保留每个项目的原输入、包构建和依赖环境。换版本时，以原输入另建项目并重新复核，旧证据另存。
  **不要修改项目校验值、审批记录或中间计算文件来强行恢复旧项目。**
  见 [API 变化](docs/dev/API_CONSOLIDATION.md)和[版本记录](NEWS.md)。

## 更多资料

- [English operator guide](docs/SCIENTIFIC_REVIEW_QUICKSTART.md) · [中文操作指南](docs/RESEARCHER_PROTOCOL_ZH.md)
- [10x 输入与样本表](docs/TENX_INPUT.md)
- [R 分析协议](docs/R_ANALYSIS_PROTOCOL.md)
- [分析方法](docs/dev/ANALYSIS_STRATEGY_SUPPORT.md) · [注释复核](docs/dev/ANNOTATION_REVIEW.md)
- [网页和远程服务器](workbench/README.md) · [文档索引](docs/README.md)

R 帮助：`?sc_start`、`?sc_analyze`、`help(package="scAgentKit")`。

[版本记录](NEWS.md) · [许可证](LICENSE.md)
