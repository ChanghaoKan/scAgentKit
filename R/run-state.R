# Durable local coordinator. A single rename commits state plus hash-chained history.
.sc_run_hash <- function(x) digest::digest(x, algo = "sha256", serialize = TRUE, serializeVersion = 2L)
.sc_run_time <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
.sc_run_atomic <- function(value, path, json = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(".commit-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  if (json) writeLines(.sc_project_json(value, pretty = TRUE), temporary, useBytes = TRUE)
  else saveRDS(value, temporary, version = 2L)
  if (!file.rename(temporary, path)) stop("Atomic state publication failed.", call. = FALSE)
  invisible(path)
}
.sc_run_root <- function(project_dir, create = FALSE) {
  .sc_project_string(project_dir, "project_dir")
  if (create) dir.create(path.expand(project_dir), recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(path.expand(project_dir), mustWork = TRUE)
  if (nzchar(Sys.readlink(root))) stop("Project directory must not be a symlink.", call. = FALSE)
  root
}
.sc_run_lock <- function(root) {
  path <- file.path(root, ".run-lock")
  if (!dir.create(path, showWarnings = FALSE)) stop("Project is locked. Inspect .run-lock/owner.rds; recover explicitly with sc_run_unlock after the owning process has stopped.", call. = FALSE)
  owner <- list(token = .sc_run_hash(list(Sys.getpid(), Sys.time(), tempfile())), pid = Sys.getpid(),
                host = unname(Sys.info()["nodename"]), created_at = .sc_run_time())
  saveRDS(owner, file.path(path, "owner.rds"))
  owner
}
.sc_run_release <- function(root, owner) {
  file <- file.path(root, ".run-lock", "owner.rds")
  if (!file.exists(file)) return(invisible(NULL))
  current <- tryCatch(readRDS(file), error = function(e) NULL)
  if (!is.null(current) && identical(current$token, owner$token)) unlink(dirname(file), recursive = TRUE)
  invisible(NULL)
}
.sc_run_event <- function(state, action, details = list()) {
  previous <- if (length(state$history)) tail(state$history, 1)[[1]]$hash else strrep("0", 64)
  event <- list(sequence = length(state$history) + 1L, created_at = .sc_run_time(),
                action = action, details = details, previous_hash = previous)
  event$hash <- .sc_run_hash(event)
  state$history[[length(state$history) + 1L]] <- event
  state$revision <- state$revision + 1L
  state
}
.sc_run_save <- function(root, state) {
  envelope <- list(schema = "scagentkit.run-state.v1", hash = .sc_run_hash(state), state = state)
  .sc_run_atomic(envelope, file.path(root, "state.rds"))
  # JSON is a convenience projection. state.rds remains the only commit authority.
  .sc_run_atomic(.sc_run_public(state), file.path(root, "status.json"), json = TRUE)
  if (!is.null(state$pending)) .sc_run_atomic(state$pending$proposal, file.path(root, "proposal.json"), json = TRUE)
  .sc_run_atomic(list(schema = "scagentkit.run-history.v1", events = state$history), file.path(root, "decision_history.json"), json = TRUE)
  invisible(state)
}
.sc_run_load <- function(root, verify = TRUE, verify_subcluster = TRUE) {
  envelope <- readRDS(file.path(root, "state.rds"))
  if (!identical(envelope$schema, "scagentkit.run-state.v1") || !identical(envelope$hash, .sc_run_hash(envelope$state)))
    stop("State checksum mismatch; no operation was performed.", call. = FALSE)
  state <- envelope$state
  previous <- strrep("0", 64)
  for (i in seq_along(state$history)) {
    event <- state$history[[i]]; hash <- event$hash; event$hash <- NULL
    if (!identical(event$sequence, i) || !identical(event$previous_hash, previous) || !identical(hash, .sc_run_hash(event)))
      stop("Decision history hash chain mismatch.", call. = FALSE)
    previous <- hash
  }
  if (verify) {
    for (record in state$files) {
      path <- file.path(root, record$path)
      if (!file.exists(path) || nzchar(Sys.readlink(path)) || !identical(.sc_project_sha_file(path), record$sha256))
        stop(paste0("Saved input/evidence/checkpoint changed: ", record$path, ". Stale approval rejected."), call. = FALSE)
    }
    if (!is.null(state$source$path) && (!file.exists(state$source$path) ||
        !identical(.sc_project_sha_file(state$source$path), state$source$rds_sha256)))
      stop("Original input RDS changed; stale approval/resume rejected. Start a new project for the new input.", call. = FALSE)
    if (!is.null(state$pending) && !isTRUE(.sc_run_check_binding(state, state$pending)))
      stop("Pending proposal/input/evidence hashes changed; stale approval rejected.", call. = FALSE)
    if (isTRUE(verify_subcluster)) .sc_run_subcluster_guard(root, state)
  }
  state
}
.sc_run_put <- function(root, state, name, value) {
  # Versioned immutable snapshots make an interrupted state commit harmless.
  path <- file.path("checkpoints", paste0(name, "-", .sc_run_hash(value), ".rds"))
  full <- file.path(root, path)
  if (!file.exists(full)) .sc_run_atomic(value, full)
  state$files[[name]] <- list(path = path, sha256 = .sc_project_sha_file(full))
  state
}
.sc_run_get <- function(root, state, name) readRDS(file.path(root, state$files[[name]]$path))
.sc_run_binding <- function(state, file_names = names(state$files)) {
  list(input_hash = state$input_hash, config_hash = state$config_hash,
       implementation_hash = state$implementation_hash, files = state$files[file_names])
}
.sc_run_pending_hash <- function(state, pending) {
  .sc_run_hash(list(kind = pending$kind, stage = pending$stage,
                   next_stage = pending$next_stage,
                   evidence_hash = pending$evidence_hash, proposal = pending$proposal,
                   revision_created = pending$revision_created, binding = pending$binding))
}
.sc_run_check_binding <- function(state, pending) {
  identical(pending$binding, .sc_run_binding(state, names(pending$binding$files))) &&
    identical(pending$hash, .sc_run_pending_hash(state, pending))
}
.sc_run_pending <- function(state, kind, proposal, evidence_hash, next_stage = NULL, file_names = NULL) {
  if (is.null(file_names) && kind == "annotation" && isTRUE(state$config$strategy))
    file_names <- intersect(c("input", "analysis", "markers", "reference", "annotation_history_input",
      "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review"), names(state$files))
  if (is.null(file_names)) file_names <- names(state$files)
  pending <- list(kind = kind, stage = state$stage, proposal = proposal, evidence_hash = evidence_hash,
                  revision_created = state$revision, next_stage = next_stage, binding = .sc_run_binding(state, file_names))
  pending$hash <- .sc_run_pending_hash(state, pending)
  state$pending <- pending; state$status <- "awaiting_review"; state$nodes[[state$stage]] <- "AWAITING_APPROVAL"
  .sc_run_event(state, "awaiting_review", list(kind = kind, proposal_hash = pending$hash, evidence_hash = evidence_hash))
}

.sc_run_public <- function(state) {
  result <- list(schema = "scagentkit.run.v1", project_id = state$project_id, status = state$status,
       stage = state$stage, revision = state$revision, input_hash = state$input_hash,
       diagnostics = state$diagnostics, context = state$config$context, nodes = state$nodes,
       config_hash = state$config_hash, implementation_hash = state$implementation_hash,
       batch_integration = if (isTRUE(state$config$strategy)) "Defaults to none; explicit reviewed Harmony embedding correction for identifiable declared designs; manual remains a boundary" else "skipped; choose and validate integration separately",
       pending = if (is.null(state$pending)) NULL else state$pending[setdiff(names(state$pending), "binding")], failure = state$failure, completed = state$completed,
       output = state$output, history_head = if (length(state$history)) tail(state$history, 1)[[1]]$hash else NULL)
  if (!is.null(state$config$subcluster_origin)) result$subcluster <- list(
    schema = "scagentkit.subcluster-summary.v1",
    parent_project_id = state$config$subcluster_origin$parent$project_id,
    parent_revision = state$config$subcluster_origin$parent$revision,
    parent_scope_hash = state$config$subcluster_origin$parent_scope_hash,
    selected_scope_hash = state$config$subcluster_origin$scope_hash,
    selected_clusters = as.list(state$config$subcluster_origin$selected_clusters),
    selected_cell_count = length(state$config$subcluster_origin$selected_cells),
    choices = state$config$subcluster_creation$choices,
    source_cluster_column = state$config$subcluster_creation$source_cluster_column,
    child_cluster_column = state$config$cluster_column,
    plan_source = state$config$subcluster_creation$plan_source,
    policy = "Independent raw-count child; parent labels are source metadata. Apply creates a derived parent object by exact approved cell IDs.")
  if (!is.null(state$config$annotation_context)) {
    if (!identical(state$config$annotation_context$parent_snapshot,
        state$config$subcluster_creation$parent_annotation_context))
      stop("Child context parent snapshot differs from immutable creation provenance.", call. = FALSE)
    result$child_context <- .sc_run_child_context_public(state$config$annotation_context)
  }
  result
}

.sc_run_stage_counts <- function(root, state) {
  unavailable <- function(status = "unavailable", source = NULL) list(
    status = status, source = source, artifact_sha256 = NULL, cells = NULL)
  saved <- function(name, source) {
    record <- state$files[[name]]
    if (is.null(record)) return(unavailable())
    object <- .sc_run_get(root, state, name)
    if (!inherits(object, "Seurat")) return(unavailable(source = "non_seurat_checkpoint"))
    list(status = "saved", source = source, artifact_sha256 = record$sha256,
      cells = ncol(object))
  }
  reused <- identical(state$config$start_stage, "processed")
  counts <- list(schema = "scagentkit.stage-counts.v1",
    input = saved("input", "input_checkpoint"),
    qc = if (reused) unavailable("processed_reused", "explicit_processed_input") else
      saved("qc_object", "executed_quality_qc_checkpoint"),
    selection = if (reused) unavailable("processed_reused", "explicit_processed_input") else
      saved("strategy_selected", "executed_doublet_selection_checkpoint"),
    analysis = saved("analysis", if (reused) "processed_reused_analysis_checkpoint" else "executed_analysis_checkpoint"),
    output = saved("output:output/seurat.rds", "final_output_checkpoint"),
    prefilter = list(status = "unavailable", source = NULL, artifact_sha256 = NULL,
      original_cells = NULL, eligible_cells = NULL, excluded_cells = NULL))
  if (!is.null(state$files$prefilter)) {
    record <- .sc_run_get(root, state, "prefilter")
    .sc_run_prefilter_verify(record)
    counts$prefilter <- list(status = "saved", source = "verified_prefilter_record",
      artifact_sha256 = state$files$prefilter$sha256, method = record$options$method,
      original_cells = length(record$cell_ids), eligible_cells = length(record$keep_cells),
      excluded_cells = length(record$excluded_cells))
  }
  # Counts describe verified objects/records already on disk. Proposal impact
  # estimates and source misc execution claims cannot populate these fields.
  counts
}

#' Inspect a durable analysis run without a browser
#' @param project_dir Server-side run directory.
#' @return Status, proposal hash, aggregate evidence, diagnostics and output paths.
#' @export
sc_run_inspect <- function(project_dir) {
  root <- .sc_run_root(project_dir)
  state <- .sc_run_load(root)
  result <- .sc_run_public(state)
  result$evidence <- if (state$stage %in% c("qc_propose", "qc_apply")) .sc_run_get(root, state, "qc_evidence")$summary
    else if (state$stage %in% c("annotation_propose", "annotation_apply")) .sc_run_get(root, state, "annotation_evidence")$summary else NULL
  result$qc_preview <- if (!is.null(state$files$qc_preview)) .sc_run_qc_preview_verify(root, state) else NULL
  result$annotation_review <- .sc_run_annotation_review_view(root, state)
  result$strategy_review <- if (!is.null(state$files$strategy_review)) .sc_run_strategy_review_verify(root, state) else NULL
  if (isTRUE(state$config$strategy) && !is.null(state$files$strategy_basis)) {
    basis <- .sc_run_get(root, state, "strategy_basis")
    candidates <- basis@misc$strategy_execution$basis$pca$top50_candidates
    .sc_run_pc_verify(candidates)
    result$computed_diagnostics <- list(pc_candidates = candidates,
      basis_artifact_sha256 = state$files$strategy_basis$sha256,
      boundary = "Saved post-approval PCA diagnostic; the original review remains immutable. Revise the strategy to review these actual candidates with fresh authority.")
    pca <- basis@misc$strategy_execution$basis$pca
    # Project already saved actual computed-PC fractions, including PCs beyond
    # the top-50 reference. Never infer an uncomputed component or run PCA here.
    result$computed_diagnostics$all_pc_variance <- c(list(status = "saved",
      basis_artifact_sha256 = state$files$strategy_basis$sha256,
      source = "strategy_basis_saved_pca_evidence"),
      pca[c("available_pcs", "fraction_per_pc", "cumulative_fraction", "denominator", "interpretation")])
    if (!is.null(state$files$strategy_batch))
      result$computed_diagnostics$batch <- .sc_run_get(root, state, "strategy_batch")@misc$strategy_execution$batch
    if (!is.null(state$files$analysis)) {
      cluster <- .sc_run_get(root, state, "analysis")@misc$strategy_execution$cluster
      if (!is.null(cluster$candidates)) {
        fields <- c("resolution", "chosen", "n_clusters", "min_cluster_size",
          "max_cluster_size", "cluster_sizes", "ari_vs_chosen", "ari_vs_previous")
        result$computed_diagnostics$cluster_candidates <- list(status = "saved",
          basis_artifact_sha256 = state$files$strategy_basis$sha256,
          analysis_artifact_sha256 = state$files$analysis$sha256,
          source = "analysis_saved_louvain_diagnostics",
          method = cluster$method, cluster_column = cluster$cluster_column,
          chosen_resolution = cluster$resolution,
          candidates = lapply(cluster$candidates, function(row) row[fields]),
          interpretation = cluster$diagnostic_interpretation)
      }
    }
  }
  if (is.null(result$computed_diagnostics)) result$computed_diagnostics <- list()
  result$computed_diagnostics$stage_counts <- .sc_run_stage_counts(root, state)
  if (state$stage %in% c("strategy_propose", "strategy_apply")) result$evidence <- .sc_run_get(root, state, "strategy_evidence")$summary
  result$review_node <- .sc_run_review_node(root, state)
  # Completed/legacy projects retain their existing inspection contract. The
  # suggestion view is relevant only to a current saved proposal stage.
  if (state$stage %in% c("strategy_propose", "qc_propose", "annotation_propose"))
    result$suggestion <- .sc_run_suggestion_view(root, state)
  result
}

#' Approve or reject the exact current review node
#' @param project_dir Server-side run directory.
#' @param proposal_hash Exact hash returned by sc_run_inspect.
#' @param reviewer Analyst identity for the audit history.
#' @param reason Analyst rationale.
#' @param preview_hash Optional exact QC preview hash. QC proposal hashes always
#'   bind the preview; the workbench sends this additional explicit check.
#' @param expected_revision Optional optimistic concurrency revision.
#' @return Updated run status. Approval does not run computation or contact a provider.
#' @export
sc_run_approve <- function(project_dir, proposal_hash, reviewer, reason = "", preview_hash = NULL, expected_revision = NULL) {
  .sc_run_decide(project_dir, proposal_hash, reviewer, reason, TRUE, preview_hash, expected_revision)
}
#' @rdname sc_run_approve
#' @export
sc_run_reject <- function(project_dir, proposal_hash, reviewer, reason, preview_hash = NULL, expected_revision = NULL) {
  .sc_run_decide(project_dir, proposal_hash, reviewer, reason, FALSE, preview_hash, expected_revision)
}
.sc_run_decide <- function(project_dir, proposal_hash, reviewer, reason, approve, preview_hash = NULL, expected_revision = NULL) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(proposal_hash, "proposal_hash")
  if (!is.character(reason) || length(reason) != 1L || is.na(reason)) stop("reason must be one string.", call. = FALSE)
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_decide_locked(root, state, proposal_hash, reviewer, reason, approve, preview_hash, expected_revision)
}
.sc_run_decide_locked <- function(root, state, proposal_hash, reviewer, reason, approve, preview_hash = NULL, expected_revision = NULL) {
  .sc_run_subcluster_guard(root, state)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) || !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; approval is stale.", call. = FALSE)
  if (is.null(state$pending)) {
    prior <- Filter(function(e) e$action == (if (approve) "approved" else "rejected") && identical(e$details$proposal_hash, proposal_hash), state$history)
    if (length(prior)) {
      decision <- tail(prior, 1)[[1]]$details
      if (!identical(decision$input_hash, state$input_hash) ||
          !identical(decision$config_hash, state$config_hash) ||
          !identical(decision$implementation_hash, state$implementation_hash))
        stop("Stale historical approval/rejection binding; inspect the current proposal and context.", call. = FALSE)
      if (!is.null(preview_hash) && !identical(preview_hash, decision$preview_hash)) stop("Stale QC preview hash.", call. = FALSE)
      return(sc_run_inspect(root)) # identical decision is idempotent, even at its original revision
    }
    stop("No current proposal matches this decision.", call. = FALSE)
  }
  if (state$status != "awaiting_review" || !identical(proposal_hash, state$pending$hash)) stop("Stale proposal hash; inspect the current proposal before deciding.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
  if (state$pending$kind == "qc") {
    preview <- .sc_run_qc_preview_verify(root, state)
    if (!is.null(preview_hash) && !identical(preview_hash, preview$hash)) stop("Stale QC preview hash.", call. = FALSE)
  } else if (!is.null(preview_hash)) stop("QC preview hash cannot approve another review kind.", call. = FALSE)
  decision <- list(proposal_hash = proposal_hash, reviewer = reviewer, reason = reason,
                   kind = state$pending$kind, evidence_hash = state$pending$evidence_hash,
                   input_hash = state$input_hash, config_hash = state$config_hash,
                   implementation_hash = state$implementation_hash, decision_id = paste0("decision-", state$revision + 1L))
  if (state$pending$kind == "qc") decision <- .sc_run_qc_decision_details(state, reviewer, reason, root)
  if (state$pending$kind == "annotation") decision <- .sc_run_annotation_review_decision_details(root, state, reviewer, reason)
  if (state$pending$kind == "strategy") decision <- .sc_run_strategy_decision_details(root, state, reviewer, reason)
  state <- .sc_run_event(state, if (approve) "approved" else "rejected", decision)
  if (approve) {
    state$approvals[[proposal_hash]] <- decision
    if (identical(decision$kind, "strategy")) state <- .sc_run_strategy_authorize(state, decision)
    state$status <- "ready"; state$nodes[[state$stage]] <- "APPROVED"
    if (state$pending$kind == "external_transfer") {
      state$transfer_hashes <- unique(c(state$transfer_hashes, state$pending$proposal$request_hash))
      state$pending <- NULL
    } else {
      state$approved <- state$pending
      state$stage <- state$pending$next_stage
      state$pending <- NULL
    }
  } else { state$status <- "rejected"; state$pending <- NULL }
  .sc_run_save(root, state)
  .sc_run_public(state)
}

#' Recover a lock after confirming the owning process has stopped
#' @param project_dir Run directory.
#' @param token Exact owner token from .run-lock/owner.rds.
#' @param reason Explanation of how process termination was verified.
#' @return Invisibly TRUE. Never removes a mismatching lock.
#' @export
sc_run_unlock <- function(project_dir, token, reason) {
  .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir); path <- file.path(root, ".run-lock", "owner.rds")
  owner <- readRDS(path)
  if (!identical(token, owner$token)) stop("Lock token mismatch.", call. = FALSE)
  if (identical(owner$host, unname(Sys.info()["nodename"]))) {
    alive <- tryCatch(tools::pskill(owner$pid, signal = 0L), error = function(e) FALSE)
    if (isTRUE(alive)) stop("Owning process is still alive; lock retained.", call. = FALSE)
  }
  provider_lock <- file.path(root, "provider", ".dispatch-lock")
  nested <- if (dir.exists(provider_lock)) jsonlite::fromJSON(file.path(provider_lock, "owner.json"), simplifyVector = FALSE) else NULL
  if (!is.null(nested) && (!identical(nested$host, owner$host) || nested$pid != owner$pid))
    stop("Provider lock belongs to another owner; retained for explicit investigation.", call. = FALSE)
  unlink(dirname(path), recursive = TRUE)
  next_owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, next_owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!is.null(nested)) .sc_run_provider_release(provider_lock, nested$token)
  state <- .sc_run_event(state, "lock_recovered", list(owner = owner, reason = reason))
  .sc_run_save(root, state); invisible(TRUE)
}
