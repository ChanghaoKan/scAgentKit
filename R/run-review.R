# One typed review boundary shared by headless R and the live local workbench.
# It saves decisions; computation and provider dispatch remain explicit resume.
.sc_run_review_hash_string <- function(value, name) {
  .sc_project_string(value, name)
  if (!grepl("^[a-f0-9]{64}$", value)) stop(name, " must be an exact SHA256 fingerprint.", call. = FALSE)
  value
}
.sc_run_review_node <- function(root, state) {
  if (!is.null(state$pending) && !state$pending$kind %in% c("qc", "annotation", "strategy")) return(NULL)
  # QC is embedded in the central strategy and has no independent proposal.
  # Configuration boundaries have evidence but no review node until an actual
  # proposal exists; never invent a node with a NULL proposal/review hash.
  kind <- if (!is.null(state$pending)) state$pending$kind else
    if (isTRUE(state$config$strategy) && !is.null(state$files$strategy_review) &&
        state$stage %in% c("strategy_propose", "strategy_apply")) "strategy" else
    if (!is.null(state$files$annotation_review)) "annotation" else
    if (isTRUE(state$config$strategy)) NULL else
    if (!is.null(state$files$qc_preview)) "qc" else NULL
  if (is.null(kind)) return(NULL)
  record <- if (kind == "strategy") .sc_run_strategy_review_verify(root, state) else if (kind == "qc") .sc_run_qc_preview_verify(root, state) else
    .sc_run_annotation_review_verify(root, state)
  waiting <- Filter(function(event) identical(event$action, "awaiting_review") &&
    identical(event$details$kind, kind), state$history)
  proposal_hash <- if (!is.null(state$pending)) state$pending$hash else
    if (length(waiting)) tail(waiting, 1)[[1]]$details$proposal_hash else NULL
  decision <- if (!is.null(proposal_hash)) state$approvals[[proposal_hash]] else NULL
  undone <- if (is.null(decision)) FALSE else any(vapply(state$history, function(event)
    identical(event$action, "annotation_undone") &&
      identical(event$details$decision_id, decision$decision_id), logical(1)))
  # Undo is offered only for the current exact annotation approval with an
  # executed checkpoint referencing the currently saved annotated object.
  executed <- !is.null(state$files$annotated) && any(vapply(state$history, function(event)
    identical(event$action, "executed") && identical(event$details$stage, "annotation_apply") &&
      identical(event$details$files$annotated, state$files$annotated), logical(1)))
  can_undo <- kind == "annotation" && !is.null(decision) && !undone && executed &&
    "annotation_apply" %in% state$completed && !is.null(state$approved) &&
    identical(state$approved$hash, proposal_hash) && identical(decision$review_hash, record$hash)
  can_revise <- (identical(state$stage, paste0(kind, "_propose")) || (kind == "strategy" && state$stage == "strategy_apply")) &&
    state$status %in% c("awaiting_review", "awaiting_configuration", "rejected")
  list(kind = kind, project_id = state$project_id, input_hash = state$input_hash,
    review_hash = record$hash, proposal_hash = proposal_hash,
    expected_revision = state$revision, decision_id = if (is.null(decision)) NULL else decision$decision_id,
    can_decide = identical(state$status, "awaiting_review") && !is.null(state$pending),
    can_revise = can_revise, can_undo = can_undo, undone = undone,
    boundary = "Save review only; explicitly resume computation in R.")
}

