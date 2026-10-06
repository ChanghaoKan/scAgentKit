# One optional strategy boundary, with existing typed QC embedded in its review.
.sc_run_strategy_design <- function(value) {
  if (is.null(value)) return(NULL)
  value <- .sc_run_strategy_fields(value, character(), c("type", "technical_batch", "notes"), "context$design")
  for (key in intersect(c("type", "notes"), names(value)))
    value[[key]] <- .sc_run_strategy_text(value[[key]], paste0("context$design$", key))
  if (!is.null(value$technical_batch) && !identical(value$technical_batch, TRUE) && !identical(value$technical_batch, FALSE))
    stop("context$design$technical_batch must be an explicit logical fact.", call. = FALSE)
  value
}
.sc_run_strategy_review_hash <- function(record) .sc_run_hash(record[setdiff(names(record), "hash")])
.sc_run_strategy_scope_config_hash <- function(config) {
  fields <- c("context", "assay", "counts_layer", "normalized_layer", "cluster_column", "start_stage")
  if (!is.null(config$cycle_diagnostics)) fields <- c(fields, "cycle_diagnostics")
  if (!is.null(config$doublet_diagnostics)) fields <- c(fields, "doublet_diagnostics")
  if (!is.null(config$prefilter)) fields <- c(fields, "prefilter")
  if (!is.null(config$qc_mad)) fields <- c(fields, "qc_mad")
  if (!is.null(config$subcluster_origin)) fields <- c(fields, "subcluster_origin", "subcluster_creation")
  .sc_run_hash(config[fields])
}
.sc_run_strategy_batch_source <- function(plan) {
  if (!identical(plan$batch$method, "harmony") || !requireNamespace("harmony", quietly = TRUE))
    return(NULL)
  .sc_run_harmony_source()
}
.sc_run_strategy_pc_review <- function(root, state, validated, evidence) {
  policy <- validated$proposal$pcs
  result <- list(schema = "scagentkit.strategy.pc-review.v1",
    status = if (state$config$start_stage == "processed") "processed_reuse" else "pending_computation",
    policy = policy,
    interpretation = if (state$config$start_stage == "processed")
      "Supplied analysis is reused; this strategy does not compute or select new PCs." else
      "Approval selects a deterministic PC rule. Actual dimensions and 80/85% diagnostics are unavailable until the approved QC and PCA checkpoint has completed; no pre-approval PCA is run.")
  artifact <- state$files$strategy_basis
  if (is.null(artifact)) return(result)
  path <- file.path(root, artifact$path)
  if (!file.exists(path) || nzchar(Sys.readlink(path)) ||
      !identical(artifact$sha256, .sc_project_sha_file(path)))
    stop("Cached PCA artifact changed; the strategy review is stale.", call. = FALSE)
  basis <- .sc_run_get(root, state, "strategy_basis")
  execution <- basis@misc$strategy_execution$basis
  if (is.null(execution) || !identical(execution$dependency_hash, validated$dependency_hashes$basis) ||
      !identical(execution$parameters, validated$proposal$analysis))
    stop("Cached PCA parameters or dependency fingerprint differ from the reviewed basis.", call. = FALSE)
  expected <- if (!is.null(validated$selected_cells)) validated$selected_cells else
    if (!is.null(validated$qc_validated)) validated$qc_validated$keep_cells else evidence$private$cell_ids
  if (!identical(colnames(basis), expected))
    stop("Cached PCA cell IDs or order differ from the exact reviewed QC/selection.", call. = FALSE)
  # Reading the existing PCA does not execute a batch choice. A manual/design
  # blocker must remain reviewable even while the raw PCA cache is reusable.
  pca_plan <- validated$proposal
  pca_plan$batch <- list(method = "none", reason = "Read the immutable raw PCA diagnostics without executing a batch operation.")
  measured <- .sc_run_strategy_pca_evidence(basis,
    .sc_run_strategy_runtime_settings(pca_plan), select = FALSE)
  .sc_run_pc_verify(measured$top50_candidates)
  if (!identical(execution$pca, measured))
    stop("Cached PCA diagnostic record differs from the actual reduction.", call. = FALSE)
  result$status <- "computed"
  result$artifact <- artifact
  result$basis_dependency_hash <- execution$dependency_hash
  result$actual <- measured
  result$interpretation <- "Actual saved PCA diagnostics are bound to the immutable basis artifact and its scientific dependency fingerprint. The 80/85% candidates describe the first min(50, computed PCs), not total expressed-gene variance or a proven biological optimum."
  result
}
.sc_run_strategy_batch_review <- function(root, state, validated, evidence) {
  artifact <- state$files$strategy_batch
  if (is.null(artifact)) return(NULL)
  if (!identical(validated$proposal$batch$method, "harmony"))
    stop("Cached batch correction does not match the reviewed batch method.", call. = FALSE)
  path <- file.path(root, artifact$path)
  if (!file.exists(path) || nzchar(Sys.readlink(path)) ||
      !identical(artifact$sha256, .sc_project_sha_file(path)))
    stop("Cached Harmony artifact changed; the strategy review is stale.", call. = FALSE)
  corrected <- .sc_run_get(root, state, "strategy_batch")
  execution <- corrected@misc$strategy_execution$batch
  expected <- if (!is.null(validated$selected_cells)) validated$selected_cells else
    if (!is.null(validated$qc_validated)) validated$qc_validated$keep_cells else evidence$private$cell_ids
  if (is.null(execution) || !identical(execution$dependency_hash, validated$dependency_hashes$batch) ||
      is.null(state$files$strategy_basis) ||
      !identical(execution$basis_sha256, state$files$strategy_basis$sha256) ||
      !identical(colnames(corrected), expected))
    stop("Cached Harmony basis, dependency fingerprint or literal cell scope differs from the reviewed strategy.", call. = FALSE)
  list(artifact = artifact, dependency_hash = execution$dependency_hash,
    basis_sha256 = execution$basis_sha256)
}
.sc_run_strategy_review_publish <- function(root, state, validated, evidence) {
  .sc_run_subcluster_guard(root, state)
  .sc_run_subcluster_strategy(state, validated, evidence)
  qc <- NULL
  if (!is.null(validated$qc_validated)) {
    state <- .sc_run_put(root, state, "qc_validated", validated$qc_validated)
    state <- .sc_run_qc_preview_publish(root, state, validated$qc_validated, evidence$qc)
    qc <- .sc_run_get(root, state, "qc_preview")$details
  }
  state <- .sc_run_put(root, state, "strategy_validated", validated)
  summary <- evidence$summary
  record <- list(schema = "scagentkit.strategy.review.v1", input_hash = state$input_hash,
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    calculation_scope_hash = .sc_run_strategy_scope_config_hash(state$config),
    evidence_hash = evidence$evidence_hash,
    cell_scope_hash = .sc_run_hash(if (!is.null(validated$selected_cells)) validated$selected_cells else
      if (is.null(validated$qc_validated)) evidence$private$cell_ids else validated$qc_validated$keep_cells),
    details = list(canonical_proposal = validated$proposal,
      background = list(facts = summary$background_facts, missing = summary$missing_facts),
      quality = summary$quality, qc_impact = qc, capabilities = summary$capabilities,
      applicability = list(executable = validated$executable, blockers = validated$blockers, details = validated$applicability),
      dependency_hashes = validated$dependency_hashes,
      execution_plan = if (state$config$start_stage == "processed") list("Reuse the supplied QC and processed analysis; compute current markers after approval.") else
        list("Apply the exact projected QC once under this strategy approval.", "LogNormalize, VST HVGs, HVG scaling and PCA.",
          "Select reviewed PCs; explicit PCA neighbors and optional UMAP.", "Explicit Louvain resolution and optional local numeric diagnostics.",
          "Compute markers and stop for the separate annotation review."),
      source = list(kind = if (!is.null(state$files$manual_strategy)) "manual_typed_strategy" else "saved_provider_response",
        provider = state$config$provider, facts = "User declarations and measured local aggregates; proposal inferences are not facts."),
      limitations = summary$interpretation))
  adopted <- .sc_run_suggestion_source(root, state, "strategy", validated$proposal)
  if (!is.null(adopted)) {
    if (isTRUE(adopted$matches_current)) record$details$source <- adopted
    else record$details$source$previous_suggestion <- adopted
  }
  record$details$pc_diagnostics <- .sc_run_strategy_pc_review(root, state, validated, evidence)
  if (state$config$start_stage != "processed")
    record$details$capabilities$qc_rules <- list(schema = "scagentkit.qc.rules.v1",
      remove_if = c("any", "all"), max_rules = 32L, max_mad_predicates = 1L,
      operations = if (is.null(summary$qc_mad)) "range" else c("range", "mad_preset"),
      interpretation = "any/all combines failure predicates (OR/AND). Saved minimal-prefilter eligibility remains mandatory; doublet removal is a separate explicit choice.")
  if (!is.null(state$config$subcluster_origin)) {
    record$details$subcluster <- list(
      parent_project_id = state$config$subcluster_origin$parent$project_id,
      parent_revision = state$config$subcluster_origin$parent$revision,
      parent_scope_hash = state$config$subcluster_origin$parent_scope_hash,
      selected_scope_hash = state$config$subcluster_origin$scope_hash,
      selected_clusters = as.list(state$config$subcluster_origin$selected_clusters),
      selected_cells = length(state$config$subcluster_origin$selected_cells),
      retained_cells = validated$applicability$retained_cells,
      choices = state$config$subcluster_creation$choices,
      source_context = state$config$subcluster_creation$source_context,
      source_scores = state$config$subcluster_creation$source_scores,
      reference = state$config$subcluster_creation$reference,
      plan_source = state$config$subcluster_creation$plan_source,
      boundary = "One exact child strategy decision; fresh raw-count normalization/PCA/clusters. Parent selection and inherited score metadata are source provenance, not biological truth or child regression/filtering authority.")
  }
  batch_source <- .sc_run_strategy_batch_source(validated$proposal)
  if (!is.null(batch_source)) record$details$batch_runtime_source <- batch_source
  else if (identical(validated$proposal$batch$method, "harmony"))
    record$details$batch_runtime_policy <- "The optional Harmony runtime is unavailable. The first explicitly approved execution must bind its audited runtime source; dependency installation does not substitute for design approval."
  batch_cache <- .sc_run_strategy_batch_review(root, state, validated, evidence)
  if (!is.null(batch_cache)) record$details$batch_cache <- batch_cache
  if (!is.null(validated$harmony)) {
    record$details$harmony <- list(choice = validated$harmony$choice,
      audit = validated$harmony$audit, applicability = validated$harmony$applicability,
      executable = validated$harmony$executable, blockers = validated$harmony$blockers,
      dependency_hash = validated$dependency_hashes$batch)
    if (state$config$start_stage != "processed") record$details$execution_plan <- c(record$details$execution_plan[1:3],
      list("Execute the exact reviewed Harmony correction on selected PCA dimensions in a separate immutable batch checkpoint; preserve raw counts, metadata and cell IDs. Neighbors, UMAP and clustering use the approved corrected reduction."),
      record$details$execution_plan[-(1:3)])
  }
  if (!is.null(summary$prefilter)) {
    record$details$prefilter <- summary$prefilter
    record$details$prefilter_evidence_hash <- evidence$private$prefilter_record$evidence_hash
  }
  if (!is.null(summary$qc_mad)) {
    record$details$mad_panel <- summary$qc_mad
    record$details$qc_mad <- list(panel_hash = evidence$private$mad_record$panel_hash,
      evidence_hash = evidence$private$mad_record$evidence_hash,
      choice = if (is.null(validated$qc_validated)) NULL else validated$qc_validated$proposal,
      impact = validated$applicability$qc_mad)
    record$details$execution_plan <- c(list(if (identical(validated$proposal$qc$schema, "scagentkit.qc.rules.v1"))
      "Use the saved pre-score eligibility and exact sample-aware MAD statistics. One central approval selects the explicit range/MAD failure rules and OR/AND combination; no cells outside the prefilter cohort can be restored." else
      "Use the saved sample-aware MAD statistics from the explicit pre-score cohort. One central approval selects one finite preset for all declared QC groups; no per-group approval or automatic preset change is performed."),
      record$details$execution_plan)
  }
  if (!is.null(summary$cycle_diagnostics)) {
    record$details$cycle_diagnostics <- summary$cycle_diagnostics
    record$details$applicability$cycle <- validated$applicability$cycle
    record$details$execution_plan <- c(list("Use the saved nonfiltering full-input cycle diagnostic reference; preserve counts and cell identities. Regression defaults to none; only the exact approved full/difference scores may enter scaling."),
      record$details$execution_plan)
  }
  if (!is.null(summary$doublet_diagnostics)) {
    record$details$doublet_diagnostics <- summary$doublet_diagnostics
    record$details$doublet_evidence_hash <- evidence$private$doublet_record$evidence_hash
    record$details$applicability$doublet <- validated$applicability$doublet
    record$details$execution_plan <- c(list(if (!is.null(summary$prefilter))
      "Use the fixed scDblFinder predictions from the explicitly prefiltered pre-score cohort by declared capture/loading unit. Prefilter-excluded cells remain unscored, with explicit provenance. Keep is the default; after approved quality QC, remove_predicted removes only the exact reviewed intersection. Scores are predictions, not calibrated probabilities or truth." else
      "Use the fixed full-input scDblFinder predictions by declared capture/loading unit. Keep is the default. After approved QC, only the exact reviewed remove_predicted intersection may be removed in a separate derived selection checkpoint; scores are predictions, not calibrated probabilities or truth."),
      record$details$execution_plan)
  }
  record$hash <- .sc_run_strategy_review_hash(record)
  .sc_run_put(root, state, "strategy_review", record)
}
.sc_run_strategy_review_verify <- function(root, state) {
  .sc_run_subcluster_guard(root, state)
  if (is.null(state$files$strategy_review)) stop("Strategy review is missing.", call. = FALSE)
  record <- .sc_run_get(root, state, "strategy_review")
  evidence <- .sc_run_get(root, state, "strategy_evidence")
  saved <- .sc_run_get(root, state, "strategy_validated")
  current <- .sc_run_strategy_validate(saved$proposal, evidence)
  .sc_run_subcluster_strategy(state, current, evidence)
  if (!is.null(state$config$subcluster_origin) &&
      (is.null(record$details$subcluster) ||
       !identical(record$details$subcluster$parent_scope_hash, state$config$subcluster_origin$parent_scope_hash) ||
       !identical(record$details$subcluster$selected_scope_hash, state$config$subcluster_origin$scope_hash) ||
       !identical(record$details$subcluster$choices, state$config$subcluster_creation$choices)))
    stop("Child strategy review origin or explicit inheritance choices changed.", call. = FALSE)
  if (!is.null(record$details$batch_runtime_source) &&
      !identical(record$details$batch_runtime_source, .sc_run_strategy_batch_source(saved$proposal)))
    stop("Harmony runtime source changed; this strategy approval is stale. Explicitly revise the saved strategy to review the current source and rebuild only its derived correction.", call. = FALSE)
  pc_review <- record$details$pc_diagnostics
  # Initial approval remains a rule approval when its PCA is subsequently
  # computed. A revised review with cached diagnostics binds that exact cache.
  if (is.null(pc_review) || !identical(pc_review$policy, saved$proposal$pcs))
    stop("PC review rule differs from the exact canonical strategy.", call. = FALSE)
  if (identical(pc_review$status, "computed") &&
      !identical(pc_review, .sc_run_strategy_pc_review(root, state, saved, evidence)))
    stop("Cached PC diagnostics or artifact binding changed; approve a fresh strategy review.", call. = FALSE)
  if (!is.null(record$details$batch_cache) &&
      !identical(record$details$batch_cache, .sc_run_strategy_batch_review(root, state, saved, evidence)))
    stop("Cached Harmony artifact binding changed; approve a fresh strategy review.", call. = FALSE)
  if (!is.null(saved$harmony) && !identical(record$details$harmony,
      list(choice = saved$harmony$choice, audit = saved$harmony$audit,
        applicability = saved$harmony$applicability, executable = saved$harmony$executable,
        blockers = saved$harmony$blockers, dependency_hash = saved$dependency_hashes$batch)))
    stop("Harmony parameters or reviewed design audit changed; the strategy approval is stale.", call. = FALSE)
  if (!is.null(state$config$prefilter)) {
    prefilter <- .sc_run_get(root, state, "prefilter")
    .sc_run_prefilter_verify(prefilter)
    if (!identical(prefilter, evidence$private$prefilter_record) ||
        !identical(prefilter$options, state$config$prefilter) ||
        !identical(record$details$prefilter, evidence$summary$prefilter) ||
        !identical(record$details$prefilter_evidence_hash, prefilter$evidence_hash))
      stop("Prefilter scope or authoritative artifact changed; the strategy approval is stale.", call. = FALSE)
  }
  if (!is.null(state$config$qc_mad)) {
    mad <- .sc_run_get(root, state, "qc_mad")
    .sc_run_mad_verify(mad)
    if (!identical(mad, evidence$private$mad_record) ||
        !identical(mad$options, state$config$qc_mad) ||
        !identical(record$details$mad_panel, evidence$summary$qc_mad) ||
        !identical(record$details$qc_mad$panel_hash, mad$panel_hash) ||
        !identical(record$details$qc_mad$evidence_hash, mad$evidence_hash) ||
        !identical(record$details$qc_mad$choice, saved$qc_validated$proposal) ||
        !identical(record$details$qc_mad$impact, saved$applicability$qc_mad))
      stop("MAD panel, preset or authoritative artifact changed; the strategy approval is stale.", call. = FALSE)
  }
  if (!is.null(state$config$cycle_diagnostics)) {
    cycle <- .sc_run_get(root, state, "cycle_diagnostics")
    .sc_run_cycle_verify(cycle)
    if (!identical(cycle, evidence$private$cycle_record) || !identical(cycle$options, state$config$cycle_diagnostics) ||
        !identical(record$details$cycle_diagnostics, evidence$summary$cycle_diagnostics))
      stop("Cycle diagnostic scope or authoritative artifact changed; the strategy approval is stale.", call. = FALSE)
  }
  if (!is.null(state$config$doublet_diagnostics)) {
    doublet <- .sc_run_get(root, state, "doublet_diagnostics")
    .sc_run_doublet_verify(doublet)
    if (!identical(doublet, evidence$private$doublet_record) ||
        !identical(doublet$options, state$config$doublet_diagnostics) ||
        !identical(record$details$doublet_diagnostics, evidence$summary$doublet_diagnostics) ||
        !identical(record$details$doublet_evidence_hash, doublet$evidence_hash) ||
        !identical(record$cell_scope_hash, .sc_run_hash(saved$selected_cells)))
      stop("Doublet diagnostic scope or selected literal cells changed; the strategy approval is stale.", call. = FALSE)
  }
  if (!identical(record$hash, .sc_run_strategy_review_hash(record)) ||
      !identical(record$input_hash, state$input_hash) || !identical(record$calculation_scope_hash, .sc_run_strategy_scope_config_hash(state$config)) ||
      !identical(record$implementation_hash, state$implementation_hash) ||
      !identical(record$evidence_hash, evidence$evidence_hash) || !identical(current, saved) ||
      !identical(record$details$canonical_proposal, saved$proposal) ||
      !identical(record$details$dependency_hashes, saved$dependency_hashes))
    stop("Strategy evidence, parameters or review fingerprint changed; inspect and approve a fresh proposal.", call. = FALSE)
  if (!is.null(saved$qc_validated)) .sc_run_qc_preview_verify(root, state)
  record
}
.sc_run_strategy_pending <- function(root, state, validated, evidence) {
  state$stage <- "strategy_propose"
  record <- .sc_run_strategy_review_verify(root, state)
  files <- intersect(c("input", "prefilter", "qc_mad", "qc_evidence", "strategy_evidence", "cycle_diagnostics", "doublet_diagnostics", "manual_strategy",
    "strategy_validated", "strategy_review", "qc_validated", "qc_preview", "qc_preview_plot", "strategy_basis", "strategy_batch"), names(state$files))
  .sc_run_pending(state, "strategy", list(plan = validated$proposal, review_hash = record$hash),
    evidence$evidence_hash, "strategy_apply", file_names = files)
}
.sc_run_strategy_decision_details <- function(root, state, reviewer, reason) {
  record <- .sc_run_strategy_review_verify(root, state)
  list(kind = "strategy", proposal_hash = state$pending$hash, review_hash = record$hash,
    evidence_hash = record$evidence_hash, cell_scope_hash = record$cell_scope_hash,
    input_hash = state$input_hash, config_hash = state$config_hash,
    implementation_hash = state$implementation_hash, dependency_hashes = record$details$dependency_hashes,
    reviewer = reviewer, reason = reason, decision_id = paste0("decision-", state$revision + 1L),
    boundary = "One strategy decision authorizes its exact QC and supported analysis; annotation requires later evidence review.")
}
.sc_run_strategy_authorize <- function(state, decision) {
  previous <- state$strategy_authorizations
  for (key in names(decision$dependency_hashes)) {
    old <- previous[[key]]
    if (is.null(old) || !identical(old$dependency_hash, decision$dependency_hashes[[key]]))
      previous[[key]] <- list(dependency_hash = decision$dependency_hashes[[key]], decision_id = decision$decision_id)
  }
  state$strategy_authorizations <- previous
  state
}
.sc_run_strategy_require <- function(root, state) {
  .sc_run_require_approval(state, "strategy")
  record <- .sc_run_strategy_review_verify(root, state)
  for (key in names(record$details$dependency_hashes))
    if (!identical(state$strategy_authorizations[[key]]$dependency_hash, record$details$dependency_hashes[[key]]))
      stop("Strategy component authorization is stale.", call. = FALSE)
  .sc_run_get(root, state, "strategy_validated")
}
.sc_run_strategy_manual_boundary <- function(root, state) {
  validated <- .sc_run_get(root, state, "strategy_validated")
  blockers <- validated$blockers
  messages <- vapply(blockers, function(blocker) blocker$message, character(1))
  boundary <- list(dispatch = "not_sent", operation = "batch", blockers = blockers,
    message = paste(c("The reviewed batch strategy is blocked and no correction has run.", messages), collapse = " "))
  if (identical(state$status, "awaiting_configuration") && identical(state$diagnostics$strategy_manual_boundary, boundary)) return(state)
  state$status <- "awaiting_configuration"; state$nodes$strategy_apply <- "NEEDS_CONFIGURATION"
  state$diagnostics$strategy_manual_boundary <- boundary
  state <- .sc_run_event(state, "strategy_manual_required", boundary)
  .sc_run_save(root, state)
  state
}
.sc_run_strategy_apply_gate <- function(root, state) {
  validated <- .sc_run_strategy_require(root, state)
  if (!isTRUE(validated$executable)) return(.sc_run_strategy_manual_boundary(root, state))
  state$diagnostics$strategy_manual_boundary <- NULL
  if (!is.null(state$strategy_return)) {
    previous <- state$strategy_return
    state$strategy_return <- NULL
    state$stage <- previous$stage; state$status <- previous$status
    state$pending <- previous$pending; state$approved <- previous$approved
    state <- .sc_run_event(state, "strategy_text_revision_reused", list(dependency_hashes = validated$dependency_hashes,
      restored_stage = state$stage, reason = "Only explanatory text changed; calculations and downstream scientific authorization are unchanged."))
    .sc_run_save(root, state)
    return(state)
  }
  next_stage <- if (state$config$start_stage == "processed") "markers" else
    if (is.null(state$files$qc_object)) "qc_apply" else
    if (!is.null(state$config$doublet_diagnostics) && is.null(state$files$strategy_selected)) "strategy_selection" else
    if ((!is.null(state$config$cycle_diagnostics) || !is.null(state$config$doublet_diagnostics)) &&
        is.null(state$files$strategy_preprocess)) "strategy_preprocess" else
    if (is.null(state$files$strategy_basis)) "strategy_basis" else
    if (identical(validated$proposal$batch$method, "harmony") && is.null(state$files$strategy_batch)) "strategy_batch" else
    if (is.null(state$files$strategy_neighbors)) "strategy_neighbors" else
    if (is.null(state$files$analysis)) "strategy_cluster" else
    if (is.null(state$files$markers)) "markers" else
    if (is.null(state$files$annotation_evidence)) "annotation_evidence" else "annotation_propose"
  .sc_run_checkpoint(root, state, "strategy_apply", next_stage)
}
.sc_run_strategy_propose_locked <- function(root, state, proposal, reviewer, reason) {
  .sc_run_subcluster_guard(root, state)
  if (!isTRUE(state$config$strategy)) stop("Strategy mode was not enabled for this project.", call. = FALSE)
  if (state$status %in% c("complete", "running") || "annotation_apply" %in% state$completed || !is.null(state$files$annotated))
    stop("Strategy revisions require a stopped project before annotation writeback; start a new project for an applied result.", call. = FALSE)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) || !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; strategy revision is stale.", call. = FALSE)
  evidence <- .sc_run_get(root, state, "strategy_evidence")
  validated <- .sc_run_strategy_validate(proposal, evidence)
  .sc_run_subcluster_strategy(state, validated, evidence)
  old <- if (is.null(state$files$strategy_validated)) NULL else .sc_run_get(root, state, "strategy_validated")
  changed <- if (is.null(old)) names(validated$dependency_hashes) else names(validated$dependency_hashes)[vapply(names(validated$dependency_hashes), function(key)
    !identical(validated$dependency_hashes[[key]], old$dependency_hashes[[key]]), logical(1))]
  cached_runtime_changed <- FALSE
  old_source <- new_source <- NULL
  if (identical(validated$proposal$batch$method, "harmony") && !is.null(state$files$strategy_batch)) {
    old_source <- .sc_run_get(root, state, "strategy_batch")@misc$strategy_execution$batch$source
    new_source <- .sc_run_strategy_batch_source(validated$proposal)
    if (is.null(new_source))
      stop("Cached Harmony requires its runtime dependency. Install it explicitly before revising; the correction cannot be silently reused or skipped.", call. = FALSE)
    cached_runtime_changed <- !identical(old_source, new_source)
    if (cached_runtime_changed) changed <- unique(c(changed, "batch", "neighbors", "clustering", "umap"))
  }
  all_downstream <- c("markers", "annotation_evidence", "annotation_request", "annotation_response", "annotation_validated", "annotation_review", "manual_annotation", "annotated")
  drop <- character()
  if ("qc" %in% changed) drop <- c(drop, "qc_object", "strategy_selected", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "analysis")
  else if ("selection" %in% changed) drop <- c(drop, "strategy_selected", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "analysis")
  else if ("preprocess" %in% changed) drop <- c(drop, "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "analysis")
  else if ("basis" %in% changed) drop <- c(drop, "strategy_basis", "strategy_batch", "strategy_neighbors", "analysis")
  else if (length(intersect(changed, c("pcs", "batch")))) drop <- c(drop, "strategy_batch", "strategy_neighbors", "analysis")
  else if (length(intersect(changed, c("neighbors", "umap")))) drop <- c(drop, "strategy_neighbors", "analysis")
  # A processed entry's supplied foundation is immutable input to this run;
  # revising a batch none/manual boundary must retain it for current markers.
  if (state$config$start_stage == "processed") drop <- setdiff(drop, "analysis")
  else if ("clustering" %in% changed) drop <- c(drop, "analysis")
  if (length(changed)) drop <- c(drop, all_downstream, names(state$files)[startsWith(names(state$files), "output:")])
  return_state <- if (!length(changed) && !is.null(old) && !state$stage %in% c("strategy_propose", "strategy_apply"))
    list(stage = state$stage, status = state$status, pending = state$pending, approved = state$approved) else NULL
  old_pending <- state$pending$hash
  dropped_files <- intersect(drop, names(state$files))
  state$files <- state$files[!names(state$files) %in% unique(c(drop, "strategy_request", "strategy_response"))]
  invalidated_stages <- character()
  if ("qc_object" %in% drop) invalidated_stages <- c(invalidated_stages, "qc_apply")
  if ("strategy_selected" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_selection")
  if ("strategy_preprocess" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_preprocess")
  if ("strategy_basis" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_basis")
  if ("strategy_batch" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_batch")
  if ("strategy_neighbors" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_neighbors")
  if ("analysis" %in% drop) invalidated_stages <- c(invalidated_stages, "strategy_cluster", "analysis")
  if (length(changed)) invalidated_stages <- c(invalidated_stages, "markers", "annotation_evidence", "annotation_propose", "annotation_apply", "finalize")
  state$completed <- setdiff(state$completed, invalidated_stages)
  for (key in invalidated_stages) state$nodes[[key]] <- "INVALIDATED"
  if (length(changed)) state$output <- NULL
  state$strategy_return <- return_state
  state$pending <- NULL; state$approved <- NULL; state$failure <- NULL
  state <- .sc_run_put(root, state, "manual_strategy", validated$proposal)
  state <- .sc_run_strategy_review_publish(root, state, validated, evidence)
  if (cached_runtime_changed) state <- .sc_run_event(state, "cached_harmony_runtime_invalidated", list(
    cached_runtime_changed = TRUE, old_source_hash = .sc_run_hash(old_source), new_source_hash = .sc_run_hash(new_source),
    preserved_basis_sha256 = state$files$strategy_basis$sha256,
    invalidated_active_artifacts = dropped_files,
    scientific_dependency_hashes_unchanged = !is.null(old) && identical(old$dependency_hashes, validated$dependency_hashes),
    policy = "A fresh central approval binds the current audited runtime. Recompute only the derived Harmony correction and downstream analysis; preserve input, QC and raw PCA."))
  state <- .sc_run_event(state, "strategy_revised", list(reviewer = reviewer, reason = reason,
    changed_dependencies = changed, invalidated_active_artifacts = dropped_files,
    cached_runtime_changed = cached_runtime_changed,
    previous_proposal_hash = old_pending, history_and_versioned_files_retained = TRUE,
    retained_component_authorizations = state$strategy_authorizations[setdiff(names(state$strategy_authorizations), changed)]))
  state <- .sc_run_strategy_pending(root, state, validated, evidence)
  .sc_run_save(root, state)
  .sc_run_public(state)
}

#' Revise a stopped strategy while retaining unaffected analysis checkpoints
#' @param project_dir Durable strategy project directory.
#' @param proposal Complete typed strategy proposal, never executable R.
#' @param project_id,input_hash,expected_revision Exact inspected project snapshot.
#' @param reviewer,reason Analyst identity and rationale.
#' @return Awaiting concentrated strategy review. No computation or provider call.
#' @export
sc_run_strategy_revise <- function(project_dir, proposal, project_id, input_hash,
                                   expected_revision, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_run_review_hash_string(input_hash, "input_hash")
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; inspect this project.", call. = FALSE)
  if (is.null(expected_revision)) stop("An exact inspected revision is required.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
  .sc_run_strategy_propose_locked(root, state, proposal, reviewer, reason)
}
