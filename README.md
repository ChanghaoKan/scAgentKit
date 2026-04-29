
# scAgentKit

> **An LLM-orchestratable, fully auditable toolkit for single-cell RNA-seq analysis.**

scAgentKit turns the tacit knowledge of single-cell analysis into explicit, reproducible, and auditable steps. Every decision — QC thresholds, number of PCs, batch variable, clustering resolution, cell-type annotation — is made with evidence, recorded with reasoning, and can be replayed as plain R code.

**Core philosophy**: No black boxes. Every LLM call produces a written rationale. Every step appends to a decision log. At the end you get a clean, dependency-free R script + machine-readable audit trail + human-readable HTML report.

---

## Why scAgentKit exists

A typical single-cell analyst makes 15–20 small but consequential decisions per dataset. Most of these decisions are made silently and never appear in the methods section. Two analysts can produce completely different biological stories from the same data with no way to audit *why*.

scAgentKit makes every decision a first-class, recorded step. The LLM sees the same evidence a human analyst would (marker tables, UMAPs, clustree, proportions, reference matches), writes its reasoning in plain English, and the choice is permanently logged.

This is **not** “LLM does your analysis for you.”  
It is a **collaborative analysis partner** that forces transparency and reproducibility.

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Full audit trail** | Every decision is recorded with parameters, rationale, and reproducible code |
| **Three-step annotation workflow** | Coarse annotation → quality cleaning → fine subclustering per lineage |
| **Smart quality control** | `annot_clean_celltypes()` automatically merges singular/plural names and flags/removes low-quality clusters |
| **Vision-driven QC** | Optional LLM vision mode to visually judge whether small clusters are real biology or contamination |
| **Multi-LLM support** | DeepSeek, Grok, Claude, Qwen, Kimi, OpenAI, or any OpenAI-compatible endpoint |
| **Per-sample QC** | Proper `qc_split` → `qc_mad`/`qc_doublet` → `qc_merge` workflow |
| **Self-contained outputs** | Clean R script, JSON decision log, and beautiful HTML report |

---

## Installation

```r
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
```

Set at least one LLM API key in `~/.Renviron`:

```bash
DEEPSEEK_API_KEY=sk-...
# or
ANTHROPIC_API_KEY=sk-ant-...
# or
XAI_API_KEY=xai-...
```

---

## Recommended Pipeline (2026 Updated)

```r
library(scAgentKit)

chat_text   <- chat_deepseek()
chat_vision <- chat_grok()          # vision capable

obj <- AgentSeurat(seurat_obj)

# ====================== STEP 1: Coarse annotation ======================
obj <- annot_llm_annotate(obj, 
                          chat_fn = chat_text,
                          tissue = "mouse colorectal cancer",
                          data_context = "Focus on major lineages first")

obj <- annot_apply(obj)

# ====================== STEP 2: Clean names + quality filter ======================
obj <- annot_clean_celltypes(obj,
                             merge_plural = TRUE,
                             min_cells    = 50,
                             action       = "flag",           # or "remove"
                             vision       = TRUE,             # LLM visually judges quality
                             chat_fn      = chat_vision,
                             tissue       = "mouse colorectal cancer")

# ====================== STEP 3: Fine subclustering (only on key lineages) ======================
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        target = c("T_NK", "B", "Macrophage"),
                        tissue = "mouse colorectal cancer",
                        data_context = "Focus on macrophage polarization and T cell states")

# ====================== Outputs ======================
export_script(obj, "reproducible_script.R")
export_decisions(obj, "decisions.json")
report_html(obj, "analysis_report.html")
```

**Why this three-step approach?**
- First pass focuses on major biological structure (avoids over-fragmentation)
- `annot_clean_celltypes()` merges naming variants and removes technical noise
- Vision mode lets the LLM *see* the UMAP and decide if small clusters are real or artifacts
- Final subclustering is only applied to lineages you actually care about

---

## Quality Control & Cleaning (`annot_clean_celltypes`)

```r
obj <- annot_clean_celltypes(obj,
                             merge_plural = TRUE,   # Macrophages → Macrophage
                             min_cells    = 50,
                             action       = "flag", # or "remove"
                             vision       = TRUE)   # LLM looks at UMAP
```

**What it does:**
- Automatically merges singular/plural cell type names
- Flags or removes clusters with very few cells (often contaminants or doublets)
- When `vision = TRUE`, generates a UMAP highlighting suspicious clusters and asks the LLM to visually judge whether they are real biology or technical artifacts

This step greatly improves annotation quality before doing expensive fine subclustering.

---

## Core Design Principles

1. Every LLM-touching function records a written rationale
2. Two-step (now three-step) annotation is first-class
3. Vision is optional but powerful for ambiguous visual decisions
4. Per-sample processing is the default for QC and doublet detection
5. You always stay in control — the LLM recommends, you execute

---

## Important Notes

- `data_context` is only supported in `annot_llm_annotate()`, `annot_subcluster()`, and `annot_clean_celltypes()`
- `sc_select_pcs_visual()` and `sc_select_batch_var()` do **not** accept `data_context`
- For mouse data, always pass `species = "mouse"` to `qc_add_metrics()` and `qc_remove_genes()`
- Vision steps require a vision-capable model (Grok, Claude, GPT-4o, Qwen-VL, etc.)

---

## Output Artifacts

| File | Description |
|------|-------------|
| `reproducible_script.R` | Pure Seurat code with no scAgentKit dependency |
| `decisions.json` | Complete machine-readable decision log |
| `analysis_report.html` | Self-contained HTML report with embedded figures and reasoning |
| `checkpoints/*.qs` | Fast resume points after major stages |

---

## Limitations (Honest)

- Vision steps require a vision-capable model and can be slower
- LLM decisions are not ground truth — always validate important findings marker-by-marker
- Very small datasets (< 3,000 cells) may not benefit from the full pipeline
- `annot_clean_celltypes(vision = TRUE)` currently uses a single combined UMAP; per-cluster detailed judgment will be added in future versions

---

## Citation

If you use scAgentKit in your work, please cite:

```
Changhao K. scAgentKit: An LLM-orchestratable single-cell RNA-seq toolkit with full auditability.
GitHub, 2026. https://github.com/kanyy/scAgentKit
```

---

## Acknowledgments

Designed and built at Shenzhen Bay Laboratory (Deng Lab), 2025–2026.

The package was developed through extensive iteration with Claude (Anthropic) and real-world validation on multiple cancer scRNA-seq datasets, including GSE149614.

---

**License**: MIT

---

**Contributing**

Issues and pull requests are very welcome. The package is intentionally modular. Two rules must be followed:

1. Every function that calls an LLM must record a `rationale`.
2. Every function must append a reproducible script snippet via `.record_step()`.

---

**Contact**

- GitHub Issues: https://github.com/kanyy/scAgentKit/issues
- Author: Kan Changhao (Shenzhen Bay Laboratory)


---

