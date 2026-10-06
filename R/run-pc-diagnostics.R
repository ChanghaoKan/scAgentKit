# Fixed 80/85% diagnostics use only the first at most 50 actually computed
# principal components. They are choices for review, not biological optima or
# estimates of total expressed-gene variance. The legacy selector is unchanged.
.sc_run_pc_hash <- function(record) {
  record$hash <- NULL
  .sc_run_hash(record)
}

.sc_run_pc_candidates <- function(deviation) {
  if (!is.numeric(deviation) || !is.null(dim(deviation)) ||
      !typeof(deviation) %in% c("integer", "double") || length(deviation) < 2L ||
      length(deviation) > .Machine$integer.max || anyNA(deviation) ||
      any(!is.finite(deviation)) || any(deviation <= 0))
    .sc_project_fail("PC diagnostics require a finite, strictly positive numeric standard-deviation vector with at least two actually computed PCs.")
  deviation <- unname(as.numeric(deviation))
  variances <- deviation^2
  if (any(!is.finite(variances)) || any(variances <= 0))
    .sc_project_fail("PC diagnostics standard deviations produce overflowing or underflowing variances; no clipping or variance repair is supported.")
  total <- as.integer(length(deviation))
  reference <- min(50L, total)
  variance <- variances[seq_len(reference)]
  denominator <- sum(variance)
  if (!is.finite(denominator) || denominator <= 0)
    .sc_project_fail("PC diagnostics reference-PC variance sum is invalid or overflowing; no alternate denominator is substituted.")
  fractions <- as.numeric(variance / denominator)
  cumulative <- as.numeric(cumsum(fractions))
  if (any(!is.finite(fractions)) || any(fractions <= 0) || any(!is.finite(cumulative)))
    .sc_project_fail("PC diagnostics reference fractions are invalid or underflowing; no repaired cumulative rule is substituted.")
  candidate <- function(threshold) {
    crossing <- which(cumulative >= threshold)
    if (!length(crossing)) .sc_project_fail("PC diagnostics did not reach a required reference threshold.")
    ndim <- as.integer(crossing[1L])
    supported <- ndim >= 2L
    list(threshold = threshold, ndim = ndim, supported = supported,
      reason = if (supported)
        "First exact cumulative reference-PC variance fraction reaching this threshold; an empirical reviewed dimensionality option, not a biological optimum." else
        "This threshold selects only one PC and is unsupported by the coordinator; choose another supported policy explicitly. It is never clipped to two PCs.")
  }
  record <- list(schema = "scagentkit.pc.candidates.v1", deviation = deviation,
    deviation_hash = .sc_run_hash(deviation), total_computed_pcs = total,
    reference_pcs = reference, target_reference_pcs = 50L,
    shortfall = reference < 50L, shortfall_count = 50L - reference,
    denominator = "sum of variances of the first reference_pcs actually computed PCs (at most 50); not total expressed-gene variance and not the variance sum of additional computed PCs",
    denominator_value = as.numeric(denominator), variance = as.numeric(variance),
    fraction_per_pc = fractions, cumulative_fraction = cumulative,
    threshold_comparison = "First cumulative_fraction >= threshold using exact saved numeric values; displayed rounding never changes selection.",
    candidates = list(p80 = candidate(.80), p85 = candidate(.85)),
    interpretation = "80% and 85% are finite empirical options for analyst review. A short reference records fewer than 50 computed PCs without inventing missing components; none of these diagnostics certifies biological correctness.")
  record$hash <- .sc_run_pc_hash(record)
  record
}

.sc_run_pc_verify <- function(record) {
  if (!is.list(record) || !identical(record$schema, "scagentkit.pc.candidates.v1") ||
      !identical(record$hash, .sc_run_pc_hash(record)))
    .sc_project_fail("PC candidate diagnostics are missing or changed; restore the saved basis evidence and obtain fresh review.")
  canonical <- .sc_run_pc_candidates(record$deviation)
  if (!identical(record, canonical))
    .sc_project_fail("PC candidate diagnostics are inconsistent with the exact computed standard deviations, reference denominator, or first threshold crossings.")
  invisible(TRUE)
}

.sc_run_pc_table <- function(record) {
  .sc_run_pc_verify(record)
  pc <- seq_len(record$reference_pcs)
  data.frame(pc = pc, variance = record$variance,
    fraction_per_pc = record$fraction_per_pc, cumulative_fraction = record$cumulative_fraction,
    p80_boundary = pc == record$candidates$p80$ndim,
    p85_boundary = pc == record$candidates$p85$ndim,
    p80_supported = record$candidates$p80$supported,
    p85_supported = record$candidates$p85$supported,
    stringsAsFactors = FALSE, check.names = FALSE)
}

.sc_run_pc_plot <- function(record, path) {
  .sc_run_pc_verify(record); .sc_project_string(path, "PC diagnostic plot path")
  grDevices::png(path, width = 1120L, height = 740L, res = 120L)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(1L, 2L), mar = c(5, 4, 4, 1), oma = c(2, 0, 2, 0))
  pc <- seq_len(record$reference_pcs)
  graphics::plot(pc, record$fraction_per_pc, type = "b", pch = 16L, cex = .55,
    xlab = "Computed reference PC", ylab = "Fraction of reference-PC variance",
    main = "Reference PC variance")
  graphics::plot(pc, record$cumulative_fraction, type = "b", pch = 16L, cex = .55,
    ylim = c(0, 1), xlab = "Computed reference PC", ylab = "Cumulative reference-PC variance",
    main = "Exact 80% / 85% candidates")
  candidates <- record$candidates
  colors <- c("#366da8", "#bf6d2c")
  for (index in seq_along(candidates)) {
    item <- candidates[[index]]
    graphics::abline(h = item$threshold, v = item$ndim, col = colors[index], lty = 2L)
    graphics::points(item$ndim, record$cumulative_fraction[item$ndim],
      pch = if (item$supported) 16L else 4L, col = colors[index], cex = 1.1)
  }
  labels <- vapply(candidates, function(item) paste0(as.integer(100 * item$threshold), "%: ",
    item$ndim, " PCs", if (item$supported) "" else " (unsupported)"), character(1))
  graphics::legend("bottomright", legend = labels, col = colors, lty = 2L, bty = "n", cex = .85)
  graphics::mtext(paste0("Reference: first ", record$reference_pcs, " of ", record$total_computed_pcs,
    " computed PCs", if (record$shortfall) paste0("; ", record$shortfall_count, " below target 50") else ""),
    side = 3L, outer = TRUE, cex = .9)
  graphics::mtext("Denominator is reference-PC variance only; biological correctness requires analyst review.",
    side = 1L, outer = TRUE, cex = .8)
  invisible(path)
}
