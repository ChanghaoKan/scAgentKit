# =============================================================
# Example: Using annot_query_cellmarker() + report_html()
#
# Shows how to (a) query CellMarker 2.0 directly and (b) generate an HTML
# review report at the end of a pipeline.
# =============================================================

library(scAgentKit)

# ---- 1. Resume from a post-markers checkpoint ------------------------------
obj <- load_checkpoint("checkpoints/05_markers.qs")

# ---- 2. Query CellMarker 2.0 directly --------------------------------------
# First call downloads and caches the XLSX (~50 MB). Subsequent calls
# are instant. Filters by species and tissue substring match.
ref <- annot_query_cellmarker(
  species     = "mouse",
  tissue      = "colon",    # case-insensitive substring match
  cancer_only = FALSE       # include normal + cancer entries
)

# Inspect the reference we just built
nrow(ref)
length(unique(ref$cell_type))
head(ref)

# If the cache goes stale / you want a fresh copy:
# annot_clear_cache()

# You can combine CellMarker with a custom TSV by rbind'ing:
# custom <- annot_load_reference("my_curated.tsv", tissue_filter = "colon")
# ref <- unique(rbind(ref[, colnames(custom)], custom))

# ---- 3. Use it in the normal annotation flow ------------------------------
obj <- annot_match_reference(obj, reference = ref, top_n_candidates = 5)

chat_fn <- chat_claude()

obj <- annot_llm_annotate(
  obj,
  chat_fn = chat_fn,
  tissue  = "mouse colon (Ca vs Ctrl)"
)
obj <- annot_apply(obj, source = "llm", drop_rejected = FALSE)
obj <- sc_plot_umap(obj, group_bys = "cell_type", tag = "annotated")

# ---- 4. Generate an HTML review report ------------------------------------
# Review the report and its provenance metadata before sharing or archiving it.
report_html(
  obj,
  path  = "analysis_report.html",
  title = "Ca vs Ctrl mouse colon scRNA-seq"
)

# Sections in the output:
#   - Overview (stage, cell/gene count, timestamps)
#   - Resolution recommendation (if sc_resolution_recommend was run)
#   - Decision log (every parameter, timestamp, rationale)
#   - Figure gallery (all PNGs embedded as base64)
#   - LLM annotations (cluster, annotation, confidence,
#     supporting/contradicting markers, action, reasoning)
#   - Generated R script trace (review before execution)

# ---- 5. Also emit the plain-text artifacts (complementary) ----------------
export_script(obj,    "generated_script_trace.R")
export_decisions(obj, "decisions.json")
save_checkpoint(obj,  "checkpoints/06_annotated.qs")
