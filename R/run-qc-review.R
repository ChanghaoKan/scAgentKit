# Immutable impact review, shared by headless R and the loopback workbench.
.sc_run_qc_preview_options <- function(options = list()) {
  if (!is.list(options) || (length(options) &&
      (is.null(names(options)) || anyDuplicated(names(options)) || anyNA(names(options)) ||
       any(!nzchar(names(options))) || length(setdiff(names(options), c("sensitivity", "gene_panels"))))))
    stop("qc_preview supports only named sensitivity and gene_panels settings.", call. = FALSE)
  result <- list(sensitivity = if (is.null(options$sensitivity)) list() else options$sensitivity,
                 gene_panels = if (is.null(options$gene_panels)) list() else options$gene_panels)
  .sc_project_json_check(result)
  if (!is.list(result$sensitivity) || length(result$sensitivity) > 6L ||
      (length(result$sensitivity) && !is.null(names(result$sensitivity))) || !is.list(result$gene_panels))
    stop("Preview requires at most six explicit typed candidates and a named gene_panels list.", call. = FALSE)
  result
}
.sc_run_qc_current_options <- function(state) {
  .sc_run_qc_preview_options(if (!is.null(state$qc_preview_options)) state$qc_preview_options else state$config$qc_preview)
}
.sc_run_qc_preview_hash <- function(record) .sc_run_hash(record[setdiff(names(record), "hash")])
.sc_run_qc_preview_summary <- function(record) record[setdiff(names(record), c("details", "plots"))]
.sc_run_qc_preview_publish <- function(root, state, validated, evidence) {
  options <- .sc_run_qc_current_options(state)
  details <- .sc_run_qc_preview_build(validated$proposal, evidence, options$sensitivity, options$gene_panels)
  state$qc_preview_options <- details$canonical_parameters[c("sensitivity", "gene_panels")]
  record <- list(schema = "scagentkit.qc.review.v1", input_hash = state$input_hash,
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    evidence_hash = .sc_run_hash(evidence), rules_hash = .sc_run_hash(validated$proposal),
    parameters_hash = .sc_run_hash(details$canonical_parameters),
    cell_scope_hash = .sc_run_hash(list(input = evidence$metrics$cell_id, keep = details$keep_cells, remove = details$remove_cells)),
    details = details)
  if (isTRUE(state$config$strategy)) record$calculation_scope_hash <- .sc_run_strategy_scope_config_hash(state$config)
  # A descriptive figure is an immutable, local artifact, with no model call.
  metric <- value <- population <- NULL
  long <- do.call(rbind, lapply(c("nCount", "nFeature", "percent_mt"), function(name) {
    x <- evidence$metrics[[name]]; finite <- is.finite(x); keep <- evidence$metrics$cell_id %in% details$keep_cells
    chunk <- function(index, label) data.frame(metric = rep(name, sum(index)), value = x[index],
      population = rep(label, sum(index)), stringsAsFactors = FALSE)
    rbind(chunk(finite, "before"), chunk(finite & keep, "retained"), chunk(finite & !keep, "removed"))
  }))
  plot <- ggplot2::ggplot(long, ggplot2::aes(x = value, colour = population)) +
    ggplot2::stat_ecdf(geom = "step") + ggplot2::facet_wrap(~metric, scales = "free_x") +
    ggplot2::theme_bw() + ggplot2::labs(title = "QC impact before approval", y = "Empirical cumulative fraction",
      subtitle = "Measured values only; unavailable counts are disclosed separately. These distributions do not establish optimal cutoffs.")
  dir.create(file.path(root, "review"), showWarnings = FALSE)
  relative <- file.path("review", paste0("qc-distributions-", .sc_run_hash(record), ".png"))
  full <- file.path(root, relative)
  if (!file.exists(full)) {
    temporary <- tempfile(".qc-plot-", tmpdir = file.path(root, "review"), fileext = ".png")
    on.exit(unlink(temporary), add = TRUE)
    ggplot2::ggsave(temporary, plot, width = 10, height = 4, dpi = 120)
    if (!file.rename(temporary, full)) stop("QC plot publication failed.", call. = FALSE)
  }
  record$plots <- list(distributions = relative)
  state$files$qc_preview_plot <- list(path = relative, sha256 = .sc_project_sha_file(full))
  record$hash <- .sc_run_qc_preview_hash(record)
  .sc_run_put(root, state, "qc_preview", record)
}
.sc_run_qc_pending <- function(state, validated, evidence, root) {
  record <- .sc_run_get(root, state, "qc_preview")
  .sc_run_pending(state, "qc", list(rules = validated$proposal, retention = validated$retention,
    preview = .sc_run_qc_preview_summary(record)), .sc_run_hash(evidence), "qc_apply")
}
.sc_run_qc_preview_verify <- function(root, state) {
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; QC preview/approval is stale. Use the frozen version or a new project.", call. = FALSE)
  if (is.null(state$files$qc_preview)) stop("Required QC preview is absent; obtain a fresh preview.", call. = FALSE)
  record <- .sc_run_get(root, state, "qc_preview")
  if (!identical(record$hash, .sc_run_qc_preview_hash(record)) ||
      !identical(record$input_hash, state$input_hash) ||
      !(if (is.null(record$calculation_scope_hash)) identical(record$config_hash, state$config_hash) else identical(record$calculation_scope_hash, .sc_run_strategy_scope_config_hash(state$config))) ||
      !identical(record$implementation_hash, state$implementation_hash))
    stop("QC preview/input/parameters fingerprint changed; approval is stale.", call. = FALSE)
  evidence <- .sc_run_get(root, state, "qc_evidence")
  validated <- .sc_run_get(root, state, "qc_validated")
  options <- .sc_run_qc_current_options(state)
  current <- .sc_run_qc_preview_build(validated$proposal, evidence, options$sensitivity, options$gene_panels)
  if (!identical(record$details, current) || !identical(record$evidence_hash, .sc_run_hash(evidence)) ||
      !identical(record$rules_hash, .sc_run_hash(validated$proposal)) ||
      !identical(record$parameters_hash, .sc_run_hash(current$canonical_parameters)) ||
      !identical(current$keep_cells, validated$keep_cells) ||
      !identical(record$cell_scope_hash, .sc_run_hash(list(input = evidence$metrics$cell_id,
        keep = current$keep_cells, remove = current$remove_cells))))
    stop("QC preview no longer matches the exact reviewed rules, parameters or cell scope.", call. = FALSE)
  node <- if (!is.null(state$pending) && identical(state$pending$kind, "qc")) state$pending else
    if (!is.null(state$approved) && identical(state$approved$kind, "qc")) state$approved else NULL
  if (!is.null(node) && (!isTRUE(.sc_run_check_binding(state, node)) ||
      !identical(node$proposal$preview, .sc_run_qc_preview_summary(record))))
    stop("QC review node binding changed; preview approval is stale.", call. = FALSE)
  record
}
.sc_run_qc_revision_check <- function(state, expected_revision) {
  if (!is.null(expected_revision) && (!is.numeric(expected_revision) || length(expected_revision) != 1L ||
      !is.finite(expected_revision) || expected_revision != floor(expected_revision) ||
      !identical(as.numeric(expected_revision), as.numeric(state$revision))))
    stop("Stale review revision; inspect the current saved preview before deciding.", call. = FALSE)
}
.sc_run_qc_decision_details <- function(state, reviewer, reason, root) {
  record <- .sc_run_qc_preview_verify(root, state)
  c(list(proposal_hash = state$pending$hash, reviewer = reviewer, reason = reason, kind = "qc",
    evidence_hash = state$pending$evidence_hash, input_hash = state$input_hash,
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    decision_id = paste0("decision-", state$revision + 1L)),
    list(preview_hash = record$hash, parameters_hash = record$parameters_hash,
      rules_hash = record$rules_hash, cell_scope_hash = record$cell_scope_hash,
      preview_path = state$files$qc_preview$path, revision_reviewed = state$revision))
}
.sc_run_qc_preview_update <- function(root, state, sensitivity, gene_panels, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  if (state$stage != "qc_propose" || state$status != "awaiting_review" || state$pending$kind != "qc")
    stop("Preview settings can only be revised at the current QC review node.", call. = FALSE)
  old <- .sc_run_qc_preview_verify(root, state)
  options <- .sc_run_qc_current_options(state)
  if (!is.null(sensitivity)) options$sensitivity <- sensitivity
  if (!is.null(gene_panels)) options$gene_panels <- gene_panels
  options <- .sc_run_qc_preview_options(options)
  evidence <- .sc_run_get(root, state, "qc_evidence")
  validated <- .sc_run_get(root, state, "qc_validated")
  .sc_run_qc_preview_build(validated$proposal, evidence, options$sensitivity, options$gene_panels)
  state$qc_preview_options <- options
  previous_proposal_hash <- state$pending$hash
  state$pending <- NULL; state$approved <- NULL
  state <- .sc_run_event(state, "qc_preview_revised", list(reviewer = reviewer, reason = reason,
    previous_proposal_hash = previous_proposal_hash,
    previous_preview_hash = old$hash, previous_parameters_hash = old$parameters_hash,
    options = options))
  state <- .sc_run_qc_preview_publish(root, state, validated, evidence)
  state <- .sc_run_qc_pending(state, validated, evidence, root)
  .sc_run_save(root, state)
  state
}

