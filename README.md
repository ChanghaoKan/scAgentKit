# scAgentKit

Agent-friendly, atomic toolkit for single-cell RNA-seq pipelines in R.

Every analysis step is an atomic function that takes and returns the same
S4 container (`AgentSeurat`), accumulating (a) the Seurat data, (b) a
structured decision log, (c) a line-by-line reproducible R script, and
(d) a registry of saved figure paths. This design makes the package
equally suitable as a manual toolkit *and* as the tool layer underneath
an LLM orchestrator.

## Design principles

1. **One container, one contract.** Every tool function is
   `f(AgentSeurat, ...) -> AgentSeurat`. There are no hidden globals, no
   external scratch files. Chains and branches compose naturally.
2. **Atomic, not pipeline.** Each function does one thing. An agent (or
   a human) decides which to call, in which order, with which params.
   Re-running a single step costs one call; nothing further downstream
   is silently rebuilt.
3. **Reproducibility is a side-effect.** Every call appends a raw R
   snippet to `@scripts`. After the run, `export_script()` concatenates
   them into a self-contained `.R` file that reproduces the analysis
   from scratch — no Agent or LLM required to replay it.
4. **Agent-friendly state.** Params, cell counts, and rationales are
   stored in a structured `@decisions` list. Figures are written to disk
   and registered as paths, so a vision-capable LLM can inspect a
   violin plot or UMAP before deciding the next step.
5. **Defensive defaults with opinionated exceptions.** Most functions
   ship sensible defaults; a small set of high-stakes choices (batch
   variable for Harmony, clustering resolution, final annotations) are
   *deliberately required* so they can never be applied silently.

## The container

```
<AgentSeurat>
  Stage:      markers_summarized
  Data type:  seurat
  Cells:      42317
  Genes:      18952
  Decisions:  14 steps recorded
  Figures:    6
  Updated:    2026-04-24 14:23:11
```

Slots:

| Slot           | Purpose                                                       |
|----------------|---------------------------------------------------------------|
| `@data`        | Seurat object or named list of Seurat objects                 |
| `@data_type`   | `"seurat"` or `"seurat_list"` — which branch we're in         |
| `@stage`       | Current pipeline stage tag                                    |
| `@decisions`   | List of `{step, function_name, timestamp, params, rationale, success}` |
| `@scripts`     | Character vector of R snippets; `paste()` them to replay      |
| `@figures`     | Data frame `(step, path, description)` of saved plots         |
| `@params`      | Scratch space for cross-step artifacts (e.g. `markers_filtered`, `llm_annotations`) |
| `@created_at`, `@updated_at` | Timestamps                                      |

## Function catalog

### QC layer — atomic

| Function           | Purpose                                             |
|--------------------|-----------------------------------------------------|
| `qc_add_metrics`   | Add percent.mt / percent.ribo / percent.hb          |
| `qc_split`         | Split Seurat by metadata column (e.g. sample)       |
| `qc_threshold`     | Fixed floor filter                                  |
| `qc_mad`           | MAD-based dynamic filter (per-sample aware)         |
| `qc_doublet`       | Per-sample doublet detection via scDblFinder        |
| `qc_remove_genes`  | Drop mt / ribo / hb gene families                   |
| `qc_merge`         | Merge seurat list back into a single Seurat object  |
| `qc_plot`          | Save violin plots + register in `@figures`          |

### Pipeline layer — atomic

| Function              | Purpose                                                          |
|-----------------------|------------------------------------------------------------------|
| `sc_normalize`        | LogNormalize (or CLR/RC)                                         |
| `sc_find_hvg`         | Variable feature selection                                       |
| `sc_scale`            | Centering + optional `vars.to.regress`                           |
| `sc_pca`              | PCA on variable features                                         |
| `sc_select_pcs`       | Auto-select `ndim` by cumulative variance; save elbow plot       |
| `sc_harmony`          | Batch integration (`group_by_vars` is required on purpose)       |
| `sc_umap`             | UMAP on Harmony (falls back to PCA)                              |
| `sc_find_neighbors`   | SNN graph                                                        |
| `sc_cluster_sweep`    | Multi-resolution sweep + clustree plot (exploration phase)       |
| `sc_cluster`          | Commit to a single resolution                                    |
| `sc_find_markers`     | FindAllMarkers; stored at `@params$all_markers`                  |
| `sc_markers_summary`  | Filter (log2FC, padj), rank by `pct.1 - pct.2`, export text file |
| `sc_plot_umap`        | Save UMAPs + register in `@figures`                              |

### Annotation layer — atomic

| Function                 | Purpose                                                                |
|--------------------------|------------------------------------------------------------------------|
| `annot_load_reference`   | Load a marker-to-celltype reference (CSV/TSV, tissue-filtered)         |
| `annot_query_cellmarker` | Fetch CellMarker 2.0 directly (cached); returns same shape             |
| `annot_clear_cache`      | Clear the cached CellMarker download                                   |
| `annot_match_reference`  | Overlap-score each cluster's markers against every reference cell type |
| `annot_llm_annotate`     | LLM reconciliation with strict JSON schema (see below)                 |
| `annot_apply`            | Write `cell_type` column, drop `reject`-flagged clusters, apply manual overrides |

The LLM call is **provider-agnostic**: supply any `chat_fn(system_prompt,
user_prompt) -> character` that returns a JSON string. Concrete wrappers
for Anthropic, OpenAI, DeepSeek, and local Ollama are in
`inst/examples/llm_wrappers.R`.

### IO

