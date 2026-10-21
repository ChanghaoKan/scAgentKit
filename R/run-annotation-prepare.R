# A blank worksheet is not a proposal or approval. Only a complete analyst
# submission enters the existing immutable annotation review boundary.
.sc_run_annotation_preparation <- function(root, state) {
  if (!identical(state$stage, "annotation_propose") ||
      !state$status %in% c("awaiting_configuration", "ready", "rejected") ||
      !is.null(state$pending) || !is.null(state$files$annotation_review) ||
      is.null(state$files$annotation_evidence)) return(NULL)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation())) return(NULL)
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  list(schema = "scagentkit.annotation-preparation.v1", project_id = state$project_id,
    input_hash = state$input_hash, expected_revision = state$revision,
    evidence_hash = state$files$annotation_evidence$sha256,
    output_column = state$config$annotation_column,
    clusters = evidence$summary$clusters,
    boundary = "Blank local worksheet only. Submit a complete proposal, then review and approve it separately.")
}

#' Submit a first manual annotation proposal from an inspected evidence boundary
#' @param project_dir Saved project directory.
#' @param project_id,input_hash,expected_revision,evidence_hash Exact inspected binding.
#' @param proposal Complete typed scagentkit.annotation.v1 proposal.
#' @param reviewer,reason Analyst identity and submission rationale.
#' @param request_id Stable identifier for retrying this exact submission.
#' @return Fresh inspection awaiting annotation review, without approval or execution.
#' @export
sc_run_prepare_annotation <- function(project_dir, project_id, input_hash,
  expected_revision, evidence_hash, proposal, reviewer, reason, request_id) {
  .sc_project_format_entry(project_dir)
  for (field in c("project_id", "reviewer", "reason", "request_id"))
    .sc_project_string(get(field), field)
  .sc_run_review_hash_string(input_hash, "input_hash")
  .sc_run_review_hash_string(evidence_hash, "evidence_hash")
  if (!is.numeric(expected_revision) || length(expected_revision) != 1L ||
      !is.finite(expected_revision) || expected_revision < 0 || expected_revision != floor(expected_revision))
    stop("Use the exact inspected revision.", call. = FALSE)
  if (!is.list(proposal) || !identical(proposal$schema, "scagentkit.annotation.v1"))
    stop("Submit a complete typed annotation proposal.", call. = FALSE)
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root)
  on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(state$project_id, project_id) || !identical(state$input_hash, input_hash) ||
      !identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Foreign project, changed input or changed configuration/runtime.", call. = FALSE)
  submitted <- list(project_id = project_id, input_hash = input_hash,
    expected_revision = expected_revision, evidence_hash = evidence_hash,
    proposal = proposal, reviewer = reviewer, reason = reason)
  request_hash <- .sc_run_hash(submitted)
  prior <- Filter(function(event) identical(event$action, "manual_proposal") &&
    identical(event$details$annotation_prepare_request_id, request_id), state$history)
  if (length(prior)) {
    if (!identical(tail(prior, 1L)[[1L]]$details$annotation_prepare_request_hash, request_hash))
      stop("Annotation request ID was reused with different content.", call. = FALSE)
    return(sc_run_inspect(root))
  }
  available <- .sc_run_annotation_preparation(root, state)
  if (is.null(available) || !identical(evidence_hash, available$evidence_hash) ||
      as.numeric(expected_revision) != as.numeric(state$revision))
    stop("Stale or unavailable annotation preparation; inspect the saved evidence again.", call. = FALSE)
  .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE,
    review_binding = list(annotation_prepare_request_id = request_id,
      annotation_prepare_request_hash = request_hash, evidence_reviewed = evidence_hash,
      revision_reviewed = expected_revision))
  sc_run_inspect(root)
}
