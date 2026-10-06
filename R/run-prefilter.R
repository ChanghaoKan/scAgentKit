# Explicit minimal prefiltering precedes loading-unit doublet scoring. This
# record always binds the complete supplied input; a prefilter is never inferred
# from a quality preset or a donor/sample relationship.
.sc_run_prefilter_options <- function(value) {
  if (is.null(value) || identical(value, FALSE)) value <- list(method = "none")
  canonical <- is.list(value) && identical(value$schema, "scagentkit.prefilter-options.v1")
  if (canonical) value$schema <- NULL
  .sc_run_doublet_fields(value, "method", c("method", "min_counts", "source", "preapproved"), "prefilter")
  if (!is.character(value$method) || length(value$method) != 1L || is.na(value$method) ||
      !value$method %in% c("none", "min_counts"))
    .sc_project_fail("Prefilter method must explicitly be none or min_counts; no quality preset is inferred.")
  if (identical(value$method, "none")) {
    if (!is.null(value$min_counts)) .sc_project_fail("The none prefilter cannot supply a count threshold.")
    if (!is.null(value$preapproved) && !identical(value$preapproved, FALSE))
      .sc_project_fail("The none prefilter has no deletion to preapprove; omit preapproved or set FALSE.")
    source <- if (is.null(value$source)) "Explicit no-prefilter policy; every supplied cell enters the pre-score cohort." else
      .sc_run_doublet_text(value$source, "prefilter source")
    return(list(schema = "scagentkit.prefilter-options.v1", method = "none", source = source,
                preapproved = FALSE))
  }
  .sc_run_doublet_fields(value, c("method", "min_counts", "source", "preapproved"), label = "min_counts prefilter")
  if (!identical(value$preapproved, TRUE))
    .sc_project_fail("min_counts prefilter changes the cell set before review and requires explicit preapproved=TRUE plus provenance; no unapproved deletion occurs.")
  minimum <- .sc_run_strategy_runtime_number(value$min_counts, "prefilter min_counts", 1, 200, integer = TRUE)
  list(schema = "scagentkit.prefilter-options.v1", method = "min_counts", min_counts = minimum,
       source = .sc_run_doublet_text(value$source, "prefilter source"), preapproved = TRUE)
}

.sc_run_prefilter_hash <- function(record) {
  record$evidence_hash <- NULL
  .sc_run_hash(record)
}

.sc_run_prefilter_scopes <- function(metrics, keep_cells) {
  roles <- intersect(c("sample", "capture", "qc_group"), names(metrics))
  stats::setNames(lapply(roles, function(role) {
    labels <- unique(metrics[[role]])
    stats::setNames(lapply(labels, function(label) {
      cells <- metrics$cell_id[metrics[[role]] == label]
      retained <- cells[cells %in% keep_cells]
      list(original_cells = length(cells), pre_score_cells = length(retained),
           excluded_cells = length(cells) - length(retained), measured = TRUE,
           retained_fraction = length(retained) / length(cells),
           original_cell_hash = .sc_run_hash(cells), pre_score_cell_hash = .sc_run_hash(retained))
    }), labels)
  }), roles)
}

