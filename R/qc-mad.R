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
#' For `nCount_RNA` and `nFeature_RNA`, the median/MAD are computed on
#' `log10(x)` rather than the raw counts. These distributions are heavily
#' right-skewed; filtering in linear space systematically discards healthy
#' large cells while the lower bound becomes meaningless (negative). This
#' matches scater::isOutlier(log = TRUE), OSCA, and Pijuan-Sala 2019.
#'
#' For `percent.mt`, `percent.ribo`, and `percent.hb` only the upper bound
#' is applied (removing high-expression outliers), in linear space, as low
#' values for these are biologically benign.
#'
#' For the upper-only percentage metrics the MAD is floored at 1 percentage
#' point. Without it, a metric that is exactly 0 in most cells (for example
#' `percent.hb` in non-blood tissue) has MAD 0 and the band `x <= 0` removes
#' every cell with a single read, while a genuine outlier (60% mt among cells
#' at 5%) is still removed. A count metric whose MAD is zero or not finite in
#' a group is not filtered there; such metrics are recorded in
#' `params$skipped_metrics`. Cells whose `group_by` value is NA form their own
#' group rather than being dropped.
#'
#' @param obj An AgentSeurat object with QC metrics.
#' @param nmad Numeric, number of MADs to allow. Default 3.
#' @param group_by Optional metadata column for grouping (only used when
#'   data_type == "seurat"). If NULL and data is a single Seurat, filtering
#'   is global.
#' @param metrics Character vector of QC metrics to filter on.
#'   Default `c("nCount_RNA", "nFeature_RNA", "percent.mt", "percent.ribo",
#'   "percent.hb")`.
#' @param log_metrics Character vector of metrics to log10-transform
#'   before MAD computation. Default
#'   `c("nCount_RNA", "nFeature_RNA")`. Set to `character(0)` to recover
#'   pre-v0.1.24 linear-space behaviour.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat object.
#' @export
qc_mad <- function(obj,
                   nmad        = 3,
                   group_by    = NULL,
                   metrics     = c("nCount_RNA", "nFeature_RNA",
                                   "percent.mt", "percent.ribo", "percent.hb"),
                   log_metrics = c("nCount_RNA", "nFeature_RNA"),
                   rationale   = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))

  # Upper-bound-only metrics (for these low values are not problematic)
  upper_only <- c("percent.mt", "percent.ribo", "percent.hb")

  skipped <- character(0)
  build_keep <- function(meta, label = "all") {
    keep <- rep(TRUE, nrow(meta))
    for (m in metrics) {
      if (!m %in% colnames(meta)) next
      x_raw <- meta[[m]]
      use_log <- m %in% log_metrics
      # log10(x) is undefined at 0; guard with x > 0. Cells with 0 count
      # would have been removed by qc_threshold already, but be defensive.
      x <- if (use_log) {
        ifelse(x_raw > 0, log10(x_raw), NA_real_)
      } else {
        x_raw
      }
      med <- stats::median(x, na.rm = TRUE)
      mad_val <- stats::mad(x, na.rm = TRUE)
      if (m %in% upper_only) {
        mad_val <- max(mad_val, 1, na.rm = TRUE)
      } else if (!is.finite(mad_val) ||
                 mad_val <= sqrt(.Machine$double.eps) * max(1, abs(med), na.rm = TRUE)) {
        skipped <<- c(skipped, sprintf("%s:%s", label, m))
        next
      }
      if (m %in% upper_only) {
        keep <- keep & (!is.na(x) & x <= med + nmad * mad_val)
      } else {
        keep <- keep &
          (!is.na(x) &
             x >= med - nmad * mad_val &
             x <= med + nmad * mad_val)
      }
    }
    keep
  }

  filter_one <- function(seu, label = "all") {
    meta <- seu@meta.data
    keep <- build_keep(meta, label)
    cells_keep <- rownames(meta)[keep]
    subset(seu, cells = cells_keep)
  }

  filter_grouped <- function(seu, group_col) {
    meta <- seu@meta.data
    values <- meta[[group_col]]
    groups <- unique(values)
    keep_cells <- character(0)
    for (g in groups) {
      in_group <- if (is.na(g)) is.na(values) else !is.na(values) & values == g
      sub_meta <- meta[in_group, , drop = FALSE]
      keep <- build_keep(sub_meta, as.character(g))
      keep_cells <- c(keep_cells, rownames(sub_meta)[keep])
    }
    subset(seu, cells = keep_cells)
  }

  n_before <- .count_cells(obj)

  if (obj@data_type == "seurat_list") {
    labels <- names(obj@data) %||% as.character(seq_along(obj@data))
    obj@data <- Map(filter_one, obj@data, labels)
  } else if (!is.null(group_by)) {
    obj@data <- filter_grouped(obj@data, group_by)
  } else {
    obj@data <- filter_one(obj@data)
  }

  n_after <- .count_cells(obj)

  # Build reproducible script
  metrics_str     <- paste0('c(', paste0('"', metrics, '"',
                                          collapse = ", "), ')')
  log_metrics_str <- paste0('c(', paste0('"', log_metrics, '"',
                                          collapse = ", "), ')')

  if (obj@data_type == "seurat_list") {
    script <- sprintf(
'# ---- MAD-based QC (per sample, %g MADs; log10 on %s) ----
dynamic_filter_single <- function(seu, nmad = %g) {
  meta <- seu@meta.data
  keep <- rep(TRUE, nrow(meta))
  metrics     <- %s
  log_metrics <- %s
  upper_only  <- c("percent.mt", "percent.ribo", "percent.hb")
  for (m in metrics) {
    if (!m %%in%% colnames(meta)) next
    x_raw <- meta[[m]]
    x <- if (m %%in%% log_metrics) ifelse(x_raw > 0, log10(x_raw), NA_real_) else x_raw
    med <- median(x, na.rm = TRUE)
    mad <- mad(x,    na.rm = TRUE)
    if (m %%in%% upper_only) mad <- max(mad, 1, na.rm = TRUE)
    else if (!is.finite(mad) || mad <= sqrt(.Machine$double.eps) * max(1, abs(med), na.rm = TRUE)) next
    if (m %%in%% upper_only) {
      keep <- keep & !is.na(x) & x <= med + nmad * mad
    } else {
      keep <- keep & !is.na(x) & x >= med - nmad * mad & x <= med + nmad * mad
    }
  }
  subset(seu, cells = rownames(meta)[keep])
}
seurat_list <- lapply(seurat_list, dynamic_filter_single)',
      nmad, paste(log_metrics, collapse = "/"),
      nmad, metrics_str, log_metrics_str
    )
  } else {
    script <- sprintf(
'# ---- MAD-based QC (%s, %g MADs; log10 on %s) ----
# See dynamic_filter_single() definition in utils.',
      if (is.null(group_by)) "global" else sprintf("grouped by %s", group_by),
      nmad, paste(log_metrics, collapse = "/")
    )
  }

  if (is.null(rationale)) {
    rationale <- sprintf(
      "MAD filter (%g MADs; log10 on %s) on %s. Removed %d cells (%d -> %d, %.1f%%).",
      nmad,
      if (length(log_metrics) == 0) "(none)" else paste(log_metrics, collapse = "/"),
      paste(metrics, collapse = "/"),
      n_before - n_after, n_before, n_after,
      100 * (n_before - n_after) / max(n_before, 1)
    )
  }

  .record_step(
    obj            = obj,
    step_name      = "qc_mad",
    function_name  = "qc_mad",
    params         = list(
      nmad        = nmad,
      group_by    = group_by,
      metrics     = metrics,
      log_metrics = log_metrics,
      n_before    = n_before,
      n_after     = n_after,
      n_removed   = n_before - n_after,
      skipped_metrics = unique(skipped)
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "qc_mad_filtered"
  )
}
