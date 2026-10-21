# Finite combinations of measured ranges and one immutable MAD candidate.
# Rules describe failure predicates; no code, gene filtering or scorer is run.
.sc_run_qc_rule_range <- function(rule, metrics) {
  .sc_run_strategy_fields(rule, c("op", "metric"), c("min", "max", "group"), "QC range rule")
  if (!identical(rule$op, "range")) .sc_project_fail("QC range rules require op='range'.")
  .sc_project_string(rule$metric, "rule$metric")
  if (!rule$metric %in% c("nCount", "nFeature", "percent_mt"))
    .sc_project_fail("Unsupported QC metric; supported metrics are nCount, nFeature, and percent_mt.")
  bounds <- lapply(c("min", "max"), function(name) {
    value <- rule[[name]]
    if (!is.null(value) && (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0))
      .sc_project_fail(paste0("QC ", name, " must be one finite nonnegative number or NULL."))
    if (!is.null(value) && rule$metric %in% c("nCount", "nFeature") && value != floor(value))
      .sc_project_fail("nCount/nFeature QC bounds must be integers.")
    if (!is.null(value) && rule$metric == "percent_mt" && value > 100)
      .sc_project_fail("percent_mt bounds must be between 0 and 100.")
    if (is.null(value)) NULL else unname(as.numeric(value))
  })
  names(bounds) <- c("min", "max")
  if (all(vapply(bounds, is.null, logical(1)))) .sc_project_fail("Every QC range must declare at least one bound.")
  if (!is.null(bounds$min) && !is.null(bounds$max) && bounds$min > bounds$max)
    .sc_project_fail("QC range min cannot exceed max.")
  selector <- rule$group
  selected <- rep(TRUE, nrow(metrics))
  if (!is.null(selector)) {
    if (!is.list(selector) || !length(selector) || is.null(names(selector)) ||
        anyNA(names(selector)) || any(!nzchar(names(selector))) || anyDuplicated(names(selector)) ||
        length(setdiff(names(selector), c("sample", "capture"))))
      .sc_project_fail("QC group must select explicitly declared sample/capture literal values only.")
    selector <- selector[intersect(c("sample", "capture"), names(selector))]
    for (role in names(selector)) {
      .sc_project_string(selector[[role]], paste0("rule$group$", role))
      if (!role %in% names(metrics)) .sc_project_fail(paste0("QC group role `", role, "` was not declared in input context."))
      selected <- selected & metrics[[role]] == selector[[role]]
    }
    if (!any(selected)) .sc_project_fail("QC group selector does not match any actual sample/capture group; hallucinated or stale group values are rejected.")
  }
  values <- metrics[[rule$metric]]
  unavailable <- selected & !is.finite(values)
  measured <- selected & !unavailable
  low <- high <- rep(FALSE, nrow(metrics))
  if (!is.null(bounds$min)) low[measured] <- values[measured] < bounds$min
  if (!is.null(bounds$max)) high[measured] <- values[measured] > bounds$max
  list(rule = list(op = "range", metric = rule$metric, min = bounds$min, max = bounds$max, group = selector),
    selected = selected, low = low, high = high, unavailable = unavailable, failed = low | high)
}

# A valid empty policy has no failure predicates. v2 requires nonempty
# replacements with baseline rule coverage, so it cannot be an empty policy.
.sc_run_qc_empty_rules <- function(proposal) {
  tryCatch({
    .sc_run_strategy_fields(proposal, c("schema", "rationale", "risks", "remove_if", "rules"),
      name = "Empty QC rules proposal")
    .sc_run_strategy_text(proposal$rationale, "QC rules rationale")
    .sc_run_strategy_array(proposal$risks, "QC rules risks")
    identical(proposal$schema, "scagentkit.qc.rules.v1") &&
      is.character(proposal$remove_if) && length(proposal$remove_if) == 1L &&
      !is.na(proposal$remove_if) && proposal$remove_if %in% c("any", "all") &&
      is.list(proposal$rules) && is.null(names(proposal$rules)) && length(proposal$rules) == 0L
  }, error = function(e) FALSE)
}

# Only canonical scientific parameters determine computation reuse. Exact
# proposal and preview hashes independently retain the author's text/operator.
.sc_run_qc_scientific_key <- function(proposal) {
  key <- proposal[intersect(c("schema", "remove_if", "rules", "diagnostic_hash",
    "membership_hash", "replacements"), names(proposal))]
  if (.sc_run_qc_empty_rules(proposal)) key$remove_if <- NULL
  if (!is.null(key$replacements)) key$replacements <- lapply(key$replacements,
    function(item) item[setdiff(names(item), "reason")])
  key
}