| Function            | Purpose                                                |
|---------------------|--------------------------------------------------------|
| `save_checkpoint`   | Persist full AgentSeurat to `.qs`                      |
| `load_checkpoint`   | Reload from `.qs` (resume from any stage)              |
| `export_script`     | Emit self-contained reproducible `.R` file             |
| `export_decisions`  | Emit decision log as JSON (audit trail)                |
| `report_html`       | Emit a single self-contained HTML report (decisions + figures + script) |

### Getters

`get_seurat()` / `get_decisions()` / `get_script()` / `get_figures()`.

## The anti-hallucination annotation design

The LLM annotation step is where most agents silently fail. We use
four structural defenses:

1. **Strict JSON schema.** Every cluster response must include
   `primary_annotation`, `confidence`, `supporting_markers`,
   `contradicting_markers`, `alternative_annotations`,
   `proportion_assessment`, `recommended_action`, `reasoning`. No free
   prose, no markdown fences.

2. **Required `contradicting_markers` field.** This is the key
   mechanism. Forcing the model to also list evidence *against* its own
   choice dramatically lowers confabulation. If there truly are no
   contradictions, it returns an empty list — but it can't silently
   gloss over inconsistent markers.

3. **Proportion sanity check.** The model receives the cluster's
   percentage of the dataset and is asked whether that fraction is
   plausible for the assigned cell type in the given tissue. Reviewers
   appreciate this.

4. **`recommended_action` with `reject` / `flag_for_review`.** The
   model can say "this looks like a doublet / contaminant / stressed
   cells; do not keep." `annot_apply(drop_rejected = TRUE)` honors
   that — the same workflow as the manual cluster-15 / cluster-17
   removal in the original Ca_Ctrl analysis.

## Quick example

```r
library(scAgentKit)

obj <- AgentSeurat(readRDS("my.rds"))

# QC
obj <- qc_add_metrics(obj, species = "mouse")
obj <- qc_split(obj, split_by = "sample")
obj <- qc_threshold(obj, min_nCount = 1000, min_nFeature = 500, max_percent_mt = 50)
obj <- qc_mad(obj, nmad = 3)
obj <- qc_doublet(obj, remove = TRUE)
obj <- qc_remove_genes(obj, species = "mouse")
obj <- qc_merge(obj)

# Pipeline
obj <- sc_normalize(obj)
obj <- sc_find_hvg(obj)
obj <- sc_scale(obj)
obj <- sc_pca(obj)
obj <- sc_select_pcs(obj, threshold = 0.80)
obj <- sc_harmony(obj, group_by_vars = "sample")   # required arg
obj <- sc_umap(obj)
obj <- sc_find_neighbors(obj)
obj <- sc_cluster_sweep(obj, resolutions = seq(0.05, 0.5, 0.05))
obj <- sc_cluster(obj, resolution = 0.3)           # inspect clustree first
obj <- sc_find_markers(obj)
obj <- sc_markers_summary(obj, top_n = 30)

# Annotation
ref <- annot_load_reference("references/cellmarker_mouse.tsv",
                            tissue_filter = "colon")
obj <- annot_match_reference(obj, ref)

source(system.file("examples", "llm_wrappers.R", package = "scAgentKit"))
chat_fn <- make_chat_fn_anthropic()

obj <- annot_llm_annotate(obj, chat_fn = chat_fn,
                          tissue = "mouse colon (Ca vs Ctrl)")
obj <- annot_apply(obj, source = "llm", drop_rejected = TRUE)

# Export artifacts
export_script(obj, "reproducible_script.R")
export_decisions(obj, "decisions.json")
```

Full walk-throughs are in `inst/examples/`:

- `qc_pipeline_example.R` — QC only
- `full_pipeline_example.R` — load -> annotation
- `annotation_example.R` — resume from a marker checkpoint and iterate on
  LLM annotation without re-running upstream steps
- `llm_wrappers.R` — concrete `chat_fn` implementations (Anthropic /
  OpenAI / DeepSeek / local Ollama / mock)

A reference template in the expected format is at
`inst/extdata/reference_template.tsv`.

## Installation

```r
# From a local clone
devtools::install_local("path/to/scAgentKit")

# Required
install.packages(c("Seurat", "dplyr", "tibble", "ggplot2", "Matrix", "qs"))

# Optional (per feature)
install.packages(c("harmony", "clustree", "jsonlite", "ellmer", "httr2"))
BiocManager::install(c("scDblFinder", "SingleCellExperiment"))
```

## Status and scope

This is a single-user, local-deployment toolkit. Scaling up to multi-user
SaaS needs different decisions around state persistence, authentication,
and queuing — none of which belong in this package.

**Seurat v5 compatibility.** All QC and pipeline functions auto-handle
`Assay5` with split layers. In practice this means: after `merge()` or
reimport, the package joins layers transparently before running
`VlnPlot`, `subset(features=)`, `as.SingleCellExperiment`,
`NormalizeData`, etc. You do not need to call `JoinLayers` manually.

Pending:

- `sc_regress_cellcycle` helper (done; see `sc_cellcycle_score` /
  `sc_cellcycle_regress`)
- `annot_query_cellmarker` (done) / `annot_query_act` (pending)
- `report_html` (done)
- Test suite under `tests/testthat/`

## Why S4?

- Strict slot contracts — fewer silent bugs when the agent composes calls
- Clean `show` / `summary` surface for future method dispatch
- Interops naturally with Bioconductor classes (SCE, etc.)
- Forces the container to be a *type*, not a convention — important when
  an LLM composes function calls from a tool schema.