#' Read or revise the saved local QC impact preview
#' @param project_dir Run directory.
#' @param sensitivity Explicit list of up to six id/proposal comparisons; NULL reads current settings.
#' @param gene_panels Named lists of literal genes for availability disclosure only.
#' @param reviewer,reason Required identity and rationale when changing preview settings.
#' @param proposal_hash,preview_hash,expected_revision Optional exact saved review fingerprints.
#' @return Immutable impact preview with local exact cell scope, overlap and distributions.
#' @export
sc_run_qc_preview <- function(project_dir, sensitivity = NULL, gene_panels = NULL, reviewer = NULL,
                              reason = NULL, proposal_hash = NULL, preview_hash = NULL, expected_revision = NULL) {
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  .sc_run_qc_revision_check(state, expected_revision)
  record <- .sc_run_qc_preview_verify(root, state)
  if (!is.null(proposal_hash) && (is.null(state$pending) || !identical(proposal_hash, state$pending$hash)))
    stop("Stale proposal hash.", call. = FALSE)
  if (!is.null(preview_hash) && !identical(preview_hash, record$hash)) stop("Stale QC preview hash.", call. = FALSE)
  if (!is.null(sensitivity) || !is.null(gene_panels)) {
    state <- .sc_run_qc_preview_update(root, state, sensitivity, gene_panels, reviewer, reason)
    record <- .sc_run_qc_preview_verify(root, state)
  }
  record
}

