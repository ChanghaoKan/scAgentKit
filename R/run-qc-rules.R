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

.sc_run_qc_rules_evaluate <- function(proposal, evidence) {
  if (!is.list(evidence) || is.null(evidence$metrics) ||
      !identical(evidence$evidence_hash, .sc_run_qc_hash(evidence)))
    .sc_project_fail("QC evidence is missing or changed; regenerate the evidence and obtain a fresh proposal/approval.")
  .sc_run_strategy_fields(proposal, c("schema", "rationale", "risks", "remove_if", "rules"), name = "QC rules proposal")
  if (!identical(proposal$schema, "scagentkit.qc.rules.v1")) .sc_project_fail("Unsupported QC rules schema.")
  rationale <- .sc_run_strategy_text(proposal$rationale, "QC rules rationale")
  risks <- .sc_run_strategy_array(proposal$risks, "QC rules risks")
  if (!is.character(proposal$remove_if) || length(proposal$remove_if) != 1L ||
      is.na(proposal$remove_if) || !proposal$remove_if %in% c("any", "all"))
    .sc_project_fail("QC remove_if must be 'any' (OR failures) or 'all' (AND failures).")
  rules <- proposal$rules
  if (!is.list(rules) || !length(rules) || length(rules) > 32L || !is.null(names(rules)))
    .sc_project_fail("QC rules must be a nonempty unnamed array of at most 32 supported rules.")
  metrics <- evidence$metrics; cells <- metrics$cell_id
  .sc_project_ids(cells, "QC evidence cell IDs")
  base <- rep(TRUE, length(cells)); record <- evidence$mad_record
  if (!is.null(record)) {
    # Reuse the existing exact MAD-to-QC binding validation. keep_all verifies
    # the pre-score base, without imposing a component's final-cell constraint.
    baseline <- .sc_run_mad_validate(list(schema = "scagentkit.qc.mad.v1",
      rationale = "Verify the immutable pre-score cohort for this combined review.",
      risks = character(), preset_id = "keep_all", panel_hash = record$panel_hash), evidence)
    base <- cells %in% baseline$keep_cells
  }
  mad_count <- 0L
  statuses <- lapply(rules, function(rule) {
    if (!is.list(rule) || !is.character(rule$op) || length(rule$op) != 1L || is.na(rule$op))
      .sc_project_fail("Every QC rule must declare one supported typed op.")
    if (identical(rule$op, "range")) return(.sc_run_qc_rule_range(rule, metrics))
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
    list(rule = list(op = "mad_preset", preset_id = unname(rule$preset_id), panel_hash = record$panel_hash),
      selected = selected, low = rep(FALSE, length(cells)), high = rep(FALSE, length(cells)),
      unavailable = rep(FALSE, length(cells)), failed = failed)
  })
  statuses <- lapply(statuses, function(status) {
    status$failed <- status$failed & base
    status
  })
  failures <- do.call(cbind, lapply(statuses, `[[`, "failed"))
  # Outside a rule's literal group its failure is false, not a guessed match.
  removed <- if (identical(proposal$remove_if, "any")) rowSums(failures) > 0L else
    rowSums(failures) == length(statuses)
  keep <- base & !removed
  for (status in statuses) if (any(status$unavailable & keep))
    .sc_project_fail("QC metric is unavailable for one or more otherwise retained cells; unknown measurements cannot become an implicit keep or removal rule.")
  if (!any(keep)) .sc_project_fail("QC proposal would remove every cell; revise the rules before approval.")
  groups <- .sc_run_qc_groups(metrics)
  retention_groups <- lapply(seq_along(groups), function(i) {
    group <- groups[[i]]; before <- length(group$indices); after <- sum(keep[group$indices])
    list(group_id = paste0("group", i), selector = group$selector, before = before,
      retained = after, removed = before - after, fraction_retained = after / before)
  })
  canonical <- list(schema = "scagentkit.qc.rules.v1", rationale = rationale, risks = risks,
    remove_if = unname(proposal$remove_if), rules = lapply(statuses, `[[`, "rule"))
  mad_rule <- Filter(function(rule) identical(rule$op, "mad_preset"), canonical$rules)
  summary <- list(method = "typed_rules", remove_if = canonical$remove_if,
    rule_count = length(statuses), preset_id = if (length(mad_rule)) mad_rule[[1L]]$preset_id else NULL,
    original_cells = length(cells), pre_score_cells = sum(base), post_qc_cells = sum(keep),
    prefilter_removed = sum(!base), quality_removed = sum(base & !keep),
    high_rna_action = "flag only", ribo_hb_action = "diagnostic only")
  list(validated = list(proposal = canonical,
    retention = list(before = nrow(metrics), retained = sum(keep), removed = sum(!keep),
      fraction_retained = mean(keep), groups = retention_groups), keep_cells = cells[keep],
    evidence_hash = evidence$evidence_hash, summary = summary),
    statuses = statuses, failures = failures, base = base, keep = keep)
}

.sc_run_qc_rules_validate <- function(proposal, evidence) {
  .sc_run_qc_rules_evaluate(proposal, evidence)$validated
}
