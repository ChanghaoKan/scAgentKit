# =============================================================
# BRCA single-cell pipeline using scAgentKit
#
# Adapts the user's existing data-loading code to feed an AgentSeurat
# container, then runs the full pipeline with LLM assistance for
# (a) batch-variable selection, (b) resolution selection, and
# (c) cell-type annotation.
#
# Run from a directory that contains:
#   sparse_matrix_BRCA.mtx
#   geneinfo_BRCA.csv
#   cellinfo_BRCA.csv
# =============================================================

# ---- 0. Setup ---------------------------------------------------------------
library(Matrix)
library(Seurat)
library(qs)
library(future)
library(dplyr)
library(ggplot2)
library(scAgentKit)

# Parallel + memory (you already had this; tweak workers to your machine)
plan(multisession, workers = 32)
options(future.globals.maxSize = 100 * 1024^3)   # 100 GB

# Set the API key in the SHELL or in ~/.Renviron, NOT in this script:
#   echo 'ANTHROPIC_API_KEY=sk-ant-...' >> ~/.Renviron
#   ## or DEEPSEEK_API_KEY / OPENAI_API_KEY etc.
# Restart R after editing .Renviron so Sys.getenv() picks it up.

# ---- 1. Load the BRCA matrices and build a Seurat object -------------------
count_matrix <- readMM("sparse_matrix_BRCA.mtx")
count_matrix <- t(count_matrix)             # genes x cells (Seurat convention)

gene_info <- read.csv("geneinfo_BRCA.csv", row.names = 1)
cell_info <- read.csv("cellinfo_BRCA.csv", row.names = 1)
rownames(count_matrix) <- rownames(gene_info)
colnames(count_matrix) <- rownames(cell_info)

seurat_obj <- CreateSeuratObject(counts = count_matrix, meta.data = cell_info)

# Wrap in AgentSeurat. The initial_script will be prepended to the
# auto-generated reproducible_script.R later.
obj <- AgentSeurat(
  seurat_obj,
  initial_script = '
# ---- Load BRCA matrices into a Seurat object ----
count_matrix <- t(readMM("sparse_matrix_BRCA.mtx"))
gene_info  <- read.csv("geneinfo_BRCA.csv", row.names = 1)
cell_info  <- read.csv("cellinfo_BRCA.csv", row.names = 1)
rownames(count_matrix) <- rownames(gene_info)
colnames(count_matrix) <- rownames(cell_info)
seurat_obj <- CreateSeuratObject(counts = count_matrix, meta.data = cell_info)
'
)
obj   # quick sanity print

# Inspect available metadata columns (helpful before batch-var selection)
colnames(obj@data@meta.data)
# e.g. "Batch.Set.ID", "Patient.ID", "tumor_subtype", "Sex", ...

# ---- 2. Configure an LLM chat function -------------------------------------
# Pick ONE provider. Anthropic is recommended for vision (clustree).
source(system.file("examples", "llm_wrappers.R", package = "scAgentKit"))

# Default: Anthropic (needs ANTHROPIC_API_KEY in env)
chat_fn <- make_chat_fn_anthropic(model = "claude-sonnet-4-5")

# Alternatives — uncomment whichever you prefer:
# chat_fn <- make_chat_fn_openai(model   = "gpt-4o-mini")             # OPENAI_API_KEY
# chat_fn <- make_chat_fn_deepseek()                                   # DEEPSEEK_API_KEY (text-only, no vision)
# chat_fn <- make_chat_fn_ollama(model   = "qwen2-vl:7b",              # local, supports vision
#                                supports_vision = TRUE)
# chat_fn <- make_chat_fn_mock()                                       # dry-run, no network

# ---- 3. QC -----------------------------------------------------------------
obj <- qc_add_metrics(obj, species = "human")    # BRCA -> human; uses ^MT- pattern
obj <- qc_plot(obj, tag = "before",
               group_by = "Batch.Set.ID",         # change to whichever column you have
               out_dir  = "figures")

# Per-sample QC requires splitting by a per-sample column. For BRCA
# multi-donor data this is typically a patient/sample ID, NOT the
# treatment/subtype column.
obj <- qc_split(obj, split_by = "Batch.Set.ID")   # adjust to your column

obj <- qc_threshold(obj,
                    min_nCount     = 1000,
                    min_nFeature   = 500,
                    max_percent_mt = 25)           # tumor data; 25 is often saner than 50
obj <- qc_mad(obj, nmad = 3)
obj <- qc_doublet(obj, remove = TRUE)              # per-sample, v5-safe
obj <- qc_remove_genes(obj, species = "human")     # drops MT-/RPS/RPL/HBA/HBB
obj <- qc_merge(obj, join_layers = TRUE)           # v5: joins layers automatically

