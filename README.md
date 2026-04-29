# scAgentKit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R: >= 4.2](https://img.shields.io/badge/R-%3E%3D%204.2-blue)](https://www.r-project.org/)
[![Seurat: >= 5.0](https://img.shields.io/badge/Seurat-%3E%3D%205.0-orange)](https://satijalab.org/seurat/)

**An LLM-orchestratable toolkit for single-cell RNA-seq analysis with full auditability.**

scAgentKit reshapes the standard single-cell workflow into a set of atomic, LLM-driven functions. Every decision point — QC thresholds, number of principal components, batch variable selection, clustering resolution, and cell-type annotation — is made with evidence, accompanied by written reasoning, and permanently recorded for reproducibility.

The package is designed to convert tacit analytical knowledge into explicit, auditable knowledge.

---

## Features

- **Complete decision logging** — Every step records parameters, rationale, timestamp, and reproducible R code.
- **Three-step annotation workflow** — Coarse annotation → automated quality cleaning → lineage-specific fine subclustering.
- **Quality control module** — `annot_clean_celltypes()` merges singular/plural labels and flags or removes low-quality clusters, with optional vision-based judgment.
- **Vision-enabled decisions** — Supports visual inspection of UMAPs and clustree plots for PC selection, resolution recommendation, and cluster quality assessment.
- **Per-sample QC pipeline** — Recommended workflow for accurate doublet detection and MAD-based filtering.
- **Multi-provider LLM support** — Compatible with DeepSeek, Grok (xAI), Claude, Qwen, Kimi, OpenAI, and any OpenAI-compatible endpoint.
- **Self-contained outputs** — Generates a dependency-free R script, JSON decision log, and a standalone HTML report with embedded figures.

---

## Installation

```r
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
```

Set at least one API key in your `~/.Renviron` file:

```bash
DEEPSEEK_API_KEY=sk-...
XAI_API_KEY=xai-...
ANTHROPIC_API_KEY=sk-ant-...
```

---

## Recommended Workflow

```r
library(scAgentKit)
library(Seurat)

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

# Dimensionality reduction and integration
obj <- sc_select_pcs_visual(obj, chat_fn = chat_vision, variance_thresholds = c(0.80, 0.85, 0.90))
obj <- sc_select_batch_var(obj, chat_fn = chat_text)
obj <- sc_harmony(obj, group_by_vars = obj@params$batch_recommendation$recommended)
obj <- sc_umap(obj)

# Clustering
obj <- sc_cluster_sweep(obj)
obj <- sc_resolution_recommend(obj, chat_fn = chat_vision, vision = TRUE)
obj <- sc_cluster(obj, resolution = obj@params$resolution_recommendation$chosen)

# Annotation (three-step)
obj <- annot_llm_annotate(obj, chat_fn = chat_text, tissue = "mouse colorectal cancer")
obj <- annot_apply(obj)

obj <- annot_clean_celltypes(obj, merge_plural = TRUE, min_cells = 50, vision = TRUE, chat_fn = chat_vision)
obj <- annot_subcluster(obj, chat_fn = chat_text, target = c("T_NK", "B", "Macrophage"), tissue = "mouse colorectal cancer")

# Output
export_script(obj, "reproducible_script.R")
export_decisions(obj, "decisions.json")
report_html(obj, "analysis_report.html")
```

---

## Important Notes

- Vision features require a vision-capable model (e.g., Grok, Claude Sonnet, GPT-4o).

---

## Output Artifacts

| File                        | Description                                      |
|----------------------------|--------------------------------------------------|
| `reproducible_script.R`    | Pure Seurat code with no scAgentKit dependency   |
| `decisions.json`           | Complete machine-readable decision log           |
| `analysis_report.html`     | Self-contained HTML report with embedded figures |

---

## Citation

If scAgentKit contributes to your research, please cite:

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

MIT License
```
