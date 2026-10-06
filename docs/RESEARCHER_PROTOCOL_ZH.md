# scAgentKit 研究者操作协议

这份指南面向第一次使用 scAgentKit 的研究者：在数据所在的机器上用 `sc_run()` 创建项目，检查 AI 或人工提出的参数，批准后继续计算，最后读取新的 Seurat 对象。网页是同一项目的可选复核窗口；日常分析不需要手动搬运大 RDS 或导出、导入 ZIP。默认没有外部模型调用。

建议先用第 3 节的公开小数据、零费用示例练习完整流程，再接入自己的数据。已有处理好的 Seurat 对象可从第 5 节进入，明确复用已有基础计算。需要网页时，按第 8 节启动一个只绑定本机的服务。

本文面向包版本 `0.5.0.9000` 的开发版本；科学／UI 候选起点为 `f3c43d8`，本次另加入研究者文档及公开小数据示例。发布后的安装入口是公开仓库的 `main`，不是一个稳定 release tag；复现时记录你实际安装的完整 commit SHA。程序成功运行、模型与数据库意见一致，都不等于阈值最优或细胞身份已经得到生物学验证。

## 1. 先理解四个动作

| 动作 | 保存或执行什么 | 研究者要检查什么 |
| --- | --- | --- |
| 预览并批准模型请求 | 批准这一次确切的汇总内容、模型和生成设置 | 是否允许发送这些背景、QC、marker 或表达汇总；预算是否足够 |
| 采纳或修改候选建议 | 保存一份尚未获科学审批的结构化提案 | 阈值、预计保留细胞、PC、分辨率、校正方法或标签是否合理 |
| 批准科学提案 | 保存针对这份提案和证据的决定、审核人、理由 | 整份方案及风险；修改后须重新检查和批准 |
| Continue／继续计算 | 执行已经批准的本地步骤 | 数据和计算环境是否仍与项目绑定一致 |

模型请求批准不批准科学方案，采纳模型候选也不执行计算。科学审批与执行是两个动作。`sc_run_continue()` 只执行固定的本地阶段，不调用模型；`sc_run_resume()` 则恢复协调器，可能在已批准的模型请求处调用初始化时配置的 provider。选择前先检查当前 `stage` 和 `status`。

项目可以停在 `awaiting_review` 并正常结束 R 进程。稍后另开 R 或 Rscript，用同一个 `project_dir` 检查、批准、恢复。无需让计算节点一直等网页。

## 2. 安装与版本确认

### 2.1 安装这份候选，而不是旧 tag

