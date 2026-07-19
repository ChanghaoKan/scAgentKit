# scAgentKit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R: >= 4.1](https://img.shields.io/badge/R-%3E%3D%204.1-blue)](https://www.r-project.org/)
[![Seurat: >= 5.0](https://img.shields.io/badge/Seurat-%3E%3D%205.0-orange)](https://satijalab.org/seurat/)
[![R-CMD-check](https://github.com/ChanghaoKan/scAgentKit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ChanghaoKan/scAgentKit/actions/workflows/R-CMD-check.yaml)

> **An experimental, human-in-the-loop toolkit for provenance-tracked single-cell RNA-seq analysis.**

---

## What scAgentKit is, and what it is not

scAgentKit wraps a Seurat workflow spanning QC, integration, dimensionality reduction, clustering, annotation, and sub-annotation. Optional language-model calls can review the same summaries, plots, and marker lists presented to an analyst. Pipeline functions retain parameters, rationales, figures, and generated R snippets so decisions can be inspected later.

This is a research-software prototype, not an autonomous analyst. The biological interpretation, model output, and generated code all require human review. No comparative accuracy or benchmark claim is made until the planned evaluations have been completed and released.

### Current design elements

1. **Broad workflow coverage.** QC → integration → clustering → annotation → sub-annotation, with optional model assistance at selected judgement points.
2. **`AgentSeurat` S4 container with a decision log and generated script trace.** Pipeline-mutating functions take and return the container so their recorded state travels with the analysis.
3. **Vision-capable upstream decisions.** `sc_select_pcs_visual` shows the LLM elbow/cumulative-variance plots; `sc_resolution_recommend` shows multi-panel UMAP + clustree.
4. **Cycling-cluster lineage rescue.** Proliferating clusters where MKI67/TOP2A dominate the differential markers get a separate "high-expression non-cell-cycle, non-housekeeping" rescue list, with structured naming (`Cycling cells (lineage candidate: X)`).
5. **Structured contamination prompts.** Candidate contamination calls are presented with explicit criteria that the model and analyst can review.

### Current prototype (v0.4.0)

- **Best-effort token tracking.** Built-in providers record usage when the API returns token metadata; inspect it with `get_token_usage(obj)` / `token_usage_summary()`.
- **Parallel annotation.** `annot_llm_annotate(parallel = TRUE)` under `future::plan()`.
- **Ensemble + hybrid confidence + marker-citation validation** (see `?annot_llm_annotate`).
- **Cell Ontology mapping** via exact-match-only (`annot_map_to_cl`).
- **Checkpoint versioning.** `@version` slot + `upgrade_checkpoint()` for backward compatibility.
- **Development checks.** A Docker development environment pins the R base image and core release reference; GitHub Actions runs `R CMD check` on Ubuntu.
- **Experimental evaluation scaffolding.** `benchmark/` contains a partial harness and planned studies, not published results.

---

## Honest limitations (read before relying on this)

- **Annotation performance is not established.** The current repository does not contain a completed, independently reviewed benchmark against dedicated annotation tools.
- **Adaptive curves were calibrated on HCC/liver.** The default resolution formula (`0.05 + 0.10 * log10(n)` clamped) and the subcluster `n_hvg / n_pcs` curves were tuned on liver data, 10-50k cells. PBMC, developing brain, organoid topologies may need different curves. Pass explicit numeric values for those.
- **LLM calls are non-deterministic.** Even with `temperature = 0`, providers can change models or serving behavior. Ensembles add further variability; disagreement fields expose some, but not all, uncertainty.
- **Failure modes we know about.** Sparse marker DB tissues (gonad, placenta, embryonic intermediates), extremely rare populations (< 0.1%), cross-species mixtures, highly proliferative tumors where even cycling rescue cannot recover lineage, and patient-specific malignant populations that are themselves a lineage in single-patient atlases.
- **Generated scripts require review.** Some downstream steps currently emit reconstruction snippets or script skeletons rather than a guaranteed standalone replay from raw counts.

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Standard Workflow Template](#standard-workflow-template)
- [Complete Feature Showcase](#complete-feature-showcase)
- [Scenario-Specific Guidelines](#scenario-specific-guidelines)
- [Core Concepts](#core-concepts)
- [Function Reference](#function-reference)
- [Best Practices](#best-practices)
- [Roadmap](#roadmap)
- [Citation](#citation)
- [License](#license)

---

## Installation

### Prerequisites

- R >= 4.1.0
- Seurat >= 5.0.0

### Install from GitHub

```r
# Install remotes if not already installed
if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes")
}

# Install the shared core and scAgentKit
remotes::install_github("ChanghaoKan/agentomicsCore@v0.1.1", upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit@v0.4.0", upgrade = "never")

# Install optional dependencies for full functionality
install.packages(c("harmony", "clustree", "future.apply", "ontologyIndex"))
if (!requireNamespace("BiocManager", quietly = TRUE)) {
  install.packages("BiocManager")
}
BiocManager::install(c("scDblFinder", "SingleCellExperiment"))
```

### Configure LLM API Keys

Add API keys to your `~/.Renviron` file:

```bash
# Examples; set only the keys for providers you intend to use
DEEPSEEK_API_KEY=sk-...
XAI_API_KEY=xai-...
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

Restart R after editing `.Renviron`:

```r
# Verify that the variable exists without printing the secret
nzchar(Sys.getenv("DEEPSEEK_API_KEY"))
```

---

## Quick Start

Minimal workflow shape (runtime depends on data size, hardware, and provider):

```r
library(scAgentKit)

# Configure example LLM providers
chat_text   <- chat_deepseek()    # Example text provider
chat_vision <- chat_grok()        # Vision-capable for plot analysis

# Load and wrap your Seurat object
seu <- readRDS("your_data.rds")
obj <- AgentSeurat(
  seu,
  initial_script = 'seu <- readRDS("your_data.rds")'
)

# Basic pipeline
obj <- qc_add_metrics(obj, species = "auto")
obj <- qc_threshold(obj, min_nCount = 1000, min_nFeature = 500, max_percent_mt = 20)
obj <- sc_normalize(obj)
obj <- sc_find_hvg(obj, nfeatures = 2000)
obj <- sc_scale(obj)
obj <- sc_pca(obj, npcs = 50)
obj <- sc_select_pcs(obj, threshold = 0.85)
obj <- sc_umap(obj)
obj <- sc_find_neighbors(obj)
obj <- sc_cluster(obj, resolution = 0.5)

# Annotation
obj <- sc_find_markers(obj)
obj <- sc_markers_summary(obj, top_n = 30)
obj <- annot_llm_annotate(obj, chat_fn = chat_text, tissue = "your tissue context")
# Keep every cluster until the suggestions have been independently reviewed.
obj <- annot_apply(obj, drop_rejected = FALSE)

# Export
export_script(obj, "analysis.R")
report_html(obj, "report.html")
```

---

## Standard Workflow Template

This template illustrates a multi-sample dataset with batch effects. Replace
all thresholds, metadata fields, and biological context with values justified
for your experiment.

```r
library(scAgentKit)
library(Seurat)

# ============================================================
# 1. INITIALIZATION
# ============================================================
seu <- readRDS("merged_seurat.rds")
obj <- AgentSeurat(seu, initial_script = 'seu <- readRDS("merged_seurat.rds")')

# Configure example LLM providers
chat_text   <- chat_deepseek()    # Example text provider
chat_vision <- chat_grok()        # Verify selected model image support

# ============================================================
# 2. QUALITY CONTROL (Per-Sample)
# ============================================================
# Add QC metrics (auto-detects species from gene names)
obj <- qc_add_metrics(obj, species = "auto")

# Visualize before filtering
obj <- qc_plot(obj, tag = "before_qc", group_by = "sample")

# Split by sample for per-sample processing
obj <- qc_split(obj, split_by = "sample")

# Conservative fixed thresholds
obj <- qc_threshold(obj, 
                    min_nCount = 1000, 
                    min_nFeature = 500, 
                    max_percent_mt = 20)

# Adaptive MAD-based filtering (removes outliers per sample)
obj <- qc_mad(obj, nmad = 3)

# Doublet detection (MUST run per-sample to avoid false positives)
obj <- qc_doublet(obj, remove = TRUE, seed = 999)

# Remove unwanted gene categories
obj <- qc_remove_genes(obj, species = "human")

# Merge samples back
obj <- qc_merge(obj, join_layers = TRUE)

# Visualize after filtering
obj <- qc_plot(obj, tag = "after_qc", group_by = "sample")

# Save checkpoint
obj <- save_checkpoint(obj, "checkpoints/01_qc.qs")

# ============================================================
# 3. NORMALIZATION & FEATURE SELECTION
# ============================================================
obj <- sc_normalize(obj, method = "LogNormalize", scale_factor = 10000)
obj <- sc_find_hvg(obj, nfeatures = 2000)
obj <- sc_scale(obj)

# ============================================================
# 4. DIMENSIONALITY REDUCTION
# ============================================================
obj <- sc_pca(obj, npcs = 50)

# LLM-assisted PC selection (vision: analyzes elbow plot)
obj <- sc_select_pcs_visual(obj, 
                            chat_fn = chat_vision, 
                            variance_thresholds = c(0.80, 0.85, 0.90))

obj <- save_checkpoint(obj, "checkpoints/02_pca.qs")

# ============================================================
# 5. BATCH INTEGRATION (if needed)
# ============================================================
# Request a batch-variable recommendation, then inspect it
obj <- sc_select_batch_var(obj, chat_fn = chat_text)
View(obj@params$batch_candidates)
batch_var <- obj@params$batch_recommendation$recommended
# Override batch_var here if it is biological or otherwise inappropriate.

# Run Harmony integration
obj <- sc_harmony(obj, 
                  group_by_vars = batch_var,
                  max_iter = 10)

# ============================================================
# 6. UMAP & NEIGHBOR GRAPH
# ============================================================
obj <- sc_umap(obj)                    # Auto-uses harmony if available
obj <- sc_find_neighbors(obj)          # Builds SNN graph

obj <- save_checkpoint(obj, "checkpoints/03_integrated.qs")

# ============================================================
# 7. CLUSTERING
# ============================================================
# Multi-resolution sweep
obj <- sc_cluster_sweep(obj, resolutions = seq(0.2, 1.0, 0.1))

# LLM-assisted resolution selection (vision: analyzes clustree + UMAPs)
obj <- sc_resolution_recommend(obj, 
                               chat_fn = chat_vision,
                               tissue = "human PBMC",
                               expected_n_celltypes = c(8, 15),
                               vision = TRUE)

# Review the evidence and adopt or override the recommendation
obj@params$resolution_recommendation
chosen_resolution <- obj@params$resolution_recommendation$chosen
obj <- sc_cluster(obj, resolution = chosen_resolution)

# Visualize clusters
obj <- sc_plot_umap(obj, group_bys = c("seurat_clusters", "sample"))

obj <- save_checkpoint(obj, "checkpoints/04_clustered.qs")

# ============================================================
# 8. MARKER GENE IDENTIFICATION
# ============================================================
obj <- sc_find_markers(obj, only_pos = FALSE, min_pct = 0.25)
obj <- sc_markers_summary(obj, 
                          top_n = 30, 
                          log2fc_cut = 1, 
                          padj_cut = 0.05)

obj <- save_checkpoint(obj, "checkpoints/05_markers.qs")

# ============================================================
# 9. CELL TYPE ANNOTATION (Three-Step Strategy)
# ============================================================

# Step 1: Reference database matching (optional)
# Supply a curated human reference for this PBMC example. The small file in
# inst/extdata is a format template with mouse-style symbols, not a validated
# human PBMC reference.
ref <- annot_load_reference(
  path = "references/pbmc_human_markers.tsv",
  tissue_filter = "blood",
  species = "human"
)
obj <- annot_match_reference(obj, reference = ref, top_n_candidates = 5)

# Step 2: LLM-driven broad annotation
obj <- annot_llm_annotate(obj, 
                          chat_fn = chat_text,
                          tissue = "human PBMC",
                          expected_celltypes = c("T cell", "B cell", "NK cell", 
                                                "Monocyte", "DC", "Platelet"))

# Inspect LLM suggestions before applying
View(obj@params$llm_annotations)

# Step 3: Apply annotations (with optional manual overrides)
obj <- annot_apply(obj, 
                   source = "llm",
                   drop_rejected = FALSE,
                   manual_overrides = c("5" = "Plasma cell"))  # Override cluster 5

# Visualize annotations
obj <- sc_plot_umap(obj, group_bys = c("cell_type", "sample"))

obj <- save_checkpoint(obj, "checkpoints/06_annotated.qs")

# ============================================================
# 10. FINE-GRAINED ANNOTATION (Optional)
# ============================================================

# Clean up cell type names
obj <- annot_clean_celltypes(obj, 
                             merge_plural = TRUE,
                             min_cells = 50,
                             vision = TRUE,
                             chat_fn = chat_vision)

# Per-lineage subclustering for fine cell types
obj <- annot_subcluster(obj, 
                        chat_fn = chat_text,
                        target = c("T cell", "B cell", "Monocyte"),
                        tissue = "human PBMC",
                        subcluster_resolution = "adaptive")

obj <- save_checkpoint(obj, "checkpoints/07_final.qs")

# ============================================================
# 11. EXPORT RESULTS
# ============================================================
export_script(obj, "generated_analysis_trace.R")
export_decisions(obj, "decision_log.json")
report_html(obj, "analysis_report.html", title = "PBMC scRNA-seq Analysis")

# Extract final Seurat object
final_seu <- get_seurat(obj)
saveRDS(final_seu, "final_annotated_seurat.rds")
```

---

## Complete Feature Showcase

This section demonstrates selected extended options, including cell-cycle
regression and comparison with author annotations.

```r
library(scAgentKit)

# ============================================================
# EXTENDED QC OPTIONS
# ============================================================

# Manual species specification (if auto-detection fails)
obj <- qc_add_metrics(obj, 
                      species = "mouse",
                      mt_pattern = "^mt-",
                      ribo_pattern = "^Rp[sl]")

# Custom QC thresholds
obj <- qc_threshold(obj,
                    min_nCount = 500,
                    min_nFeature = 200,
                    max_percent_mt = 25,
                    min_percent_mt = 0.5)  # Remove ambient RNA

# Keep doublets for inspection (don't remove)
obj <- qc_doublet(obj, remove = FALSE, seed = 999)

# Choose which built-in gene categories to remove
obj <- qc_remove_genes(obj, 
                       species = "mouse",
                       remove_mt = TRUE,
                       remove_ribo = FALSE,  # Keep ribosomal genes
                       remove_hb = TRUE)

# ============================================================
# CELL CYCLE HANDLING
# ============================================================

# Score cell cycle phases
obj <- sc_cellcycle_score(obj, species = "mouse")

# Visualize cell cycle distribution
obj <- sc_plot_umap(obj, group_bys = c("Phase", "S.Score", "G2M.Score"))

# SCENARIO 1: Developmental/Tumor studies - DO NOT regress
# (Cell cycle is biologically relevant)
# → Skip sc_cellcycle_regress()

# SCENARIO 2: Steady-state immune profiling - REGRESS
# (Cell cycle is technical noise)
obj <- sc_cellcycle_regress(
  obj,
  mode = "full",
  rationale = "Removing cell-cycle effects for immune cell-type identification"
)

# ============================================================
# ADVANCED DIMENSIONALITY REDUCTION
# ============================================================

# Manual PC selection (without LLM)
obj <- sc_select_pcs(obj, 
                     threshold = 0.85,      # Cumulative variance
                     plot_elbow = TRUE)

# Or: Fixed number of PCs
obj@params$ndim <- 30

# Alternative: Visual selection with custom variance thresholds
obj <- sc_select_pcs_visual(obj,
                            chat_fn = chat_vision,
                            variance_thresholds = c(0.75, 0.80, 0.85, 0.90, 0.95))

# ============================================================
# BATCH CORRECTION OPTIONS
# ============================================================

# Manual batch variable selection (skip LLM recommendation)
obj <- sc_harmony(obj, 
                  group_by_vars = c("sample", "batch"),  # Multiple variables
                  ndim = 30,
                  max_iter = 20)

# No batch correction (single-sample or well-controlled experiment)
# → Skip sc_select_batch_var() and sc_harmony()

# ============================================================
# CLUSTERING STRATEGIES
# ============================================================

# Strategy 1: Manual resolution (fast, no LLM)
obj <- sc_cluster(obj, resolution = 0.6)

# Strategy 2: Sweep + manual inspection
obj <- sc_cluster_sweep(obj, resolutions = seq(0.1, 1.5, 0.1))
# → Inspect figures/clustree.png manually
obj <- sc_cluster(obj, resolution = 0.8)

# Strategy 3: LLM-assisted (text-only, no vision)
obj <- sc_resolution_recommend(obj,
                               chat_fn = chat_text,
                               tissue = "mouse liver",
                               vision = FALSE)

# Strategy 4: LLM-assisted with multi-panel vision (experimental)
obj <- sc_resolution_recommend(obj,
                               chat_fn = chat_vision,
                               tissue = "mouse liver",
                               expected_n_celltypes = c(10, 18),
                               vision = TRUE,
                               vision_panels = c(0.2, 0.4, 0.6, 0.8))

# ============================================================
# ANNOTATION STRATEGIES
# ============================================================

# Option A: LLM-only annotation (no reference database)
obj <- annot_llm_annotate(obj,
                          chat_fn = chat_text,
                          tissue = "human brain cortex",
                          condition = "Alzheimer's vs Control")

# Option B: Reference-guided annotation
ref <- annot_load_reference("cellmarker_human.tsv", 
                            tissue_filter = "brain",
                            species = "human")
obj <- annot_match_reference(obj, reference = ref)
obj <- annot_llm_annotate(obj, chat_fn = chat_text, tissue = "human brain cortex")

# Option C: Constrain output to an expected cell-type vocabulary
obj <- annot_llm_annotate(obj,
                          chat_fn = chat_text,
                          tissue = "mouse tumor microenvironment",
                          expected_celltypes = c("T cell", "B cell", "Macrophage", 
                                                "MDSC", "CAF", "Endothelial", 
                                                "Tumor cell"))

# Option D: Partial annotation (specific clusters only)
obj <- annot_llm_annotate(obj,
                          chat_fn = chat_text,
                          tissue = "human PBMC",
                          clusters = c(0, 3, 5, 7))  # Annotate only these clusters

# ============================================================
# ANNOTATION REFINEMENT
# ============================================================

# Compare with author's original annotations (if available)
obj <- annot_compare_with_reference(obj, 
                                    reference_col = "celltype")  # Author's column

# Collapse fine types to broad categories
obj@data$cell_type_broad <- annot_collapse_to_broad(obj@data$cell_type)

# Clean and merge similar cell type names
obj <- annot_clean_celltypes(obj,
                             merge_plural = TRUE,
                             min_cells = 30,
                             vision = TRUE,
                             chat_fn = chat_vision)

# ============================================================
# ADVANCED SUBCLUSTERING
# ============================================================

# Auto-select targets (all broad types with >= 200 cells)
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        tissue = "mouse colon tumor",
                        subcluster_resolution = "adaptive")

# Manual target selection with fixed resolution
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        target = c("T cell", "Macrophage"),
                        tissue = "mouse colon tumor",
                        subcluster_resolution = 0.5)

# Per-target custom resolutions
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        target = c("T cell", "B cell", "Macrophage"),
                        tissue = "human PBMC",
                        subcluster_resolution = c("T cell" = 0.6, 
                                                 "B cell" = 0.4,
                                                 "Macrophage" = 0.5))

# LLM-assisted per-lineage resolution (experimental; review each choice)
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        target = c("T cell", "Myeloid"),
                        tissue = "tumor microenvironment",
                        subcluster_resolution = "auto")  # LLM picks per lineage

# ============================================================
# VISUALIZATION
# ============================================================

# Multi-group UMAP
obj <- sc_plot_umap(obj, 
                    group_bys = c("cell_type", "cell_type_fine", 
                                 "sample", "Phase", "seurat_clusters"),
                    tag = "final")

# ============================================================
# CHECKPOINT MANAGEMENT
# ============================================================

# Save at any stage
obj <- save_checkpoint(obj, "checkpoints/custom_stage.qs")

# Load and resume
obj <- load_checkpoint("checkpoints/custom_stage.qs")

# ============================================================
# EXPORT & REPORTING
# ============================================================

# Export with custom header
export_script(obj, 
              "full_analysis.R",
              header_comment = "Complete scRNA-seq pipeline with all optional steps")

# Export decisions as JSON
export_decisions(obj, "decisions.json")

# Generate comprehensive HTML report
report_html(obj, 
            "comprehensive_report.html",
            title = "Multi-Sample Tumor scRNA-seq Analysis",
            include_script = TRUE,
            include_params = TRUE)

# ============================================================
# INTROSPECTION
# ============================================================

# View decision log
decisions <- get_decisions(obj)
View(decisions)

# View accumulated script
cat(get_script(obj))

# View figure registry
figures <- get_figures(obj)
View(figures)

# Access specific results
obj@params$llm_annotations           # LLM annotation results
obj@params$resolution_recommendation # Resolution choice reasoning
obj@params$batch_recommendation      # Batch variable recommendation
obj@params$markers_filtered          # Top markers per cluster
obj@params$subcluster_results        # Per-lineage subclustering results
```

---

## Scenario-Specific Guidelines

### 🧬 Scenario 1: Tumor Microenvironment Analysis

**Key Considerations:**
- **DO NOT** regress cell cycle (proliferation is biologically relevant)
- Expect high heterogeneity (use higher resolution)
- Contamination is common (use subclustering with contamination audit)

```r
# Skip cell cycle regression
obj <- sc_cellcycle_score(obj, species = "mouse")  # Score only, don't regress

# Higher resolution for tumor heterogeneity
obj <- sc_cluster_sweep(obj, resolutions = seq(0.3, 1.5, 0.1))
obj <- sc_resolution_recommend(obj, chat_fn = chat_vision, 
                               tissue = "mouse colorectal tumor",
                               expected_n_celltypes = c(15, 25))

# Comprehensive subclustering with contamination detection
obj <- annot_subcluster(obj, chat_fn = chat_text,
                        tissue = "tumor microenvironment",
                        subcluster_resolution = "adaptive",
                        suggest_followups = TRUE)  # Flags potential doublets
```

### 🩸 Scenario 2: PBMC / Immune Profiling

**Key Considerations:**
- Cell cycle is usually noise (consider regression)
- Well-defined cell types (use reference database)
- Moderate resolution sufficient

```r
# Regress cell cycle for cleaner immune cell separation
obj <- sc_cellcycle_score(obj, species = "human")
obj <- sc_cellcycle_regress(obj, mode = "full")

# Use curated immune reference
ref <- annot_load_reference("cellmarker_human_immune.tsv", 
                            tissue_filter = "blood")
obj <- annot_match_reference(obj, reference = ref)

# Moderate resolution
obj <- sc_cluster(obj, resolution = 0.5)
```

### 🧠 Scenario 3: Brain / Developmental Studies

**Key Considerations:**
- Cell cycle is biologically relevant (DO NOT regress)
- Rare cell types important (use lower resolution initially)
- Subclustering essential for neuronal subtypes

```r
# Keep cell cycle information
obj <- sc_cellcycle_score(obj, species = "mouse")  # Score only

# Conservative initial resolution
obj <- sc_cluster(obj, resolution = 0.4)

# Extensive subclustering for neuronal diversity
obj <- annot_subcluster(obj, chat_fn = chat_text,
                        target = c("Neuron", "Astrocyte", "Oligodendrocyte"),
                        tissue = "mouse cortex",
                        subcluster_resolution = "auto")
```

### 🔬 Scenario 4: Single-Sample / No Batch Effects

**Key Considerations:**
- Skip batch correction entirely
- Simpler QC (no per-sample splitting needed)

```r
# Simplified QC (no splitting)
obj <- qc_add_metrics(obj, species = "auto")
obj <- qc_threshold(obj, min_nCount = 1000, min_nFeature = 500)
obj <- qc_mad(obj, nmad = 3)

# Skip batch correction
# obj <- sc_harmony(...)  # NOT NEEDED

# Direct UMAP from PCA
obj <- sc_umap(obj)  # Uses PCA reduction
```

### 📊 Scenario 5: Large-Scale Atlas (>100k cells)

**Key Considerations:**
- Use checkpoints frequently
- Consider downsampling for initial exploration
- Batch correction critical

```r
# Aggressive QC to reduce size
obj <- qc_threshold(obj, min_nCount = 2000, min_nFeature = 1000)

# Checkpoint after every major step
obj <- save_checkpoint(obj, "checkpoints/01_qc.qs")
obj <- save_checkpoint(obj, "checkpoints/02_pca.qs")
obj <- save_checkpoint(obj, "checkpoints/03_harmony.qs")

# Use text-only LLM for cost efficiency
chat_text <- chat_deepseek()  # Example text provider; check current terms/pricing
obj <- sc_resolution_recommend(
  obj,
  chat_fn = chat_text,
  tissue = "your tissue context",
  vision = FALSE
)
```

---

## Core Concepts

### AgentSeurat S4 Class

The central data structure that wraps a Seurat object with decision tracking:

```r
obj <- AgentSeurat(seurat_obj)

# Slots:
obj@data          # Seurat object (or list during per-sample QC)
obj@data_type     # "seurat" or "seurat_list"
obj@stage         # Current pipeline stage
obj@decisions     # List of decision records
obj@scripts       # Generated R snippets / reconstruction trace
obj@figures       # Figure registry (path, description)
obj@params        # Latest parameters + intermediate results
obj@created_at    # Timestamp
obj@updated_at    # Timestamp
```

### Chat Function Interface

All LLM interactions use a unified signature:

```r
chat_fn <- function(system_prompt, user_prompt, image_path = NULL) {
  # Returns: character string (usually JSON)
}

# Built-in providers:
chat_deepseek()   # Text-only preset
chat_grok()       # Image-capable preset; verify selected model support
chat_claude()     # Vision-capable
chat_openai()     # Text + vision

# Custom provider:
chat_custom <- make_chat_fn_openai_compatible(
  base_url = "https://api.example.com/v1",
  model = "custom-model",
  api_key_env = "CUSTOM_API_KEY"
)
```

### Decision Recording

Pipeline-mutating functions are designed to record:

```r
decision <- list(
  step          = "sc_cluster",
  function_name = "sc_cluster",
  timestamp     = Sys.time(),
  params        = list(resolution = 0.6, n_clusters = 13),
  rationale     = "Chose resolution 0.6 based on ARI stability...",
  success       = TRUE
)
```

### Generated Script Trace

Pipeline functions append generated R snippets. Some are runnable; others are
reconstruction skeletons that require the recorded input-loading code and
analyst review:

```r
# Accumulated in obj@scripts
snippet <- '
# ---- Clustering (resolution = 0.6) ----
seurat_obj <- FindClusters(seurat_obj, resolution = 0.6)
'

# Export the accumulated script trace
export_script(obj, "analysis.R")
```

---

## Function Reference

### Quality Control

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `qc_add_metrics()` | Add QC metrics (MT%, ribo%, Hb%) | `species` (auto/human/mouse) |
| `qc_plot()` | Visualize QC distributions | `group_by`, `tag` |
| `qc_split()` | Split by sample for per-sample QC | `split_by` |
| `qc_threshold()` | Fixed threshold filtering | `min_nCount`, `max_percent_mt` |
| `qc_mad()` | MAD-based outlier removal | `nmad` (default 3) |
| `qc_doublet()` | scDblFinder doublet detection | `remove` (TRUE/FALSE) |
| `qc_remove_genes()` | Remove MT/ribo/Hb genes | `species`, `mt_pattern`, `ribo_pattern`, `hb_pattern` |
| `qc_merge()` | Merge samples back | `join_layers` |

### Normalization & Scaling

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_normalize()` | LogNormalize counts | `method`, `scale_factor` |
| `sc_find_hvg()` | Identify highly variable genes | `nfeatures` (default 2000) |
| `sc_scale()` | Z-score scaling | `vars_to_regress` |
| `sc_cellcycle_score()` | Score S/G2M phases | `species` |
| `sc_cellcycle_regress()` | Regress cell cycle | `mode` (`full`/`difference`) |

### Dimensionality Reduction

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_pca()` | Principal component analysis | `npcs` (default 50) |
| `sc_select_pcs()` | Manual PC selection | `threshold`, `plot_elbow` |
| `sc_select_pcs_visual()` | LLM-assisted PC selection | `chat_fn`, `variance_thresholds` |
| `sc_umap()` | UMAP embedding | `reduction` (auto-detects) |

### Batch Integration

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_select_batch_var()` | LLM recommends batch variable | `chat_fn` |
| `sc_harmony()` | Harmony integration | `group_by_vars` (required) |

### Clustering

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_find_neighbors()` | Build SNN graph | `reduction`, `ndim` |
| `sc_cluster_sweep()` | Multi-resolution sweep | `resolutions` |
| `sc_resolution_recommend()` | LLM-assisted resolution choice | `chat_fn`, `tissue`, `vision` |
| `sc_cluster()` | Commit to resolution | `resolution` |

### Marker Genes

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_find_markers()` | FindAllMarkers wrapper | `only_pos`, `min_pct` |
| `sc_markers_summary()` | Filter & rank by pct_diff | `top_n`, `log2fc_cut` |

### Annotation

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `annot_load_reference()` | Load marker reference database | `path`, `tissue_filter` |
| `annot_match_reference()` | Score clusters vs reference | `reference`, `top_n_candidates` |
| `annot_llm_annotate()` | LLM-driven annotation | `chat_fn`, `tissue`, `expected_celltypes` |
| `annot_apply()` | Apply annotations; rejected clusters are retained by default | `source`, `drop_rejected`, `manual_overrides` |
| `annot_clean_celltypes()` | Merge & clean cell type names | `merge_plural`, `min_cells`, `vision` |
| `annot_collapse_to_broad()` | Fine → broad label vector | `x`, `extra_map`, `keep_unmapped` |
| `annot_subcluster()` | Per-lineage fine annotation | `target`, `subcluster_resolution`, `tissue` |
| `annot_compare_with_reference()` | Compare with author labels | `reference_col`, `predicted_col` |

### Visualization

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `sc_plot_umap()` | Multi-panel UMAP plots | `group_bys`, `tag` |
| `qc_plot()` | QC metric distributions | `group_by`, `tag` |

### Export & Checkpointing

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `save_checkpoint()` | Save AgentSeurat object | `path` (.qs format) |
| `load_checkpoint()` | Load AgentSeurat object | `path` |
| `export_script()` | Export accumulated R script trace | `path`, `header_comment` |
| `export_decisions()` | Export decision log as JSON | `path` |
| `report_html()` | Generate HTML report | `path`, `title`, `include_script` |

### Introspection

| Function | Purpose | Returns |
|----------|---------|---------|
| `get_seurat()` | Extract Seurat object | Seurat or list |
| `get_decisions()` | Get decision log | List of decisions |
| `get_script()` | Get accumulated script | Character string |
| `get_figures()` | Get figure registry | Data frame |

---

## Best Practices

### 1. **LLM Provider Selection**

One possible provider combination (verify current model availability,
capabilities, privacy terms, and pricing with each provider):

```r
chat_text   <- chat_deepseek()
chat_vision <- chat_grok()
```

**Alternative options:**

```r
# Alternative provider:
chat_text   <- chat_claude()
chat_vision <- chat_claude()      # Same configured model for consistency

# Local endpoint (resource use and privacy depend on your deployment):
chat_text <- make_chat_fn_openai_compatible(
  base_url = "http://localhost:11434/v1",
  model = "qwen2.5:14b",
  api_key_env = ""  # No key needed
)
```

### 2. **Checkpoint Strategy**

Save checkpoints after computationally expensive steps:

```r
obj <- save_checkpoint(obj, "checkpoints/01_qc.qs")           # After QC
obj <- save_checkpoint(obj, "checkpoints/02_pca.qs")          # After PCA
obj <- save_checkpoint(obj, "checkpoints/03_harmony.qs")      # After integration
obj <- save_checkpoint(obj, "checkpoints/04_clustered.qs")    # After clustering
obj <- save_checkpoint(obj, "checkpoints/05_markers.qs")      # After markers
obj <- save_checkpoint(obj, "checkpoints/06_annotated.qs")    # After annotation
obj <- save_checkpoint(obj, "checkpoints/07_final.qs")        # Final result
```

### 3. **Cell Cycle Handling Decision Tree**

```r
# Ask: Is cell cycle biologically relevant to my question?

# YES (tumor, development, stem cells):
obj <- sc_cellcycle_score(obj, species = "mouse")  # Score only
# → DO NOT regress

# NO (steady-state immune, tissue homeostasis):
obj <- sc_cellcycle_score(obj, species = "mouse")
obj <- sc_cellcycle_regress(obj, mode = "full")
# → Regress to reduce noise

# UNSURE:
# → Run both pipelines in parallel and compare
```

### 4. **Resolution Selection Guidelines**

There is no dataset-type-specific resolution range that is generally valid.
Sweep a defensible grid, inspect cluster stability, marker coherence, sample
composition, and sensitivity to neighboring resolutions, then record the
analyst's choice. Treat `sc_resolution_recommend()` as a review aid rather
than ground truth.

### 5. **Annotation Quality Control**

Always inspect LLM annotations before applying:

```r
# View LLM suggestions
ann <- obj@params$llm_annotations
View(ann[, c("cluster", "primary_annotation", "confidence", 
             "contradicting_markers", "recommended_action")])

# Check for low-confidence clusters (self-report or heuristic label)
low_conf <- ann[
  ann$confidence %in% "low" | ann$hybrid_confidence_label %in% "low",
]

# Treat rejection as a review flag, not an automatic deletion decision
rejected <- ann[ann$recommended_action == "reject", ]

# Apply with manual overrides
obj <- annot_apply(obj, 
                   source = "llm",
                   drop_rejected = FALSE,
                   manual_overrides = c(
                     "3" = "Plasma cell",      # Override cluster 3
                     "7" = "Proliferating T"   # Override cluster 7
                   ))
```

### 6. **Batch Correction Decision**

```r
# When to use Harmony:
# ✓ Multiple samples from different batches/donors
# ✓ Technical batch effects visible in UMAP
# ✓ Same cell types cluster separately by sample

# When to SKIP Harmony:
# ✗ Single sample
# ✗ Biological differences (treatment vs control) are the question
# ✗ Well-controlled experiment with minimal batch effects

# Request a model recommendation, then review it:
obj <- sc_select_batch_var(obj, chat_fn = chat_text)
# → Inspect obj@params$batch_recommendation$reasoning
```

### 7. **Subclustering Strategy**

```r
# When to subcluster:
# ✓ Broad type has enough cells for the planned resolution and replicate design
# ✓ Known heterogeneity (e.g., T cells: CD4/CD8/Treg/MAIT)
# ✓ Biological question requires fine resolution

# Adaptive resolution (default HCC/liver-calibrated heuristic; review first):
obj <- annot_subcluster(obj, 
                        chat_fn = chat_text,
                        tissue = "your tissue context",
                        subcluster_resolution = "adaptive")
# → Small lineages get lower resolution (avoid over-fragmentation)
# → Large lineages get higher resolution (capture diversity)

# Fixed resolution (predictable):
obj <- annot_subcluster(obj, 
                        chat_fn = chat_text,
                        tissue = "your tissue context",
                        subcluster_resolution = 0.5)

# Per-lineage custom (full control):
obj <- annot_subcluster(obj,
                        chat_fn = chat_text,
                        tissue = "your tissue context",
                        subcluster_resolution = c(
                          "T cell" = 0.6,      # High diversity
                          "B cell" = 0.4,      # Moderate diversity
                          "Macrophage" = 0.5
                        ))
```

### 8. **Provenance and reconstruction checklist**

```r
# Set seeds for stochastic steps
obj <- qc_doublet(obj, seed = 999)
obj <- sc_harmony(obj, group_by_vars = "sample", seed = 999)

# Export review artifacts
export_script(obj, "analysis.R")
export_decisions(obj, "decisions.json")
report_html(obj, "report.html")

# Record the exact model identifiers returned by your providers
writeLines(c("text_model=<provider-returned-id>",
             "vision_model=<provider-returned-id>"),
           "model_versions.txt")

# Save session info
writeLines(capture.output(sessionInfo()), "session_info.txt")
```

---

## Advanced Topics

### Custom Reference Database

Create your own marker reference:

```r
# Format: cell_type, marker, tissue, source (optional)
ref <- data.frame(
  cell_type = c("Hepatocyte", "Hepatocyte", "Kupffer cell", "Kupffer cell"),
  marker = c("ALB", "AFP", "CD68", "CLEC4F"),
  tissue = c("liver", "liver", "liver", "liver"),
  source = c("manual", "manual", "manual", "manual")
)

write.table(ref, "my_reference.tsv", sep = "\t", 
            row.names = FALSE, quote = FALSE)

# Load and use
ref <- annot_load_reference("my_reference.tsv", 
                            tissue_filter = "liver")
obj <- annot_match_reference(obj, reference = ref)
```

### Custom Chat Function

Integrate any LLM provider:

```r
# Example: Local Ollama server
chat_local <- make_chat_fn_openai_compatible(
  base_url = "http://localhost:11434/v1",
  model = "qwen2.5:14b",
  api_key_env = "",  # No key needed
  supports_vision = FALSE,
  temperature = 0,
  max_tokens = 2000
)

# Example: Custom API with httr2
chat_custom <- function(system_prompt, user_prompt, image_path = NULL) {
  # Your custom implementation
  response <- httr2::request("https://api.example.com/chat") |>
    httr2::req_body_json(list(
      system = system_prompt,
      user = user_prompt
    )) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  
  return(response$message)
}
```

Azure OpenAI and other provider-specific gateways may require custom
authentication headers, URL layouts, or query parameters. The generic helper
does not promise those provider-specific conventions; use a reviewed custom
`chat_fn` like the template above when they are required.

### Parallel Processing for Large Datasets

```r
# Enable parallel processing for marker finding
library(future)
plan(multisession, workers = 8)

obj <- sc_find_markers(obj, only_pos = FALSE)

# Reset to sequential
plan(sequential)
```

### Integration with Other Tools

```r
# Export to Scanpy (Python)
seu <- get_seurat(obj)
SeuratDisk::SaveH5Seurat(seu, "data.h5seurat")
SeuratDisk::Convert("data.h5seurat", dest = "h5ad")

# Export to CellxGene
seu <- get_seurat(obj)
# Follow CellxGene schema requirements

# Export markers for enrichment analysis
markers <- obj@params$markers_filtered
write.csv(markers, "markers_for_enrichment.csv")
```

---

## Troubleshooting

### Common Issues

#### 1. **"ndim not set" Error**

```r
# Problem: Downstream functions need PC count
# Solution: Run PC selection first
obj <- sc_select_pcs(obj, threshold = 0.85)
# Or manually set:
obj@params$ndim <- 30
```

#### 2. **Seurat v5 Layer Errors**

```r
# Problem: "Cannot find 'counts' in this Assay"
# Solution: scAgentKit handles this automatically, but if you see this:
seu <- get_seurat(obj)
seu[["RNA"]] <- JoinLayers(seu[["RNA"]])
obj@data <- seu
```

#### 3. **LLM Returns Malformed JSON**

```r
# Problem: JSON parse error in annot_llm_annotate()
# Solution 1: Increase max_retries
obj <- annot_llm_annotate(obj, chat_fn = chat_text, 
                          tissue = "...", max_retries = 5)

# Solution 2: Try another provider/model and validate its structured output
chat_text <- chat_claude()
```

#### 4. **Out of Memory**

```r
# Problem: Large dataset (>100k cells)
# Solution 1: Aggressive QC
obj <- qc_threshold(obj, min_nCount = 2000, min_nFeature = 1000)

# Solution 2: Reduce HVG count
obj <- sc_find_hvg(obj, nfeatures = 1000)

# Solution 3: Use fewer PCs
obj <- sc_pca(obj, npcs = 30)
```

#### 5. **Doublet Detection Fails**

```r
# Problem: scDblFinder error on merged object
# Solution: MUST run on split object
obj <- qc_split(obj, split_by = "sample")
obj <- qc_doublet(obj, remove = TRUE)
obj <- qc_merge(obj)
```

#### 6. **Vision Model Ignores Images**

```r
# Problem: LLM doesn't reference the plot
# Solution: Verify vision support
chat_vision <- chat_grok()  # Confirm the selected model supports images
# Or Claude:
chat_vision <- chat_claude()  # Confirm the selected model supports images

# Check if image file exists
obj@figures  # Verify plot was saved
```

---

## Performance and cost

scAgentKit v0.4.0 records token fields from built-in chat providers when the
API returns usage metadata. Custom chat functions are not automatically
metered, and the package does not calculate currency costs:

```r
# After running your pipeline:
get_token_usage(obj)        # per-step breakdown
token_usage_summary()       # global by provider+model
```

Provider pricing, caching rules, and model identifiers change. Use the
recorded token counts together with the provider's current billing page; do
not infer a cost from unverified examples in this repository.

---

## Frequently Asked Questions

### Q: Can I use scAgentKit without an LLM?

**A:** Yes, partially. You can use all QC, normalization, and clustering functions without LLM. For annotation, you'll need to manually specify parameters:

```r
# No LLM needed:
obj <- sc_select_pcs(obj, threshold = 0.85)  # Manual threshold
obj <- sc_cluster(obj, resolution = 0.6)     # Manual resolution

# LLM required for these model-assisted paths:
# - annot_llm_annotate()
# - sc_resolution_recommend()
# sc_select_batch_var(chat_fn = NULL) can use its rule-based path.
```

### Q: How do I handle species other than human/mouse?

**A:** Automatic species handling is currently limited to human and mouse.
For another species, supply patterns that match its gene naming convention;
the `species` value still has to select the closest built-in convention:

```r
obj <- qc_add_metrics(obj, 
                      species = "mouse",
                      mt_pattern = "^Mt-",
                      ribo_pattern = "^Rp[sl]",
                      hb_pattern = "^Hb[ab]")
```

### Q: Can I modify LLM decisions after the fact?

**A:** Yes, use manual overrides:

```r
# Override specific clusters
obj <- annot_apply(obj, 
                   drop_rejected = FALSE,
                   manual_overrides = c(
                     "3" = "Corrected cell type",
                     "7" = "Another correction"
                   ))

# Or edit metadata directly
seu <- get_seurat(obj)
seu$cell_type[seu$seurat_clusters == 3] <- "Corrected type"
obj@data <- seu
```

### Q: How do I cite scAgentKit in my paper?

**A:** See [Citation](#citation) section below. Include:
1. Software citation
2. LLM provider citations (DeepSeek, xAI, etc.)
3. Seurat citation
4. Method-specific citations (Harmony, scDblFinder, etc.)

### Q: Is my data sent to LLM providers?

**A:** The built-in model-assisted steps send selected summaries, labels,
marker lists, prompts, and—when enabled—plot images, rather than the full
count matrix. Those artifacts can still contain sensitive or unpublished
information. Custom chat functions can send anything their author programs.
Inspect prompts and plots, review the provider's data policy, and use a
trusted local endpoint when required by consent or institutional policy.

### Q: Can I run this on a cluster/HPC?

**A:** Yes, scAgentKit works in non-interactive environments:

```bash
#!/bin/bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G

module load R/4.3.0
Rscript my_analysis.R
```

Ensure API keys are in `~/.Renviron` or set via `Sys.setenv()`.

---

## Detailed limitations (extended)

In addition to the [headline limitations at the top of this README](#honest-limitations-read-before-relying-on-this), some practical things you should know once you start using the package on real data:

- **The LLM is not ground truth.** It rationalizes (we observed it justifying 27% γδT in HCC by inventing an "HCC enrichment" argument — which happens to be partially correct, but not for the reasons it gave). It over-corrects when prompts are too strict. It under-corrects when prompts are too lax. Validate marker-by-marker for any finding you'll publish.

- **Small-lineage subclustering is unstable.** A B subset of 1500 cells split into 11 sub-clusters of 100–300 cells each has weak markers; the LLM's confidence (and any tool's confidence) is genuinely low here. This is a sample-size limit, not a tool limit.

- **Prompts are tissue/disease-specific.** Built-in vocabulary covers liver/HCC well, plus generic immune and major tumour types. Cardiac, renal, neural tissue may need custom `data_context` or vocabulary overrides.

- **Hosted API calls may incur cost.** `get_token_usage(obj)` reports provider-returned token fields, not currency; local/custom providers may behave differently.

- **Validation is on you.** scAgentKit is a **collaborator**, not a replacement. Every annotation needs marker-level review by someone who knows the biology. Trust the reasoning the way you'd trust a trainee's first pass — useful starting point, not final answer.

- **Vision uploads can be large.** Base64-encoded plots increase request size and may be unsuitable for slow links or sensitive data. Configure networking according to your institution and provider.

- **Seurat v5 only.** v4 compatibility is not tested.

---

## Roadmap

### v0.4.0 (current) — human-in-the-loop prototype

Available now: Seurat workflow wrappers, provenance records, provider
adapters, optional vision-assisted decisions, annotation citation checks,
checkpoints, reports, and unit tests for selected logic.

### Planned / experimental

- A reviewed high-level orchestrator with explicit user approval points.
- Global annotation review and calibrated uncertainty evaluation.
- Completed, versioned benchmarks across public datasets and baselines.

### Longer-term

- Persistent memory across runs (the agent remembers your dataset's quirks)
- Multi-dataset comparative annotation (cross-tissue label consistency)
- Annotation uncertainty quantification (which cells are most ambiguous)

---

## Citation

If you use scAgentKit in your research, please cite:

### Software Citation

```bibtex
@software{scAgentKit2026,
  author = {Kan, Changhao},
  title = {scAgentKit: A human-in-the-loop toolkit for provenance-tracked single-cell RNA-seq analysis},
  year = {2026},
  publisher = {GitHub},
  url = {https://github.com/ChanghaoKan/scAgentKit},
  version = {0.4.0}
}
```

### Dependency Citations

Please also cite the underlying methods:

**Seurat:**
```bibtex
@article{Hao2021,
  title={Integrated analysis of multimodal single-cell data},
  author={Hao, Yuhan and Hao, Stephanie and Andersen-Nissen, Erica and others},
  journal={Cell},
  volume={184},
  number={13},
  pages={3573--3587},
  year={2021},
  publisher={Elsevier}
}
```

**Harmony (if used):**
```bibtex
@article{Korsunsky2019,
  title={Fast, sensitive and accurate integration of single-cell data with Harmony},
  author={Korsunsky, Ilya and Millard, Nghia and Fan, Jean and others},
  journal={Nature Methods},
  volume={16},
  number={12},
  pages={1289--1296},
  year={2019}
}
```

**scDblFinder (if used):**
```bibtex
@article{Germain2021,
  title={Doublet identification in single-cell sequencing data using scDblFinder},
  author={Germain, Pierre-Luc and Lun, Aaron and Garcia Meixide, Carlos and others},
  journal={F1000Research},
  volume={10},
  pages={979},
  year={2021}
}
```

### Example Methods Section

> "Single-cell RNA-seq analysis used scAgentKit v0.4.0 (Kan, 2026) with Seurat v5. Quality-control thresholds, integration variables, clustering parameters, and annotation review procedures were selected by the analysts and recorded with the analysis artifacts. Where language-model assistance was used, we report the provider-returned model identifier, prompts/evidence supplied, and all manual overrides. Generated script snippets and the decision log were reviewed and archived with the package environment and original input-loading code."

---

## Contributing

Contributions can be proposed through GitHub issues or pull requests.

### Areas for Contribution

- 🧬 Additional species support (zebrafish, rat, etc.)
- 🗃️ Curated reference databases (tissue-specific)
- 🔌 New LLM provider integrations
- 📊 Additional visualization functions
- 🧪 Unit tests and benchmarks
- 📚 Documentation improvements
- 🐛 Bug reports and fixes

### Development Setup

```bash
git clone https://github.com/ChanghaoKan/scAgentKit.git
cd scAgentKit

# Install development dependencies
Rscript -e 'install.packages(c("devtools", "testthat", "roxygen2"))'

# Build documentation
Rscript -e 'devtools::document()'

# Run tests
Rscript -e 'devtools::test()'

# Check package
Rscript -e 'devtools::check()'
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Support

- 📧 **Email**: kch_ynu@163.com
- 🐛 **Issues**: [GitHub Issues](https://github.com/ChanghaoKan/scAgentKit/issues)

---

## Acknowledgments

- **Seurat Team** (Satija Lab) for the foundational single-cell analysis framework
- **Harmony Team** (Raychaudhuri Lab) for batch correction methodology
- **scDblFinder Authors** for doublet detection
- **LLM Providers** (DeepSeek, xAI, Anthropic, OpenAI) for API access
- **Shenzhen Bay Laboratory** for institutional support

---

## Related Projects

- [Seurat](https://satijalab.org/seurat/) - Core single-cell analysis framework
- [Scanpy](https://scanpy.readthedocs.io/) - Python alternative
- [CellTypist](https://www.celltypist.org/) - Automated cell type annotation
- [scGPT](https://github.com/bowang-lab/scGPT) - Foundation model for single-cell
- [Azimuth](https://azimuth.hubmapconsortium.org/) - Reference-based annotation

---

<p align="center">
  <strong>Made with ❤️ for the single-cell community</strong><br>
  <sub>Making analysis decisions easier to inspect and review</sub>
</p>
