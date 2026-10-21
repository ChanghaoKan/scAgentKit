# One reviewed project workflow

This is a development API consolidation, based on the reviewed PR11 head
`7884b72509246fa4708a0a0dffb6dd8d80dc4e08`. There are no existing analyses to
migrate. Repository-owned examples/benchmarks are updated to the current engine;
development test projects can be rebuilt. No long legacy compatibility facade
is retained. Published Git/release history, frozen baseline evidence and
unrelated research data remain untouched.

## The primary workflow

`sc_start()` opens the local browser; `sc_analyze()` prepares the same project
from R. `sc_open()`, `sc_review()` and `sc_result()` inspect, decide and retrieve
its result. Advanced `sc_run_*` operations are clients of the same saved state,
not another analysis implementation. Initial strategy, measured clustering and
annotation approvals remain separate. Model requests still require the saved
provider/budget and exact transfer consent. No model fees are authorized here.

Shared marker discovery/summary, reference-overlap, strict validation and ARI
kernels were extracted before retiring the old orchestration. The native marker
and reference adapters no longer construct AgentSeurat. Public `pbmc_small`
marker tables, summaries/cycling statistics and complete native reference
evidence were compared to the preserved pre-extraction baseline exactly.
Source-level validator/ARI signatures and bodies were preserved during moves.

## Retained useful tools and their types

| Utility | Input | Output / boundary |
| --- | --- | --- |
| `qc_add_metrics` | Seurat, explicitly declared species or complete regexes, exact count layer | Seurat copy with measurements; no filtering or species inference |
| `qc_split` / `qc_merge` | Seurat / Seurat list, explicit metadata key or collision prefixes | Seurat list / new Seurat; no guessed sample role, prefix stripping or gene union |
| `qc_plot` / `sc_plot_umap` | Seurat with measurements / an existing UMAP | Real PNG paths; no model request or parameter selection |
| `sc_find_markers` | Prepared Seurat and saved `seurat_clusters` | Full marker data.frame |
| `sc_markers_summary` | Marker data.frame | Filtered table, summary/cycling attributes; unchanged numerical policy |
| `annot_load_reference` / `annot_query_cellmarker` | Explicit reference path/scope/cache | Reference table and recorded provenance |
| `annot_match_reference` | Selected marker table and reference | Candidate table with full matches/provenance attributes; coverage is not confidence |
| `annot_map_to_cl` / `cl_lookup` | Label table or Seurat / query and explicit local ontology or documented cache | Exact dictionary matches or lookup candidates, never identity validation |
| `annot_collapse_to_broad` | Explicit supplied labels and optional map | Standalone label transformation; never automatic during project review |
| `annot_compare_with_reference` | Seurat label column plus explicit reference column or exact-ID vector | Descriptive agreement list with denominators; no prefix/role guessing or identity-truth claim |
| `sc_project_prepare` / `sc_project_export` | Named counts/Seurat / prepared Seurat | Explicit preparation / verified portable bundle; input remains unchanged |
| `sc_review_validate` / `sc_review_apply` | Seurat, bound project/journal | Validation / a new Seurat copy with ID-aligned review metadata |

These tools operate on copies/tables and do not silently modify project
checkpoints or grant review authority. An ontology or reference match is an
inspectable hypothesis. Supporting-citation positivity and the selected main
marker pool remain unchanged; see the [methods appendix](../SCIENTIFIC_METHODS_APPENDIX.md).

## Removed exports

The exact machine-readable surface is [inst/api-contract.json](../../dev/api-contract.json).
The following 36 functions and the AgentSeurat class export are removed:

- `qc_threshold`
- `qc_mad`
- `qc_doublet`
- `qc_remove_genes`
- `sc_normalize`
- `sc_find_hvg`
- `sc_scale`
- `sc_pca`
- `sc_select_pcs`
- `sc_select_pcs_visual`
- `sc_select_batch_var`
- `sc_harmony`
- `sc_cellcycle_score`
- `sc_cellcycle_regress`
- `sc_find_neighbors`
- `sc_cluster`
- `sc_cluster_sweep`
- `sc_resolution_recommend`
- `sc_umap`
- `annot_llm_annotate`
- `annot_apply`
- `annot_subcluster`
- `annot_review_evidence`
- `annot_clean_celltypes`
- `AgentSeurat`
- `save_checkpoint`
- `load_checkpoint`
- `upgrade_checkpoint`
- `get_seurat`
- `get_script`
- `get_figures`
- `get_decisions`
- `export_decisions`
- `export_script`
- `get_token_usage`
- `report_html`

These were direct mutable-object orchestration or object-specific
checkpoint/script/report facades. The current project already owns checkpoints,
reports and decision history. Provider factories and token utilities remain;
the reviewed engine reads the dependency's live token state directly, preserving
cached requests, conservative holds and explicit reconciliation.

No automatic MT/ribo/HB deletion, metadata-guessed batch selection,
image-to-parameter application, HCC-specific adaptive subclustering or
uncalibrated hybrid-score decision is transplanted. Existing measured cycle and
expression panels, explicit custom panels, reference contrasts, qualitative
rationales/uncertainty and Unknown remain available for human review. This is
not full parity with every arbitrary old normalization/regression/model option.

## Repository code, tests and dependencies

Old model-specific benchmark drivers are replaced by
[the counts-only reviewed workflow](../../benchmark/evaluation-v1/run_workflow.R).
Its input/reference are frozen, it writes a new directory, uses three explicit
software-control approvals, and retains Unknown labels with provider=NULL.
[The benchmark guide](../../benchmark/README.md) identifies the single command.
Old result/metric files are preserved for comparison. They are not overwritten
or presented as newly validated biology.

Strict JSON, IDs, source-layer identity, markers/references, approval/undo,
child scopes and provider accounting continue to be checked in the project
suite and new Seurat/table utility tests. Test retirement is not a declaration
that the old failures passed; pre-consolidation baseline reports are retained.

Unused legacy-only lifecycle, SeuratData/remotes, clustree, future.apply,
base64enc, magick and png declarations are removed. Seurat/SeuratObject,
agentomicsCore, sparse/data/plot dependencies, actual provider transport,
optional verified analysis adapters, reference/ontology and test/vignette
packages remain. No new third-party dependency was installed for this cleanup.

## Development project identity

The execution fingerprint follows the actual shared kernels, not the retired
PC-selection wrapper. The startup manifest and its builder cover the new shared
function layout consistently. This deliberately changes implementation identity.
Create fresh development test projects or use the exact original published
build for historical inspection. Do not edit saved hashes, approvals, input
matrices or checkpoints to force continuation. No automatic old-object migration
or long compatibility facade is provided.

## 中文摘要

开发代码只保留一个项目工作流，旧直接编排和 AgentSeurat 类已退场；有价值的绘图、marker/reference、
ontology 和精确 ID 对照工具直接使用 Seurat 或表格。上述 36 个函数不是继续保留的兼容 facade。
仓库示例、基准脚本及测试同步更新；测试项目可重建，不假设用户已有分析迁移负担。

共享 kernel 先抽取并核对 baseline，再清理入口。counts、精确 ID、审批与模型预算约束不放宽；
不移入自动删基因、猜 batch、自动图片选参数、HCC 专属调参或未经校准的 hybrid score 决策。
发布历史、baseline 和无关研究数据保留。此构建 hash 改变，不能修改旧项目 hashes 强行恢复。
