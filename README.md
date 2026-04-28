# scAgentKit

<<<<<<< HEAD
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

| Slot                         | Purpose                                                      |
| ---------------------------- | ------------------------------------------------------------ |
| `@data`                      | Seurat object or named list of Seurat objects                |
| `@data_type`                 | `"seurat"` or `"seurat_list"` — which branch we're in        |
| `@stage`                     | Current pipeline stage tag                                   |
| `@decisions`                 | List of `{step, function_name, timestamp, params, rationale, success}` |
| `@scripts`                   | Character vector of R snippets; `paste()` them to replay     |
| `@figures`                   | Data frame `(step, path, description)` of saved plots        |
| `@params`                    | Scratch space for cross-step artifacts (e.g. `markers_filtered`, `llm_annotations`) |
| `@created_at`, `@updated_at` | Timestamps                                                   |

## Function catalog

### QC layer — atomic

| Function          | Purpose                                            |
| ----------------- | -------------------------------------------------- |
| `qc_add_metrics`  | Add percent.mt / percent.ribo / percent.hb         |
| `qc_split`        | Split Seurat by metadata column (e.g. sample)      |
| `qc_threshold`    | Fixed floor filter                                 |
| `qc_mad`          | MAD-based dynamic filter (per-sample aware)        |
| `qc_doublet`      | Per-sample doublet detection via scDblFinder       |
| `qc_remove_genes` | Drop mt / ribo / hb gene families                  |
| `qc_merge`        | Merge seurat list back into a single Seurat object |
| `qc_plot`         | Save violin plots + register in `@figures`         |

### Pipeline layer — atomic

| Function             | Purpose                                                      |
| -------------------- | ------------------------------------------------------------ |
| `sc_normalize`       | LogNormalize (or CLR/RC)                                     |
| `sc_find_hvg`        | Variable feature selection                                   |
| `sc_scale`           | Centering + optional `vars.to.regress`                       |
| `sc_pca`             | PCA on variable features                                     |
| `sc_select_pcs`      | Auto-select `ndim` by cumulative variance; save elbow plot   |
| `sc_harmony`         | Batch integration (`group_by_vars` is required on purpose)   |
| `sc_umap`            | UMAP on Harmony (falls back to PCA)                          |
| `sc_find_neighbors`  | SNN graph                                                    |
| `sc_cluster_sweep`   | Multi-resolution sweep + clustree plot (exploration phase)   |
| `sc_cluster`         | Commit to a single resolution                                |
| `sc_find_markers`    | FindAllMarkers; stored at `@params$all_markers`              |
| `sc_markers_summary` | Filter (log2FC, padj), rank by `pct.1 - pct.2`, export text file |
| `sc_plot_umap`       | Save UMAPs + register in `@figures`                          |

### Annotation layer — atomic

| Function                 | Purpose                                                      |
| ------------------------ | ------------------------------------------------------------ |
| `annot_load_reference`   | Load a marker-to-celltype reference (CSV/TSV, tissue-filtered) |
| `annot_query_cellmarker` | Fetch CellMarker 2.0 directly (cached); returns same shape   |
| `annot_clear_cache`      | Clear the cached CellMarker download                         |
| `annot_match_reference`  | Overlap-score each cluster's markers against every reference cell type |
| `annot_llm_annotate`     | LLM reconciliation with strict JSON schema (see below)       |
| `annot_apply`            | Write `cell_type` column, drop `reject`-flagged clusters, apply manual overrides |

The LLM call is **provider-agnostic**: supply any `chat_fn(system_prompt,
user_prompt) -> character` that returns a JSON string. Concrete wrappers
for Anthropic, OpenAI, DeepSeek, and local Ollama are in
`inst/examples/llm_wrappers.R`.

### IO

| Function           | Purpose                                                      |
| ------------------ | ------------------------------------------------------------ |
| `save_checkpoint`  | Persist full AgentSeurat to `.qs`                            |
| `load_checkpoint`  | Reload from `.qs` (resume from any stage)                    |
| `export_script`    | Emit self-contained reproducible `.R` file                   |
| `export_decisions` | Emit decision log as JSON (audit trail)                      |
| `report_html`      | Emit a single self-contained HTML report (decisions + figures + script) |

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
  =======

