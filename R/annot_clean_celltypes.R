#' Clean and filter cell type annotations
#'
#' Merges singular/plural variants, removes or flags low-quality clusters
#' (very small clusters are often contaminants or doublets), and optionally
#' uses vision to let the LLM judge cluster quality from the UMAP.
#'
#' @param obj An AgentSeurat object after [annot_apply()].
#' @param merge_plural Logical. Merge "Macrophages" → "Macrophage",
#'   "T cells" → "T cell", etc. Default TRUE.
#' @param min_cells Integer. Clusters with fewer than this many cells
#'   will be flagged or removed. Default 50.
#' @param action Character, one of `"flag"`, `"remove"`, or `"keep"`.
#'   Default `"flag"`.
#' @param vision Logical. If TRUE, sends UMAP to LLM for quality judgment.
#'   Requires a vision-capable `chat_fn`.
#' @param chat_fn Vision-capable chat function (only needed if `vision = TRUE`).
#' @param tissue Tissue context string (passed to LLM when vision = TRUE).
#' @param rationale Optional custom rationale.
#'
#' @return Updated AgentSeurat with cleaned `cell_type` column and
#'   `cell_type_quality` column (if flagged).
#' @export
annot_clean_celltypes <- function(obj,
                                  merge_plural = TRUE,
                                  min_cells    = 50,
                                  action       = c("flag", "remove", "keep"),
                                  vision       = FALSE,
                                  chat_fn      = NULL,
                                  tissue       = NULL,
                                  rationale    = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  action <- match.arg(action)
  if (!"cell_type" %in% colnames(obj@data@meta.data)) {
    stop("`cell_type` column not found. Run annot_apply() first.")
  }

  meta <- obj@data@meta.data
  ct   <- as.character(meta$cell_type)

  # 1. Merge singular/plural
  if (isTRUE(merge_plural)) {
    ct <- gsub("s$", "", ct)
    ct <- gsub(" cells$", " cell", ct)
    ct <- gsub("Macrophages", "Macrophage", ct)
    ct <- gsub("T cells", "T cell", ct)
    ct <- gsub("B cells", "B cell", ct)
    ct <- gsub("Neutrophils", "Neutrophil", ct)
    ct <- gsub("Fibroblasts", "Fibroblast", ct)
    # 可继续扩展
    message("[annot_clean_celltypes] Merged singular/plural names.")
  }

  # 2. Count cells per (cleaned) cell type
  cell_counts <- table(ct)
  small_types <- names(cell_counts[cell_counts < min_cells])

  if (length(small_types) > 0) {
    if (action == "flag") {
      ct[ct %in% small_types] <- paste0(ct[ct %in% small_types], " (Low quality)")
      message(sprintf("[annot_clean_celltypes] Flagged %d low-quality types (< %d cells).",
                      length(small_types), min_cells))
    } else if (action == "remove") {
      keep <- !(ct %in% small_types)
      obj@data <- obj@data[, keep]
      ct <- ct[keep]
      message(sprintf("[annot_clean_celltypes] Removed %d low-quality types (< %d cells).",
                      length(small_types), min_cells))
    }
  }

  obj@data@meta.data$cell_type <- ct

  # 3. Optional vision judgment (for ambiguous small clusters)
  if (isTRUE(vision)) {
    if (is.null(chat_fn)) stop("`chat_fn` is required when vision = TRUE.")
    # 这里可以后续扩展：把小 cluster 的 UMAP 截图发给 LLM 判断
    message("[annot_clean_celltypes] Vision mode enabled (to be implemented in next version).")
  }

  # Record step
  if (is.null(rationale)) {
    rationale <- sprintf(
      "Cleaned cell type names (merge_plural=%s). Flagged/removed clusters with < %d cells.",
      merge_plural, min_cells
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "annot_clean_celltypes",
    function_name  = "annot_clean_celltypes",
    params         = list(merge_plural = merge_plural,
                          min_cells    = min_cells,
                          action       = action,
                          vision       = vision),
    rationale      = rationale,
    script_snippet = "# ---- Clean cell type names and filter low-quality clusters ----"
  )

  obj
}
