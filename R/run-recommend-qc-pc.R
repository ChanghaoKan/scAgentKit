# Pure local interpretation of existing, bound QC/PC evidence. These functions
# neither execute analysis nor choose a policy on behalf of the author.
.sc_run_recommend_qc_pc_step <- function(id, title) {
  list(id = id, status = "insufficient_information", assessment = "unavailable", title = title,
    reasons = list(), completed = list(), candidates = list(), conflicts = list(),
    uncertainty = list(), missing = list(), next_decision = "Supply the missing evidence and review a fresh proposal.")
}

.sc_run_recommend_qc <- function(evidence, validated) {
  step <- .sc_run_recommend_qc_pc_step("qc", "Assess measured quality flags and compare QC choices")
  step$uncertainty <- as.list(c("MAD flags are descriptive outliers, not biological quality truth; high RNA is flag-only and ribosomal/haemoglobin fractions are diagnostic-only.",
    "Keep-all is a comparison or an explicit deferral; quality assessment is incomplete until the author reviews the evidence and its applicability."))
  if (identical(evidence$summary$start_stage, "processed")) {
    step$status <- "recommend_skip"
    step$reasons <- list("Processed entry explicitly reuses its input; this step has not assessed raw quality or performed new QC.")
    step$next_decision <- "Confirm processed reuse or start a raw project to assess quality."
    return(step)
  }
  panel <- evidence$summary$qc_mad
  qc <- validated$proposal$qc
  if (is.null(panel) || is.null(evidence$qc$mad_record) || is.null(qc)) {
    step$missing <- list(list(field = "qc_mad", label = "Bound QC measurements and MAD panel",
      reason = "Actual sample/group measurements, flags and executable candidate impacts are unavailable."))
    return(step)
  }
  if (!identical(panel, evidence$qc$mad_record$summary)) {
    step$missing <- list(list(field = "qc_mad", label = "Consistent saved MAD summary",
      reason = "The displayed summary differs from the exact bound MAD record; review fresh measurements."))
    return(step)
  }
  step$assessment <- "assessed"
  step$sample_comparison <- evidence$qc$summary$sample_comparison
  step$completed <- list("Measured group QC distributions and saved MAD flags.")
  replace_preset <- function(id) {
    choice <- qc
    if (identical(choice$schema, "scagentkit.qc.mad.v1")) {
      choice$preset_id <- id
    } else if (identical(choice$schema, "scagentkit.qc.rules.v1")) {
      index <- which(vapply(choice$rules, function(rule) identical(rule$op, "mad_preset"), logical(1)))
      if (length(index) != 1L) return(NULL)
      choice$rules[[index]]$preset_id <- id
    } else return(NULL)
    choice
  }
  baseline_choice <- replace_preset("keep_all")
  if (is.null(baseline_choice)) {
    step$missing <- list(list(field = "qc.mad_preset", label = "An explicit bound MAD choice",
      reason = "No existing MAD selector can be replaced without changing the declared range/combination policy."))
    return(step)
  }
  evaluate <- function(choice) tryCatch(.sc_run_qc_validate(choice, evidence$qc), error = function(e) list(error = conditionMessage(e)))
  baseline <- evaluate(baseline_choice)
  current <- evaluate(qc)
  if (!is.null(baseline$error) || !is.null(current$error)) {
    step$assessment <- "unavailable"
    step$conflicts <- as.list(c(baseline$error, current$error))
    return(step)
  }
  for (group in panel$groups) {
    if (isTRUE(group$pre_score == 0L)) next
    for (metric in c("nCount", "nFeature", "percent_mt")) {
      measured <- group$metrics[[metric]]
      if (!isTRUE(measured$available)) step$missing <- c(step$missing, list(list(
        field = paste0("qc.groups.", group$group_id, ".", metric),
        label = paste(group$value, metric), reason = paste(measured$unavailable_reasons, collapse = " "))))
    }
    warnings <- unlist(group$warnings, use.names = FALSE)
    separated <- warnings[grepl("large-gap|separated subpopulations|multimodal", warnings, ignore.case = TRUE)]
    if (length(separated)) step$conflicts <- c(step$conflicts, as.list(paste(group$value, separated)))
  }
  if (identical(panel$grouping$id, "unstratified_input")) step$missing <- c(step$missing,
    list(list(field = "context.columns.sample", label = "Declared quality/sample groups",
      reason = "The input is explicitly unstratified; per-sample QC suitability cannot be inferred.")))
  range_only <- baseline
  if (identical(qc$schema, "scagentkit.qc.rules.v1")) {
    range_proposal <- qc
    range_proposal$rules <- Filter(function(rule) !identical(rule$op, "mad_preset"), qc$rules)
    if (length(range_proposal$rules)) range_only <- evaluate(range_proposal)
  }
  if (!is.null(range_only$error)) {
    step$conflicts <- list(paste("The original range-only policy cannot be evaluated:", range_only$error))
    return(step)
  }
  flags <- c("low_count", "low_feature", "high_mt")
  counts <- vapply(flags, function(flag) {
    values <- lapply(Filter(function(group) !isTRUE(group$pre_score == 0L), panel$groups), function(group) group$flags[[flag]])
    if (!length(values) || any(vapply(values, is.null, logical(1)))) NA_real_ else sum(unlist(values))
  }, numeric(1))
  step$reasons <- as.list(paste0(names(counts), ": ", ifelse(is.na(counts), "unavailable", counts), " measured pre-score flags."))
  # Use measured joint/union impacts and nonzero marginal flags to select
  # comparisons. This is not a static list of six presets or a quality score.
  implicated <- c("keep_all", if (isTRUE(counts["low_count"] > 0)) "low_counts3",
    if (isTRUE(counts["low_feature"] > 0)) "low_features3", if (isTRUE(counts["high_mt"] > 0)) "high_mt3")
  for (id in c("conservative_and3", "any_quality3")) {
    entry <- Filter(function(item) identical(item$preset_id, id), panel$presets)
    if (length(entry) == 1L && isTRUE(entry[[1L]]$available) && isTRUE(entry[[1L]]$quality_removed > 0)) implicated <- c(implicated, id)
  }
  groups <- baseline$retention$groups
  candidates <- lapply(unique(implicated), function(id) {
    saved <- Filter(function(item) identical(item$preset_id, id), panel$presets)
    choice <- replace_preset(id)
    result <- evaluate(choice)
    conflicts <- character()
    if (!is.null(result$error)) conflicts <- c(conflicts, result$error)
    if (length(saved) != 1L || !isTRUE(saved[[1L]]$available)) conflicts <- c(conflicts,
      if (length(saved)) saved[[1L]]$unavailable_reasons else "The candidate is absent from the saved finite panel.")
    impact <- list()
    if (is.null(result$error)) {
      added <- setdiff(baseline$keep_cells, result$keep_cells)
      restored <- setdiff(result$keep_cells, baseline$keep_cells)
      impact <- list(retained = result$retention$retained, removed = result$retention$removed,
        additional_removed_vs_keep_all = length(added), restored_vs_keep_all = length(restored),
        range_only_retained = length(range_only$keep_cells),
        new_removed_within_range_keep = length(setdiff(range_only$keep_cells, result$keep_cells)),
        reintroduced_range_failed = length(setdiff(result$keep_cells, range_only$keep_cells)),
        removed_vs_current = length(setdiff(current$keep_cells, result$keep_cells)),
        restored_vs_current = length(setdiff(result$keep_cells, current$keep_cells)),
        groups = result$retention$groups, outer_logic = choice$remove_if,
        comparison = "Exact full proposal versus keep_all under the same original ranges and outer logic; not an invented range-first intersection.")
      if (impact$reintroduced_range_failed > 0L) conflicts <- c(conflicts,
        "The existing outer combination reintroduces range-failed cells; this cannot be endorsed as post-range filtering. Reconsider the combination explicitly, without an automatic AND/OR change.")
      if (length(restored)) conflicts <- c(conflicts, "This candidate restores cells relative to the same-policy keep-all comparison; inspect the exact combination before choosing.")
      if (result$retention$retained < 21L) conflicts <- c(conflicts, "Fewer than 21 retained cells cannot support the current fixed 20-neighbor raw analysis graph.")
      empty <- vapply(seq_along(groups), function(i) groups[[i]]$retained > 0L && result$retention$groups[[i]]$retained == 0L, logical(1))
      if (any(empty)) conflicts <- c(conflicts, "The candidate empties a previously retained sample/group; establish context before endorsing deletion.")
      if (id != "keep_all" && impact$new_removed_within_range_keep == 0L) conflicts <- c(conflicts, "No additional range-passing cells are removed under the existing outer logic; this is a redundant comparison, not additional QC evidence.")
    }
    list(id = id, label = if (id == "keep_all") "Keep-all comparison / defer quality deletion" else saved[[1L]]$label,
      changes = list(qc = choice), available = !length(conflicts),
      reasons = as.list(if (id == "keep_all") "Preserves the explicit original range/combination policy as a comparison; does not certify acceptable quality." else
        paste0("Measured ", id, " flags implicate this saved policy; compare its exact impact, not just its name.")),
      impact = impact, conflicts = as.list(conflicts))
  })
  # Equivalent cell selections are disclosed, without ranking equal policies
  # by retained counts or claiming that the least deletion is biologically best.
  selections <- lapply(candidates, function(item) {
    result <- evaluate(item$changes$qc)
    if (is.null(result$error)) result$keep_cells else NULL
  })
  for (i in seq_along(candidates)) candidates[[i]]$impact$equivalent_candidates <- as.list(vapply(
    which(vapply(seq_along(candidates), function(j) j != i && !is.null(selections[[i]]) && identical(selections[[i]], selections[[j]]), logical(1))),
    function(j) candidates[[j]]$id, character(1)))
  step$candidates <- candidates
  current_preset <- if(identical(qc$schema,"scagentkit.qc.mad.v1")) qc$preset_id else {
    selector <- Filter(function(rule) identical(rule$op,"mad_preset"),qc$rules)
    if(length(selector)==1L) selector[[1L]]$preset_id else NULL
  }
  eligible <- Filter(function(item) identical(item$id,"any_quality3") && isTRUE(item$available) &&
    isTRUE(item$impact$new_removed_within_range_keep>0) && isTRUE(item$impact$removed<=.1*baseline$retention$before) &&
    all(vapply(item$impact$groups,function(group) isTRUE(group$retained>=.8*group$before),logical(1))),candidates)
  # A bounded draft comparison is not a scientific default or approved deletion.
  step$draft_preselection <- if(length(eligible)==1L && identical(current_preset,"keep_all") && !length(step$conflicts) && !length(step$missing))
    list(candidate_id="any_quality3",automatic=TRUE,draft_only=TRUE,
      reason="Measured joint evidence is complete and this OR comparison removes <=10% overall and <=20% of each group. These are UI risk caps, not biological optimality. Preselected draft is unsaved and unapproved.") else
    list(candidate_id=NULL,automatic=FALSE,draft_only=TRUE,
      reason="No preselection: preserve an explicit saved policy, incomplete/conflicting evidence, or an unavailable/nonredundant OR comparison outside the 10% total/20% group draft caps.")
  step$completed <- c(step$completed, list("Computed exact candidate impacts under the unchanged range and outer-combination policy."))
  executable <- any(vapply(candidates, function(item) item$id != "keep_all" && item$available, logical(1)))
  if (!length(step$missing) && !length(step$conflicts) && executable) step$status <- "recommend_execute"
  if (!length(step$missing) && !length(step$conflicts) && all(is.finite(counts)) && all(counts == 0)) {
    step$status <- "recommend_skip"
    step$reasons <- c(step$reasons, list("All three measured flags are zero in every eligible group; there is no measured reason to add a MAD deletion rule. This is not completed biological quality validation."))
  }
  if (any(is.finite(counts) & counts > 0) && !executable) step$conflicts <- c(step$conflicts,
    list("Measured flags exist but no supported nonredundant candidate is executable under the current range/combination policy."))
  step$next_decision <- "Review group distributions, unknowns, flag overlap, exact impacts and study context; choose a justified available candidate or explicitly defer quality deletion. No preset is a universal first choice."
  step
}

