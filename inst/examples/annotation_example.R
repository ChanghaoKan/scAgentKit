# =============================================================
# Example: Annotation-only workflow, starting from a post-marker checkpoint
#
# Use case: markers are already computed, you want to iterate on the
# reference / tissue context / LLM model without re-running QC+PCA+cluster.
#
# Workflow:
#   load checkpoint -> load reference -> match -> LLM annotate
#                   -> review -> apply -> plot
# =============================================================

library(scAgentKit)

# ---- 1. Resume from the post-markers checkpoint ----------------------------
obj <- load_checkpoint("checkpoints/05_markers.qs")
obj  # inspect stage / decisions so far

# ---- 2. Load reference -----------------------------------------------------
# Minimal file format: TSV with columns cell_type, marker (optionally
# tissue, source). One row per (cell_type, marker) pair. Build your own from
# CellMarker 2.0, PanglaoDB, ACT exports, or domain curation.
ref <- annot_load_reference(
  path          = "references/cellmarker_mouse.tsv",
  tissue_filter = "colon",
  species       = "mouse"
)

# ---- 3. Reference overlap scoring ------------------------------------------
obj <- annot_match_reference(obj, reference = ref, top_n_candidates = 5)

# Inspect per-cluster candidates
head(obj@params$reference_matches, 20)

# ---- 4. Build a chat_fn (pick any one) -------------------------------------
source(system.file("examples", "llm_wrappers.R", package = "scAgentKit"))

chat_fn <- make_chat_fn_anthropic(model = "claude-sonnet-4-5")
# chat_fn <- make_chat_fn_openai(model   = "gpt-4o-mini")
# chat_fn <- make_chat_fn_deepseek()
# chat_fn <- make_chat_fn_ollama(model   = "llama3.1:70b")    # fully local
# chat_fn <- make_chat_fn_mock("T cell")                      # dry run

# ---- 5. LLM annotation -----------------------------------------------------
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

# ---- 6. Review LLM output --------------------------------------------------
# Review fields: primary_annotation, confidence, contradicting_markers,
# recommended_action. Flagged clusters deserve a closer look.
ann <- obj@params$llm_annotations
print(ann[, c("cluster", "primary_annotation", "confidence",
              "recommended_action", "contradicting_markers")])

# Convenience: show only flagged / uncertain calls
flagged <- ann[ann$recommended_action %in% c("flag_for_review", "reject") |
                 ann$confidence == "low", ]
print(flagged)

# ---- 7. (Optional) Re-annotate specific clusters ---------------------------
# You can re-run only particular clusters after refining the prompt or
# after swapping the reference database.
# obj <- annot_llm_annotate(obj, chat_fn = chat_fn,
#                           tissue = "mouse colon",
#                           clusters = c("3", "11"))

# ---- 8. Apply annotations --------------------------------------------------
# drop_rejected drops clusters flagged 'reject' (e.g. the cluster17
# pancreatic-contamination case from the original Ca_Ctrl analysis).
# manual_overrides always win over the LLM call.
obj <- annot_apply(
  obj,
  source           = "llm",
  drop_rejected    = TRUE,
  manual_overrides = c("3" = "Inflammatory Myeloid cell")
)

# ---- 9. Inspect and plot ---------------------------------------------------
table(obj@data$cell_type)
obj <- sc_plot_umap(obj, group_bys = "cell_type", tag = "annotated")
obj <- sc_plot_umap(obj, group_bys = "cell_type", split_by = "group",
                    tag = "by_group")

# ---- 10. Checkpoint + export -----------------------------------------------
obj <- save_checkpoint(obj, "checkpoints/06_annotated.qs")
export_script(obj,    "reproducible_script.R")
export_decisions(obj, "decisions.json")
