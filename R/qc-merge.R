#' Merge a Seurat list back into a single Seurat object
#'
#' After per-sample QC and doublet detection, combine the list into a
#' single object for downstream normalization / integration. For Seurat
#' v5, layers are joined via [Seurat::JoinLayers()].
#'
#' @param obj An AgentSeurat object with `data_type == "seurat_list"`.
#' @param join_layers Logical, whether to run `JoinLayers` after merging.
#'   Default TRUE (required for standard Seurat v5 workflows).
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat with `data_type == "seurat"`.
#' @export
qc_merge <- function(obj, join_layers = TRUE, rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat_list") {
    stop("qc_merge requires data_type == 'seurat_list'.")
  }

  seurat_list <- obj@data

  # Auto-detect whether cell names already start with the sample prefix.
  # If they do, do NOT add cell ids again (would create double prefix
  # like "HCC01T_HCC01T_AAACCTGAGGGCATGT" — common with GSE data where
  # the original counts matrix was already in <sample>_<barcode> format).
  sample_names <- names(seurat_list)
  add_ids <- TRUE
  if (!is.null(sample_names) && length(seurat_list) > 0) {
    first_name <- sample_names[1]
    first_cells <- colnames(seurat_list[[1]])
    if (length(first_cells) > 0 &&
        all(startsWith(first_cells, paste0(first_name, "_")))) {
      add_ids <- FALSE
      message(sprintf(
        "[qc_merge] cell names already prefixed with '%s_'; skipping add.cell.ids.",
        first_name
      ))
    }
  }

  combined <- if (add_ids) {
    merge(
      x            = seurat_list[[1]],
      y            = seurat_list[-1],
      add.cell.ids = sample_names
    )
  } else {
    merge(x = seurat_list[[1]], y = seurat_list[-1])
  }
  if (join_layers) {
    combined[["RNA"]] <- SeuratObject::JoinLayers(combined[["RNA"]])
  }

  obj@data      <- combined
  obj@data_type <- "seurat"

  script <- sprintf(
'# ---- Merge per-sample objects ----
combined_seurat <- merge(x = seurat_list[[1]],
                         y = seurat_list[-1],
                         add.cell.ids = names(seurat_list))
%s',
    if (join_layers) 'combined_seurat[["RNA"]] <- JoinLayers(combined_seurat[["RNA"]])' else ''
  )

  n_cells <- ncol(combined)
  if (is.null(rationale)) {
    rationale <- sprintf(
      "Merged %d samples into a single Seurat object (%d cells total)%s.",
      length(seurat_list), n_cells,
      if (join_layers) "; layers joined for Seurat v5 compatibility" else ""
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_merge",
    function_name  = "qc_merge",
    params         = list(join_layers = join_layers, n_samples = length(seurat_list),
                          n_cells = n_cells),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "merged"
  )
}