.sc_run_prefilter_evidence <- function(seu, config) {
  seu <- .sc_project_unwrap(seu)
  options <- .sc_run_prefilter_options(config$prefilter)
  assay <- config$assay; counts_layer <- config$counts_layer
  .sc_project_string(assay, "prefilter assay"); .sc_project_string(counts_layer, "prefilter counts_layer")
  if (grepl("^(data|scale\\.data|normalized)(\\.|$)", counts_layer, ignore.case = TRUE))
    .sc_project_fail("Prefilter requires genuine raw counts, not a normalized or scaled layer.")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  counts_hash <- .sc_project_sparse_hash(counts)
  cells <- colnames(seu); .sc_project_ids(cells, "Prefilter source cell IDs")
  if (!setequal(colnames(counts), cells) || !identical(rownames(seu[[]]), cells))
    .sc_project_fail("Prefilter counts and metadata must cover every literal source cell exactly.")
  features <- rownames(counts); .sc_project_ids(features, "Prefilter source feature IDs")
  counts <- counts[, cells, drop = FALSE]
  totals <- as.numeric(Matrix::colSums(counts))
  detected <- as.numeric(Matrix::colSums(counts > 0))
  if (any(!is.finite(totals)) || any(!is.finite(detected)))
    .sc_project_fail("Prefilter raw-count totals and detected features must be finite; overflowing measurements cannot select cells.")
  metrics <- data.frame(cell_id = cells, nCount = totals, nFeature = detected,
                        stringsAsFactors = FALSE, check.names = FALSE, row.names = cells)
  columns <- config$context$columns
  if (is.null(columns)) columns <- list()
  metadata <- seu[[]]
  roles <- intersect(c("sample", "capture", "qc_group"), names(columns))
  for (role in roles) {
    column <- columns[[role]]
    .sc_project_string(column, paste0("prefilter context$columns$", role))
    if (sum(names(metadata) == column) != 1L)
      .sc_project_fail(paste0("Declared prefilter ", role, " column is absent or ambiguous."))
    values <- metadata[cells, column]
    if (!(is.character(values) || is.factor(values) || is.numeric(values) || is.logical(values)) ||
        anyNA(values) || any(!nzchar(trimws(as.character(values)))) ||
        (is.numeric(values) && any(!is.finite(values))))
      .sc_project_fail("Explicit prefilter group labels must be finite, nonempty, nonmissing atomic values; no group is guessed.")
    metrics[[role]] <- as.character(values)
  }
  if (!is.null(config$doublet_diagnostics) && !identical(config$doublet_diagnostics, FALSE)) {
    doublet <- .sc_run_doublet_options(config$context, config$doublet_diagnostics)
    metrics$capture <- unname(.sc_run_doublet_captures(seu, doublet, cells))
  }
  keep <- if (identical(options$method, "none")) cells else cells[totals >= options$min_counts]
  excluded <- cells[!cells %in% keep]
  scopes <- .sc_run_prefilter_scopes(metrics, keep)
  summary <- list(schema = "scagentkit.prefilter.evidence.v1", assay = assay, counts_layer = counts_layer,
    options = options, original_cells = length(cells), pre_score_cells = length(keep), excluded_cells = length(excluded),
    retained_fraction = if (length(cells)) length(keep) / length(cells) else NA_real_,
    scopes = scopes, per_sample = scopes$sample, per_capture = scopes$capture,
    metrics = list(nCount = .sc_run_qc_distribution(totals), nFeature = .sc_run_qc_distribution(detected)),
    interpretation = c("Inclusive minimum raw-count prefiltering is separate from later reviewed quality filtering.",
      "none keeps every supplied cell; min_counts executes only an explicit preapproved rule with recorded provenance.",
      "Sample, quality group, and physical capture are independent explicitly declared roles; no donor relationship is inferred.",
      "A known empty pre-score group has zero cells, not an unknown measurement.",
      "Doublet rates use original full-called capture size; prefilter exclusions never become doublet predictions."))
  record <- list(summary = summary, options = options, context = config$context, cell_ids = cells, feature_ids = features,
    metrics = metrics, keep_cells = keep, excluded_cells = excluded, group_columns = columns[roles],
    counts_hash = counts_hash, count_cell_hashes = .sc_run_cycle_cell_counts(counts, cells),
    context_hash = .sc_run_hash(config$context),
    cell_hash = .sc_run_hash(cells), features_hash = .sc_run_hash(features), metrics_hash = .sc_run_hash(metrics),
    options_hash = .sc_run_hash(options), keep_hash = .sc_run_hash(keep), excluded_hash = .sc_run_hash(excluded))
  record$evidence_hash <- .sc_run_prefilter_hash(record)
  .sc_run_prefilter_verify(record)
  record
}

