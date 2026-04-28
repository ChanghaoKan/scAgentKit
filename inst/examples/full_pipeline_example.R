# =============================================================
# Example: Full pipeline from raw Seurat to annotated clusters
#
#   load -> QC -> normalize -> HVG -> scale -> PCA -> select PCs
#        -> Harmony -> UMAP -> neighbors -> cluster sweep
#        -> commit resolution -> find markers -> marker summary
#        -> plot UMAPs -> checkpoint -> export
# =============================================================

library(scAgentKit)
library(Seurat)

# ---- 1. Ingest ----
seu <- readRDS("Ca_Ctrl_merged_JoinLayers_seurat.rds")
obj <- AgentSeurat(seu,
                   initial_script = 'seurat_obj <- readRDS("Ca_Ctrl_merged_JoinLayers_seurat.rds")')

# ---- 2. QC ----
obj <- qc_add_metrics(obj, species = "mouse")
obj <- qc_plot(obj, tag = "before", group_by = "sample")
obj <- qc_split(obj, split_by = "sample")
obj <- qc_threshold(obj, min_nCount = 1000, min_nFeature = 500,
                    max_percent_mt = 50)
obj <- qc_mad(obj, nmad = 3)
obj <- qc_doublet(obj, remove = TRUE, seed = 999)
obj <- qc_remove_genes(obj, species = "mouse")
obj <- qc_merge(obj, join_layers = TRUE)
obj <- qc_plot(obj, tag = "after", group_by = "sample")
obj <- save_checkpoint(obj, "checkpoints/01_qc.qs")

# ---- 3. Normalization / HVG / scaling / PCA ----
obj <- sc_normalize(obj)
obj <- sc_find_hvg(obj, nfeatures = 2000)
obj <- sc_scale(obj)
obj <- sc_pca(obj, npcs = 50)
obj <- sc_select_pcs(obj, threshold = 0.80, plot_elbow = TRUE)
obj <- save_checkpoint(obj, "checkpoints/02_pca.qs")

# ---- 4. Integration (Harmony) ----
# NOTE: group_by_vars is intentionally required. Pick the real batch var
# for your design. If Ca vs Ctrl is a *biological* variable rather than a
# technical batch, do NOT use it here; use the sample or prep-batch ID.
obj <- sc_harmony(obj, group_by_vars = "sample", max_iter = 10)

# ---- 5. Dimension reduction + neighbors ----
obj <- sc_umap(obj)                 # auto-picks harmony reduction
obj <- sc_find_neighbors(obj)       # also auto-picks harmony + ndim
obj <- save_checkpoint(obj, "checkpoints/03_harmony.qs")

# ---- 6. Clustering: sweep, inspect, commit ----
obj <- sc_cluster_sweep(obj, resolutions = seq(0.05, 0.5, 0.05))

# 6a. (Optional) LLM resolution recommendation — vision mode reads the
#     clustree PNG that sc_cluster_sweep just saved. Auto-picks the most
#     recent sweep figure from @figures.
source(system.file("examples", "llm_wrappers.R", package = "scAgentKit"))
chat_fn <- make_chat_fn_anthropic()

obj <- sc_resolution_recommend(
  obj, chat_fn = chat_fn,
  tissue = "mouse colon (Ca vs Ctrl)",
  expected_n_celltypes = c(10, 18),
  vision = TRUE   # send clustree.png alongside the numeric table
)
rec <- obj@params$resolution_recommendation
rec$chosen          # suggested resolution (snapped to sweep grid)
rec$clustree_notes  # what the model saw in the image
rec$reasoning

# Commit — adopt the suggestion or override with your own number.
obj <- sc_cluster(obj, resolution = rec$chosen)

obj <- sc_plot_umap(obj,
                    group_bys = c("seurat_clusters", "sample", "group"))
obj <- save_checkpoint(obj, "checkpoints/04_clustered.qs")

# ---- 7. Markers ----
obj <- sc_find_markers(obj, only_pos = FALSE, min_pct = 0.25,
                       logfc_threshold = 0)
obj <- sc_markers_summary(obj, top_n = 30,
                          log2fc_cut = 1, padj_cut = 0.05,
                          output_path = "markers_top30_per_cluster.txt")
obj <- save_checkpoint(obj, "checkpoints/05_markers.qs")

# ---- 8. Annotation ----
# 8a. Reference overlap: load a curated cell-type reference and match
#     each cluster's top markers against it. Restrict by tissue to
#     avoid hits from irrelevant contexts.
ref <- annot_load_reference(
  path          = "references/cellmarker_mouse.tsv",
  tissue_filter = "colon",
  species       = "mouse"
)
obj <- annot_match_reference(obj, reference = ref, top_n_candidates = 5)

# 8b. LLM reconciliation: for each cluster, send marker list + reference
#     candidates + cluster proportion to the LLM. See
#     inst/examples/llm_wrappers.R for concrete chat_fn implementations.
source(system.file("examples", "llm_wrappers.R", package = "scAgentKit"))
chat_fn <- make_chat_fn_anthropic(model = "claude-sonnet-4-5")  # or openai/ollama

obj <- annot_llm_annotate(
  obj,
  chat_fn            = chat_fn,
  tissue             = "mouse colon (Ca vs Ctrl)",
  condition          = "Tumor vs healthy control",
  expected_celltypes = c("T cell", "B cell", "Plasma cell",
                         "Macrophage", "MDSC", "Enterocyte",
                         "CAF", "Endothelial cell", "Pericyte",
                         "Smooth muscle cell", "Enteric glial cell")
)

# 8c. Inspect LLM output before committing
obj@params$llm_annotations[,
  c("cluster", "primary_annotation", "confidence",
    "recommended_action", "contradicting_markers")]

# 8d. Apply annotations, dropping clusters the LLM flagged 'reject'.
#     Manual overrides win over the LLM if you disagree with any call.
obj <- annot_apply(
  obj,
  source           = "llm",
  drop_rejected    = TRUE,
  manual_overrides = c("3" = "Inflammatory Myeloid cell")  # e.g. MDSC/Neu mix
)

obj <- sc_plot_umap(obj, group_bys = c("cell_type", "group"),
                    tag = "annotated")
obj <- save_checkpoint(obj, "checkpoints/06_annotated.qs")

# ---- 9. Export reproducibility artifacts ----
export_script(obj, "reproducible_script.R",
              header_comment = "Ca_Ctrl full pipeline with annotation")
export_decisions(obj, "decisions.json")

# ---- Inspect ----
obj
get_figures(obj)                      # all figures registered
head(obj@params$markers_filtered)     # filtered + ranked markers
table(obj@data$cell_type)             # final annotation distribution
cat(obj@params$markers_summary[1])    # cluster0:Gene1,Gene2,...
