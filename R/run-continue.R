# Local continuation is deliberately separate from runtime provider resume.
# The browser supplies typed snapshot identities, never a callback or R text.
.sc_run_continue_stages <- function() {
  c("prefilter", "qc_evidence", "qc_apply", "analysis", "strategy_evidence", "strategy_apply", "strategy_selection", "strategy_preprocess", "strategy_basis", "strategy_batch", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence",
    "annotation_apply", "finalize")
}
.sc_run_continue_boundary <- function(root, state, kind) {
  boundary <- list(stage = state$stage, kind = kind, dispatch = "not_sent",
    message = paste("Local Continue stopped because a typed", kind,
      "proposal is needed. Supply a manual proposal, or explicitly use sc_run_resume in R with your provider. Continue never calls a provider."))
  if (identical(state$status, "awaiting_configuration") &&
      identical(state$diagnostics$local_continue_boundary, boundary)) return(state)
  state$status <- "awaiting_configuration"
  state$nodes[[state$stage]] <- "NEEDS_CONFIGURATION"
  state$diagnostics$local_continue_boundary <- boundary
  state <- .sc_run_event(state, "local_continue_boundary", boundary)
  .sc_run_save(root, state)
  state
}
.sc_run_continue_crash <- function(point) {
  if (identical(getOption("scAgentKit.continue_crash"), point))
    stop(paste0("Injected local continuation failure at ", point), call. = FALSE)
}

#' Continue approved local computation without calling a provider
#' @param project_dir Durable project directory on the analysis machine.
#' @param project_id,input_hash Exact project and input identities from inspection.
#' @param expected_revision Exact nonnegative inspected state revision, required.
#' @param retry Explicit TRUE to retry a failed/interrupted local computation.
#'   Proposal/provider failures require explicit R configuration or resume.
#' @return Durable run status. Stops at review, rejection, completion, or a
#'   missing typed proposal with awaiting_configuration. No provider is invoked.
#' @export
sc_run_continue <- function(project_dir, project_id, input_hash, expected_revision, retry = FALSE) {
  .sc_project_string(project_id, "project_id")
  .sc_run_review_hash_string(input_hash, "input_hash")
  if (!is.numeric(expected_revision) || length(expected_revision) != 1L ||
      !is.finite(expected_revision) || expected_revision < 0 || expected_revision != floor(expected_revision))
    stop("expected_revision must be the exact nonnegative inspected revision.", call. = FALSE)
  if (!is.logical(retry) || length(retry) != 1L || is.na(retry))
    stop("retry must be TRUE or FALSE.", call. = FALSE)
  root <- .sc_run_root(project_dir)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_subcluster_guard(root, state)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; inspect the configured project.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; local continuation is stale.", call. = FALSE)
  if (is.null(state$files$input) || !identical(state$input_hash, state$files$input$sha256))
    stop("Saved input fingerprint changed; local continuation is stale.", call. = FALSE)
  if (state$stage == "qc_apply") .sc_run_require_approval(state, if (isTRUE(state$config$strategy)) "strategy" else "qc")
  if (state$stage == "annotation_apply") .sc_run_require_approval(state, "annotation")
  # Validate a saved approval before any event/cleanup/write, including when
  # continuing from an already computed downstream stage.
  if (!is.null(state$approved)) {
    kind <- state$approved$kind
    if (!kind %in% c("qc", "annotation", "strategy", "external_transfer")) stop("Unsupported saved computation approval.", call. = FALSE)
    .sc_run_require_approval(state, kind)
    if (kind == "qc") .sc_run_qc_preview_verify(root, state)
    else if (kind == "annotation") .sc_run_annotation_review_verify(root, state)
    else if (kind == "strategy") .sc_run_strategy_require(root, state)
    else if (!state$stage %in% c("qc_propose", "annotation_propose"))
      stop("Provider/transfer approval must resume explicitly in R; local Continue never dispatches.", call. = FALSE)
  }
  if (state$status %in% c("complete", "awaiting_review", "rejected")) return(.sc_run_public(state))
  if (state$status %in% c("failed", "running")) {
    if (!retry) return(.sc_run_public(state))
    if (!state$stage %in% .sc_run_continue_stages())
      stop("Continue retries only local computation stages. Configure a typed proposal or explicitly resume the provider/proposal step in R.", call. = FALSE)
    state <- .sc_run_event(state, "local_continue_retry_requested", list(stage = state$stage,
      mode = "local_only", dispatch = "not_sent"))
    state$status <- "ready"; state$failure <- NULL
    .sc_run_save(root, state)
  }
  state <- .sc_run_cleanup(root, state)
  # A repeated boundary inspection should not rewrite bytes or grow history.
  if (state$stage == "strategy_apply" && !isTRUE(.sc_run_get(root, state, "strategy_validated")$executable))
    return(.sc_run_public(.sc_run_strategy_manual_boundary(root, state)))
  if (state$stage %in% c("qc_propose", "annotation_propose", "strategy_propose")) {
    kind <- if (state$stage == "strategy_propose") "strategy" else if (state$stage == "qc_propose") "qc" else "annotation"
    if (is.null(state$files[[paste0("manual_", kind)]]))
      return(.sc_run_public(.sc_run_continue_boundary(root, state, kind)))
  }
  state <- .sc_run_event(state, "local_continue_requested", list(stage = state$stage,
    revision_requested = as.numeric(expected_revision), mode = "local_only", retry = retry))
  .sc_run_save(root, state)
  .sc_run_drive(root, state, provider = NULL, chat_fn = NULL, retry = FALSE, local_only = TRUE)
}