> **An LLM-orchestratable toolkit for single-cell RNA-seq analysis.**
> Each pipeline decision is made by an LLM looking at evidence, gives a written rationale, and can be audited. No black boxes.

scAgentKit is an R package that re-shapes the standard scRNA-seq workflow (QC → normalization → integration → clustering → annotation → fine sub-typing) into a set of *atomic functions an LLM can drive*. Every decision point — which batch variable to use, how many PCs, what clustering resolution, which cell type a cluster is — becomes a transparent step where the LLM looks at the actual evidence (statistics, plots, markers), produces a written reasoning, and the choice is recorded. The pipeline ends with a reproducible R script and a JSON decision log alongside the data.

The goal is to convert *tacit knowledge* (the heuristics single-cell analysts learn from their lab's senior members but rarely write down) into *explicit, auditable knowledge*.

```r
chat_fn <- chat_grok()                                   # any provider you like

obj <- create_agent_seurat(counts, meta)
obj <- sc_qc(obj, chat_fn)                               # LLM picks QC thresholds
obj <- sc_select_batch_var(obj, chat_fn)                 # LLM picks batch variable
obj <- sc_select_pcs_visual(obj, chat_fn,                # LLM looks at UMAPs
                            variance_thresholds = c(0.80, 0.85, 0.90))
obj <- sc_resolution_recommend(obj, chat_fn,             # LLM looks at clustree
                               vision = TRUE)            # + UMAP panels
obj <- annot_llm_annotate(obj, chat_fn)                  # broad annotation
obj <- annot_subcluster(obj, chat_fn,                    # fine annotation per lineage
                        target = c("B", "T_NK"),
                        suggest_followups = TRUE,
                        data_context = "HCC metastasis study, ...")

# Every decision has reasoning attached:
obj@params$batch_recommendation$reasoning
# "Patient ID accounts for 73% of cell-distribution variance vs 12% for sample..."
```

---

## Why this exists

A single-cell analyst makes ~10 small decisions per dataset that determine the final story:

- Should I integrate by patient or sample?
- 30 PCs or 40?
- Resolution 0.5 or 0.7?
- Is cluster 7 a CD8 effector or just an activated CD4?
- Should I subcluster the T/NK pool to find Tregs?

Each is half-mechanical, half judgment. Most are made silently. They never appear in the methods section. They cannot be reproduced without the original analyst. Two analysts running the same data produce different stories — and there's no way to audit *why*.

scAgentKit makes each decision a function call. The LLM sees the same evidence the analyst would (numbers, plots, marker tables), writes its reasoning in plain English, and the choice plus reasoning is stored. After running, you have a `reproducible_script.R` and a `decisions.json` that explain the pipeline at the level of "we chose resolution 0.6 because ARI vs prev 0.991 indicates stability and 13 clusters fits the expected 6-12 broad immune+stromal types in HCC."

This is not "LLM does your analysis for you." It's a tool to make analysis steps *explainable*.

---

## Install

```r
# Requirements: R >= 4.2, Seurat >= 5.0
remotes::install_github("changhaokan/scAgentKit", upgrade = "never")

# Or from local source
# tar xzf scAgentKit.tar.gz
devtools::install_local("scAgentKit", force = TRUE, upgrade = "never")
```

Set at least one LLM API key (any one works):

```r
# in ~/.Renviron, then restart R
DEEPSEEK_API_KEY=sk-...                    # cheapest text path
# or
ANTHROPIC_API_KEY=sk-ant-...               # strongest reasoning + vision
# or
XAI_API_KEY=xai-...                        # cheap vision, 2M context
```

Verify:

```r
library(scAgentKit)
list_chat_providers()                       # see all built-in presets

chat_fn <- chat_deepseek()                  # or chat_grok(), chat_claude(), ...
chat_fn("Reply only JSON.", '{"ok": true}')
# [1] "{\"ok\": true}"
```

---

## Core concepts

### `AgentSeurat` (S4 class)

Wraps a `Seurat` object plus four extra slots:

| slot         | what's in it                                                 |
| ------------ | ------------------------------------------------------------ |
| `@data`      | the Seurat object (you can still call any Seurat verb on it) |
| `@params`    | every decision the agent made — the chosen value AND the reasoning |
| `@decisions` | full log: timestamp, function, parameters, rationale, script snippet |
| `@figures`   | registry of plots generated during the run, with descriptions for the report |
| `@stage`     | a "where am I in the pipeline" tracker                       |

```r
str(obj@params$batch_recommendation)
# List of 4
#  $ recommended : chr "patient"
#  $ reasoning   : chr "Patient ID accounts for 73% of cell-distribution..."
#  $ confidence  : chr "high"
#  $ alternatives: chr [1:2] "sample" "site"
```

### `chat_fn`: one signature, any provider

Every LLM call goes through a function with the same signature:

```r
chat_fn(system_prompt, user_prompt, image_path = NULL) -> character
```

So you swap providers by changing one line. Vision-capable providers automatically receive an image; text-only ones silently ignore it.

### Decision log

Every step that touches the agent records:

- *what function ran*
- *parameters chosen*
- *rationale in plain English*
- *executable R snippet to re-do this step*

After the run:

```r
write_reproducible_script(obj, "out.R")     # plain R script, runs without scAgentKit
write_decisions_json(obj, "decisions.json") # machine-readable audit log
generate_html_report(obj, "report.html")    # human-readable with embedded plots
```

---

## Multi-LLM provider system

This is the most differentiating feature. You're not locked to one model.

### Built-in presets

```r
list_chat_providers()
```

| Helper            | Default model       | Vision   | Best for                                                     |
| ----------------- | ------------------- | -------- | ------------------------------------------------------------ |
| `chat_deepseek()` | `deepseek-chat`     | no       | Cheapest text path. Annotation, batch selection.             |
| `chat_grok()`     | `grok-4-1-fast`     | yes      | Cheap vision, 2M context. UMAP / clustree comparisons.       |
| `chat_claude()`   | `claude-sonnet-4-5` | yes      | Strongest reasoning + vision. Critical decisions, contamination review. |
| `chat_qwen()`     | `qwen-plus`         | optional | Good Chinese-language; vision via `qwen-vl-max`.             |
| `chat_kimi()`     | `moonshot-v1-32k`   | optional | Long-context for very large marker tables.                   |
| `chat_openai()`   | `gpt-4o-mini`       | yes      | Industry-standard alternative.                               |

### Universal adapter for anything OpenAI-compatible

Most providers (DeepSeek, xAI, Qwen, Kimi, Doubao, Zhipu, OpenRouter, vLLM, local Ollama, …) implement OpenAI's `/v1/chat/completions` exactly. One factory handles them all:

```r
chat_local <- make_chat_fn_openai_compatible(
  base_url        = "http://localhost:11434/v1",     # Ollama
  model           = "qwen2.5:14b",
  api_key_env     = "",                              # no key needed locally
  supports_vision = FALSE
)

chat_or <- make_chat_fn_openai_compatible(
  base_url        = "https://openrouter.ai/api/v1",
  model           = "anthropic/claude-sonnet-4-5",
  api_key_env     = "OPENROUTER_API_KEY",
  supports_vision = TRUE,
  extra_headers   = c(`HTTP-Referer` = "https://yourapp.dev")
)
```

Anthropic is *not* OpenAI-compatible (different headers, system field lifted out, image blocks use `source.base64`). It has its own factory: `make_chat_fn_claude()`. Same `chat_fn` signature on the outside.

### Mix-and-match strategy

Use the cheapest model that gets the job done at each step:

```r
chat_text   <- chat_deepseek()                 # text-only steps
chat_vision <- chat_grok()                     # vision steps
chat_review <- chat_claude()                   # quality-critical reviews

obj <- sc_select_batch_var(obj,    chat_fn = chat_text)         # routine
obj <- sc_select_pcs_visual(obj,   chat_fn = chat_vision)       # needs eyes
obj <- sc_resolution_recommend(obj, chat_fn = chat_vision,
                                vision = TRUE)
obj <- annot_llm_annotate(obj,     chat_fn = chat_text)         # routine
obj <- annot_subcluster(obj,       chat_fn = chat_review,        # quality-critical
                                    target = "T_NK",
                                    tissue = "human HCC")
```

A full pipeline on a 70k-cell HCC dataset typically costs **<$1** in API fees with this hybrid pattern.

---

## Vision-driven decisions

Some pipeline choices look ambiguous as numbers but obvious as plots. scAgentKit lets the LLM look.

### `sc_select_pcs_visual()` — "which ndim gives the cleanest UMAP"

Variance-threshold-driven by default (matches how biologists actually think):

```r
obj <- sc_select_pcs_visual(
  obj,
  chat_fn             = chat_grok(),
  variance_thresholds = c(0.80, 0.85, 0.90),    # default
  tissue              = "human HCC"
)
```

The function renders one UMAP per ndim, composes them into a single panel image (using `magick` if available, falling back to base R + `png`), sends it to the LLM, and asks: *"which gives the cleanest cluster separation, no over-fragmentation, no bridging stringy connections?"*

```r
obj@params$pcs_visual_recommendation
# $ chosen          : int 15
# $ chosen_variance : num 0.809
# $ confidence      : chr "high"
# $ reasoning       : chr "ndim=15 shows the tightest major cell-type clusters with
#                          minimal bridging. ndim=20 introduces fragmentation
#                          (clusters 33-35); ndim=26 over-fragments into noisy
#                          micro-clusters (5,16,17,35)..."
```

You can also pass explicit `candidates = c(20, 30, 40, 50)` for manual mode.

### `sc_resolution_recommend(vision = TRUE)` — clustree + UMAP panels together

The agent automatically picks 3 representative resolutions (anchored on the resolution closest to your `expected_n_celltypes`, with neighbors), renders one UMAP per resolution, prepends the clustree dendrogram if available, and asks the LLM to cross-validate stability against actual layout.

The prompt forces the chosen resolution to be one the LLM saw on screen, with a built-in retry that re-prompts if the model returns an out-of-panel value or an empty `visual_notes`.

---

## Two-step annotation: the unique value

Single-resolution clustering is a fundamental compromise. T/NK cells need fine resolution (to resolve CD8/CD4/Treg/NK); hepatocytes over-fragment at the same resolution. There is no global resolution that makes every lineage right.

`annot_subcluster()` resolves this by giving each broad lineage its own complete sub-pipeline: subset → re-find HVGs → re-PCA → re-UMAP → re-cluster → markers → LLM annotation with **lineage-specific** prompts.

```r
obj <- annot_subcluster(
  obj,
  chat_fn               = chat_text,
  target                = c("B", "T_NK", "Myeloid"),    # or NULL = auto
  subcluster_resolution = "adaptive",                    # default
  tissue                = "human hepatocellular carcinoma"
)
```

### Adaptive resolution

By default, resolution scales by `log10(cell count)` — small subsets get ~0.25, large subsets ~0.45. This avoids over-fragmenting a 1500-cell B lineage while still surfacing real structure in a 20000-cell T lineage. You can override:

- `subcluster_resolution = 0.5` — fixed for all lineages
- `subcluster_resolution = "auto"` — let the LLM pick per lineage (calls `sc_resolution_recommend`, ~6× more LLM calls)
- `subcluster_resolution = c(T_NK = 0.6, B = 0.4)` — per-lineage overrides

### Lineage-aware prompts (cross-tissue, cross-species)

Each lineage gets a vocabulary suggestion (e.g. T/NK: CD8 effector, CD8 exhausted, Treg, NK cytotoxic, NKT, MAIT, gamma-delta T, …) that's tilted toward HCC/tumour context but isn't a hard whitelist — the LLM may use any reasonable sub-type the markers support.

The prompt is **tissue-aware** (built-in ambient gene lists for liver, blood, pancreas, lung, breast, stomach, intestine, kidney, brain, prostate, skin) and **species-aware** (auto-detects human vs mouse from gene symbol convention; both `CD8A` and `Cd8a` are accepted).

It includes a **proportion sanity check**: typical fractions for each sub-type within its lineage, with HCC-liver-specific overrides (γδT 5–25% in liver vs 1–5% elsewhere). The LLM is asked to cross-reference its candidate label against typical proportion ranges.

### Contamination as a first-class concept

A subcluster within "T/NK" sometimes turns out to be a few hundred mast cells, plasma cells, or hepatocytes that got mis-grouped at the broad annotation step. This is a **scientific finding, not a failure** — the broad annotation pipeline missed them.

The prompt teaches the LLM to use the format `{broad} (contaminant: <true type>)` when ALL of:

- ≥3 canonical lineage-defining genes for the OTHER lineage
- High `avg_log2FC` (>1.5)
- None on the tissue-specific ambient list
- None on the stress / immediate-early list (HSP family, FOS/JUN, NR4A1, …)
- The other lineage is a genuinely different broad type (not a sub-state)

Plasma cells in B, NK in T/NK, Kupffer cells in myeloid — these are *lineage-internal* end-states, never contaminants.

### Optional follow-up suggestions

```r
obj <- annot_subcluster(
  obj, chat_fn = chat_review,
  target = "T_NK",
  tissue = "human hepatocellular carcinoma",
  suggest_followups = TRUE,
  data_context = paste(
    "HCC metastasis study, pre-metastatic licensing window framework.",
    "Key axis: E2F8 -> KIF18A -> CIN tolerance -> cGAS-STING -> NF-kB -> BCL-XL."
  )
)
```

For each sub-cluster, the LLM produces a 1–2 sentence concrete next-step suggestion anchored to your research framework. Generic suggestions ("validate with flow cytometry") are explicitly excluded by the prompt.

---

## Real-data case study: GSE149614 (human HCC)

A pan-HCC scRNA-seq atlas — 71915 cells, 21 samples, 10 patients, 4 sites (tumour, NTL, lymph node, peripheral blood), 6 broad cell types in the original publication.

### Broad annotation (single-pass)

```r
obj  # AgentSeurat, 48858 cells post-QC, 18 sub-clusters at res=0.6
obj <- annot_llm_annotate(obj, chat_fn = chat_deepseek(), tissue = "human HCC")
annot_compare_with_reference(obj, reference_col = "celltype")
```

Per-class concordance vs the published annotation:

| broad type  | sensitivity | precision |
| ----------- | ----------- | --------- |
| Endothelial | 99.7%       | 94.4%     |
| Fibroblast  | 97.0%       | 99.1%     |
| Hepatocyte  | 98.8%       | 90.1%     |
| Myeloid     | 97.9%       | 98.5%     |
| T/NK        | 93.5%       | 94.8%     |
| **B**       | **58.9%**   | **93.1%** |

B cells are correctly *typed* when called (high precision) but heavily *missed* (low sensitivity). The cause: at resolution 0.6, plasma cells and naive B mix in the same cluster, and the dominant naive B markers drive the LLM's call.

### Two-step annotation fixes the B problem

```r
obj <- annot_subcluster(obj, chat_fn = chat_deepseek(),
                        target = "B", tissue = "human HCC")
table(obj@data@meta.data$cell_type_fine)
```

Result on the 1546-cell B subset:

| sub-type                    | cells                | confidence                |
| --------------------------- | -------------------- | ------------------------- |
| naive B                     | 573                  | high                      |
| plasma cell                 | 192 (3 sub-clusters) | high                      |
| B (unspecified)             | 226                  | low                       |
| B (contaminant: hepatocyte) | 226                  | high — real contamination |
| B (contaminant: pDC)        | 94                   | high                      |
| B (contaminant: T cell)     | 35                   | high                      |

Plasma cells are now identified as their own population — the 41% sensitivity gap is closed.

### Subcluster as audit: T/NK reveals 13.7% broad-level errors

```r
obj <- annot_subcluster(obj, chat_fn = chat_deepseek(),
                        target = "T_NK", tissue = "human HCC")
```

Of 21962 cells called T/NK at the broad stage:

| true identity (markers)    | cells    | %         | canonical evidence                             |
| -------------------------- | -------- | --------- | ---------------------------------------------- |
| Hepatocyte / cholangiocyte | 1320     | 6.0%      | HPD, CYP2C9, CYP2E1, SERPINC1, ADH1A/B, CYP7A1 |
| Tumour / oncofetal HCC     | 833      | 3.8%      | DLK1, PRAME, CLDN6, HOXC9/10, GAGE12H, SSX5    |
| Plasma cell                | 850      | 3.9%      | JCHAIN, MZB1, TNFRSF17, DERL3, IGHG1/2/3/4     |
| **Total mis-classified**   | **3003** | **13.7%** |                                                |

Each contamination is supported by ≥4 canonical, non-ambient, non-stress markers. The broad-level annotation step never flagged these — they only became visible after lineage-specific re-clustering surfaced them as their own sub-cluster with strong cross-lineage signature.

This is **the unique scientific value** of the two-step approach: it doesn't just refine annotations within a lineage, it audits the broad annotation itself.

---

## Where scAgentKit fits

### vs Azimuth / SingleR / scType

These tools use curated reference atlases. On well-characterized tissues (PBMC, lung, heart) they are *more accurate* and *much faster* than scAgentKit. **Use them when a strong reference exists for your tissue.**

scAgentKit's advantages:

- Works on any tissue, no reference required — including pan-cancer, mouse, novel disease contexts where curated references don't exist or are stale.
- Every call has a written rationale (Azimuth's score doesn't tell you *why*).
- Identifies cell states not in standard references (HCC γδT enrichment, SPP1+ TAM, dataset-specific stress states).

### vs CellTypist

CellTypist runs a logistic-regression model trained on a curated atlas. Stable and fast. But it can't tell you *why* a cluster is CD8 effector and not memory — it just outputs probabilities. scAgentKit's marker-grounded reasoning is what you need when writing a methods section.

### vs other LLM annotation tools

Single-step LLM annotation tools (focused only on labelling clusters from marker tables) lock you to one model. scAgentKit's differences:

- **Whole pipeline, not one step** — QC → norm → integration → cluster → annotate → subcluster, each LLM-driven where it makes sense.
- **Provider-agnostic** — drop in any model, mix-and-match per step.
- **Two-step subclustering with audit** — the broad-error finding above is unique.

### vs hand-running Seurat

Hand-running can match scAgentKit's accuracy or beat it (if you tune everything). What hand-running cannot give you: a reproducible script + decision log + plain-English rationale for every step, automatically. **scAgentKit's value is documentation, not speed or accuracy.**

---

## Honest limitations

The package is a working prototype, not a production tool. You should know:

1. **The LLM is not ground truth.** It rationalizes (we observed it justifying 27% γδT in HCC by inventing an "HCC enrichment" argument — which happens to be partially correct, but not for the reasons it gave). It over-corrects when prompts are too strict. It under-corrects when prompts are too lax. Validate marker-by-marker for any finding you'll publish.

2. **Small-lineage subclustering is unstable.** A B subset of 1500 cells split into 11 sub-clusters of 100–300 cells each has weak markers; the LLM's confidence (and any tool's confidence) is genuinely low here. This is a sample-size limit, not a tool limit.

