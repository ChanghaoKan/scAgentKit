#' MAD-based dynamic QC filter
#'
#' Applies a median +/- n*MAD filter on the standard QC metrics, adapting
#' thresholds to each sample's empirical distribution. This is the
#' recommended second-stage filter after [qc_threshold()].
#'
#' When `data_type == "seurat_list"`, MAD is computed within each element
#' (per-sample). When `data_type == "seurat"` and `group_by` is supplied,
#' MAD is computed within each group of the metadata column. When
#' `data_type == "seurat"` and `group_by` is NULL, MAD is computed globally.
#'
#' For `percent.mt`, `percent.ribo`, and `percent.hb` only the upper bound
#' is applied (removing high-expression outliers), as low values for these
#' are biologically benign.
#'
#' @param obj An AgentSeurat object with QC metrics.
#' @param nmad Numeric, number of MADs to allow. Default 3.
#' @param group_by Optional metadata column for grouping (only used when
#'   data_type == "seurat"). If NULL and data is a single Seurat, filtering
#'   is global.
#' @param metrics Character vector of QC metrics to filter on.
#'   Default `c("nCount_RNA", "nFeature_RNA", "percent.mt", "percent.ribo",
#'   "percent.hb")`.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat object.
#' @export
qc_mad <- function(obj,
                   nmad       = 3,
                   group_by   = NULL,
                   metrics    = c("nCount_RNA", "nFeature_RNA",
                                  "percent.mt", "percent.ribo", "percent.hb"),
                   rationale  = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))

  # Upper-bound-only metrics (for these low values are not problematic)
  upper_only <- c("percent.mt", "percent.ribo", "percent.hb")

  build_keep <- function(meta) {
    keep <- rep(TRUE, nrow(meta))
    for (m in metrics) {
      if (!m %in% colnames(meta)) next
      x <- meta[[m]]
      med <- stats::median(x, na.rm = TRUE)
      mad_val <- stats::mad(x, na.rm = TRUE)
      if (m %in% upper_only) {
        keep <- keep & (x <= med + nmad * mad_val)
      } else {
        keep <- keep & (x >= med - nmad * mad_val) & (x <= med + nmad * mad_val)
      }
    }
    keep
  }

  filter_one <- function(seu) {
    meta <- seu@meta.data
    keep <- build_keep(meta)
    cells_keep <- rownames(meta)[keep]
    subset(seu, cells = cells_keep)
  }

  filter_grouped <- function(seu, group_col) {
    meta <- seu@meta.data
    groups <- unique(meta[[group_col]])
    keep_cells <- character(0)
    for (g in groups) {
      sub_meta <- meta[meta[[group_col]] == g, , drop = FALSE]
      keep <- build_keep(sub_meta)
      keep_cells <- c(keep_cells, rownames(sub_meta)[keep])
    }
    subset(seu, cells = keep_cells)
  }

  n_before <- .count_cells(obj)

  if (obj@data_type == "seurat_list") {
    obj@data <- lapply(obj@data, filter_one)
  } else if (!is.null(group_by)) {
    obj@data <- filter_grouped(obj@data, group_by)
  } else {
    obj@data <- filter_one(obj@data)
  }

  n_after <- .count_cells(obj)

  # Build reproducible script
  metrics_str <- paste0('c(', paste0('"', metrics, '"', collapse = ", "), ')')

  if (obj@data_type == "seurat_list") {
    script <- sprintf(
'# ---- MAD-based QC (per sample, %d MADs) ----
dynamic_filter_single <- function(seu, nmad = %d) {
  meta <- seu@meta.data
  keep <- rep(TRUE, nrow(meta))
  metrics    <- %s
  upper_only <- c("percent.mt", "percent.ribo", "percent.hb")
  for (m in metrics) {
    if (!m %%in%% colnames(meta)) next
    x   <- meta[[m]]
    med <- median(x, na.rm = TRUE)
    mad <- mad(x,    na.rm = TRUE)
    if (m %%in%% upper_only) {
      keep <- keep & (x <= med + nmad * mad)
    } else {
      keep <- keep & (x >= med - nmad * mad) & (x <= med + nmad * mad)
    }
  }
  subset(seu, cells = rownames(meta)[keep])
}
seurat_list <- lapply(seurat_list, dynamic_filter_single)',
      nmad, nmad, metrics_str
    )
  } else {
    script <- sprintf(
'# ---- MAD-based QC (%s, %d MADs) ----
# See dynamic_filter_single() definition in utils.',
      if (is.null(group_by)) "global" else sprintf("grouped by %s", group_by),
      nmad
    )
  }

  if (is.null(rationale)) {
    rationale <- sprintf(
      "MAD filter (%d MADs) on %s. Removed %d cells (%d -> %d, %.1f%%).",
      nmad, paste(metrics, collapse = "/"),
      n_before - n_after, n_before, n_after,
      100 * (n_before - n_after) / max(n_before, 1)
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_mad",
    function_name  = "qc_mad",
    params         = list(
      nmad      = nmad,
      group_by  = group_by,
      metrics   = metrics,
      n_before  = n_before,
      n_after   = n_after,
      n_removed = n_before - n_after
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "qc_mad_filtered"
  )
}
