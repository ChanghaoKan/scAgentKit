# Pure optional-step recommendations. These helpers never score, integrate,
# approve, delete cells, or invoke a provider. Missing optional tools stay local
# to their candidate rather than blocking unrelated scientific decisions.
.sc_run_recommend_optional_missing <- function(field, label, reason) {
  list(field = field, label = label, reason = reason)
}
.sc_run_recommend_optional_step <- function(id, title) {
  list(id = id, status = "insufficient_information", assessment = "unavailable",
    title = title, reasons = list(), completed = list(), candidates = list(),
    conflicts = list(), uncertainty = list(), missing = list(),
    next_decision = "Supply the missing study facts and review again; no computation is approved.")
}
.sc_run_recommend_optional_candidate <- function(id, label, changes, available,
                                                reasons, impact = list(), conflicts = list()) {
  list(id = id, label = label, changes = changes, available = isTRUE(available),
    reasons = as.list(reasons), impact = impact, conflicts = as.list(conflicts))
}

.sc_run_recommend_doublet_options <- function(config) {
  facts <- config$doublet_diagnostics
  if (is.null(facts) || identical(facts, FALSE)) facts <- config$recommendation_facts$doublet
  if (is.null(facts)) facts <- list()
  missing <- list(); blockers <- list()
  add <- function(field, label, reason) {
    missing[[length(missing) + 1L]] <<- .sc_run_recommend_optional_missing(field, label, reason)
  }
  text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  for (key in c("data_type", "technology", "input_source")) if (!text(facts[[key]]))
    add(paste0("doublet.", key), key, "Declare the actual assay and called-cell provenance; they are not inferred from a sample label or MEX path.")
  if (!is.logical(facts$empty_droplets_removed) || length(facts$empty_droplets_removed) != 1L || is.na(facts$empty_droplets_removed))
    add("doublet.empty_droplets_removed", "Empty droplets removed", "Declare whether upstream cell calling has already produced called cells; import does not perform it.")
  if (!is.null(facts$data_type) && !identical(facts$data_type, "scrna_droplet"))
    blockers <- c(blockers, list("This adapter supports declared droplet scRNA-seq called-cell counts only; nuclei, plate, ATAC, multiome, HT and Flex are outside its contract."))
  if (identical(facts$empty_droplets_removed, FALSE))
    blockers <- c(blockers, list("Upstream cell calling is not complete; raw MEX import is not empty-droplet removal."))
  if (!text(facts$capture$method)) add("doublet.capture.method", "Capture declaration", "Declare physical loading units explicitly; sample and donor are not capture substitutes.")
  if (!text(facts$capture$source)) add("doublet.capture.source", "Capture provenance", "Record the source of the physical loading-unit declaration.")
  if (identical(facts$capture$method, "column") && !text(facts$capture$column))
    add("doublet.capture.column", "Capture metadata column", "Choose the real metadata column of physical loading units.")
  if (identical(facts$capture$method, "single") && !text(facts$capture$id))
    add("doublet.capture.id", "Single capture ID", "An explicit single loading unit needs its own identifier and source.")
  if (!text(facts$rate$method)) add("doublet.rate.method", "Expected-rate method", "Choose a sourced manual rate or supported standard-10x full-called-cohort rule.")
  if (!text(facts$rate$source)) add("doublet.rate.source", "Expected-rate source", "An expected doublet rate is an external model assumption, never a deletion quota.")
  if (identical(facts$rate$method, "manual") && is.null(facts$rate$value))
    add("doublet.rate.value", "Manual expected rate", "Supply a sourced scalar or exact per-capture rate map.")
  if (identical(facts$rate$method, "10x_standard") && is.null(facts$full_called_cohort))
    add("doublet.full_called_cohort", "Complete called-cell cohort", "The standard-10x rule requires the full called-cell loading unit before heavy QC.")
  context <- config$context
  if (!is.null(config$recommendation_facts$columns)) {
    supplied <- config$recommendation_facts$columns
    for (role in names(supplied)) if (is.null(context$columns[[role]])) context$columns[[role]] <- supplied[[role]]
  }
  if (identical(facts$capture$method, "column") && text(facts$capture$column) && is.null(context$columns$capture))
    context$columns$capture <- facts$capture$column
  if (!text(context$species)) add("species", "Species", "Declare the actual species before preparing a supported doublet diagnostic.")
  options <- NULL
  if (!length(missing) && !length(blockers)) options <- tryCatch(
    .sc_run_doublet_options(context, facts), error = function(e) {
      blockers[[length(blockers) + 1L]] <<- conditionMessage(e); NULL
    })
  if (!is.null(options)) {
    versions <- .sc_run_doublet_versions()
    required <- c("scDblFinder", "SingleCellExperiment", "SummarizedExperiment", "S4Vectors", "BiocParallel", "xgboost")
    unavailable <- required[vapply(versions[required], function(x) is.null(x) || is.na(x), logical(1))]
    if (length(unavailable)) blockers <- c(blockers, list(paste("Optional diagnostic packages unavailable:", paste(unavailable, collapse = ", ")))) else
      tryCatch(.sc_run_doublet_classifier_versions_verify(versions[c("scDblFinder", "xgboost")]),
        error = function(e) blockers[[length(blockers) + 1L]] <<- conditionMessage(e))
  }
  list(ready = !is.null(options) && !length(missing) && !length(blockers),
    options = options, missing = missing, blockers = blockers)
}

