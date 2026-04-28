#' Fixed-threshold QC filter
#'
#' Applies a conservative floor-filter on the standard QC metrics. Intended
#' to be run *before* MAD-based filtering. Works on either a single Seurat
#' object or a Seurat list (per-sample).
#'
#' @param obj An AgentSeurat object with QC metrics already computed
#'   (see [qc_add_metrics()]).
#' @param min_nCount Minimum UMI count per cell. Default 1000.
#' @param min_nFeature Minimum genes per cell. Default 500.
#' @param max_percent_mt Maximum mitochondrial percentage. Default 50.
#' @param min_percent_mt Optional minimum mitochondrial percentage
#'   (useful for excluding unusual populations). Default 0.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat object with low-quality cells removed.
#'   Cell counts before/after are recorded in the decision log.
#' @export
qc_threshold <- function(obj,
                         min_nCount     = 1000,
                         min_nFeature   = 500,
                         max_percent_mt = 50,
                         min_percent_mt = 0,
                         rationale      = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))

  apply_filter <- function(seu) {
    subset(
      seu,
      subset = nCount_RNA   > min_nCount   &
               nFeature_RNA > min_nFeature &
               percent.mt   < max_percent_mt &
               percent.mt   >= min_percent_mt
    )
  }

  n_before <- .count_cells(obj)
  obj <- .apply_to_data(obj, apply_filter)
  n_after  <- .count_cells(obj)

  script <- sprintf(
'# ---- Fixed-threshold QC filter ----
# Removes cells below a conservative quality floor.
%s',
    if (obj@data_type == "seurat") {
      sprintf(
'seurat_obj <- subset(seurat_obj,
                     subset = nCount_RNA   > %s &
                              nFeature_RNA > %s &
                              percent.mt   < %s &
                              percent.mt   >= %s)',
        min_nCount, min_nFeature, max_percent_mt, min_percent_mt
      )
    } else {
      sprintf(
'seurat_list <- lapply(seurat_list, function(seu) {
  subset(seu,
         subset = nCount_RNA   > %s &
                  nFeature_RNA > %s &
                  percent.mt   < %s &
                  percent.mt   >= %s)
})',
        min_nCount, min_nFeature, max_percent_mt, min_percent_mt
      )
    }
  )

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Fixed-threshold filter: nCount > %s, nFeature > %s, percent.mt in [%s, %s). Removed %d cells (%d -> %d, %.1f%%).",
      min_nCount, min_nFeature, min_percent_mt, max_percent_mt,
      n_before - n_after, n_before, n_after,
      100 * (n_before - n_after) / max(n_before, 1)
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_threshold",
    function_name  = "qc_threshold",
    params         = list(
      min_nCount      = min_nCount,
      min_nFeature    = min_nFeature,
      max_percent_mt  = max_percent_mt,
      min_percent_mt  = min_percent_mt,
      n_before        = n_before,
      n_after         = n_after,
      n_removed       = n_before - n_after
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "qc_threshold_filtered"
  )
}

# Helper: count cells whether data is a single seurat or a list
.count_cells <- function(obj) {
  if (obj@data_type == "seurat") {
    ncol(obj@data)
  } else {
    sum(vapply(obj@data, function(s) as.integer(ncol(s)), integer(1)))
  }
}