obj <- qc_plot(obj, tag = "after", group_by = "Batch.Set.ID")
obj <- save_checkpoint(obj, "checkpoints/01_qc.qs")

# ---- 4. Normalization, HVG, scaling, PCA -----------------------------------
obj <- sc_normalize(obj)
obj <- sc_find_hvg(obj, n_features = 2000)

# Optional: cell-cycle scoring. Inspect Phase distribution before deciding
# to regress. With BRCA you almost always want the proliferating signal
# (tumor cells cycle), so prefer mode = "difference" if you regress at all.
obj <- sc_cellcycle_score(obj, species = "human")
table(obj@data$Phase)

obj <- sc_scale(obj)
# If after first UMAP you find clustering driven by Phase, re-run from here:
#   obj <- sc_cellcycle_regress(obj, mode = "difference")
#   obj <- sc_pca(obj); obj <- sc_select_pcs(obj); ...

obj <- sc_pca(obj)
obj <- sc_select_pcs(obj, threshold = 0.80)        # also saves elbow plot

# ---- 5. Choose the batch variable (LLM-assisted) ---------------------------
# Instead of hard-coding `group_by_vars = "sample"`, score every metadata
# column and let the LLM pick. The function returns a table; the LLM
# pick is stored at obj@params$batch_recommendation.
obj <- sc_select_batch_var(
  obj,
  chat_fn = chat_fn,
  tissue  = "human breast cancer scRNA-seq, multiple donors / batches"
)

print(obj@params$batch_candidates)        # the scored table
rec <- obj@params$batch_recommendation
rec$recommended    # e.g. "Batch.Set.ID"
rec$confidence
rec$reasoning
rec$warnings       # any concerns the LLM flagged

# You can accept the recommendation or override:
batch_var <- rec$recommended
# batch_var <- "Patient.ID"            # manual override example

# ---- 6. Harmony integration + UMAP -----------------------------------------
obj <- sc_harmony(obj, group_by_vars = batch_var)
obj <- sc_umap(obj)
obj <- sc_find_neighbors(obj)

# ---- 7. Resolution sweep + LLM recommendation (vision) ---------------------
obj <- sc_cluster_sweep(obj, resolutions = seq(0.1, 1.0, 0.1))

obj <- sc_resolution_recommend(
  obj, chat_fn = chat_fn,
  tissue = "human breast cancer scRNA-seq",
  expected_n_celltypes = c(10, 20),     # rough prior; not strict
  vision = TRUE                          # auto-attaches the clustree PNG
)
rec_res <- obj@params$resolution_recommendation
rec_res$chosen
rec_res$clustree_notes
rec_res$reasoning

obj <- sc_cluster(obj, resolution = rec_res$chosen)
obj <- sc_plot_umap(obj, group_bys = c("seurat_clusters", batch_var))
obj <- save_checkpoint(obj, "checkpoints/02_clustered.qs")

# ---- 8. Markers + annotation -----------------------------------------------
obj <- sc_find_markers(obj)
obj <- sc_markers_summary(obj, top_n = 30,
                          output_path = "markers_top30.txt")

# Pull a breast-tissue reference straight from CellMarker 2.0 (cached
# after first download)
ref <- annot_query_cellmarker(
  species     = "human",
  tissue      = "breast",
  cancer_only = FALSE
)

obj <- annot_match_reference(obj, reference = ref, top_n_candidates = 5)

obj <- annot_llm_annotate(
  obj,
  chat_fn = chat_fn,
  tissue  = "human breast tumor microenvironment",
  expected_celltypes = c(
    "Epithelial cell", "Cancer cell", "T cell", "B cell", "Plasma cell",
    "Macrophage", "Dendritic cell", "Endothelial cell",
    "CAF", "Pericyte", "Mast cell", "NK cell"
  )
)

# Review LLM calls before applying — particularly any flagged ones
ann <- obj@params$llm_annotations
print(ann[, c("cluster", "primary_annotation", "confidence",
              "recommended_action", "contradicting_markers")])

obj <- annot_apply(obj, source = "llm", drop_rejected = TRUE)
obj <- sc_plot_umap(obj, group_bys = "cell_type", tag = "annotated")
obj <- save_checkpoint(obj, "checkpoints/03_annotated.qs")

# ---- 9. Export everything --------------------------------------------------
export_script(obj, "reproducible_script.R",
              header_comment = "BRCA scAgentKit pipeline")
export_decisions(obj, "decisions.json")
report_html(obj, path = "BRCA_report.html",
            title = "BRCA scRNA-seq analysis report")