3. **Prompts are tissue/disease-specific.** Built-in vocabulary covers liver/HCC well, plus generic immune and major tumour types. Cardiac, renal, neural tissue may need custom `data_context` or vocabulary overrides.

4. **API costs are not zero.** A full pipeline on a 70k-cell dataset costs ~$0.3–$3 depending on provider mix. Running 100 datasets is $30–$300, not free.

5. **Validation is on you.** scAgentKit is a *collaborator*, not a *replacement*. Every annotation needs marker-level review by someone who knows the biology. Trust the reasoning the way you'd trust a trainee's first pass — useful starting point, not final answer.

6. **Vision over slow networks.** Sending base64-encoded PNGs to xAI / Anthropic from China requires a proxy. Set `Sys.setenv(http_proxy=...)` before vision calls.

7. **Seurat v5 only.** v4 compatibility is not tested.

---

## Pipeline reference

| function                                  | role                                                   | LLM?                 |
| ----------------------------------------- | ------------------------------------------------------ | -------------------- |
| `create_agent_seurat()`                   | wrap Seurat in AgentSeurat                             | no                   |
| `sc_qc()`                                 | per-sample QC threshold pick                           | yes (text)           |
| `sc_normalize()`                          | normalization                                          | no                   |
| `sc_hvg()`                                | highly variable genes                                  | no                   |
| `sc_select_batch_var()`                   | which metadata column to integrate over                | yes (text)           |
| `sc_scale()`                              | scaling on HVG                                         | no                   |
| `sc_pca()`                                | PCA                                                    | no                   |
| `sc_select_pcs()`                         | variance-threshold ndim                                | no                   |
| `sc_select_pcs_visual()`                  | UMAP-comparison ndim                                   | yes (vision)         |
| `sc_harmony()`                            | Harmony integration                                    | no                   |
| `sc_umap()`                               | UMAP                                                   | no                   |
| `sc_cluster_sweep()`                      | sweep clustering across resolutions                    | no                   |
| `sc_resolution_recommend()`               | pick resolution                                        | yes (text or vision) |
| `sc_cluster()`                            | commit one resolution                                  | no                   |
| `sc_markers()`                            | FindAllMarkers                                         | no                   |
| `sc_markers_summary()`                    | per-cluster marker summary + cycling-cluster detection | no                   |
| `annot_llm_annotate()`                    | broad cell-type annotation per cluster                 | yes (text)           |
| `annot_apply()`                           | write annotations to meta.data                         | no                   |
| `annot_collapse_to_broad()`               | map fine labels to broad types                         | no                   |
| `annot_compare_with_reference()`          | confusion matrix + per-class metrics                   | no                   |
| `annot_subcluster()`                      | per-lineage refinement + contamination audit           | yes (text)           |
| `save_checkpoint()` / `load_checkpoint()` | qs-based checkpoints                                   | no                   |
| `write_reproducible_script()`             | flat R script                                          | no                   |
| `write_decisions_json()`                  | machine-readable audit log                             | no                   |
| `generate_html_report()`                  | HTML with embedded figures                             | no                   |

