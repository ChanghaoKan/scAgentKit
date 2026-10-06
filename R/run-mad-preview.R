# Pure local projection of one immutable finite MAD panel. Exact cell IDs and
# flags belong to the local review, not its remote aggregate representation.
.sc_run_mad_preview_build <- function(proposal, evidence, sensitivity = list(), gene_panels = list()) {
  if (!is.list(sensitivity) || length(sensitivity))
    stop("MAD review uses its saved finite preset panel; custom range sensitivity is unsupported.", call. = FALSE)
  validated <- .sc_run_qc_validate(proposal, evidence)
  record <- evidence$mad_record
  .sc_run_mad_verify(record)
  panels <- .sc_run_qc_preview_gene_panels(gene_panels, evidence)
  cells <- evidence$metrics$cell_id
  keep <- cells %in% validated$keep_cells
  prefilter_keep <- record$flags$prefilter_pass[match(cells, record$flags$cell_id)]
  if (anyNA(prefilter_keep) || any(keep & !prefilter_keep))
    stop("MAD projection contradicts the exact prefilter eligibility.", call. = FALSE)
  population <- list(prefilter_excluded = !prefilter_keep,
    quality_removed = prefilter_keep & !keep, retained = keep)
  patterns <- lapply(names(population), function(name) {
    index <- population[[name]]
    list(filter_ids = name, reason_ids = name, unavailable_filter_ids = character(),
      count = sum(index), cell_ids = cells[index], retained = sum(index & keep), removed = sum(index & !keep))
  })
  list(schema = "scagentkit.qc.preview.v1", evidence_hash = validated$evidence_hash,
    canonical_parameters = list(proposal = validated$proposal, sensitivity = list(), gene_panels = panels$parameters),
    retention = validated$retention, keep_cells = cells[keep], remove_cells = cells[!keep],
    keep_cell_hash = .sc_run_qc_preview_cells_hash(cells[keep]),
    remove_cell_hash = .sc_run_qc_preview_cells_hash(cells[!keep]),
    metrics = evidence$metrics, filter_impacts = list(), patterns = patterns,
    overlap = list(filter_ids = character(), counts = list(),
      interpretation = "One saved preset combines flags with its declared AND/OR logic; independent flags are not independent exclusions."),
    distributions = .sc_run_qc_preview_distributions(evidence$metrics, keep),
    unavailable = list(metrics = lapply(c("nCount", "nFeature", "percent_mt"), function(metric) {
      missing <- !is.finite(evidence$metrics[[metric]])
      list(metric = metric, count = sum(missing), cell_ids = cells[missing])
    }), zero_count_cells = cells[evidence$metrics$nCount == 0],
      mitochondrial = evidence$summary$mitochondrial, gene_panels = panels$records),
    sensitivity = list(), mad_panel = record$summary, mad_flags = record$flags,
    interpretation = c("Exact saved thresholds and preset logic execute; rounded display values do not define comparisons.",
      "Minimal prefilter eligibility and later quality filtering are separate declared stages.",
      "QC grouping is independent of capture/donor. Missing or inapplicable metrics remain Unknown, not zero.",
      "High RNA is flag-only; ribosomal and hemoglobin measurements never authorize deletion.",
      "Candidate impacts describe consequences, not a universal optimum or biological truth.",
      "All exact cell IDs and per-cell flags in this preview remain local."))
}

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
    interpretation = if (identical(validated$proposal$qc$schema, "scagentkit.qc.rules.v1"))
      "Declared statistics, mandatory pre-score eligibility and exact reviewed range/MAD failure-rule combination; no automatic biological acceptance, best-rule selection or integration." else
      "Declared statistics and exact reviewed preset execution; no automatic biological acceptance, best-preset selection or integration.")
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