公开仓库地址是 [ChanghaoKan/scAgentKit](https://github.com/ChanghaoKan/scAgentKit)。本协议随新的 `main` 开发版交付；旧版本或旧 tag 不一定包含本文的协调器、网页和子群功能。安装后核对 `0.5.0.9000` 和下列 exports，而不是仅凭安装成功判断功能齐全。

在将运行分析的 R 环境中使用独立 library。公开 `main` 合入本次开发版后，下面是基础安装入口，会联系 CRAN／GitHub；只安装基础 Depends/Imports，不启用可选算法：

```r
private_lib <- path.expand("~/R/scagentkit-preview-library")
dir.create(private_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(private_lib, .libPaths()))
if (!requireNamespace("remotes", quietly = TRUE))
  install.packages("remotes", lib = private_lib, repos = "https://cloud.r-project.org")
remotes::install_github("ChanghaoKan/scAgentKit@main", lib = private_lib,
                       dependencies = c("Depends", "Imports"),
                       upgrade = "never", build = FALSE)
library(scAgentKit, lib.loc = private_lib)
```

`main` 会变化，稳定复现应将 `main` 替换成自己已经核实的完整 commit SHA。此命令不是依赖锁文件，也不保证 CRAN 未来版本与所有可选方法兼容；本轮没有重新执行网络安装。已经在私有 library 准备好依赖的环境完成了本地 `R CMD INSTALL` 和 installed helper source 验证，但这与全新联网依赖安装不同。

HPC 已有维护者提供的受支持依赖环境时，可选本地 checkout 安装：

```sh
sc_checkout=/absolute/path/to/verified/scAgentKit-checkout
sc_r_library=/absolute/path/to/new/private-r-library
mkdir -p "$sc_r_library"
cd "$sc_checkout"
R_LIBS_USER="$sc_r_library" R CMD INSTALL --library="$sc_r_library" .
```

该命令不下载或修复依赖。实际版本和可选运行时 guards 仍须核对，R 自带 methods 无需另装。

不要为安装候选而更新其他正在运行项目的全局 library。恢复旧项目时，继续使用该项目绑定的实现和依赖环境；升级包后旧审批可能因实现指纹变化被拒绝，不能直接修改状态文件绕过检查。

### 2.2 最低声明与已测环境是两件事

包的最低声明来自 [DESCRIPTION](../DESCRIPTION)：R `>= 4.2.0`、Seurat `>= 5.0.0`、agentomicsCore `>= 0.1.1`，以及 SeuratObject、Matrix、dplyr、ggplot2、magrittr、jsonlite、digest、methods。SeuratObject 在 DESCRIPTION 中没有独立数值下限；这里不补造一个。agentomicsCore 的声明安装来源为 `ChanghaoKan/agentomicsCore@v0.1.1`。

基础流程不要求安装所有 Suggests。网页另需 Python 3 和此 checkout 的 `workbench` 源码；安装 R 包本身不代表网页服务已经安装到系统。Harmony、doublet、cell-cycle 等功能有各自的参数、适用性和依赖约束，见第 7 节。

本轮在 Mac 实际加载并记录的版本如下；这是一个观察到的工作环境，不是这些依赖全部版本组合的验证矩阵：

| 项目 | 本轮 Mac 实测 |
| --- | --- |
| R | 4.6.1 |
| scAgentKit／agentomicsCore | 0.5.0.9000／0.1.1 |
| Seurat／SeuratObject | 5.6.0／5.4.0 |
| Matrix／jsonlite／digest | 1.7.5／2.0.0／0.6.39 |
| irlba／uwot | 2.4.1／0.2.5 |
| Python（本机 `python3 --version`） | 3.9.6 |

实际加载的全部 `sc_run`／`.sc_run_` 函数 formals 和 body 与 `f3c43d8` 源码核对一致。该检查和以下小数据验证没有安装依赖、读取密钥或请求真实模型。

历史上另有一个获授权 Linux 环境完成过指定源码的完整检查及受限真实算法验证，详情见 [Linux 运行范围](LINUX_RUNTIME_SUPPORT.md)。该记录绑定其源码与运行时，不代表本候选已在任意 Linux、用户的 HPC、共享文件系统或 scheduler 上验证。本文的服务器和 scheduler 命令是模板，不自动登录或提交任务。

在将运行分析的 R 进程中先确认：

```r
library(scAgentKit, lib.loc = private_lib)  # 本节上方安装所用 library
packageVersion("scAgentKit")
find.package("scAgentKit")
packageDescription("scAgentKit")$RemoteSha # remotes 安装时记录；本地安装另记 git HEAD
.libPaths()
sessionInfo()
stopifnot(all(c("sc_run", "sc_run_inspect", "sc_run_review",
                "sc_run_resume", "sc_run_continue", "sc_run_suggest") %in%
              getNamespaceExports("scAgentKit")))
```

将这段输出保存在自己的环境记录中。网页 Rscript、交互式 R 和 scheduler 中的 Rscript 应选择同一个包环境，避免读到另一份旧 scAgentKit。

## 3. 第一次练习：公开小 PBMC，mock，全程零 API

本节用随 SeuratObject 提供的公开 [`pbmc_small`](https://satijalab.github.io/seurat-object/reference/pbmc_small.html) 对象的真实 counts 层，重新创建 raw-count 项目。实测是 `dgCMatrix`，230 genes × 80 cells；官方说明为 10X PBMC3k 的小子集，不能作为完整 capture 的代表。对象很小，只适合检查审批、持久化和输出机制。示例的 QC、PC、HVG、分辨率和 `Unknown` 标签都是明确的软件控制，不能作为真实研究的参数推荐或细胞身份结论。

先选新的持久目录。已安装示例中的 helpers 只简化 inspect／exact approval／resume，仍使用同一个 `sc_run()`；source 不会自动创建项目或批准方案：

```r
library(scAgentKit)
source(system.file("examples", "researcher-pbmc.R", package = "scAgentKit"))
project_dir <- file.path(getwd(), "pbmc-tutorial")  # 必须是新项目；可改成服务器持久路径
mock <- make_researcher_pbmc_mock()
run <- researcher_pbmc_start(project_dir, chat_fn = mock)
run[c("status", "stage", "revision")]
# 此处应正常停在 strategy awaiting_review，没有自动批准。

snapshot <- researcher_pbmc_inspect(project_dir)
print(snapshot$evidence)                 # 包含实际输入、背景和 QC 汇总
print(snapshot$strategy_review$details) # 完整参数、预计保留及风险
# 读完上述内容后，才运行以下明确批准。
researcher_pbmc_decide(project_dir, snapshot, reviewer = "tutorial analyst",
  reason = "已阅读这份公开小数据软件控制策略及预计范围；不把它当成推荐QC。")
run <- researcher_pbmc_resume(project_dir, chat_fn = mock)
# 执行 approved QC/normalize/HVG/PCA/neighbors/cluster/UMAP/markers 后，
# mock 依据实际 cluster IDs 提出 Unknown/low，并停在 annotation awaiting_review。

snapshot <- researcher_pbmc_inspect(project_dir) # 必须使用新的 annotation snapshot
print(snapshot$annotation_review$details)       # 真实 markers 与 unresolved 提案
researcher_pbmc_decide(project_dir, snapshot, reviewer = "tutorial analyst",
  reason = "复核marker后，本练习保留所有身份为Unknown/low。")
done <- researcher_pbmc_resume(project_dir, chat_fn = mock)
stopifnot(identical(done$status, "complete"))
final <- readRDS(done$output$seurat)
done$output
table(final$protocol_annotation, useNA = "ifany")
```

这里 context 为 `species="human"`、`tissue="PBMC"`、`columns=list(sample="orig.ident")`，研究目标明确为离线流程练习。`orig.ident="SeuratProject"` 仅是教程对象的项目标签；donor/capture 未知，不将其推断为真实 donor 或完整 capture。mock 读取真实 aggregate evidence，但只回放显式控制：`nCount >= 1`、LogNormalize/10000、100 HVGs、10 computed PCs、固定 5 PCs、resolution 0.4、诊断分辨率 0.2/0.6、UMAP 10 neighbors、seed 20261006、batch none。该控制没有搜索或优化阈值，注释全部 Unknown/low。

本轮 Mac 真实验证完成了 strategy review → exact approve → annotation review → fresh approve → complete：80 cells／230 genes 的源对象、literal cell 顺序、raw counts 和旧注释保持不变；新列为 `protocol_annotation`。两次本地 callback 对应两个 ledger entries，费用／hold 为 US$0；完成后重复 resume 没有重算或再次 callback。这验证软件闭环，不验证 QC 最优、注释正确、真实 provider 或 HPC 行为。

可以在任意 review 停点结束 R。另一个 R 进程重新 `library()`、source 同一示例、定义 `mock <- make_researcher_pbmc_mock()`，再 inspect 和决定；已有项目不要再次调用 start。需要新回调时 `researcher_pbmc_resume(project_dir, chat_fn=mock)` 将同一 mock 重新附到内存。更换项目目录则创建一个独立练习，不能拿另一个项目的 snapshot 审批。

每次操作后都重新 inspect，并真正阅读显示的内容。不要写一个“自动批准所有阶段”的循环用于自己的数据。示例中出现的 `Unknown`／`low` 表示明确保留不确定性；mock 不是实际 DeepSeek 或 Grok 结果。

如果只想先熟悉 Rscript 分进程恢复，已安装包也提供完全 synthetic、非 PBMC 示例 [server_first.R](../inst/examples/server_first.R) 和 [first-run.R](../inst/examples/first-run.R)。它们标明数据来源、mock 规则和使用限制，不需要密钥。

## 4. 接入自己的新数据

### 4.1 支持的输入与进入前检查

`sc_run(input, project_dir, ...)` 支持有行列名的 genes × cells counts matrix／Matrix、Seurat 对象，或本机／服务器上的这些对象的 `.rds` 路径。创建项目只调用一次；已存在项目用 inspect 和 resume，重新分析则选新的目录。

| 输入 | 必须明确的内容 | 常见拒绝原因 |
| --- | --- | --- |
| counts matrix／稀疏 Matrix | 真实非负、有限、整数 raw counts；唯一完整 gene 和 cell ID | 转置矩阵、重复 ID、无名称、normalized 值冒充 counts |
| raw Seurat | `assay`、确切 `counts_layer`、已有 metadata 的角色 | 多个 split counts 层未明确覆盖全体细胞、层名歧义 |
| 本地 RDS 路径 | 文件存在且读取期间稳定；文件内部是支持对象 | 未支持格式、文件内容变化、非 counts 数据 |
| processed Seurat | 除上述 raw counts 外，明确 normalized layer、cluster 列和复用理由 | 不完整或不匹配的已有基础分析；见第 5 节 |

normalized／`data`／`scale.data` 不是 raw counts。不要将这些层改名为 counts 绕过验证。代码使用 Seurat 5 公共 layer API，并保留稀疏输入；无须为了进入协调器把大稀疏矩阵转换成 dense。

查看现有 Seurat 层：

```r
SeuratObject::Assays(seu)
SeuratObject::Layers(seu[["RNA"]])
colnames(seu[[]])
dim(SeuratObject::LayerData(seu, assay = "RNA", layer = "counts"))
```

多个 split counts 层时，先按数据来源在自己的数据准备代码中明确 join／重构，并核对 counts 层覆盖全部 object cells。协调器不会替你猜一个层，也不会悄悄修复 ID。matrix 的 gene ID 含 `_` 或 `|` 时 Seurat 会改名，需在进入前自行作有记录的明确映射并排除碰撞。

这不是任意文件格式的导入器。10x、h5ad 等先用可信、经验证的 loader 转成支持对象；不要把 `.h5ad`、ZIP 或任意压缩文件路径当作 `.rds` 输入。

### 4.2 context 描述真实研究设计

`context` 接受 `species`、`tissue`、`columns`、`notes`、`design` 和 `research_goal`。`columns` 将角色映射到 Seurat metadata 中**真实存在**的列；支持 `sample`、`qc_group`、`capture`、`batch`、`condition`、`group`、`donor`、`treatment`。声明的列必须覆盖每个细胞，并有非缺失、非空的有限值。

```r
context <- list(
  species = "human",
  tissue = "Peripheral blood",
  columns = list(sample = "sample_id", capture = "capture_id",
                 donor = "donor_id", condition = "condition"),
  research_goal = "比较患者与对照的免疫细胞状态；保留可能相关的增殖信号。",
  notes = paste("写明实际采样、建库、处理流程和已知限制。",
                "例如是否富集某一类细胞、是否有应激、低 RNA 群、",
                "处理后样本或稀有群；未知事实请明确写未知。")
)
# 只保留 seu[[]] 中确实存在且已经核对的列映射。
stopifnot(all(unlist(context$columns, use.names = FALSE) %in% colnames(seu[[]])))
```

sample、capture 和 donor 是不同角色。一个 donor 可以有多次采样或 capture，capture 也不自动代表一个 donor。`Ca/Ctrl`、病例／对照、治疗／未治疗是生物条件，不自动作为 batch。若确有技术批次，显式声明真实列及技术来源，并评估它与生物条件的混杂；列名叫 batch 仍不能证明应该校正。

裸 matrix 没有研究 metadata。可以只提供 species、tissue、notes；若需要分 sample／capture 的 QC，先创建 Seurat，再按 literal cell ID 正确添加 metadata。不要为凑示例虚构 donor 或 capture。

线粒体比例按明确 species 与实际基因计算：human 对应 `^MT-`，mouse 对应 `^mt-`。没有匹配基因或物种未声明时，这项指标 unavailable，不是 0%；不能据此应用一个虚构的 percent_mt 过滤规则。非 human/mouse 的可选诊断支持受限，应检查对应模块的适用性。

### 4.3 一次创建，随后少量检查、决定、继续

以下初始化**不会发送数据或请求模型**，会保存真实诊断并在缺少有效提案处停下：

```r
library(scAgentKit)
source(system.file("examples", "first-run.R", package = "scAgentKit"))
project_dir <- "/absolute/durable/path/to/new-study-project"
run <- sc_run(seu, project_dir, context = context, strategy = TRUE,
              provider = NULL, budget = 0,
              review = list(allow_external = FALSE),
              assay = "RNA", counts_layer = "counts",
              annotation_column = "sc_reviewed_identity")
view <- first_run_inspect(project_dir)
```

也可以把 `seu` 替换为 `counts` 或 `"/server/data/raw-study.rds"`；RDS 在所在机器就地读取。`strategy=TRUE` 将 QC 和基础分析参数作为整份策略复核。该模式不接受另一份竞争的 `analysis`／`qc_proposal` 配置；人工完整策略用 `strategy_proposal` 或下节的 revise，模型配置见第 6 节。

`provider=NULL` 且没有人工方案时 `awaiting_configuration` 是正常结果。软件不会用固定阈值伪装成 AI 决定。研究者可以查看诊断、准备 typed 人工提案，或为一个新的项目显式配置 provider。模型、generation、预算等初始化配置不是网页中的任意可变设置。

## 5. 复核、修改和复用基础分析

### 5.1 QC 与分析策略

查看 `view$strategy_review$details` 中的整份方案、背景、风险和真实 QC 预计保留情况。按实际 sample/capture 检查分布、保留比例和排除原因；多个规则的排除原因可以重叠，总数不能简单相加。检查有多少指标 unavailable、是否可能误删低 RNA／高线粒体但有意义的群体。

网页的参数控件或完整 JSON 编辑器保存的是 typed 提案，不是可执行 R。R 可修改当前完整方案，再保存供复核：

```r
view <- first_run_inspect(project_dir)
replacement <- view$strategy_review$details$canonical_proposal
# 这里只举“如何编辑字段”的例子，不给你的数据推荐数值。
# replacement$qc$filters[[1]]$min <- 已根据实际证据确定的数值
# replacement$pcs <- list(method = "fixed", ndim = 已确定的PC数)
# replacement$clustering$resolution <- 已确定的分辨率
first_run_decide(project_dir, "revise", snapshot = view,
                 proposal = replacement, reviewer = "你的审核人ID",
                 reason = "记录修改的证据、预计影响及仍不确定的部分。")
view <- first_run_inspect(project_dir)  # 新版本；旧 view 不再可批准
```

没有当前策略时，可以用完整的 `scagentkit.strategy.v1` 人工对象通过 `sc_run_strategy_revise()` 提交；字段形状见公开小数据例和 [策略支持](ANALYSIS_STRATEGY_SUPPORT.md)。不要从示例抄一套阈值到自己的数据。

本版本关键参数边界：

| 参数 | 当前支持 | 解释与限制 |
| --- | --- | --- |
| QC ranges | `nCount`、`nFeature`、可用的 `percent_mt`，inclusive min/max；真实 sample/capture selector | 保留范围边界包含等号；不支持任意 R 过滤表达式 |
| QC Boolean rules | `scagentkit.qc.rules.v1` 的 `remove_if=any`／`all`、至多 32 个允许的 failure predicates | OR／AND 组合排除条件；先检查完整逻辑和实际保留影响 |
| normalization | strategy 路径 `LogNormalize`、scale factor，VST HVG、PCA | 不是任意 normalization 方法的自动选择器 |
| PCs | `fixed`；`computed_variance`；`computed_top50` | 实际计算前不会捏造方差诊断；computed_variance 分母是实际 computed PCs 的方差，非全基因总方差；top50 只支持 0.80／0.85 参考阈值 |
| clustering | `0 < resolution <= 2`；至多 5 个诊断分辨率 | 显示已计算的群数、大小及 ARI；这些描述不自动选出“生物学最佳”分辨率 |
| UMAP | `umap` 对象只接受 run、n_neighbors | seed 来自 `analysis$seed`，维度来自已批准 pcs 策略；不要添加 `umap$seed`／`umap$dims`；邻居数须小于保留 cells |
| batch | `none`；`manual` 停点；受约束的 `harmony` | 默认 none；具体条件见第 7 节 |

当前支持的固定 `k=20` 邻居图策略要求预计保留至少 21 cells、至少 3 个可表达特征；21-cell 限制来自这条图流程，不是 PCA 本身的普遍最低细胞数。PC 数须小于 HVG 和 cells，选用维度不超过实际计算 PCs。非法参数会停下，程序不默默裁剪成另一个方案。

确认后批准，再继续：

```r
view <- first_run_inspect(project_dir)
approved <- first_run_decide(project_dir, "approve", snapshot = view,
  reviewer = "你的审核人ID", reason = "确认本次完整策略、预计细胞集合与风险。")
# 审批只保存决定。Continue 明确执行本地步骤，不请求模型。
run <- sc_run_continue(project_dir, project_id = approved$project_id,
                       input_hash = approved$input_hash,
                       expected_revision = approved$revision)
view <- first_run_inspect(project_dir)
```

执行后产生的 PC／分辨率诊断在 `view$computed_diagnostics` 中。它们是保存的测量结果，不是原审批前已经存在的证据。在注释写回之前的 stopped 项目中，若据此改参数，需 revise → 新 inspect → 新 approve → continue；协调器根据真实依赖保留或使下游检查点失效，不能承诺任何修改都不重算。`sc_run_strategy_revise()` 不接受 running／complete 或已经写回 annotation 的项目；不要把它当成完成后随意原地重跑的入口，新的基础分析使用新项目。

例如已经到 `annotation_propose` 停点、需要根据真实诊断改 PC／分辨率时，使用专门的策略接口，而不是把 annotation 的 review node 当作 strategy 审批：

```r
view <- sc_run_inspect(project_dir)
view$computed_diagnostics
replacement <- view$strategy_review$details$canonical_proposal
# 修改 replacement 中已根据证据确定的 PC／clustering 字段，再完整保存。
sc_run_strategy_revise(project_dir, proposal = replacement,
  project_id = view$project_id, input_hash = view$input_hash,
  expected_revision = view$revision, reviewer = "你的审核人ID",
  reason = "说明根据已计算诊断修改策略的依据与风险。")
view <- first_run_inspect(project_dir)  # 新策略 review，重新批准后继续
```

若不同意，`first_run_decide(..., action="reject", ...)` 保存拒绝及理由。reject 不产生一个替代建议，也不会继续计算；提出替代方案后重新复核。

### 5.2 已有 processed Seurat：不重做基础计算

适合已有验证的 QC、normalized layer、cluster membership 和 reductions，并希望计算 markers、复核注释的对象。输入仍须有真实 counts；同时明确选定的 normalized layer 与 cluster 列。

```r
processed <- readRDS("/absolute/path/to/existing-processed.rds")
project_dir <- "/absolute/durable/path/to/new-annotation-project"
run <- sc_run(processed, project_dir, context = context,
  start_stage = "processed",
  processed_reason = "写明实际已有QC、normalization、PCA/UMAP和cluster来源及复用依据。",
  assay = "RNA", counts_layer = "counts", normalized_layer = "data",
  cluster_column = "seurat_clusters", annotation_column = "sc_reviewed_identity",
  provider = NULL, budget = 0, review = list(allow_external = FALSE))
view <- first_run_inspect(project_dir)
```

这条入口记录复用原因，跳过原始 QC 执行、normalization、HVG、PCA、neighbors、cluster、UMAP 基础准备，沿选定的 cluster 计算并保存 markers，停在注释配置／审批处。它不验证你过去的阈值是否最佳，也不替换已有 cluster 的科学含义。注释用新列，旧标签保留。

如果要对已有细胞重做基础分析，应从其 genuine raw counts 新建 raw 项目并明确批准新策略；不要把 processed 入口误当成重聚类按钮。完整非网络示例见 [server_processed.R](../inst/examples/server_processed.R)。

## 6. 配置 AI、发送同意与费用

### 6.1 密钥只在运行机器环境中

内置 provider 使用 `DEEPSEEK_API_KEY` 或 `XAI_API_KEY`。在实际运行 Rscript／网页服务的机器中通过自己的环境或用户密钥机制设置，别把 key 写入脚本、context、RDS、HTML、URL、日志或浏览器字段。SSH 远端进程不会自动继承 Mac 本地 R 中的变量。

`Rscript --vanilla` 不读取用户 `.Renviron` 或 `.Rprofile`；只将 key 放在 `.Renviron` 而又使用 `--vanilla` 会导致实际运行进程找不到它。可通过安全的父进程／作业环境注入 key，或自行选择确需读取已审核用户配置的正常 R 启动方式。不要把真实 key 写成命令行参数、粘贴进这份教程或打印 `Sys.getenv()` 全部内容。

下面只读取**非密钥的配置和价格**；价格须由你核对 provider 当前计价，不能把示例数字当作报价。该 helper 检查 key 是否存在，但只返回环境变量名称，不返回或保存 key：

```r
source(system.file("examples", "first-run.R", package = "scAgentKit"))
price_env <- function(name) {
  value <- suppressWarnings(as.numeric(Sys.getenv(name)))
  stopifnot(length(value) == 1L, is.finite(value), value >= 0)
  value
}
provider <- first_run_provider(
  "deepseek",  # 或 "grok"；对应你实际配置的 key 环境变量
  model = Sys.getenv("SC_MODEL_ID"),
  pricing = list(input_per_million = price_env("SC_INPUT_USD_PER_MILLION"),
                 output_per_million = price_env("SC_OUTPUT_USD_PER_MILLION"),
                 cached_input_per_million = price_env("SC_CACHED_INPUT_USD_PER_MILLION")),
  reservation_usd = 0.05,
  generation = list(temperature = 0, max_tokens = 4096L))
# 在新目录创建新项目；provider 配置之后不可任意切换。
new_project_dir <- "/absolute/durable/path/to/new-model-study-project"
run <- sc_run(seu, new_project_dir, context = context, strategy = TRUE,
  provider = provider, budget = 0.50,
  review = list(allow_external = TRUE), annotation_column = "sc_reviewed_identity")
```

模型 ID 必须与你的 provider 账号和当前服务相符。当前代码内置默认 ID 是 `deepseek-flash` 和 `grok-4.20-0309-non-reasoning`，DeepSeek 默认关闭 thinking；它们是代码默认，不保证服务未来仍提供该 ID。使用前自行核对，不把失败改写为成功。

`allow_external=TRUE` 允许产生外传预览，不代替对确切 payload 的同意。初始化后请先 inspect：若 `pending$kind="external_transfer"`，R 可用第 3／4 节的 `first_run_inspect` 与 `first_run_decide` 对这份预览 approve/reject，再 `first_run_resume`。默认本地科学 review 页面不处理所有旧式 external_transfer 节点，不能以网页没有按钮推断请求已获批准。

### 6.2 可选统一模型建议通道

当前还支持 `sc_run_suggest()` 的 preview → approve → request → adopt／discard 通道，在整份科学审批之前保存候选。配套 helper 减少手工传 hash：

```r
source(system.file("examples", "unified-model-review.R", package = "scAgentKit"))
view <- unified_review_inspect(project_dir, simulate = FALSE)
view$suggestion$preview  # 阅读确切内容、provider/model/settings 与预算
view <- unified_review_suggest(project_dir, view, "approve",
  reviewer = "你的审核人ID", reason = "允许这一次确切汇总发送给已配置模型。")
view <- unified_review_suggest(project_dir, view, "request")  # 显式请求
view$suggestion$candidate
view <- unified_review_suggest(project_dir, view, "adopt",
  reviewer = "你的审核人ID", reason = "采纳候选为待复核提案，记录保留的疑问。")
# 接下来仍须检查、必要时 revise，再科学 approve 和本地 continue。
```

这段只在保存状态显示该模型通道 available 时使用；初始化若先到旧式 external_transfer 停点，先处理该 exact 预览。模拟示例使用 `simulate=TRUE` 和明确 mock 项目，它保存 SIMULATED 来源且零外传，不能把真实 provider 项目用网页标志临时改成 mock。

显式 `chat_fn(system_prompt, user_prompt)` 也可作为 R 内存回调；返回必须是可验证的 JSON 对象。回调必须如实声明是否 external，不可把远程函数标成 local 绕过 consent。R 重启后需重新附加同一安全配置的回调；网页不能从字段、环境变量或 source code 恢复任意 R 函数。

模型只能提出允许的结构化操作。空答复、未支持参数、非 JSON、引用不在该 cluster 证据中的基因等会成为可恢复的失败／停点，不会执行模型生成的 R 代码。人工可提供完整 typed 方案，不必为了推进而反复付费询问。

### 6.3 发送内容与预算边界

模型默认只接收经预览批准的 aggregate QC、marker／表达汇总及声明背景，不发送 raw matrix、cell barcodes 或逐细胞个人 metadata。context 自由文本、组名和汇总本身仍可能泄露私人信息；“原始数据留服务器”不等于没有外传。私人研究数据是否允许发给 provider，由研究者和所属机构决定，本协议不自动代你批准。

本地 trusted review 浏览器可以显示 exact scope／cell IDs，它与外部模型 payload 是不同目的地。导出的 `metadata.csv`、项目目录和 bundle 也可能包含敏感信息，应按自己的研究数据制度管理。

budget 是**每个项目**的费用上限机制。每次请求先预留 `reservation_usd`；已知 usage／配置价格用于记录费用，未知 usage 保留 conservative hold，允许读取已有缓存并暂停新的未缓存请求。实际账户账单仍应向 provider 核对。父项目与各 child 的预算不等于账户共享总预算，显式继承模型时尤其要分别监控。

确切相同请求利用保存的缓存，完成项目的恢复不会重新请求或重收费。没有自动付费 retry。请求超时、断网或 dispatch 状态不明时，先 inspect 项目和 provider ledger；不要删除 hold、改 journal 或连续点请求来“修复”。模型／settings 改变产生新的请求身份，且项目初始化配置不能任意变更。

## 7. 可选分析方法：先看 ready 和适用性

| 功能 | 当前流程内的能力 | 启用前要核实 |
| --- | --- | --- |
| MAD QC | 显式 `qc_mad` 候选面板和审阅；不默认替代范围规则 | 有限、预先配置的 pool、参数、固定 panel hash、实际影响；不任意重拟合最优阈值 |
| Cell-cycle | 明确 species 和 gene set 的诊断；保留、full 或受限 difference 回归 | 基因集来源／版本／映射、覆盖及研究目标；不自动删除 cycling cells |
| Doublet | 明确 droplet/raw-count/capture 适用性的 scDblFinder 评分和联合 QC 审批 | 每个 capture、率／阈值适用依据、审计成功；分数非已校准双细胞概率 |
| Harmony | 明确参数、技术变量、可识别研究设计和整份审批下的 embedding 校正 | 不从 Ca/Ctrl 自动推 batch；全混杂／嵌套别名／秩亏设计阻止校正；不保证生物信号保留 |

在这个候选中 `batch$method="manual"` 是明确人工边界，不是执行任意用户算法。默认 `none` 保留未校正基础分析。Harmony 保留 RNA counts/data 和未整合 PCA，影响后续 embedding/邻居；通过设计检查也不说明校正必要或有益。

doublet 的受审运行时组合是 scDblFinder `1.26.7` + xgboost `>=3.1`，以及 scDblFinder `1.22.0` + xgboost `1.7.11.1`；还要符合规范函数身份与每 capture 审计。Harmony 的已审执行版本为 `2.0.5`。包已安装、方法在 allowlist 内、提案 ready、真实算法已 executed 是不同状态；未知版本或修改过的 namespace 不能靠跳过 guard 获得支持。

不要为了基础练习盲目安装或启用这些模块。具体可复制范例与边界分别见 [MAD](MAD_REVIEW.md)、[cell-cycle](CELL_CYCLE_REVIEW.md)、[doublet](DOUBLET_REVIEW.md)、[Harmony/PC](HARMONY_PC_REVIEW.md)。可选包缺失是需要显式处理的依赖问题，不能在报告中写成算法已经执行。

## 8. 同一项目的可选网页与服务器运行

### 8.1 只绑定 loopback

在分析机器准备好同一 R library、固定 Rscript 和 Python 3。网页代码来自源码 checkout；安装 R 包不会自动给你这个目录。按第 2 节版本说明，在公开 `main` 合入本开发版后取得源码并记录实际 ref：

```sh
git clone https://github.com/ChanghaoKan/scAgentKit.git
cd scAgentKit
git rev-parse HEAD
```

R 包与该 checkout 应对应同一实现；若网页需要新的接口而 R library 中是旧包，应安装对应源码，不混用版本。从这个 checkout 启动：

```sh
cd /absolute/path/to/verified/scAgentKit-checkout
python3 -B workbench/server.py \
  --run-project /absolute/durable/path/to/study-project \
  --rscript /absolute/path/to/Rscript \
  --r-library /absolute/path/to/private-r-library \
  --local-continue --port 8774
```

打开 `http://127.0.0.1:8774/workbench`。当前主界面集中显示父项目、review、scope 和输出；专用页面仍有 `/review` 和 `/subclusters`。检查面板是否连接预期的 project ID、scope 和 stage，再提交决定。

`--local-continue` 明确启用本地 Rscript worker，只执行已批准计算。若不指定，网页可以复核，计算仍在 R 中继续。真实 provider 建议 worker 另需操作者显式加 `--model-suggestions`；mock 项目另加 `--model-mock`。这些 flags 不批准模型外传、不改变 provider、预算或科学方案。custom chat_fn 留在 headless R，不能由网页恢复。

子群工作区另加 `--subcluster-workspace /absolute/path/to/existing-separate-workspace`；目录须先存在，不能嵌套或与父项目重叠。浏览器只使用已配置父项目和注册 child，不能选任意路径、上传 source code、提供密钥、改变 firewall 或提交 scheduler。

当前网页支持完整科学提案复核、允许字段编辑、exact 模型预览／请求／采纳、已批准本地继续、子群创建及受限背景修正、exact-ID 新对象 apply/undo 和保存结果。它不是任意 R 工作流的可视化编辑器；非 UI 接入的边界仍在 R 中处理。当前紧凑样式为候选界面，布局不改变审批或计算合同。

### 8.2 SSH 仅做隧道，不搬数据

若服务运行在获授权服务器上，在你自己的 Mac／本地终端使用你确认的 host、user 与 SSH 端口：

```sh
# 替换全部占位符；命令不包含登录密码或私钥。
ssh -N -L 8774:127.0.0.1:8774 -p "<SSH_PORT>" "<USER>@<AUTHORIZED_HOST>"
```

随后本机浏览器打开上述 loopback URL。认证由你的 SSH 客户端、密钥或机构登录机制完成；不要把密码发到聊天、写进项目或 URL。本工具不猜测服务器地址，也不自动登入。SSH 认证失败与分析状态是两回事。

服务只绑定 `127.0.0.1`，不要为访问网页改成公网监听。无 DISPLAY 的服务器只提供 URL／隧道方式，不依赖弹出 Mac 浏览器。RDS、checkpoint、审批和结果留在原机器。SSH／浏览器断开后先 inspect 保存状态，重新打开页面不是重发计算或模型请求。

### 8.3 Rscript 与 scheduler

先用小数据确认相同 library 的 headless 脚本能在你的运行节点读写 durable project storage。使用包内 [server_first.R](../inst/examples/server_first.R) 可以练习每次一个独立 R 进程：

```sh
# 此示例创建 synthetic 项目，非你的私人研究数据。
Rscript --vanilla /path/to/installed/examples/server_first.R /durable/toy-project run
Rscript --vanilla /path/to/installed/examples/server_first.R /durable/toy-project inspect
# 阅读后单独 approve，再 resume；到新复核点再次 inspect。
```

真实研究 driver 应明确 `run` 只初始化一次，`inspect` 只读证据，`resume` 恢复既有项目；审核需单独操作。包内 [slurm_sc_run.sh](../inst/examples/slurm_sc_run.sh) 是不自动提交的模板：需按站点核对 account、partition、CPU、memory、time、模块和持久路径，再由你自己选择是否提交。不要在登录节点直接运行重计算，也不要把凭据写进 scheduler 脚本或 stdout。

模板的资源数字是示例，不能由一个 80-cell 测试推导为大数据需求。共享文件系统的原子 rename／目录锁、multiuser 权限、作业终止、节点环境和资源限制须在真实站点单独验证。

## 9. 注释复核、CellMarker 2.0 与证据来源

### 9.1 先看真实 marker 证据，再决定标签

基础分析结束后计算 markers，保存当前 literal cluster IDs、marker statistics、可选参考候选和当前提案。检查 `view$annotation_review$details`，看每个 cluster 的细胞数、来源、理由、supporting markers 和局限。

人工保留 unresolved 的最小操作：

```r
view <- first_run_inspect(project_dir)
proposal <- first_run_unknown(view)
sc_run_propose(project_dir, proposal, reviewer = "你的审核人ID",
               reason = "当前证据不足，明确保留 Unknown/low；未调用模型。")
view <- first_run_inspect(project_dir)
# 检查完整提案后按第5节 approve，再 sc_run_continue。
```

每份 `scagentkit.annotation.v1` 提案必须恰好覆盖所有当前 evidence clusters，各一次。已知标签须引用该 cluster **提供的** marker 基因，幻觉或跨群引用拒绝。这个校验只能证明引用可用，不能证明这些基因足以区分该细胞类型；`confidence` 是定性分类，不是概率。`Unknown` 可以不引用 marker。

不要以 UMAP 位置、cluster 编号或一个 marker 就自动定身份。当前 top marker 列表中没出现一个基因，不证明它不表达；未评估的 negative evidence 不写成阴性。必要时保留粗粒度标签或 Unknown，使用独立已知标志、表达证据和研究设计核实。

若要撤回**该项目已执行的注释**，从 inspect 的 `annotation_review$lifecycle$decisions` 核对确切已执行 approval 的 `decision_id`，使用 `sc_run_undo(project_dir, decision_id, reviewer, reason)`，或当前节点支持的网页 undo。它归档旧 output／bundle 到 `versions/undo-REV/`，保留早期 QC／基础计算，回到 `annotation_propose`／`awaiting_configuration`；需重新提出、阅读、批准注释，不自动重发 AI。这与第 10 节撤回一次 derived-parent application 是不同操作。

已有 child workspace 时，完成父项目在网页中只读。需要父注释撤回，应在绑定 child 工作区之前处理；不要修改一个冻结父对象来让已有 child 的旧 provenance 看似仍有效。参考或其范围改变也会使旧注释审批失效，受保护的 `sc_run_set_reference()` 可在写回前保留 analysis/markers 后更新证据，具体见 [CM2 证据复核](CM2_EVIDENCE_REVIEW.md)。

### 9.2 CM2 是什么，怎样提供本地参考

CM2 指 **CellMarker 2.0**，来源为 [Hu 等，Nucleic Acids Research 2023，DOI:10.1093/nar/gkac947](https://academic.oup.com/nar/article/51/D1/D870/6775381)。当前实现是本地 marker coverage matcher，不是 ACT，也不自动做 ontology、基因 symbol 纠错或文献检索。可先提供自己已核验、允许使用的本地 CSV／TSV 参考：

```r
reference <- annot_load_reference("/absolute/path/to/verified-local-reference.csv")
# 创建 sc_run 项目时显式传入 reference。
reference_review <- list(ai_mode = "independent", top_n = 5L,
  symbol_aliases = setNames(character(), character()),
  label_map = setNames(character(), character()),
  label_relations = data.frame(child = character(), parent = character(),
                              lineage = character(), stringsAsFactors = FALSE))
```

参考至少有 `cell_type` 和 `marker`；有范围意义的匹配还需 `species`、`tissue` 与正确 context。协调器 species/tissue 使用 trim 后不区分大小写的 exact 匹配，参考 tissue `all` 是明确宽范围声明；`Blood` 不自动包含 `Peripheral blood`。范围缺失、mismatch、无 overlap 和空参考都应保留可见。不要改组织名只为了得到更多匹配。

score 是 unique marker hits／unique reference genes 的覆盖分数，不是该细胞类型的概率；参考集大小、symbol 版本和组织覆盖会影响候选。`symbol_aliases`、`label_map`、`label_relations` 必须由你显式提供，关系也是声明，不是自动推断的标准本体。

`ai_mode="independent"` 表示模型输入不含数据库候选；`guided` 则包含这些候选。联合 review 并列展示数据库、当前 AI／人工建议、可选历史响应和已声明的命名／层级关系；同意或冲突是审阅信号，不能相乘变成可信概率，也不能把 independent 输入模式误称为所有证据彼此统计独立。

`annot_query_cellmarker(species="human"或"mouse", ...)` 是另一个**显式网络动作**，首次尝试下载并缓存完整 XLSX，需 readxl；它的 tissue 下载筛选为 substring，与运行时 reference exact scope 匹配不同。普通 `sc_run(reference=...)` 不替你自动下载 CellMarker 数据。本指南不执行下载，也不随包提供历史本地 human-blood 验证 CSV；本轮没有验证当前下载站点可用。

需要记录来源 URL、下载日期、文件 hash、species/tissue、版本、使用的 symbol 字段及变换。CellMarker 2.0 论文的许可不能自动当作数据库再发布授权；现有开发审计未确认数据库单独许可，分享参考前需自行核实。更多 provenance 字段和完整范例见 [CM2 证据复核](CM2_EVIDENCE_REVIEW.md)。

主网页中 human GeneCards／mouse MGI 与官方 human 候选等基因链接是**点击才导航**；点击会向目标站点披露所选 symbol／ID，不上传 expression 或列表。无匹配／物种不明保持无链接，不推断缺乏 ortholog。链接提供查阅入口，不等于已经做过文献或基因解释分析，见 [基因链接](GENE_LOOKUPS.md)。

## 10. 选定子群、修正背景、保存新的父对象

### 10.1 子分析是独立 raw-count 项目

父项目完成后，在 scope 页面选择真实 parent cluster ID 并检查 union cells 和来源。选择“某类细胞”是一份待检验的假设；父标签可能来自 mock、AI 或未审查旧列，不能成为 child 身份的真值。

创建 child 明确保存父项目 ID／revision／input/output/scope hash、选定 literal cell IDs、上下文和策略选择。child 从选定 raw counts 重新建立独立基础分析，不复用父 UMAP、neighbors、active identities；父旧 cluster/annotation 列保留为 provenance。默认保留选定 cells、不再次 doublet 删除、batch/cycle/reference 采用披露的默认选择，计算前仍须批准 child 策略。

R 的简短路径使用已安装 helper，先 inspect 可用 ID，再选择：

```r
source(system.file("examples", "subcluster-review.R", package = "scAgentKit"))
parent <- "/absolute/path/to/completed-parent"
child <- "/absolute/path/to/separate-workspace/child-01"
dir.create(dirname(child), recursive = TRUE, showWarnings = FALSE)
scope <- subcluster_example_scope(parent)
scope$clusters
# 下行的 literal IDs 必须替换为你刚读到并决定选择的 IDs。
selected <- subcluster_example_scope(parent, clusters = c("1", "4"))
selected$selected
subcluster_example_create(parent, child, selected,
  reviewer = "你的审核人ID", reason = "说明选择范围和拟研究的子群问题。")
child_view <- subcluster_example_inspect(child)
```

然后复核 child strategy → approve → continue，独立复核 child annotation。可继续用同一网页，无需把数据搬回 Mac。至少 21 cells 的限制来自当前固定 `k=20` 的 child 邻居图流程，不满足时不自动放宽。当前不支持 child 再派生 grandchild，也不自动合并重叠 children。

### 10.2 软背景编辑：只改变注释假设

child 注释停点可在网页或 R 编辑 `enabled`、`lineage_hint`、`identity_status`、`tissue`、`notes` 五项。`identity_status` 只能是 `labeled`／`unknown`／`mixed`／`unreviewed`；lineage_hint、tissue 最多 200 UTF-8 bytes，notes 最多 2000 bytes。`NULL` 清除 nullable 的 lineage_hint、tissue、notes。`enabled=FALSE` 只禁用父 lineage expectation，不清除 tissue、notes 或不可变来源；tissue／notes 仍可能进入后续确切的 aggregate preview，须阅读。

```r
child_view <- sc_run_subcluster_inspect(child)
run <- child_view$run
sc_run_set_child_context(child,
  context = list(enabled = TRUE, lineage_hint = "待核实的免疫谱系假设",
                 identity_status = "unreviewed", tissue = "Peripheral blood",
                 notes = "说明为什么修正父标签假设；不把它当作已证实身份。"),
  project_id = run$project_id, input_hash = run$input_hash,
  expected_revision = run$revision,
  expected_context_hash = run$child_context$hash,
  reviewer = "你的审核人ID", reason = "记录背景修正的事实依据。",
  request_id = "context-correction-001")
child_view <- sc_run_subcluster_inspect(child)
```

只在停止的 `annotation_propose`／`annotation_apply`、写回前允许此操作。已经执行的 annotation 必须先用受保护的 annotation undo 回到合适停点；完成项目的 context 显示为只读。

软编辑保留已计算 analysis、markers 和 usage ledger，增加 context generation/hash，使旧 annotation 提案、响应／采纳、科学 approvals 和有关外传 consent 失效。修正后重新检查当前证据、重新请求／提案并审批；网页保存本身不发请求、不重算基础阶段。不允许改 species、真实 metadata roles、选定 cells 或冻结父来源来规避来源约束。

同一个 request ID 的 exact payload 可重放并取得历史保存回执，不能用于不同内容。历史回执也不说明当前 context 仍等于旧编辑；读取当前 generation/hash 确认实际背景。

### 10.3 exact-ID apply 和 undo

child 完成后点击“复核确切子群标签并保存新的父对象”，检查目标新列、父／child bindings、选中与 QC 后保留 cells、outside-NA policy，再显式批准 apply。apply 动作立即生成新的 RDS，无额外 Continue；它与先保存科学审批、再 Continue 的分析步骤不同。R 中可用同一 helper：

```r
child_view <- subcluster_example_inspect(child, column = "sc_reviewed_subtype")
child_view$apply_snapshot
applied <- subcluster_example_apply(child, child_view,
  reviewer = "你的审核人ID", reason = "批准本次确切范围的子群标签写入新对象。",
  request_id = "subtype-apply-001")
derived <- readRDS(applied$application$output_path)
```

写回以 literal cell ID 对齐，只给 child 经批准 QC 后保留的 cells 新标签；范围外和 child QC 删除的选中 cells 在新列为 `NA`。不把数字 cluster ID 当作 parent cell ID。原父对象、顺序、其他 metadata／标签、layers 和 reductions 保留；apply 生成新 RDS，不覆盖父文件。目标列冲突、父 input/revision/output/membership 改变或 child 审批变化会拒绝旧 apply。

如果撤回，选择确切 active application，undo 生成恢复版本并保留旧文件及 history：

```r
child_view <- subcluster_example_inspect(child, column = "sc_reviewed_subtype")
undone <- subcluster_example_undo(child, child_view,
  application_id = applied$application$application_id,
  reviewer = "你的审核人ID", reason = "记录撤回该次子群标签的原因。",
  request_id = "subtype-undo-001")
restored <- readRDS(undone$undo$output_path)
```

只能 undo 该 child 拥有的 exact active application。新的 derived RDS 是输出文件，不自动成为一个可执行协调器项目；再次分析需明确创建新项目。替换自身 active application 的 `supersedes` 和版本链见 [子群复核](SUBCLUSTER_REVIEW.md)，多个 children 的自动合并不在本版范围内。

## 11. 输出、恢复与可复现记录

```r
view <- sc_run_inspect(project_dir)
view$status
view$output
stopifnot(identical(view$status, "complete"))
final <- readRDS(view$output$seurat)
```

输出路径以实际 `view$output`／application receipt 为准：

| 保存内容 | 用途 |
| --- | --- |
| `output/seurat.rds` | 新 Seurat；默认新注释列，源对象和旧标签不被覆盖 |
| `output/markers.csv`、`metadata.csv` | 实际 marker 表和最终 metadata；可能包含敏感 IDs／组信息 |
| `output/parameters.json`、strategy／可选方法 summary | 保存初始化参数、批准策略、实际执行与来源边界 |
| `output/annotation_evidence_summary.json` | 本地 DB／AI／历史来源摘要；不把完整数据库当作输出再发布 |
| `output/report.md`、适用时的 QC／UMAP 图 | 参数、hash、计算结果与限制；图是否存在取决于实际阶段 |
| `resume.R` | 恢复入口；需要新模型调用时仍要恢复运行时凭据或内存回调 |
| `bundle/` | 自动管理的本地 review bundle；日常不需手工 ZIP 转运 |
| checkpoint、`decision_history.json`、provider cache/ledger | 实际保存阶段、hash 链历史、请求及 usage／hold |

`decision_history.json` 等可读旁路文件便于审阅；权威状态由项目的验证机制读取，不能手工改这些文件恢复权限。`complete`／`EXECUTED` 表示计算执行完成，不等于科学结论获最终接受；最终研究解释仍由研究者负责。

R 重启后：

```r
library(scAgentKit)
project_dir <- "/absolute/durable/path/to/existing-project"
view <- sc_run_inspect(project_dir)
# awaiting_review: 先按当前 snapshot 审批。
# ready: 可用 sc_run_continue 的 exact bindings 继续本地计算。
run <- sc_run_resume(project_dir)  # 不重算完成阶段；查看返回的实际停点
```

已有 `complete` 或 `awaiting_review` 的 resume 不重新计算／请求。failed 状态不会默认重试；先查看 `failure`。确认修复后本地 stage 可用 `sc_run_continue(..., retry=TRUE)`，协调器可显式 `sc_run_resume(..., retry=TRUE)`。后者不能消除 unknown dispatch 或自动重复收费；请求不明必须先核对 ledger。不要假设按同一个按钮等于一次安全 retry。

项目有原子写盘、锁、输入／证据／提案 hash 与 revision 校验。一个项目不要同时运行两个计算进程。审批绑定旧版本会拒绝，程序不自动将它升级为针对新证据的同意。断网／网页刷新先读 saved state，再明确下一步。

## 12. 常见停点与反馈

| 现象 | 先检查 | 合适下一步 |
| --- | --- | --- |
| `awaiting_configuration` | 是否缺人工策略／注释；provider 是否 configured；环境变量是否在实际进程 | 提供 typed 人工方案，或恢复初始化 provider 的运行环境；不表示 AI 已给建议 |
| `awaiting_review` | 当前 kind、完整 evidence/proposal、project/scope、hash/revision | 读后 approve/reject/revise；批准后另一次 continue/resume |
| counts/layer/ID 错误 | 公共 LayerData、Layers、raw count 属性、完整 literal IDs | 在新输入准备代码中明确修正，并记录来源；不改 checkpoint 欺骗校验 |
| mitochondrial unavailable | species、symbol 类型、实际匹配 MT genes | 明确 unavailable；使用有实测支持的方案，不填成 0 |
| unsupported provider response／marker citation | typed shape、参数范围、该 cluster 提供的 genes | 保留失败记录，人工修正或明确重新请求；不 source 模型代码 |
| stale review／context／apply | 是否另一操作改了 revision/hash、parent scope、context generation | 重新 inspect、阅读当前状态，再作新决定 |
| lock held | 是否仍有本机／同 host 的 worker 或 job | 先查保存状态与进程；不删除锁强行并发。确需恢复锁请按已有 token/reason 接口核对 |
| browser request 失败或响应丢失 | saved job／receipt 是否已经记录操作、request ID 是否一致 | 刷新只读检查；不重复创建、付费请求或 approve 看不到的新方案 |
| SSH `Permission denied (publickey,password)` | 机构给的 host/user/port/key 和本机 SSH 客户端 | 自行修复认证；不把密码发到聊天，不推断分析项目损坏 |
| UI 没有计算／模型按钮 | 操作者 flags、当前 stage、scope 权限和模型 availability | 用同库 R 处理支持的 headless 操作；不假装完整网页能力已启用 |
| 可选算法不 ready | 包版本、source guards、适用性和明确配置 | 安全保留 none/keep/manual 或按方法协议修复环境；不宣称算法执行 |

反馈时使用下面模板，删去私密路径、cell IDs、个人组名和任何密钥；不能分享数据时先用公开／synthetic 最小例复现：

```text
源码 ref / scAgentKit 版本：
OS、R、Seurat、SeuratObject、Python（网页时）：
实际包路径及独立 library（可脱敏）：
输入类型、assay/layer、cells/features、是否 processed：
context 角色和研究问题（脱敏，不发送逐细胞 metadata）：
操作前 stage/status/revision，期望与实际结果：
准确错误文字／failure 信息：
是否有 saved job / application / request receipt；操作是否可能已完成：
是否外部调用、provider/model、ledger usage/hold（不贴 key）：
能公开分享的最小复现代码和相关 hash：
```

本版支持真实 counts 的可恢复人工／AI辅助协调、受限策略、marker/参考注释审阅和 exact-ID 子群新对象输出。它不承诺任意数据自动清洗正确，不自动判断最优 QC/PC/分辨率，不提供通用 ambient-RNA 校正、任意文献／基因聊天、跨 child 自动合并、任意网页代码执行或用户 HPC 部署保证。为研究结论保存本地参数、输入来源、环境、审批理由和独立生物证据，比只保留最终 UMAP 更有用。