---

## Roadmap

### v0.1 (current) — single-user agent toolkit ✓

Working multi-provider system, vision decisions, two-step annotation, validated on real HCC data.

### v0.2 — orchestration

A high-level `agent_run(obj, goal = "annotate broad cell types")` that decides which atomic functions to call, in what order, and when to ask the user. Tools become *callable by the LLM* via tool-use APIs rather than user-orchestrated.

### v0.3 — global annotation review

Two-pass annotation: first label clusters independently, then show the LLM the global label set and ask "are any of these inconsistent? proportions off? labels overlapping?" Single-pass annotation makes errors that global review can catch.

### Longer-term

- Persistent memory across runs (the agent remembers your dataset's quirks).
- Multi-dataset comparative annotation (cross-tissue label consistency).
- Annotation uncertainty quantification (which cells are most ambiguous).

---

## Citing

If scAgentKit contributes to your work, please cite (paper in preparation). For now:

```
Ch K. scAgentKit: An LLM-orchestratable single-cell RNA-seq toolkit.
GitHub, 2026. https://github.com/ChanghaoKan/scAgentKit
```

---

## Contributing

Issues and PRs welcome. The package is small enough that one careful read of `R/` should orient you. Two design rules:

1. Every LLM-touching function returns a recorded `@params$<name>$reasoning` field.
2. Every step appends to `@decisions` with a rationale and an executable script snippet.

Break either and the whole reproducibility-by-design contract falls apart.

---

## Acknowledgments

Designed and built by Kan Changhao at Shenzhen Bay Laboratory (Deng Lab), 2025–2026, as part of a broader project on agentic tools for cancer multi-omics analysis. Benchmark data (GSE149614, Lu et al. *Nature Communications* 2022) gratefully acknowledged.

The package was implemented through extensive iteration with Claude (Anthropic) — every architectural decision in this README was validated against real HCC data before being committed.

## License

MIT.

>>>>>>> 300c7f35833dad2314e08c646be71fa767e9ec97