.sc_run_prefilter_verify <- function(record) {
  if (!is.list(record) || !is.list(record$summary) ||
      !identical(record$summary$schema, "scagentkit.prefilter.evidence.v1") ||
      !identical(record$evidence_hash, .sc_run_prefilter_hash(record)))
    .sc_project_fail("Prefilter evidence is missing or changed; regenerate it and obtain fresh review.")
  cells <- record$cell_ids; features <- record$feature_ids
  .sc_project_ids(cells, "Prefilter reference cell IDs"); .sc_project_ids(features, "Prefilter reference feature IDs")
  options <- .sc_run_prefilter_options(record$options)
  metrics <- record$metrics
  if (!is.list(record$context)) .sc_project_fail("Prefilter context must be an intact local structured context.")
  columns <- record$context$columns
  if (is.null(columns)) columns <- list()
  roles <- intersect(c("sample", "capture", "qc_group"), names(columns))
  if (!identical(record$options, options) || !identical(record$summary$options, options) ||
      !is.list(record$context) || !identical(record$context_hash, .sc_run_hash(record$context)) ||
      !identical(record$group_columns, columns[roles]) ||
      any(!roles %in% names(metrics)) ||
      !identical(record$cell_hash, .sc_run_hash(cells)) || !identical(record$features_hash, .sc_run_hash(features)) ||
      !identical(record$options_hash, .sc_run_hash(options)) || !identical(record$metrics_hash, .sc_run_hash(metrics)) ||
      !is.data.frame(metrics) || !identical(metrics$cell_id, cells) || !identical(rownames(metrics), cells) ||
      !identical(names(metrics)[seq_len(3L)], c("cell_id", "nCount", "nFeature")) ||
      length(setdiff(names(metrics), c("cell_id", "nCount", "nFeature", "sample", "capture", "qc_group"))) ||
      !is.numeric(metrics$nCount) || any(!is.finite(metrics$nCount)) || any(metrics$nCount < 0) ||
      !is.numeric(metrics$nFeature) || any(!is.finite(metrics$nFeature)) ||
      any(metrics$nFeature < 0 | metrics$nFeature > length(features)) ||
      any(metrics$nCount != floor(metrics$nCount)) || any(metrics$nFeature != floor(metrics$nFeature)) ||
      any(metrics$nFeature > metrics$nCount) || !identical(names(record$count_cell_hashes), cells) ||
      !is.character(record$count_cell_hashes) || anyNA(record$count_cell_hashes) ||
      any(!grepl("^[0-9a-f]{64}$", record$count_cell_hashes)) ||
      !is.character(record$counts_hash) || length(record$counts_hash) != 1L ||
      is.na(record$counts_hash) || !grepl("^[0-9a-f]{64}$", record$counts_hash))
    .sc_project_fail("Prefilter source identity, metrics, or option hashes are inconsistent.")
  for (role in intersect(c("sample", "capture", "qc_group"), names(metrics)))
    if (!is.character(metrics[[role]]) || anyNA(metrics[[role]]) || any(!nzchar(trimws(metrics[[role]]))))
      .sc_project_fail("Prefilter literal group scopes must have nonempty, nonmissing labels.")
  keep <- if (identical(options$method, "none")) cells else cells[metrics$nCount >= options$min_counts]
  excluded <- cells[!cells %in% keep]
  scopes <- .sc_run_prefilter_scopes(metrics, keep)
  if (!identical(record$keep_cells, keep) || !identical(record$excluded_cells, excluded) ||
      !identical(record$keep_hash, .sc_run_hash(keep)) || !identical(record$excluded_hash, .sc_run_hash(excluded)) ||
      !identical(record$summary$original_cells, length(cells)) ||
      !identical(record$summary$pre_score_cells, length(keep)) ||
      !identical(record$summary$excluded_cells, length(excluded)) ||
      !identical(record$summary$retained_fraction, length(keep) / length(cells)) ||
      !identical(record$summary$scopes, scopes) || !identical(record$summary$per_sample, scopes$sample) ||
      !identical(record$summary$per_capture, scopes$capture) ||
      !identical(record$summary$metrics, list(nCount = .sc_run_qc_distribution(metrics$nCount),
                                            nFeature = .sc_run_qc_distribution(metrics$nFeature))))
    .sc_project_fail("Prefilter exact inclusive rule, retained IDs, or group counts are inconsistent.")
  invisible(TRUE)
}
