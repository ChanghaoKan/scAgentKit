#!/usr/bin/env Rscript
# Read-only projection of one operator-selected, registered coordinator. This
# bridge never saves state, executes analysis or dispatches a provider.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L || !identical(args[[1L]], "inspect")) quit(status = 2L)
project_dir <- args[[2L]]; response_file <- args[[4L]]
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(script) != 1L) quit(status = 2L)
source(file.path(dirname(normalizePath(script, mustWork = TRUE)), "run_workbench_projection.R"), local = TRUE)
suppressPackageStartupMessages(library(scAgentKit))
answer <- tryCatch({
  ns <- asNamespace("scAgentKit")
  get <- function(name) base::get(name, envir = ns, inherits = FALSE)
  root <- get(".sc_run_root")(project_dir)
  state_path <- file.path(root, "state.rds")
  before <- get(".sc_project_sha_file")(state_path)
  run <- tryCatch(scAgentKit::sc_run_inspect(root), error = identity)
  current_inspection <- !inherits(run, "error")
  # Public inspection has already verified every checkpoint, source, pending
  # binding and subcluster origin. Load the same authoritative envelope to get
  # the original verified journal, rather than its nonauthoritative JSON copy.
  state <- get(".sc_run_load")(root, verify = inherits(run, "error"), verify_subcluster = inherits(run, "error"))
  if (inherits(run, "error")) {
    if (!identical(state$status, "complete") || !identical(state$stage, "complete")) stop(run)
    # Older completed sources can have immutable review records from an older
    # engine. Validate the dedicated source scope, then display saved records
    # without rebuilding them under today's review rules or granting authority.
    scAgentKit::sc_run_subcluster_scope(root)
    run <- get(".sc_run_public")(state)
    for (name in c("qc_preview", "strategy_review", "annotation_review"))
      run[[name]] <- if (!is.null(state$files[[name]])) get(".sc_run_get")(root, state, name) else NULL
    run$review_node <- NULL
    run$inspection_mode <- "immutable_saved_records"
    run$inspection_boundary <- "Completed source records verified by saved artifact hashes; current review authority is not reopened."
  } else run$inspection_mode <- "current_inspector"
  if (!identical(state$config_hash, get(".sc_run_hash")(state$config)))
    stop("Saved configuration no longer matches its authority.")
  head <- if (length(state$history)) tail(state$history, 1)[[1L]]$hash else NULL
  if (!identical(run$project_id, state$project_id) || !identical(run$input_hash, state$input_hash) ||
      !identical(run$revision, state$revision) || !identical(run$history_head, head))
    stop("Run changed during read-only inspection; refresh the registered scope.")
  # Keep scientific facts, not arbitrary newly added journal/config fields.
  # Never expose secret-bearing or per-cell private detail fields to the page.
  plain <- .sc_wb_plain
  allowed <- c("stage", "kind", "reason", "reviewer", "source", "skipped", "input_hash", "config_hash",
    "implementation_hash", "proposal_hash", "preview_hash", "review_hash", "evidence_hash", "hash",
    "decision_id", "revision_reviewed", "revision_requested", "revision_created", "request_hash",
    "response_hash", "response_status", "suggestion_hash", "request_preview_hash", "parameters_hash",
    "rules_hash", "cell_scope_hash", "review_path", "target_column", "files", "output", "provider",
    "cost", "cost_usd", "cost_state", "charged_or_held_usd", "cached", "dispatch", "external", "simulated",
    "authority", "scientific_approval_required", "mode", "message", "retry", "error", "operation",
    "previous_proposal_hash", "previous_preview_hash", "previous_review_hash", "dependency_hashes",
    "canonical_proposal", "reused", "invalidated", "parent_project_id", "parent_revision", "parent_scope_hash",
    "selected_scope_hash", "selected_cell_count", "selected_clusters", "choices", "plan_source", "owner",
    "application_id", "integration_revision", "column", "outside", "supersedes", "annotation_hash",
    "review_hashes", "result", "snapshot_hash", "policy_hash", "execution_hash", "generation",
    "child_project_id", "child_input_hash", "child_revision", "origin_scope_hash", "output_path",
    "output_sha256", "parent_input_hash", "parent_output_sha256", "retained_cell_scope_hash",
    "annotation_decision_id", "annotation_review_hash", "apply_hash", "fields", "selected_cells",
    "retained_cells", "excluded_selected_cells", "restored_application_id", "undo_id", "request_id",
    "status", "active", "interpretation", "created_at")
  event_view <- function(event) {
    details <- event$details[intersect(allowed, names(event$details))]
    if (!is.null(details$provider)) details$provider <- get(".sc_run_annotation_review_provider")(details$provider)
    list(sequence = event$sequence, created_at = event$created_at, action = event$action,
      details = plain(details), omitted_detail_fields = as.list(setdiff(names(event$details), allowed)),
      previous_hash = event$previous_hash, hash = event$hash)
  }
  events <- lapply(state$history, event_view)
  integration <- NULL; integration_sha <- NULL
  if (!is.null(state$config$subcluster_origin)) {
    integration_path <- file.path(root, "reintegration", "state.rds")
    if (file.exists(integration_path)) integration_sha <- get(".sc_project_sha_file")(integration_path)
    journal <- get(".sc_run_subcluster_integration")(root)
    origin <- state$config$subcluster_origin
    expected <- list(child_project_id = state$project_id, child_input_hash = state$input_hash,
      parent_project_id = origin$parent$project_id, parent_scope_hash = origin$parent_scope_hash,
      origin_scope_hash = origin$scope_hash)
    for (event in journal$history) for (field in names(expected))
      if (!identical(event$details[[field]], expected[[field]])) stop("Foreign integration event scope.")
    integration_events <- lapply(journal$history, event_view)
    integration <- list(schema = "scagentkit.subcluster.integration-history.v1", revision = journal$revision,
      head = if (length(journal$history)) tail(journal$history, 1)[[1L]]$hash else NULL,
      events = integration_events, total_events = length(integration_events), provided_events = length(integration_events),
      truncated = FALSE, authority = if (is.null(integration_sha)) "not_created" else "reintegration/state.rds",
      hash_verification = "Original independent integration envelope, complete event hash chain and immutable derived files verified by the coordinator; displayed details are allowlisted.")
    if (!identical(integration_sha, if (file.exists(integration_path)) get(".sc_project_sha_file")(integration_path) else NULL))
      stop("Integration history changed during inspection.")
  }
  summary <- function(name) {
    record <- state$files[[paste0("output:output/", name)]]
    if (is.null(record)) return(NULL)
    jsonlite::fromJSON(file.path(root, record$path), simplifyVector = FALSE)
  }
  qc <- if (!is.null(state$files$qc_evidence)) get(".sc_run_get")(root, state, "qc_evidence")$summary else NULL
  artifacts <- lapply(state$files[startsWith(names(state$files), "output:")], function(record)
    list(path = record$path, sha256 = record$sha256))
  bundle_records <- state$files[startsWith(names(state$files), "output:bundle/")]
  bundle_scope_hash <- NULL
  stage_bundle <- NULL
  if (!is.null(state$output$bundle)) {
    if (!identical(state$output$bundle, file.path(root, "bundle"))) stop("Foreign saved bundle path.")
    exported <- jsonlite::fromJSON(file.path(root, "bundle", "project.json"), simplifyVector = FALSE)
    exported_ids <- unname(vapply(exported$cells, `[[`, character(1), "cellId"))
    if (is.null(state$files$annotation_evidence)) stop("No saved annotation cell authority for bundle.")
    expected <- get(".sc_run_get")(root, state, "annotation_evidence")$private$input_cells
    if (!is.data.frame(expected) || !all(c("cell_id", "cluster") %in% names(expected)))
      stop("Missing saved annotation cell membership.")
    expected <- expected[order(enc2utf8(expected$cell_id), method = "radix"), , drop = FALSE]
    exported_clusters <- unname(vapply(exported$cells, `[[`, character(1), "clusterId"))
    if (!identical(exported_ids, unname(expected$cell_id)) ||
        !identical(exported_clusters, unname(expected$cluster)))
      stop("Bundle exact cell IDs/membership differ from saved annotation scope.")
    bundle_scope_hash <- get(".sc_run_hash")(expected)
  }
  # A pending annotation already has immutable analysis and marker snapshots.
  # Export those saved facts to a private temporary directory, never the run.
  # This is display only: no candidates, metadata, model calls or raw assets.
  if (is.null(state$output$bundle) && state$stage %in% c("annotation_propose", "annotation_apply")) {
    if (!current_inspection || identical(state$status, "complete")) stop("No current pending-stage authority.")
    stage_bundle <- (function() {
      names <- c("analysis", "markers", "annotation_evidence")
      records <- state$files[names]
      if (length(records) != 3L || any(vapply(records, is.null, logical(1)))) stop("Missing saved analysis evidence.")
      check_records <- function() {
        for (name in names) {
          record <- records[[name]]
          if (!identical(sort(base::names(record)), c("path", "sha256")) ||
              !is.character(record$path) || length(record$path) != 1L ||
              !grepl(paste0("^checkpoints/", name, "-[a-f0-9]{64}\\.rds$"), record$path) ||
              !file.exists(file.path(root, record$path)) ||
              nzchar(Sys.readlink(file.path(root, "checkpoints"))) ||
              nzchar(Sys.readlink(file.path(root, record$path))) ||
              !identical(get(".sc_project_sha_file")(file.path(root, record$path)), record$sha256))
            stop("Saved stage checkpoint changed or is foreign.")
        }
      }
      check_records()
      seu <- get(".sc_project_unwrap")(get(".sc_run_get")(root, state, "analysis"))
      markers <- get(".sc_run_get")(root, state, "markers")
      annotation <- get(".sc_run_get")(root, state, "annotation_evidence")
      expected <- annotation$private$input_cells
      column <- state$config$cluster_column
      if (!is.data.frame(expected) || !identical(base::names(expected), c("cell_id", "cluster")) ||
          !identical(annotation$private$cluster_column, column)) stop("Missing exact annotation membership.")
      actual <- data.frame(cell_id = colnames(seu), cluster = as.character(seu[[]][colnames(seu), column]),
        stringsAsFactors = FALSE)
      if (!identical(actual, expected)) stop("Analysis cells differ from saved annotation scope.")
      scope_hash <- get(".sc_run_hash")(expected)
      if (!is.null(run$annotation_review) && !identical(run$annotation_review$cell_scope_hash, scope_hash))
        stop("Annotation review scope differs from saved analysis.")
      sorted <- expected[order(enc2utf8(expected$cell_id), method = "radix"), , drop = FALSE]
      sorted_hash <- get(".sc_run_hash")(sorted)
      table <- if (is.list(markers) && !is.data.frame(markers)) markers$marker_summary else markers
      marker_records <- get(".sc_run_annotation_marker_records")(table)
      option <- function(name, default) get(".sc_run_annotation_option")(state$config, name, default)
      reduction <- if (!is.null(state$config$reduction)) state$config$reduction
        else if ("umap" %in% SeuratObject::Reductions(seu)) "umap" else NULL
      snapshot <- list(stateSHA = before, inputHash = state$input_hash, configHash = state$config_hash,
        implementationHash = state$implementation_hash, revision = state$revision, historyHead = head,
        scopeHash = scope_hash, bundleScopeHash = sorted_hash, records = records)
      temporary <- tempfile("scagentkit-saved-stage-")
      on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
      exported <- scAgentKit::sc_project_export(seu, temporary, project_id = state$project_id,
        assay = option("assay", "RNA"), counts_layer = option("counts_layer", "counts"),
        normalized_layer = option("normalized_layer", "data"), cluster_column = column, reduction = reduction,
        marker_table = marker_records, candidate_table = NULL, model_records = NULL, source_annotation = NULL,
        directed_clusters = character(), metadata_allowlist = character(), archive = FALSE,
        parameters = list(prepare = get(".sc_project_map")(),
          analysisExecution = list(inputHash = state$input_hash, configHash = state$config_hash,
            implementationHash = state$implementation_hash), savedStageSnapshot = snapshot),
        provenance = list(generatedBy = "readonly_saved_analysis_checkpoint", scientificCompletion = FALSE))
      if (!identical(sort(list.files(temporary, all.files = TRUE, no.. = TRUE)), c("manifest.json", "project.json")))
        stop("Unexpected assets in saved stage snapshot.")
      projected <- jsonlite::fromJSON(file.path(temporary, "project.json"), simplifyVector = FALSE)
      if (!identical(unname(vapply(projected$cells, `[[`, character(1), "cellId")), unname(sorted$cell_id)) ||
          !identical(unname(vapply(projected$cells, `[[`, character(1), "clusterId")), unname(sorted$cluster)))
        stop("Stage export changed exact saved cells or membership.")
      blobs <- stats::setNames(lapply(c("project.json", "manifest.json"), function(name)
        readChar(file.path(temporary, name), file.info(file.path(temporary, name))$size, useBytes = TRUE)),
        c("project.json", "manifest.json"))
      check_records()
      list(schema = "scagentkit.saved-stage-bundle.v1", blobs = blobs, checkpoint_records = records,
        scope_hash = scope_hash, bundle_scope_hash = sorted_hash, cell_count = nrow(expected))
    })()
    # Reverify saved input/source and all pending bindings after export as well
    # as the three plotted checkpoints. This reads hashes, never recomputes a
    # review, runs a stage, or writes the original run.
    get(".sc_run_load")(root)
  }
  projection <- list(schema = "scagentkit.workbench.saved.v1", state_sha256 = before,
    source = list(start_stage = state$config$start_stage, processed_reason = state$config$processed_reason,
      source = state$source[intersect(c("type", "path", "rds_sha256"), names(state$source))]),
    provider = get(".sc_run_annotation_review_provider")(state$config$provider),
    history = list(schema = "scagentkit.run-history.v1", events = events, head = head,
      total_events = length(events), provided_events = length(events), truncated = FALSE,
      authority = "state.rds", hash_verification = "Original complete events verified by the coordinator; displayed details are an allowlisted projection."),
    qc_summary = plain(qc), strategy_summary = plain(summary("strategy_summary.json")),
    annotation_summary = plain(summary("annotation_evidence_summary.json")),
    analysis = list(parameters = plain(state$config$analysis), markers = plain(state$config$markers)),
    artifacts = unname(artifacts), bundle_records = unname(bundle_records), bundle_scope_hash = bundle_scope_hash,
    stage_bundle = stage_bundle,
    integration_history = integration, integration_state_sha256 = integration_sha)
  if (!identical(before, get(".sc_project_sha_file")(state_path)))
    stop("State changed during read-only inspection; refresh the registered scope.")
  run <- plain(run)
  projection$detail_projection <- "Scientific aggregate facts; secret-bearing and private per-cell detail fields are excluded."
  run$workbench_projection <- projection
  list(ok = TRUE, result = run, error = NULL)
}, error = function(problem) list(ok = FALSE, result = NULL,
  error = "Saved workbench inspection rejected a changed or unverifiable registered scope. Inspect the coordinator in R."))
encoded <- as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null", na = "null",
  digits = NA, force = TRUE))
if (nchar(encoded, type = "bytes") > 16 * 1024 * 1024) {
  answer <- list(ok = FALSE, result = NULL, error = paste(
    "Saved aggregate projection exceeds the 16 MiB display bound. No history was truncated.",
    "Inspect the authoritative saved project and fixed artifacts in R."))
  encoded <- as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null"))
}
writeLines(encoded, response_file, useBytes = TRUE)
quit(status = if (isTRUE(answer$ok)) 0L else 1L)
