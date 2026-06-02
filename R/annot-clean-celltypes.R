#' Clean and filter cell type annotations (with optional vision judgment)
#'
#' Merges singular/plural variants, flags or removes low-quality clusters
#' (very small clusters are often contaminants/doublets), and optionally
#' uses vision to let the LLM visually judge cluster quality from the UMAP.
#'
#' @param obj An AgentSeurat object after [annot_apply()].
#' @param merge_plural Logical. Merge singular/plural names
#'   (Macrophages -> Macrophage, T cells -> T cell, etc.). Default TRUE.
#' @param min_cells Integer. Clusters with fewer than this many cells
#'   are considered low-quality. Default 50.
#' @param action Character. What to do with low-quality clusters:
#'   `"flag"` (default), `"remove"`, or `"keep"`.
#' @param vision Logical. If TRUE, generate UMAP and ask vision-capable LLM
#'   to judge whether small clusters are real or contaminants.
#' @param chat_fn Vision-capable chat function (required when `vision = TRUE`).
#' @param tissue Tissue context passed to LLM (e.g. "mouse colorectal cancer").
#' @param rationale Optional custom rationale string.
#'
#' @return Updated AgentSeurat with cleaned `cell_type` and
#'   `cell_type_quality` columns.
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

  # ====================== 1. Merge singular/plural naming ======================
  if (isTRUE(merge_plural)) {
    ct <- gsub("s$", "", ct)
    ct <- gsub(" cells$", " cell", ct)
    ct <- gsub("Macrophages", "Macrophage", ct)
    ct <- gsub("T cells", "T cell", ct)
    ct <- gsub("B cells", "B cell", ct)
    ct <- gsub("Neutrophils", "Neutrophil", ct)
    ct <- gsub("Fibroblasts", "Fibroblast", ct)
    message("[annot_clean_celltypes] Merged singular/plural names.")
  }

  # ====================== 2. Identify low-quality cluster ======================
  cell_counts <- table(ct)
  small_types <- names(cell_counts[cell_counts < min_cells])

  if (length(small_types) == 0) {
    message("[annot_clean_celltypes] No low-quality clusters found.")
    obj@data@meta.data$cell_type <- ct
    return(obj)
  }

  # ====================== 3. Vision judgment (core new addition) ======================
  if (isTRUE(vision)) {
    if (is.null(chat_fn)) {
      stop("`chat_fn` is required when vision = TRUE.")
    }

    message("[annot_clean_celltypes] Generating UMAP for vision judgment...")

    # Highlight low-quality cluster UMAP
    obj@data@meta.data$quality_highlight <- ifelse(ct %in% small_types,
                                                   "Low quality candidate",
                                                   "Normal")

    p <- Seurat::DimPlot(obj@data,
                         reduction = "umap",
                         group.by  = "quality_highlight",
                         pt.size   = 0.4,
                         cols      = c("Low quality candidate" = "red",
                                       "Normal" = "grey80")) +
         ggplot2::ggtitle("Low-quality clusters (red) vs Normal (grey)") +
         ggplot2::theme_classic()

    dir.create("figures", showWarnings = FALSE)
    vision_path <- "figures/low_quality_clusters_umap.png"
    ggplot2::ggsave(vision_path, p, width = 8, height = 6, dpi = 150)

    # Build prompt
    system_prompt <- paste(
      "You are an expert single-cell analyst. Look at the UMAP image.",
      "Red points are candidate low-quality clusters (very small cell numbers).",
      "Decide for each red group whether it is:",
      "1. Real but rare cell type (keep)",
      "2. Likely contamination, doublet, or technical artifact (remove or flag)",
      "Return ONLY a JSON object with this format:",
      '{"decision": "flag" | "remove" | "keep",',
      ' "reasoning": "<1-2 sentences explaining what you see>"}'
    )

    user_prompt <- sprintf(
      "Tissue: %s. There are %d low-quality candidate clusters (red).",
      tissue %||% "unknown", length(small_types)
    )

    # Call vision LLM
    parsed <- tryCatch(
      chat_fn(system_prompt, user_prompt, image_path = vision_path),
      error = function(e) {
        warning("Vision call failed: ", conditionMessage(e))
        NULL
      }
    )

    if (!is.null(parsed)) {
      # Simple parse (can enhance as needed)
      if (grepl("remove", parsed, ignore.case = TRUE)) {
        action <- "remove"
      } else if (grepl("keep", parsed, ignore.case = TRUE)) {
        action <- "keep"
      } else {
        action <- "flag"
      }
      message(sprintf("[annot_clean_celltypes] LLM vision decision: %s", action))
    }
  }

  # ====================== 4. Execute final operation ======================
  if (action == "flag") {
    ct[ct %in% small_types] <- paste0(ct[ct %in% small_types], " (Low quality)")
    message(sprintf("[annot_clean_celltypes] Flagged %d low-quality types.", length(small_types)))
  } else if (action == "remove") {
    keep <- !(ct %in% small_types)
    obj@data <- obj@data[, keep]
    ct <- ct[keep]
    message(sprintf("[annot_clean_celltypes] Removed %d low-quality types.", length(small_types)))
  }

  obj@data@meta.data$cell_type <- ct

  # ====================== 5. Record decision ======================
  if (is.null(rationale)) {
    rationale <- sprintf(
      "Cleaned cell type names (merge_plural=%s). %s clusters with < %d cells (vision=%s).",
      merge_plural, action, min_cells, vision
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
    script_snippet = "# ---- Clean cell type names + quality filter (with optional vision) ----"
  )

  obj
}
