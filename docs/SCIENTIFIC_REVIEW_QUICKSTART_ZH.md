# 科学诊断：一页操作指南

本指南对应 README 的[0.8.0 工作流](../README.zh-CN.md#一个项目工作流)，
历史 v0.6.0 使用[两次审批发布路径](RELEASE_060_PROTOCOL.md)。
[English operator guide](SCIENTIFIC_REVIEW_QUICKSTART.md)。

新 raw strategy 项目默认保留适用的基础证据；额外重计算须主动开启。结果可能不变或变差，审批成功不代表生物学结论正确。
旧项目需保留原包和依赖环境，不要修改其 hashes、审批或 checkpoints 来强行恢复。

1. **明确输入和样本角色，再打开新项目。** 使用原始 counts；sample、donor、capture、condition
   分别按实际元数据声明，不从名字猜测，不把处理条件当作技术批次或样本重复。
   默认路径不需要传入 `scientific_review`：

   首次 `sc_start()` 前先决定人工或模型辅助初始化。默认为人工项目：无 provider、模型预算为零，
   标签和定性置信度由用户填写。模型项目先用 `sc_analyze()` 或 `sc_run()` 初始化 provider、model、
   设置及预算，再用 `sc_start(..., model_suggestions="configured")` 重开相同输入。
   配置不可变，网页不能后加 provider；见[模型配置与独立传输同意](UNIFIED_MODEL_REVIEW.md)。
   `sc_start()` 接受含 counts/Seurat 的 RDS **文件路径**、MEX 路径或样本表，不能直接传内存 Seurat。

   ```r
   service <- sc_start("input.rds", "new-review-project",
     context = list(species="human", tissue="Blood", research_goal="Review local evidence",
       columns=list(sample="sample_id", condition="condition")))
   ```

   仅在输入确有这两列及相应实验事实时使用该示例；没有 sample 信息就省略该声明。
   默认关闭：PC k±5、五次80%重采样、常规scan外的resolution扩展、sample-consensus HVG、QC自动预选。
   默认保留：常规LogNormalize/全局vst HVG/PCA/内部80%选择、常规resolution scan及cluster tree、
   适用的样本QC比较与肘部提示、经典面板mean/pct、引用方向和有真实背景时的Fisher/BH。
   人类 `blood`/`PBMC`/`PBMC3k`/`peripheral blood`/`peripheral blood mononuclear cells` 及 `pancreas`
   按明确的tissue声明选择内置经典面板，大小写不敏感。不从基因、条件、簇或预测猜组织。
   其他物种/组织显示不可用；缺失基因列明，不能当成零表达。可显式传
   `scientific_review=list(panels=list(my_panel=c("gene1","gene2")))` 使用适合该物种的基因。
   默认经典面板不做跨样本复核或逐细胞混合谱系组合；这些扩展仍可显式开启。

   若确需重计算，在**新项目**调用中主动传入，例如：

   ```r
   extra_review <- list(pc_sensitivity=TRUE, resampling=TRUE,
     resolution_extension=TRUE, panels="blood", cross_sample=TRUE, mixed_lineage=TRUE)
   # sc_start(..., scientific_review=extra_review)；这不是上述默认路径。
   ```

2. **审查 QC 草稿和样本比较。** 分布、每样本中位数、跨样本异常提示与组内细胞 MAD 分开显示。
   查看单指标独有命中、交集及原始/预评分/筛选后分母，不把重叠失败数相加。keep_all 只是起始提案，
   不是完成 QC 评估。counts/features 在 log10(x+1) 下只按低尾筛选，高 RNA 仅提示；MT 按原尺度上尾。
   正 MAD 也可能对应极小绝对差，须看百分比点差、技术精度、重叠及样本比较，不新增普遍最小差值、
   正态门槛、删除配额或默认 AND。无独立身份信息时不评估细胞类型删除风险，不猜作者标签或另跑注释。
   跨样本稳健异常需要至少五个可比较样本和非零 MAD。仅主动勾选实验自动预选且满足完整证据及风险上限时，页面可预填
   `any_quality3` 比较草稿，并显著标记未保存/未批准；可修改或弃用。预填不会改变 saved proposal
   或删细胞。先点保存重建影响，再单独审批，最后继续计算；缺失条件会显示不适用原因。

3. **比较分析参数，保留必要的不确定性。** 默认 HVG 仍是全局 vst；若有至少两个明确样本且每样本
   至少 30 个保留细胞，可在完整 strategy JSON 的 analysis 中显式添加
   `"hvg_method":"sample_consensus", "hvg_column":"sample_id"`，保存并审查后审批。
   PC 面板并列显示 top50 内部 80/85% 与弦距肘部，均不是最优参数；可选 k±5 和五次 80% 重采样
   在副本上重建图/聚类并显示 ARI、簇 Jaccard、覆盖及 marker 一致性。固定图分辨率扫描与重采样
   是不同证据；有限扩展也不改变已经批准的 resolution。暂不能复现的 Harmony/周期回归组合会明确
   标为不可用，不用 PCA-only 对照冒充同方法稳定性。

4. **看表达再判断注释；污染校正另存。** 经典面板提供 mean log-normalized expression、原 counts
   检出比例、组内外差值及逐样本方向；通用表达、混合面板共表达都不是类型或污染诊断真值。
   已知标签的支持引用必须有正 FC 和正检出率差；仍不验证基因与标签的语义。参考页保留 hits/
   denominator/coverage，Fisher 仅在记录精确可检验背景时显示，且对全部标签校正；不能把 p 值当概率。
   unresolved 保留 Unknown。保存完整注释后，还需要独立审批才能写入结果。

   初始审批之后须先查看实测 PC、常规 scan/tree、marker 对照及样本组成，选择实际扫描过的分辨率，
   保存编辑后再独立批准实测方案，随后才进入注释；簇树不是谱系。主流程引用和参考匹配基于筛选后的
   marker 池：默认每簇最多 30 个、严格 FC>1、校正 p<0.05，并按 pct.1−pct.2 排序，不是全测量基因。
   Seurat 的 min.pct 用两侧检出率较大值，非两侧都须过线；已知标签引用另要求正 FC、簇内检出高于簇外。
   不在列表不代表无表达，Fisher/coverage 仍受 query/参考选择限制；本轮未放宽规则。
   公开 `examples/three-gate-analysis.R` 以 Unknown、无 provider 实测三次审批，只验证软件路径。

可选 `scAgentKit::sc_run_ambient_correction()` **仅有 R API，没有网页校正入口或网页审批流程**。
实现见 `R/run-ambient-correction.R`，完整参数见 `?sc_run_ambient_correction`。
它要求明确的完整单 capture 声明及命名初步 clusters；SoupX
需要严格匹配的 raw+filtered 矩阵和额外背景 droplets。decontX 可无 raw，但其背景来自其他簇的
模型假设，可能删掉真实 RNA。返回单独 corrected counts 和前后 counts/检出/污染估计记录，
不替换原对象或项目 checkpoints；`round_counts=TRUE` 必须明确选择。先对照经典面板、稀有群和
原始结果，再决定是否用校正矩阵另建项目。依赖缺失时不会自动安装或换算法。

以下是供实际数据使用的调用模板，本次文档验收只解析代码，**未运行模板或新增拟合**。
准备三个自己的 RDS 文件：`filtered` 为有唯一基因/细胞名的原始整数稀疏 counts，
`clusters` 为按 filtered 的 exact cell IDs 命名的字符向量（至少两个初步簇）；SoupX 还需要
同一 capture 的未过滤 droplet 矩阵 `raw`。基因集合必须一致，filtered 条码及其 counts
必须在 raw 中逐一匹配，且至少有 20 个额外背景 droplets。不能用任意子集或合并 capture
代替完整单 capture；将模板中的来源与 ID 替换为真实实验记录后才可声明 `complete=TRUE`。

```r
library(scAgentKit)
filtered <- readRDS("one-capture-filtered-counts.rds")
clusters <- readRDS("one-capture-preliminary-clusters.rds")
capture <- list(id="actual_capture_id", source="actual_experiment_manifest", complete=TRUE)
stopifnot(is.character(clusters), !is.null(names(clusters)),
          setequal(names(clusters), colnames(filtered)))
clusters <- clusters[colnames(filtered)]

method <- "SoupX"  # 或显式选择 "decontX"；无 raw 时由其他簇推断背景
raw <- if (method == "SoupX") readRDS("same-capture-raw-droplets.rds") else NULL
correction <- scAgentKit::sc_run_ambient_correction(
  input=filtered, method=method, capture=capture, clusters=clusters,
  raw_counts=raw, seed=42L, round_counts=FALSE,
  output_dir=paste0("new-", method, "-output"))
corrected <- correction$corrected_counts
receipt <- correction$receipt
```

SoupX 使用 `SoupX` 包，decontX 使用 `celda`；需在既有获准环境中明确准备依赖。
输出目录必须全新，内含 `corrected-counts.rds`、`comparison.json`，记录版本、seed、输入/
校正哈希、背景来源、污染估计及前后 UMI/检出数。decontX 也可显式传入经过上述匹配验证的
raw 矩阵，只将额外 droplets 作为背景。`round_counts=FALSE` 保留浮点估计；这些估计不能
直接绕过新项目 raw-count 入口的整数检查。若研究设计选择取整，须在衍生运行中明确
`round_counts=TRUE` 并保存相应 receipt，再另建输入/项目，不能改写既有检查点。
已运行的原生 PBMC SoupX/decontX 验收与本模板是否执行是两件事，也不代表注释准确率改善。

查看[方法及限制](SCIENTIFIC_METHODS_APPENDIX.md)和[冻结评估协议](EVALUATION_PROTOCOL_V1.md)。
上述操作示例是软件路径，尚不能据此声称准确率或人工时间改善；统一效果基准和平台验收另报。

开发评估后的默认边界：自动 QC 草稿预填默认关闭。仅在用户主动勾选
“Enable experimental automatic QC draft comparison”后，才会按原有风险上限加载
未保存、未批准的比较草稿；手动候选比较始终可用。PBMC 评估未提供独立细胞质量
真值，不能把 OR 作为普遍更优的默认策略。保存与审批仍然分开。

## 开发 API 收敛

当前构建只保留一个可保存、可审批的项目工作流。冗余直接编排入口和 AgentSeurat 对象已退场；
保留的绘图、marker/reference、ontology 和精确 ID 对照工具使用 Seurat 或表格，不授予科学审批。
完整[导出与对象类型变化](API_CONSOLIDATION.md)列明退场和保留能力。

开发测试项目可以按新实现重建，不为旧测试对象维护兼容 facade；baseline 证据、发布历史及
无关研究数据保留。不要修改保存的 hashes、审批或 checkpoints 强行恢复。
R 摘要受长度约束，但完整证据仍可在 `snapshot$view` 中检查；完成流程不证明准确率或省时收益。