.sc_run_recommend_doublet <- function(evidence, validated, config) {
  step <- .sc_run_recommend_optional_step("doublet", "Capture-specific doublet evidence and reviewed handling")
  step$uncertainty <- list("Predictions are not calibrated probabilities or doublet truth; homotypic doublets can remain undetected.",
    "Doublet diagnostics do not delete cells. Any predicted-cell removal requires a separate exact strategy approval.")
  record <- evidence$private$doublet_record
  if (is.null(record)) {
    preparation <- .sc_run_recommend_doublet_options(config)
    cells <- evidence$private$cell_ids
    cohort_blockers <- list()
    if (length(cells) && length(cells) < 100L)
      cohort_blockers <- list("The actual input has fewer than 100 cells; no physical capture can meet this adapter's minimum cohort size. No classifier has executed.")
    capture_values <- evidence$private$roles$capture
    if (length(cells) && length(capture_values) == length(cells) && !anyNA(capture_values)) {
      capture_counts <- .sc_run_strategy_group_counts(capture_values)
      step$completed$prerequisite_counts <- list(captures = capture_counts, scoring_executed = FALSE)
      if (any(vapply(capture_counts, function(x) x$cells < 100L, logical(1))))
        cohort_blockers <- c(cohort_blockers, list("An explicitly declared capture has fewer than 100 input cells; partial capture scoring is unsupported."))
    }
    if (!is.null(preparation$options) && length(evidence$private$feature_ids) &&
        length(evidence$private$feature_ids) < preparation$options$nfeatures)
      cohort_blockers <- c(cohort_blockers, list("Actual input features are fewer than the declared diagnostic nfeatures; the adapter will not silently clip this prerequisite."))
    pending <- preparation$ready && !length(cohort_blockers)
    step$missing <- preparation$missing
    step$reasons <- c(list("Doublet scoring has not been configured or completed; none/keep is not an assessment."), preparation$blockers, cohort_blockers)
    declared <- config$doublet_diagnostics
    if (is.null(declared) || identical(declared, FALSE)) declared <- config$recommendation_facts$doublet
    inapplicable <- is.character(declared$data_type) && length(declared$data_type) == 1L &&
      !is.na(declared$data_type) && !identical(declared$data_type, "scrna_droplet")
    step$status <- if (inapplicable) "recommend_skip" else if (pending) "recommend_execute" else "insufficient_information"
    step$assessment <- if (pending) "pending_computation" else "unavailable"
    if (inapplicable) step$completed$applicability <- list(data_type = declared$data_type,
      supported = FALSE, scoring_executed = FALSE)
    step$candidates <- list(.sc_run_recommend_optional_candidate("prepare_doublet", "Prepare supported fixed-cohort diagnostics", list(), FALSE,
      c("Preparation is not an immediately executable deletion choice; creation-time diagnostics must first be explicitly configured and scored.", unlist(c(preparation$blockers, cohort_blockers))),
      list(options_ready = preparation$ready, known_cohort_prerequisites_supported = !length(cohort_blockers))))
    step$next_decision <- "Complete the declared capture, assay and expected-rate facts; explicitly prepare diagnostics in a supported environment before reviewing any removal."
    return(step)
  }
  keep <- validated$qc_validated$keep_cells
  if (is.null(keep) && identical(evidence$summary$start_stage, "processed")) keep <- evidence$private$cell_ids
  cells <- record$cell_ids; captures <- record$capture_map
  valid <- is.character(cells) && !anyNA(cells) && !anyDuplicated(cells) &&
    identical(names(captures), cells) && !anyNA(captures) &&
    !anyDuplicated(record$predicted_cells) && all(record$predicted_cells %in% cells) &&
    !is.null(keep) && !anyDuplicated(keep) && all(keep %in% cells)
  if (!valid) {
    step$conflicts <- list("The fixed diagnostic capture/cell binding or current pure-QC selection is incomplete; no aggregate or removal candidate can be trusted.")
    return(step)
  }
  if (!identical(record$summary$status, "available")) {
    step$reasons <- c(list("Fixed prerequisites were inspected but scoring was not executed; no doublet predictions are available."), as.list(record$summary$reasons),
      as.list(record$summary$scoring$adapter_unavailable_reason))
    step$candidates <- list(.sc_run_recommend_optional_candidate("keep", "Retain QC-passing cells without claiming doublet clearance",
      list(doublet = list(method = "keep", reason = "No supported fixed doublet scoring is available.")), TRUE, "Unsupported diagnostics do not justify deleting cells."))
    return(step)
  }
  predicted <- record$predicted_cells
  counts <- lapply(unique(unname(captures)), function(id) {
    group <- cells[captures == id]
    list(capture = id, input_cells = length(group), qc_retained = sum(group %in% keep),
      predicted_doublets = sum(group %in% predicted), predicted_after_qc = sum(group %in% intersect(predicted, keep)))
  })
  removal <- intersect(keep, predicted)
  step$completed <- list(scoring = "fixed_full_input", captures = counts,
    predicted_doublets = length(predicted), predicted_after_qc = length(removal),
    qc_retained = length(keep), refit_after_qc = FALSE)
  step$assessment <- "assessed"
  step$status <- if (length(removal)) "recommend_execute" else "recommend_skip"
  step$reasons <- list("Fixed capture-specific predictions have been compared with the exact current pure-QC selection; review both retention and predicted-cell removal.")
  removal_available <- length(removal) > 0L && length(keep) - length(removal) >= 21L && !identical(evidence$summary$start_stage, "processed")
  step$candidates <- list(
    .sc_run_recommend_optional_candidate("keep", "Keep current QC-passing cells", list(doublet = list(method = "keep", reason = "Review fixed predictions without automatic removal.")), TRUE,
      "Retain all QC-passing cells; a predicted class is not measured truth.", list(removed = 0L, retained = length(keep))),
    .sc_run_recommend_optional_candidate("remove_predicted", "Review removal of fixed predictions intersecting QC", list(doublet = list(method = "remove_predicted", reason = "Author review of exact fixed predicted-cell intersection with approved QC.")), removal_available,
      c("Only after explicit author approval; no new scoring or deletion quota.", if (!removal_available) "No nonempty supported raw-entry removal leaving at least 21 cells is available."),
      list(removed = length(removal), retained = length(keep) - length(removal))))
  step$next_decision <- "Review per-capture predictions and their QC intersection; explicitly approve keep or the exact removal candidate."
  step
}

