# =============================================================
# Example: QC pipeline using scAgentKit atomic functions
#
# This example mirrors the Ca_Ctrl workflow:
#   load -> metrics -> plot-before -> split -> threshold -> MAD
#        -> doublet -> remove_genes -> plot-after -> merge
#        -> checkpoint -> export
#
# Every step returns an updated AgentSeurat that accumulates decisions,
# figure paths, and generated R script snippets.
# =============================================================

library(scAgentKit)
library(Seurat)

# ---- 1. Load raw data and wrap in AgentSeurat ----
seu <- readRDS("Ca_Ctrl_merged_JoinLayers_seurat.rds")

obj <- AgentSeurat(
  seu,
  initial_script = 'seurat_obj <- readRDS("Ca_Ctrl_merged_JoinLayers_seurat.rds")'
)
obj

# ---- 2. Add QC metrics ----
obj <- qc_add_metrics(obj, species = "mouse")

# ---- 3. Plot BEFORE filtering ----
obj <- qc_plot(obj, tag = "before", group_by = "sample",
               out_dir = "figures")

# ---- 4. Split by sample for per-sample processing ----
obj <- qc_split(obj, split_by = "sample")

# ---- 5. Fixed-threshold filter (conservative floor) ----
obj <- qc_threshold(
  obj,
  min_nCount     = 1000,
  min_nFeature   = 500,
  max_percent_mt = 50,
  rationale      = "Conservative floor applied before MAD-based dynamic filter."
)

# ---- 6. MAD-based dynamic filter ----
obj <- qc_mad(
  obj,
  nmad     = 3,
  rationale = "Per-sample MAD (3 MADs); upper-only bounds on percent.mt/ribo/hb."
)

# ---- 7. Per-sample doublet detection ----
obj <- qc_doublet(obj, remove = TRUE, seed = 999)

# ---- 8. Remove mt / ribo / hb genes ----
obj <- qc_remove_genes(obj, species = "mouse",
                       remove_mt = TRUE, remove_ribo = TRUE, remove_hb = TRUE)

# ---- 9. Merge back into single object ----
obj <- qc_merge(obj, join_layers = TRUE)

# ---- 10. Plot AFTER filtering ----
obj <- qc_plot(obj, tag = "after", group_by = "sample",
               out_dir = "figures")

# ---- 11. Checkpoint ----
obj <- save_checkpoint(obj, "checkpoints/01_qc_complete.qs")

# ---- 12. Export generated script trace + decision log ----
export_script(obj, "generated_script_trace.R",
              header_comment = "Ca_Ctrl QC pipeline")
export_decisions(obj, "decisions.json")

# ---- Inspect state ----
obj                          # pretty print
get_figures(obj)             # figure registry
length(get_decisions(obj))   # number of steps recorded
cat(substr(get_script(obj), 1, 500))  # peek at generated script
