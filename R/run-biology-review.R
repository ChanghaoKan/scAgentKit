# Reuse annotation risk enumerations and validation, scoped to first-gate evidence.
.sc_run_biology_risks <- function(value, evidence) {
  biology <- evidence$private$biology_record
  if (is.null(biology)) {
    if (!is.null(value)) stop("Diagnostic risk fields require biological diagnostics.", call. = FALSE)
    return(NULL)
  }
  .sc_run_biology_verify(biology, evidence$qc)
  ids <- c("quality", "design", "biology",
    if (!is.null(evidence$summary$cycle_diagnostics)) "cycle",
    if (!is.null(evidence$summary$doublet_diagnostics)) "doublet")
  if (is.null(value)) {
    value <- .sc_run_react_unassessed_risks("strategy")
    value$stage <- "strategy"; value$cluster_id <- NULL
    value$evidence_hash <- biology$hash
    value$fields <- lapply(value$fields, function(field) {
      field$source <- "rule"
      if (field$name == "qc_celltype_concern" && length(biology$summary$clusters)) {
        field$value <- if (any(vapply(biology$summary$clusters,
          function(x) isTRUE(x$disproportionately_removed), logical(1)))) "suspected" else "not_detected"
        field$assessment_status <- "assessed"; field$evidence_ids <- list("biology")
      }
      if (field$name == "batch_status" && !is.null(biology$summary$batch)) {
        field$value <- biology$summary$batch$status
        field$assessment_status <- if (field$value == "not_applicable") "not_applicable" else
          if (field$value == "insufficient_evidence") "not_assessed" else "assessed"
        field$evidence_ids <- list("biology")
      }
      field
    })
  }
  .sc_run_strategy_fields(value, c("schema", "stage", "evidence_hash", "fields"),
    name = "First-gate risk record")
  if (!identical(value$stage, "strategy") || !identical(value$evidence_hash, biology$hash))
    stop("First-gate risks refer to stale diagnostic evidence.", call. = FALSE)
  proxy <- value
  proxy$stage <- "annotation"; proxy$cluster_id <- "strategy"; proxy$evidence_hash <- NULL
  proxy$fields <- lapply(proxy$fields, function(field) {
    if (!is.character(field$source) || length(field$source) != 1L ||
        !field$source %in% c("rule", "model", "human"))
      stop("Risk source must be rule, model or human.", call. = FALSE)
    field$source <- "model"; field
  })
  .sc_run_react_risks(proxy, "strategy", ids)
  value
}

.sc_run_biology_post_batch <- function(before, after, config, record, plan) {
  if (is.null(record) || !isTRUE(record$options$batch_assessment)) return(NULL)
  if (!identical(record$summary$status, "available"))
    return(list(status = "unavailable", reason = "Pre-approval diagnostic labels were unavailable."))
  cells <- colnames(after)
  labels <- unname(record$membership[match(cells, names(record$membership))])
  metadata <- after[[]]
  roles <- lapply(config$context$columns, function(column) as.character(metadata[cells, column]))
  dims <- after@misc$strategy_execution$batch$pca$ndim
  raw <- SeuratObject::Embeddings(before, "pca")[cells, seq_len(dims), drop = FALSE]
  corrected <- SeuratObject::Embeddings(after, "harmony")[cells, , drop = FALSE]
  result <- .sc_run_batch_evidence(raw, roles, labels, after = corrected,
    design_supported = isTRUE(record$summary$batch$design_supported))
  result$diagnostic_hash <- record$hash
  result$membership_hash <- record$membership_hash
  result$embedding_scope <- "Exact approved PCA and Harmony dimensions used for final neighbors"
  result
}

# A predicate table retains AND/OR semantics; it is not a new filtering engine.
.sc_run_biology_threshold_review <- function(validated, evidence) {
  record <- evidence$private$biology_record
  if (is.null(record) || !isTRUE(record$options$cluster_qc) ||
      !identical(record$summary$status, "available")) return(NULL)
  proposal <- validated$proposal$qc
  metrics <- evidence$qc$metrics
  membership <- unname(record$membership[match(metrics$cell_id, names(record$membership))])
  rules <- if (!is.null(proposal$rules)) proposal$rules else if (!is.null(proposal$filters))
    proposal$filters else list(list(op = "mad_preset", preset_id = proposal$preset_id))
  table <- list()
  add <- function(metric, selected, minimum, maximum, predicate) {
    for (cluster in sort(unique(record$membership))) {
      in_scope <- selected & !is.na(membership) & membership == cluster
      if (!any(in_scope)) next
      changed <- Filter(function(x) identical(x$cluster_id, cluster) &&
        identical(x$metric, metric), proposal$replacements)
      entry <- if (length(changed)) changed[[1L]] else NULL
      table[[length(table) + 1L]] <<- list(cluster_id = cluster, metric = metric,
        predicate = predicate, cells = sum(in_scope), baseline_min = minimum, baseline_max = maximum,
        effective_min = if (length(changed)) entry$min else minimum,
        effective_max = if (length(changed)) entry$max else maximum,
        replaced = length(changed) > 0L, reason = entry$reason)
    }
  }
  for (i in seq_along(rules)) {
    rule <- rules[[i]]
    if (identical(rule$op, "range")) {
      range <- .sc_run_qc_rule_range(rule, metrics)
      add(rule$metric, range$selected, rule$min, rule$max, paste0("rule:", i))
    } else if (identical(rule$op, "mad_preset")) {
      definition <- Filter(function(x) identical(x$preset_id, rule$preset_id),
        .sc_run_mad_presets())[[1L]]
      mad <- evidence$private$mad_record
      for (group in mad$summary$groups) for (metric in definition$required_metrics) {
        exact <- group$metrics[[metric]]$exact
        add(metric, mad$flags$prefilter_pass & mad$flags$qc_group == group$value,
          if (metric == "percent_mt") NULL else max(0, ceiling(exact$lower_raw)),
          if (metric == "percent_mt") exact$upper_raw else NULL,
          paste0("rule:", i, "/", rule$preset_id, "/", group$value))
      }
    }
  }
  list(schema = "scagentkit.diagnostic-threshold-review.v1", table = table,
    minimum_prefilter_counts = record$minimum_counts,
    replacement_impact = validated$qc_validated$summary$replacement_impact,
    remove_if = if (is.null(proposal$remove_if)) "any" else proposal$remove_if,
    interpretation = "Rows are effective bounds within each saved predicate and diagnostic cluster. Existing rule AND/OR and MAD-preset logic still combine failures; minimal prefilter and other metrics remain active. Missing bounds are unrestricted, not zero.")
}
