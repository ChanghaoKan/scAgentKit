# scAgentKit
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R: >= 4.2](https://img.shields.io/badge/R-%3E%3D%204.2-blue)](https://www.r-project.org/)
[![Seurat: >= 5.0](https://img.shields.io/badge/Seurat-%3E%3D%205.0-orange)](https://satijalab.org/seurat/)

An LLM-orchestratable toolkit for single-cell RNA-seq analysis. Each pipeline decision is made by an LLM looking at evidence, gives a written rationale, and can be audited. No black boxes.

scAgentKit is an R package that re-shapes the standard scRNA-seq workflow (QC → normalization → integration → clustering → annotation → fine sub-typing) into a set of atomic functions an LLM can drive. Every decision point — which batch variable to use, how many PCs, what clustering resolution, which cell type a cluster is — becomes a transparent step where the LLM looks at the actual evidence (statistics, plots, markers), produces a written reasoning, and the choice is recorded. The pipeline ends with a reproducible R script and a JSON decision log alongside the data.

The goal is to convert tacit knowledge (the heuristics single-cell analysts learn from their lab's senior members but rarely write down) into explicit, auditable knowledge.

```r
library(scAgentKit)
chat_text   <- chat_deepseek()
chat_vision <- chat_grok()

obj <- AgentSeurat(seurat_obj)

# QC
obj <- qc_add_metrics(obj, species = "mouse")
obj <- qc_split(obj, split_by = "sample")
obj <- qc_mad(obj, nmad = 3)
obj <- qc_doublet(obj, remove = TRUE)
obj <- qc_remove_genes(obj, species = "mouse")
obj <- qc_merge(obj)

# Processing
obj <- sc_normalize(obj)
obj <- sc_find_hvg(obj, nfeatures = 2000)
obj <- sc_scale(obj)
obj <- sc_pca(obj, npcs = 50)

# PC selection + integration
obj <- sc_select_pcs_visual(obj, chat_fn = chat_vision, variance_thresholds = c(0.80, 0.85, 0.90))
obj <- sc_select_batch_var(obj, chat_fn = chat_text)
obj <- sc_harmony(obj, group_by_vars = obj@params$batch_recommendation$recommended)
obj <- sc_umap(obj)

# Clustering
obj <- sc_cluster_sweep(obj, resolutions = c(0.2, 0.4, 0.6, 0.8, 1.0))
obj <- sc_resolution_recommend(obj, chat_fn = chat_vision, vision = TRUE, tissue = "mouse colorectal cancer")
obj <- sc_cluster(obj, resolution = obj@params$resolution_recommendation$chosen)

# Annotation (three-step)
obj <- annot_llm_annotate(obj, chat_fn = chat_text, tissue = "mouse colorectal cancer")
obj <- annot_apply(obj)

obj <- annot_clean_celltypes(obj, merge_plural = TRUE, min_cells = 50, vision = TRUE, chat_fn = chat_vision)
obj <- annot_subcluster(obj, chat_fn = chat_text, target = c("T_NK", "B", "Macrophage"), tissue = "mouse colorectal cancer")

export_script(obj, "reproducible_script.R")
export_decisions(obj, "decisions.json")
report_html(obj, "report.html")
```

---

## Why this exists

A single-cell analyst makes ~10–15 small decisions per dataset that determine the final biological story. Most are made silently and never appear in the methods section. Two analysts running the same data can produce different stories with no way to audit why.

scAgentKit makes each decision a function call. The LLM sees the same evidence the analyst would (numbers, plots, marker tables), writes its reasoning in plain English, and the choice plus reasoning is stored. After running, you have a reproducible script and a decision log that explain the pipeline at the level of “we chose resolution 0.6 because ARI vs previous was 0.991 and 13 clusters fits the expected 8–16 major types.”

This is **not** “LLM does your analysis for you.” It is a tool to make analysis steps explainable and reproducible.

---

## Installation

```r
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
```

Set at least one LLM API key in `~/.Renviron`:

```bash
DEEPSEEK_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
XAI_API_KEY=xai-...
```

---

## Core Concepts

### AgentSeurat (S4 class)
Wraps a Seurat object together with decision tracking:

- `@data` — the Seurat object (or list during per-sample QC)
- `@params` — chosen values + reasoning for every decision
- `@decisions` — full ledger of every step
- `@scripts` — executable R snippets that reproduce the analysis

### chat_fn
All LLM calls go through one signature:

```r
chat_fn(system_prompt, user_prompt, image_path = NULL)
```

You can swap providers instantly (DeepSeek, Grok, Claude, Qwen, Kimi, OpenAI, local Ollama, etc.).

---

## Key Functions

### QC
- `qc_add_metrics()`, `qc_split()`, `qc_mad()`, `qc_doublet()`, `qc_remove_genes()`, `qc_merge()`

### Processing & Dimensionality Reduction
- `sc_normalize()`, `sc_find_hvg()`, `sc_scale()`, `sc_pca()`
- `sc_select_pcs_visual()` (vision)
- `sc_select_batch_var()` (text)
- `sc_harmony()`, `sc_umap()`

### Clustering
- `sc_cluster_sweep()`, `sc_resolution_recommend()` (text or vision)
- `sc_cluster()`, `sc_find_markers()`, `sc_markers_summary()`

### Annotation
- `annot_llm_annotate()` — broad annotation
- `annot_apply()` — write to metadata
- `annot_clean_celltypes()` — merge names + flag/remove low-quality clusters (with optional vision)
- `annot_subcluster()` — per-lineage fine annotation + contamination audit

### Output
- `export_script()`, `export_decisions()`, `report_html()`
- `save_checkpoint()` / `load_checkpoint()`

---

## Honest Limitations

- The LLM is a collaborator, not ground truth. Always validate important findings marker-by-marker.
- Small lineages (< 300–500 cells) produce unstable subclustering.
- Vision steps require a vision-capable model and can be slow over poor networks.
- API costs are real (typically $0.3–3 per 70k-cell dataset with smart provider mixing).

---

## Citation

```
Kanchanghao. scAgentKit: An LLM-orchestratable single-cell RNA-seq toolkit.
GitHub, 2026. https://github.com/ChanghaoKan/scAgentKit
```

---

## Author

**Kanchanghao**  
Shenzhen Bay Laboratory

**Repository**: https://github.com/ChanghaoKan/scAgentKit

---

## License

MIT
```
