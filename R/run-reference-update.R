#' Rebuild local reference evidence before annotation has been applied
#' @param project_dir Existing durable run directory.
#' @param reference Local reference data frame/path, or NULL to remove it.
#' @param project_id,input_hash,expected_revision Exact current inspected bindings.
#' @param reviewer,reason Analyst identity and evidence-change explanation.
#' @param reference_review Updated explicit reference options; NULL keeps options.
#' @param annotation_history Optional historical import. Omit to keep it; explicit
#'   NULL removes it. This function never calls a provider or reruns markers.
#' @return Updated run status; an existing typed manual proposal is rebuilt for
#'   whole-plan review, otherwise awaiting_configuration. Prior approval is inactive.
#' @export
sc_run_set_reference <- function(project_dir, reference, project_id, input_hash,
                                 expected_revision, reviewer, reason,
                                 reference_review = NULL, annotation_history = NULL) {
  .sc_project_string(project_id, "project_id")
  .sc_run_review_hash_string(input_hash, "input_hash")
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  root <- .sc_run_root(project_dir)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; inspect the configured project.", call. = FALSE)
  .sc_run_qc_revision_check(state, expected_revision)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration/implementation changed; start a new project.", call. = FALSE)
  if (!state$stage %in% c("annotation_propose", "annotation_apply") ||
      "annotation_apply" %in% state$completed || state$status %in% c("complete", "running"))
    stop("Reference refresh is allowed only before annotation application, after markers are saved.", call. = FALSE)
  config <- state$config
  if (!is.null(reference_review)) config$reference_review <- .sc_run_reference_options(reference_review)
  options <- .sc_run_reference_options(config$reference_review)
  history <- if (missing(annotation_history)) {
    if (is.null(state$files$annotation_history_input)) NULL else .sc_run_get(root, state, "annotation_history_input")
  } else annotation_history
  # Validate all requested evidence in memory before writing state or artifacts.
  evidence <- .sc_run_annotation_evidence(.sc_run_get(root, state, "analysis"),
    .sc_run_get(root, state, "markers"), config$context, reference,
    cluster_column = config$cluster_column, reference_review = options, assay = config$assay,
    annotation_context = config$annotation_context)
  if (!is.null(history)) evidence$private$historical <- .sc_run_annotation_history_import(history, evidence)
  if (!is.null(state$files$manual_annotation))
    .sc_run_annotation_validate(.sc_run_get(root, state, "manual_annotation"), evidence)
  previous_review <- if (is.null(state$files$annotation_review)) NULL else .sc_run_get(root, state, "annotation_review")$hash
  previous_approval <- if (is.null(state$approved)) NULL else state$approved$hash
  state$config <- config; state$config_hash <- .sc_run_hash(config)
  if (is.null(reference)) state$files$reference <- NULL else state <- .sc_run_put(root, state, "reference", reference)
  if (is.null(history)) state$files$annotation_history_input <- NULL else state <- .sc_run_put(root, state, "annotation_history_input", history)
  state <- .sc_run_put(root, state, "annotation_evidence", evidence)
  state$files$annotation_review <- state$files$annotation_validated <- NULL
  state$pending <- state$approved <- NULL
  state$transfer_hashes <- character()
  state$failure <- NULL; state$output <- NULL
  state$status <- "ready"; state$stage <- "annotation_propose"
  state$completed <- setdiff(state$completed, c("annotation_propose", "annotation_apply", "finalize"))
  state <- .sc_run_event(state, "reference_evidence_reconfigured", list(reviewer = reviewer,
    reason = reason, previous_review_hash = previous_review, previous_approval_hash = previous_approval,
    evidence_hash = .sc_run_hash(evidence), config_hash = state$config_hash,
    calculation_reused = c("analysis", "markers"), provider_dispatch = "not_sent"))
  .sc_run_save(root, state)
  .sc_run_drive(root, state, provider = NULL, chat_fn = NULL, retry = FALSE, local_only = TRUE)
}