.sc_run_qc_rules_evaluate <- function(proposal, evidence, retained_scope = NULL) {
  if (!is.list(evidence) || is.null(evidence$metrics) ||
      !identical(evidence$evidence_hash, .sc_run_qc_hash(evidence)))
    .sc_project_fail("QC evidence is missing or changed; regenerate the evidence and obtain a fresh proposal/approval.")
  replacing <- identical(proposal$schema, "scagentkit.qc.rules.v2")
  fields <- c("schema", "rationale", "risks", "remove_if", "rules")
  if (replacing) fields <- c(fields, "diagnostic_hash", "membership_hash", "replacements")
  .sc_run_strategy_fields(proposal, fields, name = "QC rules proposal")
  if (!replacing && !identical(proposal$schema, "scagentkit.qc.rules.v1")) .sc_project_fail("Unsupported QC rules schema.")
  replacement <- if (replacing) .sc_run_qc_replacements(proposal, evidence) else NULL
  rationale <- .sc_run_strategy_text(proposal$rationale, "QC rules rationale")
  risks <- .sc_run_strategy_array(proposal$risks, "QC rules risks")
  if (!is.character(proposal$remove_if) || length(proposal$remove_if) != 1L ||
      is.na(proposal$remove_if) || !proposal$remove_if %in% c("any", "all"))
    .sc_project_fail("QC remove_if must be 'any' (OR failures) or 'all' (AND failures).")
  rules <- proposal$rules
  if (!is.list(rules) || length(rules) > 32L || !is.null(names(rules)))
    .sc_project_fail("QC rules must be an unnamed array of at most 32 supported rules; an empty array adds no filtering and cannot restore previously excluded cells.")
  metrics <- evidence$metrics; cells <- metrics$cell_id
  .sc_project_ids(cells, "QC evidence cell IDs")
  base <- rep(TRUE, length(cells)); record <- evidence$mad_record
  if (!is.null(record)) {
    record <- .sc_run_mad_bind_evidence(evidence)
    base <- cells %in% record$prefilter_cells
  }
  retained_cells <- .sc_run_qc_retained_scope_cells(retained_scope, evidence)
  prior_excluded <- if (!length(rules)) base & !cells %in% retained_cells else rep(FALSE, length(cells))
  mad_count <- 0L
  statuses <- lapply(rules, function(rule) {
    if (!is.list(rule) || !is.character(rule$op) || length(rule$op) != 1L || is.na(rule$op))
      .sc_project_fail("Every QC rule must declare one supported typed op.")
    if (identical(rule$op, "range")) {
      status <- .sc_run_qc_rule_range(rule, metrics)
      status$original_failed <- status$failed
      status$failed <- .sc_run_qc_replace_metric(rule$metric, status$selected & base,
        rule$min, rule$max, metrics[[rule$metric]], status$failed, replacement)
      if (!is.null(replacement)) for (entry in replacement$entries) {
        affected <- status$selected & base & entry$selected
        if (identical(entry$metric, rule$metric) && any(affected)) {
          values <- metrics[[rule$metric]][affected]
          status$low[affected] <- if (is.null(entry$min)) FALSE else values < entry$min
          status$high[affected] <- if (is.null(entry$max)) FALSE else values > entry$max
        }
      }
      return(status)
    }
    if (!identical(rule$op, "mad_preset"))
      .sc_project_fail("QC rules support only range or mad_preset; arbitrary code, genes and new operations are rejected.")
    .sc_run_strategy_fields(rule, c("op", "preset_id", "panel_hash"), name = "MAD predicate rule")
    mad_count <<- mad_count + 1L
    if (mad_count > 1L) .sc_project_fail("QC rules support at most one saved MAD predicate.")
    if (is.null(record)) .sc_project_fail("MAD predicate requires explicitly enabled qc_mad and an intact local panel.")
    .sc_run_mad_text(rule$preset_id, "MAD predicate preset_id")
    if (!identical(rule$panel_hash, record$panel_hash))
      .sc_project_fail("MAD panel hash differs from this exact local candidate panel; stale approval is rejected.")
    index <- which(vapply(record$summary$presets, `[[`, character(1), "preset_id") == rule$preset_id)
    if (length(index) != 1L) .sc_project_fail("Unsupported MAD preset; only the saved six candidates can be used.")
    panel <- record$summary$presets[[index]]
    if (!isTRUE(panel$available)) .sc_project_fail(paste0("MAD preset is unavailable: ", paste(panel$unavailable_reasons, collapse = " ")))
    selected <- base
    failed <- base & !cells %in% record$selections[[rule$preset_id]]
    original_failed <- failed
    if (!is.null(replacement)) {
      failed <- .sc_run_qc_replace_mad(record, rule$preset_id, metrics, replacement)
      failed[!base] <- FALSE
    }
    list(rule = list(op = "mad_preset", preset_id = unname(rule$preset_id), panel_hash = record$panel_hash),
      selected = selected, low = rep(FALSE, length(cells)), high = rep(FALSE, length(cells)),
      unavailable = rep(FALSE, length(cells)), failed = failed, original_failed = original_failed)
  })
  statuses <- lapply(statuses, function(status) {
    status$failed <- status$failed & base
    status
  })
  # Under AND, a cell outside any rule's literal group can never fail every
  # rule. Reject scopes that share no cell instead of silently removing none.
  if (identical(proposal$remove_if, "all") && length(statuses) > 1L &&
      !any(base & Reduce(`&`, lapply(statuses, `[[`, "selected"))))
    .sc_project_fail("QC remove_if 'all' combines rules whose groups share no cell, so no cell could ever be removed; use 'any' or align the rule groups.")
  failures <- if (length(statuses)) do.call(cbind, lapply(statuses, `[[`, "failed")) else
    matrix(FALSE, nrow = length(cells), ncol = 0L)
  # Outside a rule's literal group its failure is false, not a guessed match.
  removed <- if (!length(statuses)) rep(FALSE, length(cells)) else
    if (identical(proposal$remove_if, "any")) rowSums(failures) > 0L else
    rowSums(failures) == length(statuses)
  keep <- base & !prior_excluded & !removed
  for (status in statuses) if (any(status$unavailable & keep))
    .sc_project_fail("QC metric is unavailable for one or more otherwise retained cells; unknown measurements cannot become an implicit keep or removal rule.")
  if (!any(keep)) .sc_project_fail("QC proposal would remove every cell; revise the rules before approval.")
  groups <- .sc_run_qc_groups(metrics)
  retention_groups <- lapply(seq_along(groups), function(i) {
    group <- groups[[i]]; before <- length(group$indices); after <- sum(keep[group$indices])
    list(group_id = paste0("group", i), selector = group$selector, before = before,
      retained = after, removed = before - after, fraction_retained = after / before)
  })
  canonical <- list(schema = if (replacing) "scagentkit.qc.rules.v2" else "scagentkit.qc.rules.v1",
    rationale = rationale, risks = risks,
    remove_if = unname(proposal$remove_if), rules = lapply(statuses, `[[`, "rule"))
  if (replacing) {
    for (i in seq_along(replacement$entries)) {
      selected <- replacement$entries[[i]]$selected & base
      if (!any(selected) || !all(replacement$coverage[[i]][selected]))
        stop("Replacement requires baseline coverage of that metric throughout the diagnostic cluster.", call. = FALSE)
    }
    canonical$diagnostic_hash <- proposal$diagnostic_hash
    canonical$membership_hash <- proposal$membership_hash
    canonical$replacements <- lapply(replacement$entries, function(x)
      x[c("cluster_id", "metric", "min", "max", "reason")])
  }
  mad_rule <- Filter(function(rule) identical(rule$op, "mad_preset"), canonical$rules)
  summary <- list(method = "typed_rules", remove_if = canonical$remove_if,
    rule_count = length(statuses), preset_id = if (length(mad_rule)) mad_rule[[1L]]$preset_id else NULL,
    original_cells = length(cells), pre_score_cells = sum(base), post_qc_cells = sum(keep),
    prefilter_removed = sum(!base), prior_removed = sum(prior_excluded),
    quality_removed = sum(base & removed),
    high_rna_action = if (replacing) "according to effective approved bounds" else "flag only",
    ribo_hb_action = "diagnostic only")
  if (replacing) {
    original <- do.call(cbind, lapply(statuses, `[[`, "original_failed"))
    original_removed <- if (proposal$remove_if == "any") rowSums(original) > 0L else
      rowSums(original) == ncol(original)
    original_keep <- base & !original_removed
    summary$effective_thresholds <- replacement$effective
    summary$replacement_impact <- lapply(sort(unique(vapply(replacement$entries, `[[`,
      character(1), "cluster_id")), method = "radix"), function(id) {
      index <- replacement$entries[[which(vapply(replacement$entries, function(x)
        identical(x$cluster_id, id), logical(1)))[1L]]]$selected
      list(cluster_id = id, cells = sum(index),
        retained_before = sum(original_keep[index]), retained_after = sum(keep[index]),
        difference = sum(keep[index]) - sum(original_keep[index]))
    })
  }
  list(validated = list(proposal = canonical,
    retention = list(before = nrow(metrics), retained = sum(keep), removed = sum(!keep),
      fraction_retained = mean(keep), groups = retention_groups), keep_cells = cells[keep],
    evidence_hash = evidence$evidence_hash, summary = summary, retained_scope = retained_scope),
    statuses = statuses, failures = failures, base = base, prior_excluded = prior_excluded, keep = keep)
}

.sc_run_qc_rules_validate <- function(proposal, evidence, retained_scope = NULL) {
  .sc_run_qc_rules_evaluate(proposal, evidence, retained_scope)$validated
}
