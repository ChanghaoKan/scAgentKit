#' Split a Seurat object by a metadata column
#'
#' Splits the underlying Seurat object into a named list of Seurat objects
#' according to `split_by` (typically `"sample"`). This is the standard
#' preparation for per-sample doublet detection with scDblFinder and for
#' per-sample MAD-based QC. Updates `@@data_type` to `"seurat_list"`.
#'
#' @param obj An AgentSeurat object containing a single Seurat object
#'   (`data_type == "seurat"`).
#' @param split_by Character, the metadata column to split on.
#'   Defaults to `"sample"`.
#' @param rationale Optional LLM-supplied rationale string.
#'
#' @return Updated AgentSeurat object with `data_type == "seurat_list"`.
#' @export
qc_split <- function(obj,
                     split_by  = NULL,
                     rationale = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  if (obj@data_type != "seurat") {
    stop("qc_split expects data_type == 'seurat' (already split).")
  }

  seu <- obj@data

  # Auto-detect a sample/batch column if not supplied
  if (is.null(split_by)) {
    detected <- .detect_sample_col(seu@meta.data)
    if (is.na(detected)) {
      stop("Could not auto-detect a sample column. Pass split_by explicitly. ",
           "Available columns: ",
           paste(colnames(seu@meta.data), collapse = ", "))
    }
    split_by <- detected
    message(sprintf("[qc_split] auto-detected split_by = '%s'", split_by))
  }

  if (!split_by %in% colnames(seu@meta.data)) {
    stop(sprintf("Metadata column '%s' not found. Available: %s",
                 split_by,
                 paste(colnames(seu@meta.data), collapse = ", ")))
  }

  seurat_list <- Seurat::SplitObject(seu, split.by = split_by)
  obj@data       <- seurat_list
  obj@data_type  <- "seurat_list"

  n_per_sample <- vapply(seurat_list, function(s) as.integer(ncol(s)), integer(1))
  sample_summary <- paste(
    sprintf("%s=%d", names(n_per_sample), n_per_sample),
    collapse = ", "
  )

  script <- sprintf(
'# ---- Split by %s ----
seurat_list <- SplitObject(seurat_obj, split.by = "%s")
sapply(seurat_list, ncol)  # sanity check',
    split_by, split_by
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Split by '%s' into %d groups for per-sample processing (MAD QC / doublet detection). Cell counts: %s",
      split_by, length(seurat_list), sample_summary
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_split",
    function_name  = "qc_split",
    params         = list(split_by = split_by, n_groups = length(seurat_list),
                          cells_per_group = as.list(n_per_sample)),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "split_by_sample"
  )
}