#' Submit a QC workbench action against one exact durable review snapshot
#' @param project_dir Run directory fixed by the operator.
#' @param action One of approve, reject, revise, preview. This never resumes analysis.
#' @param proposal_hash,preview_hash,expected_revision Exact snapshot displayed to the reviewer.
#' @param reviewer,reason Analyst identity and nonempty rationale.
#' @param proposal Replacement typed QC proposal for revise only.
#' @param sensitivity,gene_panels Optional explicit comparison/availability settings.
#' @return Current run inspection. R holds one project lock throughout the action.
#' @export
sc_run_qc_review <- function(project_dir, action, proposal_hash, preview_hash, expected_revision,
                             reviewer, reason, proposal = NULL, sensitivity = NULL, gene_panels = NULL) {
  if (!is.character(action) || length(action) != 1L || is.na(action) ||
      !action %in% c("approve", "reject", "revise", "preview")) stop("Unsupported QC review action.", call. = FALSE)
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  .sc_project_string(proposal_hash, "proposal_hash"); .sc_project_string(preview_hash, "preview_hash")
  if (is.null(expected_revision)) stop("QC workbench actions require expected_revision.", call. = FALSE)
  root <- .sc_run_root(project_dir); owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  if (action %in% c("approve", "reject")) {
    if (!is.null(proposal) || !is.null(sensitivity) || !is.null(gene_panels)) stop("Decision cannot silently change reviewed parameters.", call. = FALSE)
    .sc_run_decide_locked(root, state, proposal_hash, reviewer, reason, action == "approve", preview_hash, expected_revision)
    return(sc_run_inspect(root))
  }
  .sc_run_qc_revision_check(state, expected_revision)
  if (is.null(state$pending) || state$pending$kind != "qc" || !identical(proposal_hash, state$pending$hash)) stop("Stale QC proposal hash.", call. = FALSE)
  record <- .sc_run_qc_preview_verify(root, state)
  if (!identical(preview_hash, record$hash)) stop("Stale QC preview hash.", call. = FALSE)
  if (action == "preview") {
    if (!is.null(proposal)) stop("Preview comparisons cannot change the executable proposal.", call. = FALSE)
    .sc_run_qc_preview_update(root, state, sensitivity, gene_panels, reviewer, reason)
  } else {
    if (is.null(proposal)) stop("Revise requires a typed replacement QC proposal.", call. = FALSE)
    options <- .sc_run_qc_current_options(state)
    if (!is.null(sensitivity)) options$sensitivity <- sensitivity
    if (!is.null(gene_panels)) options$gene_panels <- gene_panels
    state$qc_preview_options <- .sc_run_qc_preview_options(options)
    .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE)
  }
  sc_run_inspect(root)
}
