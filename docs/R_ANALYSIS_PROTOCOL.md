# R analysis protocol

This is the **0.8.0** protocol linked from the
[README](../README.md#one-project-workflow). Its ordinary raw-count scan has three
scientific approvals. The published v0.6.0 default has two; use the matching
[release protocol](dev/RELEASE_060_PROTOCOL.md) with that archive. Do not mix versions
when reopening projects.

Choose manual or model-assisted initialization before creating the project.
This example uses the manual default (`provider=NULL`, zero budget); you supply
annotation labels and confidence. For a model project, initialize the immutable
provider/model/settings/budget with `sc_analyze()` or `sc_run()` first, following
[model configuration](dev/UNIFIED_MODEL_REVIEW.md#what-remains-in-the-starting-r-call).
Enabling a browser component later cannot add a provider to a manual project.

## First analysis

The example uses the public 10x Genomics PBMC3k counts introduced in the
[Seurat tutorial](https://satijalab.org/seurat/articles/pbmc3k_tutorial).
Work through each review step in sequence, recording your reviewer identity
and the rationale for each decision.

### 1. Load the data

```r
data_dir <- file.path(getwd(), "pbmc3k-data")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
archive <- file.path(data_dir, "pbmc3k_filtered_gene_bc_matrices.tar.gz")
download.file(
  "https://cf.10xgenomics.com/samples/cell/pbmc3k/pbmc3k_filtered_gene_bc_matrices.tar.gz",
  archive, mode = "wb")
untar(archive, exdir = data_dir)
mex_dir <- file.path(data_dir, "filtered_gene_bc_matrices", "hg19")
project_dir <- file.path(getwd(), "pbmc3k-analysis")
```

For your own study, replace the input and describe its species, tissue,
research question and available experimental design. Use a new project
directory for a new analysis.

### 2. Review the analysis strategy

`sc_analyze()` prepares a strategy and its projected QC impact. Here, the
feature-count and mitochondrial thresholds follow the PBMC tutorial's starting
choices; select settings appropriate to the observed distributions and study.

```r
project <- sc_analyze(mex_dir, project_dir,
  sample_id="PBMC3k", matrix_kind="filtered",
  context = list(
    species = "human", tissue = "Peripheral blood",
    research_goal = "Characterize the major immune populations in this PBMC library.",
    notes = "Single public library; donor and capture metadata are unavailable."),
  plan = list(
    rationale = "PBMC starting strategy for review against measured QC distributions.",
    qc = list(nFeature = c(200, 2500), percent_mt = c(NA, 5)),
    pcs = 10, resolution = 0.5))
strategy <- sc_review(project)
```

Review cell retention, normalization, PC selection, batch handling and
clustering in the displayed plan. To change a choice, save a revision with
`sc_review(strategy, "revise", plan = list(...), reviewer = ..., reason = ...)`
and inspect the returned plan. For example, `plan = list(pcs = 12)` changes PC
selection while preserving the other displayed settings.

Approve the initial strategy to run the foundation and ordinary resolution scan:

```r
measured <- sc_review(strategy, "approve", reviewer = "researcher",
  reason = "Reviewed QC retention and the analysis strategy for this PBMC library.",
  continue = TRUE)
```

### 3. Review measured clustering before annotation

The returned object is a second strategy review, not yet the annotation worksheet.
Inspect computed PC evidence, scanned resolutions, tree, marker contrasts and
sample composition in the full saved review:

```r
measured <- sc_review(measured)
measured$view$strategy_review$details$cluster_diagnostics
# If changing resolution, choose an actually scanned value, then inspect the revision:
# measured <- sc_review(measured, "revise", plan=list(resolution=0.4),
#   reviewer="researcher", reason="Explain the measured comparison supporting this choice.")
annotation <- sc_review(measured, "approve", reviewer="researcher",
  reason="Reviewed actual PC evidence and resolution scan; retain the displayed resolution.",
  continue=TRUE)
```

The second approval binds the measured selection. A tree edge is shared-cell
overlap, not lineage or proof of an optimal resolution. Keep a fresh returned
snapshot for every subsequent action.

### 4. Review and submit cluster annotations

The returned review contains the cluster markers and an annotation worksheet.
Inspect expression and the embedding alongside the supplied marker evidence:

```r
analysis <- sc_result(annotation, stage = "analysis")
Seurat::DimPlot(analysis, reduction = "umap", label = TRUE)
Seurat::FeaturePlot(analysis, features = c("CD3D", "MS4A1", "LYZ", "NKG7"))
annotations <- utils::edit(annotation$annotations)
```

In the R data editor, retain each `clusterId` and complete the remaining fields
for every cluster:

| Field | Content |
| --- | --- |
| `label` | The reviewed cell type or population description |
| `confidence` | `low`, `medium` or `high`, as a qualitative assessment |
| `rationale` | Evidence supporting the assignment and any unresolved alternatives |
| `markers` | Semicolon-separated gene names from that cluster's supplied marker evidence |

For example, concordant CD79A and MS4A1 evidence can support a B-cell assignment;
its worksheet entry would cite `CD79A;MS4A1` and explain that interpretation.
Use `Unknown` with a rationale for unresolved populations. Cluster IDs and
annotations depend on the data and analysis settings. For file-based editing,
see the [detailed walkthrough](dev/COMPLETE_ANALYSIS_WALKTHROUGH.md#3-read-markers-and-submit-annotations).
The [annotation guide](dev/ANNOTATION_REVIEW.md) describes evidence and review decisions.

Save the completed worksheet, inspect the full annotation proposal returned by
`sc_review()`, and approve it to apply the labels:

```r
proposal <- sc_review(annotation, "revise", annotations = annotations,
  reviewer = "researcher",
  reason = "Prepared cluster annotations from the supplied markers and expression plots.")
completed <- sc_review(proposal, "approve", reviewer = "researcher",
  reason = "Reviewed the complete annotation proposal and supporting evidence.",
  continue = TRUE)
```

### 5. Retrieve results and reopen the project

```r
result <- sc_result(completed)
Seurat::DimPlot(result, reduction = "umap", group.by = "sc_annotation", label = TRUE)
table(result$sc_annotation)
completed$view$output
```

`result` is the final Seurat object with the reviewed annotations. The project
also retains marker tables, figures and the analysis record. `sc_result(...,
stage = "analysis")` retrieves the earlier analysis object when annotation is
still in progress.

In a later R session, load the same package environment and reopen the project:

```r
library(scAgentKit)
project <- sc_open("pbmc3k-analysis")
review <- sc_review(project)
result <- sc_result(project)
```

For an unfinished project, `sc_review()` displays the current stage so you can
continue its review and execution. Opening a project does not resume work.
See [recovery and saved results](RESEARCHER_PROTOCOL_ZH.md#11-输出恢复与可复现记录)
for interrupted runs and environment changes.