#' Review the exact current QC or annotation snapshot
#' @param project_dir Durable run directory on the data machine.
#' @param action approve, reject, revise, QC preview, or executed annotation undo.
#' @param kind qc or annotation, as displayed in review_node.
#' @param project_id,input_hash Exact project identity and original input fingerprint.
#' @param proposal_hash,review_hash,expected_revision Exact inspected snapshot.
#' @param reviewer,reason Analyst identity and nonempty decision rationale.
#' @param proposal Complete typed replacement proposal for revise only.
#' @param sensitivity,gene_panels Explicit QC preview settings only.
#' @param decision_id Exact current executed annotation decision for undo only.
#' @return Fresh inspection. Never computes, calls a provider or runs R text.
#' @export
sc_run_review <- function(project_dir, action, kind, project_id, input_hash,
                          proposal_hash, review_hash, expected_revision, reviewer, reason,
                          proposal = NULL, sensitivity = NULL, gene_panels = NULL, decision_id = NULL) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_project_string(project_id, "project_id")
  .sc_run_review_hash_string(input_hash, "input_hash")
  .sc_run_review_hash_string(proposal_hash, "proposal_hash")
  .sc_run_review_hash_string(review_hash, "review_hash")
  if (!is.character(kind) || length(kind) != 1L || is.na(kind) || !kind %in% c("qc", "annotation", "strategy"))
    stop("Review kind must be qc, strategy or annotation.", call. = FALSE)
  if (!is.character(action) || length(action) != 1L || is.na(action) ||
      !action %in% c("approve", "reject", "revise", "preview", "undo"))
    stop("Unsupported review action.", call. = FALSE)
  if (!is.numeric(expected_revision) || length(expected_revision) != 1L ||
      !is.finite(expected_revision) || expected_revision < 0 || expected_revision != floor(expected_revision))
    stop("expected_revision must be the exact nonnegative inspected revision.", call. = FALSE)
  if (action != "revise" && !is.null(proposal)) stop("Only revise accepts a typed proposal.", call. = FALSE)
  if (!is.null(proposal) && (!is.list(proposal) || is.null(names(proposal))))
    stop("A replacement proposal must be a typed object, never R text or a path.", call. = FALSE)
  if ((!is.null(sensitivity) || !is.null(gene_panels)) &&
      (kind != "qc" || !action %in% c("revise", "preview")))
    stop("Only QC revise/preview accepts comparison settings.", call. = FALSE)
  if (action == "preview" && kind != "qc") stop("Preview settings apply to QC only.", call. = FALSE)
  if (action != "undo" && !is.null(decision_id)) stop("Only undo accepts decision_id.", call. = FALSE)
  if (action == "undo") {
    if (kind != "annotation") stop("Only an executed annotation can be undone.", call. = FALSE)
    .sc_project_string(decision_id, "decision_id")
  }
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (!identical(project_id, state$project_id) || !identical(input_hash, state$input_hash))
    stop("Foreign project or changed input; inspect the configured project.", call. = FALSE)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; review is stale.", call. = FALSE)
  node <- .sc_run_review_node(root, state)
  if (is.null(node) || !identical(kind, node$kind) || !identical(review_hash, node$review_hash) ||
      !identical(proposal_hash, node$proposal_hash))
    stop("Stale review/proposal or different review kind; inspect the saved state.", call. = FALSE)
  if (action %in% c("approve", "reject")) {
    if (isTRUE(node$undone)) stop("This annotation approval was undone; obtain a fresh proposal.", call. = FALSE)
    .sc_run_decide_locked(root, state, proposal_hash, reviewer, reason, action == "approve",
      if (kind == "qc") review_hash else NULL, expected_revision)
  } else {
    .sc_run_qc_revision_check(state, expected_revision)
    if (action == "undo") {
      if (!isTRUE(node$can_undo) || !identical(decision_id, node$decision_id))
        stop("No current exact executed annotation decision matches this undo.", call. = FALSE)
      .sc_run_undo_locked(root, state, decision_id, reviewer, reason,
        list(kind = kind, project_id = project_id, input_hash = input_hash,
          proposal_hash = proposal_hash, review_hash = review_hash, revision_reviewed = expected_revision))
    } else {
      if (!isTRUE(node$can_revise)) stop("The current review node cannot be revised.", call. = FALSE)
      if (action == "preview") {
        .sc_run_qc_preview_update(root, state, sensitivity, gene_panels, reviewer, reason)
      } else {
        if (is.null(proposal)) stop("Revise requires a complete typed replacement proposal.", call. = FALSE)
        if (kind == "qc") {
          options <- .sc_run_qc_current_options(state)
          if (!is.null(sensitivity)) options$sensitivity <- sensitivity
          if (!is.null(gene_panels)) options$gene_panels <- gene_panels
          state$qc_preview_options <- .sc_run_qc_preview_options(options)
        }
        if (kind == "strategy") .sc_run_strategy_propose_locked(root, state, proposal, reviewer, reason) else
          .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE,
            review_binding = list(project_id = project_id, input_hash = input_hash,
              previous_review_hash = review_hash, revision_reviewed = expected_revision))
      }
    }
  }
  sc_run_inspect(root)
}