.sc_run_recommend_batch <- function(evidence, validated, config) {
  step <- .sc_run_recommend_optional_step("batch", "Declared technical batch and biological-design assessment")
  step$uncertainty <- list("Multiple samples alone do not imply technical batch or justify Harmony.",
    "Identifiability does not prove correction benefit or preserved biology; compare unintegrated and corrected embeddings without optimizing a universal quality score.")
  context <- evidence$summary$background_facts
  if (is.null(context)) context <- config$context
  columns <- evidence$summary$declared_roles
  if (is.null(columns)) columns <- context$columns
  if (is.null(columns)) columns <- config$context$columns
  technical <- context$design$technical_batch
  if (is.null(technical)) technical <- config$context$design$technical_batch
  if (is.null(technical)) technical <- config$recommendation_facts$batch$technical_batch
  none <- .sc_run_recommend_optional_candidate("none", "Keep the unintegrated analysis", list(batch = list(method = "none",
    reason = "Author choice to preserve unintegrated analysis while reviewing technical and biological evidence.")), TRUE,
    "No correction is performed; this choice alone does not establish that batch effects were assessed.")
  step$candidates <- list(none)
  roles <- evidence$private$roles
  selected <- validated$selected_cells
  if (is.null(selected)) selected <- validated$qc_validated$keep_cells
  if (is.null(selected) && identical(evidence$summary$start_stage, "processed")) selected <- evidence$private$cell_ids
  indices <- match(selected, evidence$private$cell_ids)
  if (!is.null(selected) && !anyNA(indices)) roles <- lapply(roles, function(x) x[indices]) else roles <- list()
  if (identical(technical, FALSE)) {
    step$status <- "recommend_skip"; step$assessment <- "assessed"
    step$completed <- list(technical_batch_declared = FALSE)
    step$reasons <- list("The author explicitly declared no technical batch; retain unintegrated analysis rather than treating multiple samples as a correction target.")
    step$next_decision <- "Confirm the declared design and retain none, or revise the technical provenance before considering correction."
    return(step)
  }
  batch <- roles$batch
  if (!is.null(columns$batch) && length(batch) > 0L && !anyNA(batch) &&
      all(nzchar(trimws(as.character(batch)))) && length(unique(batch)) == 1L) {
    step$status <- "recommend_skip"; step$assessment <- "assessed"
    step$completed <- list(technical_levels = 1L, retained_cells = length(batch))
    step$reasons <- list("The explicitly declared technical batch column has one retained level; between-batch correction is not applicable.")
    step$next_decision <- "Retain unintegrated analysis for this single technical level; check any other nuisance factor explicitly."
    return(step)
  }
  add <- function(field, label, reason) step$missing[[length(step$missing) + 1L]] <<- .sc_run_recommend_optional_missing(field, label, reason)
  if (!identical(technical, TRUE)) add("batch.technical_batch", "Technical batch provenance", "Declare whether the observed grouping is technical; sample/donor labels alone are insufficient.")
  if (is.null(columns$batch) || !length(batch)) add("columns.batch", "Technical batch column", "Choose actual technical metadata with complete retained-cell assignments; no sample/capture role is guessed.")
  bio <- intersect(c("group", "condition", "treatment"), names(columns))
  if (!length(bio)) add("columns.condition", "Biological contrast column", "Declare group, condition or treatment so technical and biological confounding can be checked.")
  if (length(step$missing)) return(step)
  if (anyNA(batch) || any(!nzchar(trimws(as.character(batch))))) {
    add("columns.batch", "Complete technical labels", "Every retained cell needs a nonempty technical batch value.")
    return(step)
  }
  choice <- list(method = "harmony", group_by_vars = unname(columns$batch), theta = 2, lambda = 1,
    sigma = .1, max_iter = 10L, nclust = min(50L, max(2L, length(batch) - 1L)), nested_biology = "block",
    reason = "Explicit candidate for author-reviewed embedding-only evaluation of a declared identifiable technical batch; not a claim of optimal parameters.")
  audit_evidence <- evidence
  audit_evidence$summary$declared_roles <- columns
  audit_evidence$summary$background_facts$design$technical_batch <- TRUE
  audit <- tryCatch(.sc_run_harmony_choice(choice, audit_evidence, roles,
    identical(evidence$summary$start_stage, "processed")), error = function(e) list(executable = FALSE, blockers = list(list(message = conditionMessage(e)))))
  conflicts <- lapply(audit$blockers, function(x) x$message)
  version <- tryCatch(as.character(utils::packageVersion("harmony")), error = function(e) NULL)
  dependency <- if (is.null(version)) "Optional harmony package is not installed; none remains available." else
    if (!grepl("^2[.]0[.]", version)) paste0("Harmony ", version, " is outside the supported 2.0.x contract; none remains available.") else NULL
  step$completed <- list(design_audit = audit$audit)
  step$conflicts <- conflicts
  if (length(conflicts)) {
    step$status <- "insufficient_information"; step$assessment <- "assessed"
    step$reasons <- list("Declared design does not support automatic technical/biological separation; correction is not recommended from these facts.")
    for (block in audit$blockers) if (identical(block$code, "biological_roles_missing"))
      add("columns.condition", "Complete biological design", block$message)
  } else {
    step$status <- "recommend_execute"; step$assessment <- "pending_computation"
    step$reasons <- list("The declared technical and biological design passes the supported identifiability audit; evaluate Harmony against none, rather than assuming correction helps.")
  }
  if (!is.null(dependency)) {
    step$status <- "insufficient_information"; step$assessment <- "unavailable"
    step$reasons <- c(step$reasons, list(dependency))
  }
  step$candidates[[2]] <- .sc_run_recommend_optional_candidate("harmony", "Evaluate supported Harmony embedding correction",
    list(batch = choice), isTRUE(audit$executable) && is.null(dependency),
    c("These are explicit software candidate parameters requiring author review, not optimized biological recommendations.", dependency),
    list(operation = "embedding_only", cells_deleted = 0L, assays_changed = FALSE, correction_executed = FALSE), conflicts)
  step$next_decision <- "Review design conflicts and the unintegrated baseline; explicitly approve an available complete batch choice before computation."
  step
}
