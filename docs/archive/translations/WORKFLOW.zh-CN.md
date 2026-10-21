# 三道审批操作流程

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
页面中的细胞 ID 为 `sample_id::barcode`。详细格式见[输入与 metadata 匹配](../../TENX_INPUT.md)。

RDS 内可以是 raw counts 或 Seurat 对象；传入的是**文件路径**，
`sc_start()` 不接收内存中的 Seurat 对象：

```r
input <- "a.rds"
service <- sc_start(input, project_dir, context=context)
```

只用真实存在的 metadata 列声明已经核实的 sample、donor、capture、condition 角色；未知项留空。
counts/layer 检查及明确复用已处理对象的步骤见[操作指南](RESEARCHER_PROTOCOL_ZH.md)。

### 2. 复核方案，再复核实测分群

<a id="gate-strategy"></a>

查看 QC 分布、样本对比、预计保留细胞及完整分析方案。
**Use candidate in local draft** 修改草稿；先 **Save**，阅读更新后的方案和证据，再 **Approve and continue**。
获批的本地分析运行后，页面停在实测分群复核。

<a id="gate-clustering"></a>

查看已计算 PC 曲线、簇关系树、marker 对照和样本组成，选择**实际扫描过的分辨率**。
保存修改、阅读更新后的审阅，再审批；随后进入注释工作表。
若选入的方法尚未 ready，修订选择或补足它列出的前提。
图的含义与 PC 规则见[方法附录](../../SCIENTIFIC_METHODS_APPENDIX.md)。

### 3. 复核注释

查看 marker 及 DotPlot/FeaturePlot 证据。此版本为新项目离线加载固定 ACT 快照；
[快照来源与用法](../../ACT_LOCAL_REFERENCE.md)，明确物种/组织并保留原 PMID。
缺失或零匹配会显示 unavailable，仍可按 marker/Unknown 人工复核。首轮模型注释仅看 marker；
随后进行 ACT 对比，并可使用受限的只读 ReAct 查证。CLID 使用固定版本的精确名称/同义词字典；歧义或未映射者保持缺失。

<a id="gate-annotation"></a>

打开工作表，阅读每簇 marker 和参考候选。每行填写标签或 **Unknown**、置信度、理由及提供的支持 marker。
在未编辑行选择参考候选，可复制其标签和引用；置信度与解释由你填写。
批量 Unknown 需输入理由，并保留已编辑行。

选择 **Save complete proposal**，通看各群，再 **Approve annotation and continue**。
页面应进入完成状态与结果页。请求及编辑控件见[注释辅助](../../dev/ANNOTATION_ASSISTANCE.md)。

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

重开要求项目格式与当前软件匹配，`sc_open()` 和只读 `sc_run_open()` 同样检查。
格式不匹配会在写入前拒绝，提示“请用原软件环境打开，或新建项目”；
详见[格式闸门](../../../workbench/README.md#project-format-and-reopening)。
使用原包环境、原输入和原选项重复相应入口；省略 context，以读取已保存的研究事实：

```r
# For the single-directory example:
sc_start("filtered_feature_bc_matrix", project_dir,
  sample_id="S1", matrix_kind="filtered")
# For the sample-table example: sc_start(input, project_dir)
# For the RDS example: sc_start("a.rds", project_dir)
```

页面显示保存的阶段。不依赖原输入位置查看结果时，在 R 中用 `sc_open(project_dir)`，
只读网页用 `sc_run_open(project_dir)`。见[重开与错误处理](RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录)。

