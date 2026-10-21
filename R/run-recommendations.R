# Deterministic local advice is evidence, never an approval or a calibrated
# scientific-quality score. The complete projection joins the existing review
# hash, so using a candidate still requires the normal exact-plan submission.
.sc_run_recommend_fact_editable <- function(state) {
  isTRUE(state$config$strategy) && identical(state$config$start_stage, "qc") &&
    is.null(state$config$subcluster_origin) && !length(state$approvals) &&
    !length(intersect(state$completed, c("strategy_apply", "qc_apply", "strategy_selection", "strategy_preprocess", "strategy_basis", "analysis"))) &&
    is.null(state$files$qc_object) && is.null(state$files$strategy_basis) &&
    state$stage %in% c("strategy_propose", "strategy_apply") &&
    state$status %in% c("awaiting_review", "awaiting_configuration", "rejected")
}
.sc_run_recommend_fact_value <- function(facts, key) {
  for (part in strsplit(key, ".", fixed = TRUE)[[1L]]) {
    if (!is.list(facts)) return(NULL)
    facts <- facts[[part]]
  }
  facts
}
.sc_run_recommend_fact_fields <- function(steps, state, columns, facts = state$config$recommendation_facts) {
  descriptions <- list(
    "columns.sample" = "Explicit sample column for a newly measured grouped QC panel",
    "columns.qc_group" = "Explicit quality-group column for a newly measured QC panel",
    "columns.capture" = "Physical capture/loading-unit metadata column",
    "columns.batch" = "Declared technical batch metadata column",
    "columns.condition" = "Biological condition/contrast metadata column",
    "columns.group" = "Explicit biological-group metadata column",
    "columns.treatment" = "Explicit treatment metadata column",
    "columns.donor" = "Explicit donor metadata column",
    "batch.technical_batch" = "Does the grouping represent a technical batch?",
    "batch.source" = "Source of the technical-batch declaration",
    "doublet.data_type" = "Actual assay type",
    "doublet.technology" = "Actual droplet technology",
    "doublet.input_source" = "Called-cell matrix provenance",
    "doublet.empty_droplets_removed" = "Has upstream cell calling removed empty droplets?",
    "doublet.full_called_cohort" = "Is the original complete called-cell loading unit supplied?",
    "doublet.capture.method" = "How are physical loading units declared?",
    "doublet.capture.column" = "Physical capture/loading-unit metadata column",
    "doublet.capture.id" = "Explicit single physical capture ID",
    "doublet.capture.source" = "Source of the capture/loading-unit declaration",
    "doublet.rate.method" = "Expected doublet-rate policy",
    "doublet.rate.value" = "Sourced expected doublet fraction (not a deletion quota)",
    "doublet.rate.source" = "Source of the expected-rate assumption")
  choices <- list(
    "doublet.data_type" = c(scrna_droplet = "Droplet scRNA-seq called cells", nuclei = "Nuclei-only (not supported by this adapter)", plate = "Plate-based", other = "Other/unsupported"),
    "doublet.capture.method" = c(column = "An explicit metadata column", single = "One explicitly declared physical loading unit"),
    "doublet.rate.method" = c(manual = "Manually sourced expected rate", `10x_standard` = "Standard Chromium full-called-cohort rule"))
  choices[["doublet.technology"]] <- c(`10x_chromium_standard` = "Standard Chromium (explicit declaration)", declared_droplet_other = "Other droplet protocol with a sourced manual rate", flex = "Flex/unsupported", ht = "HT/unsupported")
  missing <- unlist(lapply(steps, function(step) lapply(step$missing, function(x) x)), recursive = FALSE)
  missing <- lapply(missing, function(item) {
    if (identical(item$field, "context.columns.sample")) item$field <- "columns.sample"
    item
  })
  known_keys <- function(value, prefix = "") {
    if (!is.list(value) || is.null(names(value))) return(prefix)
    unlist(lapply(names(value), function(key) known_keys(value[[key]],
      if (nzchar(prefix)) paste(prefix, key, sep = ".") else key)), use.names = FALSE)
  }
  if (identical(state$config$metadata_role_draft$status, "needs_selection")) missing <- c(missing,
    list(list(field = "columns.sample", reason = state$config$metadata_role_draft$notice)))
  keys <- unique(c(vapply(missing, function(x) as.character(x$field), character(1)), known_keys(facts)))
  # Provenance is requested only when a declaration needs it; the author does
  # not have to fill unrelated optional protocols or algorithm parameters.
  if ("batch.technical_batch" %in% keys) keys <- c(keys, "batch.source")
  keys <- unique(keys[keys %in% names(descriptions)])
  rate_value <- facts$doublet$rate$value
  if (!is.null(rate_value) && (is.list(rate_value) || length(rate_value) != 1L))
    keys <- setdiff(keys, "doublet.rate.value") # Per-capture maps remain typed R facts; do not present a scalar editor.
  lapply(keys, function(key) {
    value <- .sc_run_recommend_fact_value(facts, key)
    options <- choices[[key]]
    if (grepl("^columns[.]|^doublet[.]capture[.]column$", key)) options <- stats::setNames(columns, columns)
    boolean <- key %in% c("batch.technical_batch", "doublet.empty_droplets_removed", "doublet.full_called_cohort")
    reasons <- vapply(Filter(function(x) identical(x$field, key), missing), function(x) x$reason, character(1))
    list(key = key, label = descriptions[[key]], type = if (boolean) "boolean" else if (!is.null(options)) "select" else
        if (identical(key, "doublet.rate.value")) "number" else "text",
      options = if (is.null(options)) list() else lapply(names(options), function(id) list(value = id, label = unname(options[[id]]))),
      value = value, required = TRUE,
      reason = if (length(reasons)) paste(unique(reasons), collapse = " ") else "Record the provenance of this explicit declaration; no study fact is inferred.")
  })
}
.sc_run_recommendations <- function(root, state, validated, evidence, pc_review, scan) {
  steps <- list(.sc_run_recommend_qc(evidence, validated),
    .sc_run_recommend_doublet(evidence, validated, state$config),
    .sc_run_recommend_pc(pc_review, validated),
    .sc_run_recommend_batch(evidence, validated, state$config),
    .sc_run_recommend_resolution(scan, validated))
  for (step in steps) {
    if (!step$status %in% c("recommend_execute", "recommend_skip", "insufficient_information") ||
        !step$assessment %in% c("assessed", "pending_computation", "unavailable"))
      stop("Recommendation status is outside the supported local contract.", call. = FALSE)
  }
  input <- .sc_run_get(root, state, "input")
  columns <- if (inherits(input, "Seurat")) names(input[[]]) else character()
  facts <- state$config$recommendation_facts
  if (is.null(facts)) facts <- list()
  if (!is.null(state$config$doublet_diagnostics)) {
    declared <- state$config$doublet_diagnostics[c("data_type", "technology", "input_source",
      "empty_droplets_removed", "full_called_cohort", "capture", "rate")]
    facts$doublet <- utils::modifyList(declared, if (is.null(facts$doublet)) list() else facts$doublet)
  }
  if (is.null(facts$batch$technical_batch) && !is.null(state$config$context$design$technical_batch))
    facts$batch$technical_batch <- state$config$context$design$technical_batch
  # Existing explicit roles are shown as facts, never guessed from column names.
  for (role in names(state$config$context$columns)) if (is.null(facts$columns[[role]]))
    facts$columns[[role]] <- state$config$context$columns[[role]]
  review_state <- state
  review_state$status <- "awaiting_review"
  list(schema = "scagentkit.recommendations.v1", policy_version = "1",
    binding = list(input_hash = state$input_hash, config_hash = state$config_hash,
      evidence_hash = evidence$evidence_hash, scan_hash = scan$hash,
      pc_basis_sha256 = pc_review$artifact$sha256),
    steps = steps, completed = list("Raw-count, ID and declared-role validation; local QC measurements and proposal impacts are saved."),
    fact_editable = .sc_run_recommend_fact_editable(review_state), fact_values = facts,
    metadata_role_candidates = state$config$metadata_role_draft,
    fact_fields = .sc_run_recommend_fact_fields(steps, state, columns, facts),
    next_decision = if (is.null(scan))
      "Review the measured QC candidates, missing optional facts, PC rule and batch alternatives together. Save the complete corrected plan, then approve this first scientific strategy; local computation stops at measured resolution review." else
      "Compare the measured resolution candidates and conflicts. Apply a candidate to the draft, save the complete strategy, and approve the measured selection; current markers and annotation then have their own third scientific submission.",
    review_boundaries = list("1. Complete initial strategy: QC, optional doublet handling, PC rule and batch choice.",
      "2. Measured resolution selection on the saved graph, cells and PCs.", "3. Complete current annotation proposal before label writeback and export."),
    limitations = list("These deterministic candidates are review aids, not universal biological standards, calibrated probabilities or an optimality score.",
      "Missing optional facts or dependencies affect that path only; continuing other computation does not mark it assessed or certify complete QC.",
      "Applying a candidate changes only a local draft; saving reconstructs the exact R review and approval remains explicit. No provider is called."))
}
.sc_run_recommendations_verify <- function(record) {
  rec <- record$details$recommendations
  if (is.null(rec))
    stop("Saved recommendation evidence is missing; review is invalid.", call. = FALSE)
  if (!identical(rec$schema, "scagentkit.recommendations.v1") ||
      !identical(rec$policy_version, "1") ||
      !identical(rec$binding$input_hash, record$input_hash) ||
      !identical(rec$binding$config_hash, record$config_hash) ||
      !identical(rec$binding$evidence_hash, record$evidence_hash) ||
      !identical(rec$binding$scan_hash, record$details$cluster_diagnostics$hash) ||
      !identical(rec$binding$pc_basis_sha256, record$details$pc_diagnostics$artifact$sha256))
    stop("Saved recommendation evidence or its calculation binding changed; review is stale.", call. = FALSE)
  invisible(rec)
}
.sc_run_scientific_assessment <- function(root, state) {
  if (!isTRUE(state$config$strategy) || is.null(state$files$strategy_review)) return(NULL)
  record <- .sc_run_get(root, state, "strategy_review")
  rec <- .sc_run_recommendations_verify(record)
  unassessed <- vapply(Filter(function(step) !identical(step$assessment, "assessed"), rec$steps), `[[`, character(1), "id")
  # Recommendations were issued before execution. Current durable artifacts
  # can establish completion of a numeric rule, never biological certification.
  if (!is.null(state$files$strategy_basis)) unassessed <- setdiff(unassessed, "pcs")
  if (!is.null(state$files$cluster_scan)) unassessed <- setdiff(unassessed, "resolution")
  if (!is.null(state$files$strategy_batch)) unassessed <- setdiff(unassessed, "batch")
  assessed_steps <- lapply(rec$steps, function(step) {
    if (identical(step$id, "qc")) {
      selected <- Filter(function(candidate) identical(candidate$changes$qc,
        record$details$canonical_proposal$qc), step$candidates)
      step$conflicts <- c(step$conflicts, unlist(lapply(selected, `[[`, "conflicts"), recursive = FALSE))
    }
    if (identical(step$id, "resolution")) {
      selected <- Filter(function(candidate)
        identical(as.numeric(candidate$changes$clustering$resolution),
          as.numeric(record$details$canonical_proposal$clustering$resolution)), step$candidates)
      step$conflicts <- c(step$conflicts, unlist(lapply(selected, `[[`, "conflicts"), recursive = FALSE))
    }
    step
  })
  unresolved <- Filter(function(step) length(step$missing) || length(step$conflicts), assessed_steps)
  unresolved_ids <- vapply(unresolved, `[[`, character(1), "id")
  qc <- record$details$canonical_proposal$qc
  rules_policy <- !is.null(qc) && qc$schema %in% c("scagentkit.qc.rules.v1", "scagentkit.qc.rules.v2")
  empty <- rules_policy && is.list(qc$rules) && length(qc$rules) == 0L
  keep <- rules_policy && any(vapply(qc$rules, function(rule)
    identical(rule$op, "mad_preset") && identical(rule$preset_id, "keep_all"), logical(1)))
  if (empty || keep || is.null(qc)) unassessed <- unique(c("qc", unassessed))
  list(schema = "scagentkit.scientific-assessment.v1", certified_qc = FALSE,
    workflow_status = state$status, unassessed_steps = as.list(unassessed),
    unresolved_steps = as.list(unresolved_ids),
    unresolved_details = lapply(unresolved, function(step) step[c("id", "missing", "conflicts", "uncertainty")]),
    qc_choice = if (is.null(qc)) "processed_reuse_raw_quality_unassessed" else
      if (empty) "no_additional_filtering_quality_deferred" else
      if (keep) "keep_all_quality_deferred" else "explicit_reviewed_quality_rule",
    message = if (length(union(unassessed, unresolved_ids))) paste0("Scientific assessment remains incomplete or has unresolved evidence for: ", paste(union(unassessed, unresolved_ids), collapse = ", "),
      ". Software completion does not certify full QC or cell identities.") else
      "Declared decisions and supported diagnostics are recorded; software completion is not biological or QC certification.",
    source_review_hash = record$hash)
}