.sc_run_recommend_pc <- function(pc_review, validated) {
  step <- .sc_run_recommend_qc_pc_step("pcs", "Review the computed-PC reference rule")
  step$uncertainty <- list("80% / 85% use the variance sum of the first at most 50 actually computed PCs, not total expression/HVG variance or a biologically optimal PC count.")
  step$next_decision <- "Review the exact reference and supported candidates; the author selects the PC policy without automatic clipping or replacement of an explicit fixed choice."
  if (identical(pc_review$status, "processed_reuse")) {
    step$status <- "recommend_skip"
    step$reasons <- list("Processed reuse computes no new PCA or PC selection; prior analysis quality is not established here.")
    return(step)
  }
  if (identical(pc_review$status, "pending_computation")) {
    step$assessment <- "pending_computation"
    step$reasons <- list("Actual PCA and variance candidates are not yet computed; the visible component bound is not measured numerical rank.")
    if (isTRUE(validated$proposal$analysis$npcs >= 2L)) step$status <- "recommend_execute"
    step$missing <- list(list(field = "strategy_basis", label = "Approved PCA checkpoint",
      reason = "Compute the approved request before interpreting actual 80% / 85% crossings."))
    return(step)
  }
  record <- pc_review$actual$top50_candidates
  verified <- tryCatch({ .sc_run_pc_verify(record); TRUE }, error = function(e) FALSE)
  if (!identical(pc_review$status, "computed") || !verified ||
      !isTRUE(pc_review$actual$available_pcs == record$total_computed_pcs) ||
      !isTRUE(pc_review$actual$available_pcs == validated$proposal$analysis$npcs)) {
    step$missing <- list(list(field = "pc_diagnostics", label = "Intact actual PCA diagnostics",
      reason = "A verified computed reference matching the current component request is unavailable."))
    return(step)
  }
  step$assessment <- "assessed"
  step$completed <- list("Read the verified saved PCA reference, exact cumulative fractions and supported crossings.")
  step$reasons <- list(paste0("Reference uses ", record$reference_pcs, " of ", record$total_computed_pcs, " actually computed PCs."))
  if (record$shortfall) step$uncertainty <- c(step$uncertainty, list(paste0("The reference is ", record$shortfall_count, " PCs below target 50; missing components are not invented.")))
  step$candidates <- lapply(names(record$candidates), function(id) {
    item <- record$candidates[[id]]
    list(id = id, label = paste0(as.integer(100 * item$threshold), "% internal reference: ", item$ndim, " PCs"),
      changes = list(pcs = list(method = "computed_top50", threshold = item$threshold)),
      available = isTRUE(item$supported), reasons = list(item$reason),
      impact = list(ndim = item$ndim, reference_pcs = record$reference_pcs,
        total_computed_pcs = record$total_computed_pcs, shortfall = record$shortfall,
        fraction_at_selected = record$cumulative_fraction[[item$ndim]], denominator = record$denominator),
      conflicts = if (item$supported) list() else list("The exact crossing selects one PC and is unsupported; no clipping to two is permitted."))
  })
  if (identical(record$elbow$status, "measured")) step$candidates <- c(step$candidates,
    list(list(id = "elbow", label = paste0("Chord-distance elbow: ", record$elbow$ndim, " PCs"),
      changes = list(pcs = list(method = "fixed", ndim = record$elbow$ndim)), available = record$elbow$ndim >= 2L,
      reasons = list(record$elbow$interpretation), impact = record$elbow, conflicts = list())))
  if (any(vapply(step$candidates, `[[`, logical(1), "available"))) step$status <- "recommend_execute" else
    step$conflicts <- list("Neither empirical crossing is supported; explicitly revise the request/rule or select a supported fixed dimension after review.")
  if (identical(validated$proposal$pcs$method, "fixed")) {
    step$status <- "recommend_skip"
    step$conflicts <- list()
    step$reasons <- c(step$reasons, list("Retain the author's explicit fixed PC choice; empirical alternatives are comparisons requiring a new explicit author decision."))
  }
  step
}
