.sc_run_qc_replacements <- function(proposal, evidence) {
  record <- evidence$biology_record
  .sc_run_biology_verify(record, evidence)
  if (!isTRUE(record$options$cluster_qc) || !identical(record$summary$status, "available"))
    stop("Diagnostic cluster QC is unavailable or disabled.", call. = FALSE)
  if (!identical(proposal$diagnostic_hash, record$hash) ||
      !identical(proposal$membership_hash, record$membership_hash))
    stop("Diagnostic checkpoint or membership changed; obtain fresh review.", call. = FALSE)
  items <- proposal$replacements
  if (!is.list(items) || !length(items) || !is.null(names(items)) || length(items) > 100L)
    stop("Supply 1 to 100 explicit cluster/metric replacements.", call. = FALSE)
  metrics <- evidence$metrics
  cluster <- unname(record$membership[match(metrics$cell_id, names(record$membership))])
  entries <- lapply(items, function(item) {
    .sc_run_strategy_fields(item, c("cluster_id", "metric", "reason"),
      c("min", "max"), "Diagnostic threshold replacement")
    .sc_project_string(item$cluster_id, "replacement cluster_id")
    if (!item$cluster_id %in% record$membership)
      stop("Replacement names an unknown diagnostic cluster.", call. = FALSE)
    reason <- .sc_run_strategy_text(item$reason, "Replacement reason", 700L)
    checked <- .sc_run_qc_rule_range(c(list(op = "range"), item[intersect(
      c("metric", "min", "max"), names(item))]), metrics)
    minimum <- record$minimum_counts
    if (!is.null(evidence$mad_record$prefilter_record))
      minimum <- evidence$mad_record$prefilter_record$options$min_counts
    if (is.null(minimum)) minimum <- 0
    if (identical(item$metric, "nCount") && minimum > 0 &&
        (is.null(checked$rule$min) || checked$rule$min < minimum))
      stop("Replacement cannot cross the approved minimum-count prefilter.", call. = FALSE)
    list(cluster_id = item$cluster_id, metric = checked$rule$metric,
      min = checked$rule$min, max = checked$rule$max, reason = reason,
      selected = !is.na(cluster) & cluster == item$cluster_id,
      eligible = isTRUE(.sc_run_biology_marker_support(record$markers, item$cluster_id,
        record$exclusions, record$options$relaxation_support)$eligible))
  })
  keys <- vapply(entries, function(x) .sc_run_hash(x[c("cluster_id", "metric")]), character(1))
  if (anyDuplicated(keys))
    stop("Overlapping or contradictory replacements for one cluster/metric are rejected.", call. = FALSE)
  runtime <- new.env(parent = emptyenv())
  runtime$entries <- entries
  runtime$coverage <- lapply(entries, function(x) rep(FALSE, nrow(metrics)))
  runtime$effective <- list()
  runtime
}

.sc_run_qc_replace_metric <- function(metric, selected, minimum, maximum, values,
                                      failed, replacement) {
  if (is.null(replacement)) return(failed)
  for (i in seq_along(replacement$entries)) {
    entry <- replacement$entries[[i]]
    if (!identical(entry$metric, metric)) next
    affected <- selected & entry$selected
    if (!any(affected)) next
    lower <- if (is.null(minimum)) 0 else minimum
    upper <- if (is.null(maximum)) Inf else maximum
    next_lower <- if (is.null(entry$min)) 0 else entry$min
    next_upper <- if (is.null(entry$max)) Inf else entry$max
    relaxed <- next_lower < lower || next_upper > upper
    if (relaxed && !entry$eligible)
      stop("Relaxation lacks three tested non-excluded top diagnostic markers.", call. = FALSE)
    actual <- values[affected]
    if (any(!is.finite(actual)))
      stop("An unavailable metric cannot be replaced or interpreted as zero.", call. = FALSE)
    failed[affected] <- actual < next_lower | actual > next_upper
    replacement$coverage[[i]][affected] <- TRUE
    replacement$effective <- append(replacement$effective, list(list(
      cluster_id = entry$cluster_id, metric = metric, cells = sum(affected),
      baseline_min = minimum, baseline_max = maximum, min = entry$min, max = entry$max,
      direction = if (relaxed) "includes_relaxation" else "tightening_or_equal",
      reason = entry$reason)))
  }
  failed
}

.sc_run_qc_replace_mad <- function(record, preset, metrics, replacement) {
  names <- c(nCount = "low_count", nFeature = "low_feature", percent_mt = "high_mt")
  definition <- Filter(function(x) identical(x$preset_id, preset), .sc_run_mad_presets())[[1L]]
  flags <- record$flags
  for (metric in definition$required_metrics) for (group in record$summary$groups) {
    selected <- flags$prefilter_pass & flags$qc_group == group$value
    statistic <- group$metrics[[metric]]$exact
    lower <- if (metric == "percent_mt") NULL else max(0, ceiling(statistic$lower_raw))
    upper <- if (metric == "percent_mt") statistic$upper_raw else NULL
    flags[[names[[metric]]]] <- .sc_run_qc_replace_metric(metric, selected, lower, upper,
      metrics[[metric]], flags[[names[[metric]]]], replacement)
  }
  switch(preset, keep_all = rep(FALSE, nrow(metrics)),
    conservative_and3 = flags$low_count & flags$low_feature & flags$high_mt,
    low_counts3 = flags$low_count, low_features3 = flags$low_feature,
    high_mt3 = flags$high_mt,
    any_quality3 = flags$low_count | flags$low_feature | flags$high_mt)
}
