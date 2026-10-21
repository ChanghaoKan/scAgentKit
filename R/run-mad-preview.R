# Local export of the immutable MAD panel and the exact approved rules outcome.
.sc_run_mad_outputs <- function(root, state, seu, strategy_record) {
  record <- .sc_run_get(root, state, "qc_mad")
  prefilter <- .sc_run_get(root, state, "prefilter")
  validated <- .sc_run_get(root, state, "strategy_validated")
  .sc_run_mad_verify(record); .sc_run_prefilter_verify(prefilter)
  cells <- record$cell_ids
  selected <- if (is.null(validated$selected_cells)) validated$qc_validated$keep_cells else validated$selected_cells
  if (!identical(colnames(seu), selected))
    stop("Final cell IDs/order differ from the exact approved MAD selection.", call. = FALSE)
  metrics <- record$metrics
  flags <- record$flags[match(metrics$cell_id, record$flags$cell_id), , drop = FALSE]
  for (name in setdiff(names(flags), names(metrics))) metrics[[name]] <- flags[[name]]
  metrics$passed_quality <- metrics$cell_id %in% validated$qc_validated$keep_cells
  metrics$retained_final <- metrics$cell_id %in% colnames(seu)
  utils::write.csv(metrics, file.path(root, "output", "qc_mad_metrics.csv"), row.names = FALSE, na = "NA")
  utils::write.csv(data.frame(cell_id = cells, passed_prefilter = cells %in% prefilter$keep_cells,
    passed_quality = cells %in% validated$qc_validated$keep_cells, retained_final = cells %in% colnames(seu)),
    file.path(root, "output", "prefilter_selection.csv"), row.names = FALSE)
  doublet <- if (is.null(state$config$doublet_diagnostics)) NULL else .sc_run_get(root, state, "doublet_diagnostics")
  output <- list(schema = "scagentkit.qc.mad.output.v1", input_hash = state$input_hash,
    panel_hash = record$summary$panel_hash, evidence_hash = record$evidence_hash,
    prefilter_hash = prefilter$evidence_hash, review_hash = strategy_record$hash,
    choice = validated$proposal$qc, panel = record$summary, prefilter = prefilter$summary,
    stages = list(original_input = length(cells), prefilter_eligible = length(prefilter$keep_cells),
      pre_score_eligible = length(prefilter$keep_cells),
      actual_scored = if (is.null(doublet)) NULL else doublet$summary$cohort$scored_cells,
      post_quality = length(validated$qc_validated$keep_cells), post_doublet = ncol(seu)),
    rate_reference = if (is.null(doublet)) NULL else doublet$summary$capture_stats,
    actual_retained_cell_ids = colnames(seu),
    interpretation = if (.sc_run_qc_empty_rules(validated$proposal$qc))
      "No additional filtering; mandatory pre-score exclusions and previously committed exclusions are not restored. No automatic biological acceptance or integration." else
      "Declared statistics, mandatory pre-score eligibility and exact reviewed range/MAD failure rules with any approved diagnostic replacements; no automatic biological acceptance, best-rule selection or integration.")
  .sc_run_atomic(output, file.path(root, "output", "qc_mad_summary.json"), json = TRUE)
  metric <- value <- qc_group <- NULL
  long <- do.call(rbind, lapply(c("nCount", "nFeature", "percent_mt"), function(name) {
    values <- metrics[[name]]
    if (name != "percent_mt") values <- log10(values + 1)
    use <- metrics$prefilter_pass & is.finite(values)
    data.frame(qc_group = metrics$qc_group[use], metric = rep(name, sum(use)), value = values[use], stringsAsFactors = FALSE)
  }))
  plot <- ggplot2::ggplot(long, ggplot2::aes(x = qc_group, y = value)) +
    ggplot2::geom_boxplot(outlier.shape = NA) + ggplot2::facet_wrap(~metric, scales = "free_y") +
    ggplot2::theme_bw() + ggplot2::labs(title = "Declared QC groups before quality filtering", x = "QC group", y = "Measured value",
      subtitle = "Counts/features: log10(x+1); mt: percent. Descriptive distributions; high RNA/ribo/Hb do not authorize deletion.")
  ggplot2::ggsave(file.path(root, "output", "qc_mad_diagnostics.png"), plot, width = 10, height = 4, dpi = 120)
  invisible(output)
}
