# Sample medians are observations here; this is distinct from cell-wise MAD.
.sc_run_sample_qc_comparison <- function(metrics) {
  if (!is.data.frame(metrics) || !"sample" %in% names(metrics))
    return(list(status = "unavailable", reason = "No explicitly declared sample column; capture/condition are not substituted."))
  samples <- as.character(metrics$sample)
  if (anyNA(samples) || any(!nzchar(samples))) stop("Sample QC requires complete sample IDs.", call. = FALSE)
  ids <- sort(unique(samples), method = "radix")
  rows <- lapply(ids, function(id) {
    selected <- samples == id
    medians <- lapply(c("nCount", "nFeature", "percent_mt"), function(key) {
      x <- metrics[[key]][selected]
      if (is.null(x) || !length(x) || any(!is.finite(x))) NULL else stats::median(x)
    }); names(medians) <- c("nCount", "nFeature", "percent_mt")
    list(sample = id, cells = sum(selected), medians = medians)
  })
  contrasts <- lapply(c("nCount", "nFeature", "percent_mt"), function(key) {
    values <- vapply(rows, function(row) if (is.null(row$medians[[key]])) NA_real_ else row$medians[[key]], numeric(1))
    valid <- is.finite(values) & values >= 0
    transformed <- if (key == "percent_mt") values else log10(values + 1)
    available <- length(ids) >= 5L && all(valid)
    center <- if (any(valid)) stats::median(transformed[valid]) else NULL
    spread <- if (any(valid)) stats::mad(transformed[valid], center = center, constant = 1.4826) else NULL
    if (is.null(spread) || !is.finite(spread) || spread <= sqrt(.Machine$double.eps)) available <- FALSE
    score <- if (available) (transformed - center) / spread else rep(NA_real_, length(ids))
    list(metric = key, status = if (available) "descriptive_flags" else "unavailable",
      center = center, scaled_mad = spread,
      reason = if (available) NULL else "At least five comparable samples, complete metrics and nonzero between-sample MAD are required.",
      samples = lapply(seq_along(ids), function(i) list(sample = ids[i], median = if(valid[i]) values[i] else NULL,
        robust_z = if(available) score[i] else NULL, flagged = if(available) abs(score[i]) > 3 else NULL)))
  })
  list(status = "measured", unit = "one median per explicitly declared sample",
    groups = rows, cross_sample = contrasts,
    interpretation = "Between-sample flags are descriptive, require biological comparability, and never delete a sample or establish quality. Within-sample cell MAD is separate; treatment effects can explain differences.")
}
