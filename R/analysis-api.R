# User-facing adapters only. Keep names outside sc_run/.sc_run_: those names
# intentionally fingerprint the execution kernel, including genuine changes.
.sc_ui_root <- function(x) {
  if (inherits(x, "sc_analysis")) x$project_dir else .sc_run_root(x)
}
.sc_ui_object <- function(root, view, reviewed = FALSE) {
  out <- list(project_dir = root, view = view)
  out$plan <- view$strategy_review$details$canonical_proposal
  clusters <- view$evidence$clusters
  out$annotations <- if (is.null(clusters)) NULL else {
    rows <- lapply(clusters, function(cl) {
      proposed <- Filter(function(row) identical(row$clusterId, cl$clusterId),
        view$annotation_review$details$annotations)
      row <- if (length(proposed)) proposed[[1]]$proposal else NULL
      data.frame(clusterId = cl$clusterId, label = if (is.null(row)) "" else row$label,
        confidence = if (is.null(row)) "" else row$confidence,
        rationale = if (is.null(row)) "" else row$rationale,
        markers = paste(unlist(row$markers, use.names = FALSE), collapse = ";"),
        stringsAsFactors = FALSE)
    })
    if (length(rows)) do.call(rbind, rows) else NULL
  }
  out$seal <- .sc_run_hash(list(root, view))
  class(out) <- c(if (reviewed) "sc_review_snapshot", "sc_analysis")
  out
}
.sc_ui_intact <- function(x, reviewed = FALSE) {
  if (!inherits(x, if (reviewed) "sc_review_snapshot" else "sc_analysis"))
    stop("Use the snapshot returned by sc_review() before deciding; paths cannot confirm a review.", call. = FALSE)
  if (!identical(x$seal, .sc_run_hash(list(x$project_dir, x$view))))
    stop("The saved review snapshot was edited; display a fresh sc_review().", call. = FALSE)
  invisible(x)
}
.sc_ui_current <- function(root, state, x) {
  .sc_ui_intact(x)
  if (!identical(state$project_id, x$view$project_id) ||
      !identical(state$input_hash, x$view$input_hash) ||
      !identical(state$revision, x$view$revision) ||
      !identical(state$config_hash, x$view$config_hash) ||
      !identical(state$implementation_hash, x$view$implementation_hash))
    stop("Stale snapshot; display sc_review() again before taking this action.", call. = FALSE)
  if (!identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()))
    stop("Configuration or implementation changed; restore the pinned environment or start a new project.", call. = FALSE)
  invisible(state)
}
.sc_ui_plan <- function(edits = list(), base = NULL, dimensions = NULL) {
  if (!is.list(edits) || (length(edits) && (is.null(names(edits)) ||
      anyDuplicated(names(edits)) || anyNA(names(edits))))) stop("plan must be a named list.", call. = FALSE)
  allowed <- c("rationale", "risks", "qc", "analysis", "pcs", "batch", "resolution", "diagnostic_resolutions", "umap")
  if (length(setdiff(names(edits), allowed))) stop("Unknown plan fields: ", paste(setdiff(names(edits), allowed), collapse = ", "), call. = FALSE)
  if (is.null(base)) {
    npcs <- min(30L, dimensions[[1]] - 1L, dimensions[[2]] - 1L)
    base <- list(schema = "scagentkit.strategy.v1",
      rationale = "Editable software starting draft. Review input QC and study facts before approval.",
      risks = list("Count-positive retention and standard analysis defaults are not scientifically optimized QC or parameter choices."),
      inferences = list(), qc = list(schema = "scagentkit.qc.v1",
        rationale = "Starting draft retains count-positive cells; analyst must review measured QC distributions.",
        risks = list("No study-specific quality threshold has been established."),
        filters = list(list(op = "range", metric = "nCount", min = 1))),
      analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
        nfeatures = min(2000L, dimensions[[1]]), npcs = npcs, seed = 17L),
      pcs = list(method = "fixed", ndim = min(10L, npcs)),
      batch = list(method = "none", reason = "No batch correction selected; technical provenance requires explicit review."),
      clustering = list(resolution = .5, diagnostic_resolutions = NULL),
      umap = list(run = TRUE, n_neighbors = min(30L, dimensions[[2]] - 1L)))
  }
  for (name in intersect(names(edits), c("rationale", "batch", "umap"))) {
    if (name == "umap" && is.logical(edits[[name]]) && length(edits[[name]]) == 1L)
      base$umap$run <- edits[[name]] else base[[name]] <- edits[[name]]
  }
  if ("risks" %in% names(edits)) base$risks <- as.list(edits$risks)
  if ("analysis" %in% names(edits)) {
    if (!is.list(edits$analysis) || is.null(names(edits$analysis)) ||
        length(setdiff(names(edits$analysis), names(base$analysis)))) stop("Unknown analysis settings.", call. = FALSE)
    base$analysis[names(edits$analysis)] <- edits$analysis
  }
  if ("pcs" %in% names(edits)) base$pcs <- if (is.numeric(edits$pcs))
    list(method = "fixed", ndim = edits$pcs) else edits$pcs
  if ("resolution" %in% names(edits)) base$clustering$resolution <- edits$resolution
  if ("diagnostic_resolutions" %in% names(edits)) base$clustering["diagnostic_resolutions"] <- list(edits$diagnostic_resolutions)
  if ("qc" %in% names(edits)) {
    qc <- edits$qc
    if (!is.list(qc) || is.null(names(qc)) || !length(qc) || anyDuplicated(names(qc)) ||
        length(setdiff(names(qc), c("nCount", "nFeature", "percent_mt"))))
      stop("qc is a named list of nCount, nFeature or percent_mt inclusive ranges c(min, max); use NA for an open bound.", call. = FALSE)
    filters <- lapply(names(qc), function(metric) {
      bounds <- qc[[metric]]
      if (!is.numeric(bounds) || length(bounds) != 2L || all(is.na(bounds)) || any(is.infinite(bounds)))
        stop("Each QC range needs two finite numbers or NA, with at least one bound.", call. = FALSE)
      row <- list(op = "range", metric = metric)
      if (!is.na(bounds[[1]])) row$min <- bounds[[1]]
      if (!is.na(bounds[[2]])) row$max <- bounds[[2]]
      row
    })
    base$qc <- list(schema = "scagentkit.qc.v1", rationale = base$rationale,
      risks = base$risks, filters = filters)
  }
  base
}
.sc_ui_annotation <- function(table) {
  if (is.character(table) && length(table) == 1L) table <- utils::read.delim(table,
    colClasses = "character", check.names = FALSE, na.strings = character(),
    comment.char = "", quote = "\"", fileEncoding = "UTF-8")
  fields <- c("clusterId", "label", "confidence", "rationale", "markers")
  if (!is.data.frame(table) || anyDuplicated(names(table)) ||
      !setequal(names(table), fields) || !nrow(table))
    stop("annotations needs exactly clusterId, label, confidence, rationale, markers columns (or a quoted TSV path).", call. = FALSE)
  if (!all(vapply(table, is.character, logical(1))) || anyNA(table) || anyDuplicated(table$clusterId))
    stop("Annotation columns must be text without missing values or duplicate literal cluster IDs.", call. = FALSE)
  list(schema = "scagentkit.annotation.v1", annotations = lapply(seq_len(nrow(table)), function(i) {
    row <- as.list(table[i, fields, drop = FALSE])
    row$markers <- as.list(Filter(nzchar, trimws(strsplit(row$markers, ";", fixed = TRUE)[[1]])))
    row
  }))
}
.sc_ui_decide <- function(root, snapshot, action, reviewer, reason) {
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root); .sc_ui_current(root, state, snapshot)
  node <- snapshot$view$review_node
  external <- identical(snapshot$view$pending$kind, "external_transfer")
  if (!external) {
    current <- .sc_run_review_node(root, state)
    if (is.null(node) || !identical(current, node) || !isTRUE(current$can_decide))
      stop("No current scientific proposal matches this displayed review.", call. = FALSE)
  }
  .sc_run_decide_locked(root, state, snapshot$view$pending$hash, reviewer, reason,
    action == "approve", if (!external && identical(node$kind, "qc")) node$review_hash else NULL,
    snapshot$view$revision)
  sc_run_inspect(root)
}

#' Start an analysis with an editable strategy draft
#' @export
sc_analyze <- function(input, project_dir, context, plan = NULL, provider = NULL,
                       chat_fn = NULL, budget = 0, review = list(allow_external = FALSE),
                       sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
                       feature_key = c("name", "id"), ...) {
  imported <- .sc_ui_tenx_input(input, context, sample_id, matrix_kind, cell_metadata, match.arg(feature_key))
  input <- imported$input; context <- imported$context
  if (imported$imported) {
    transport <- tempfile("scagentkit-tenx-",fileext=".rds")
    on.exit(unlink(transport),add=TRUE)
    saveRDS(input,transport,version=2L);input<-transport
  }
  extra <- list(...)
  blocked <- c("strategy", "strategy_proposal", "qc_proposal", "annotation_proposal", "analysis", "start_stage")
  if (length(intersect(names(extra), blocked))) stop("Use plan for raw analysis settings; advanced entries remain available through sc_run().", call. = FALSE)
  proposal <- NULL
  if (is.null(provider) || !is.null(plan)) {
    object <- if (is.character(input) && length(input) == 1L) readRDS(input) else input
    dimensions <- dim(object)
    if (length(dimensions) != 2L) stop("input must be a counts matrix, Seurat object or its RDS path.", call. = FALSE)
    proposal <- .sc_ui_plan(if (is.null(plan)) list() else plan, dimensions = dimensions)
  }
  sc_run(input, project_dir, context = context, strategy = TRUE,
    strategy_proposal = proposal, provider = provider, chat_fn = chat_fn,
    budget = budget, review = review, ...)
  sc_open(project_dir)
}

#' Open a saved analysis without executing it
#' @export
sc_open <- function(project_dir) {
  root <- .sc_ui_root(project_dir)
  .sc_ui_object(root, sc_run_inspect(root))
}

#' Display and act on a bound scientific review snapshot
#' @export
sc_review <- function(project, action = c("show", "revise", "approve", "reject", "continue", "request"),
                      reviewer = NULL, reason = NULL, plan = NULL, annotations = NULL,
                      continue = FALSE, chat_fn = NULL) {
  action <- match.arg(action)
  if (!is.logical(continue) || length(continue) != 1L || is.na(continue)) stop("continue must be TRUE or FALSE.", call. = FALSE)
  if (action == "show") {
    if (!is.null(plan) || !is.null(annotations) || continue || !is.null(chat_fn))
      stop("Use an explicit action for edits, continuation or requests.", call. = FALSE)
    fresh <- sc_open(project)
    out <- .sc_ui_object(fresh$project_dir, fresh$view, TRUE)
    print(out)
    return(invisible(out))
  }
  .sc_ui_intact(project, reviewed = !action %in% c("continue", "request"))
  if (action != "revise" && (!is.null(plan) || !is.null(annotations))) stop("Only revise accepts plan or annotations.", call. = FALSE)
  if (action != "request" && !is.null(chat_fn)) stop("Only an explicit request accepts chat_fn.", call. = FALSE)
  if (action != "approve" && continue) stop("Only scientific approve accepts continue=TRUE.", call. = FALSE)
  root <- project$project_dir; view <- project$view
  if (action %in% c("continue", "request")) {
    if (action == "continue") {
      result <- sc_run_continue(root, view$project_id, view$input_hash, view$revision, retry = FALSE)
      # No rebind to a state changed by another process after continuation.
      fresh <- sc_run_inspect(root)
      if (!identical(fresh$revision, result$revision)) stop("State changed after continuation; display a fresh review.", call. = FALSE)
    } else {
      owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
      state <- .sc_run_load(root); .sc_ui_current(root, state, project)
      if (!state$stage %in% c("strategy_propose", "qc_propose", "annotation_propose") ||
          !state$status %in% c("ready", "awaiting_configuration") || !is.null(state$pending) ||
          !is.null(state$files[[paste0("manual_", sub("_propose$", "", state$stage))]]))
        stop("Request requires a configured, nonfailed proposal boundary; review pending science/transfer first. Retry stays explicit in sc_run_resume().", call. = FALSE)
      if (!is.null(state$config$subcluster_origin)) stop("Use sc_run_suggest() for scoped child model requests.", call. = FALSE)
      provider <- state$config$provider
      if (identical(provider$name, "manual")) stop("This project has no configured provider.", call. = FALSE)
      if (!identical(.sc_run_provider_spec(provider, chat_fn)$metadata, provider)) stop("Provider settings changed.", call. = FALSE)
      .sc_run_drive(root, .sc_run_cleanup(root, state), provider, chat_fn, retry = FALSE)
      fresh <- sc_run_inspect(root)
    }
  } else {
    .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
    node <- view$review_node
    external <- identical(view$pending$kind, "external_transfer")
    if (external && continue) stop("Transfer approval cannot continue computation or dispatch; use a separate explicit request.", call. = FALSE)
    if (action == "revise") {
      if (is.null(plan) == is.null(annotations)) stop("Revise needs exactly one of plan or annotations.", call. = FALSE)
      if (!is.null(plan) && is.null(project$plan)) stop("No displayed strategy draft; use the advanced typed strategy entry.", call. = FALSE)
      proposal <- if (!is.null(plan)) .sc_ui_plan(plan, base = project$plan) else .sc_ui_annotation(annotations)
      # Lock once to bind first drafts as strictly as revisions. The public
      # sc_run_propose lacks a revision argument, so never call it blindly.
      owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
      state <- .sc_run_load(root); .sc_ui_current(root, state, project)
      if (!is.null(plan)) {
        if (is.null(project$plan)) stop("No displayed strategy draft; use the advanced typed strategy entry.", call. = FALSE)
        .sc_run_strategy_propose_locked(root, state, proposal, reviewer, reason)
      } else {
        .sc_run_propose_locked(root, state, proposal, reviewer, reason, drive = FALSE,
          review_binding = list(project_id = state$project_id, input_hash = state$input_hash,
            revision_reviewed = view$revision))
      }
      fresh <- sc_run_inspect(root)
    } else if (external) {
      fresh <- .sc_ui_decide(root, project, action, reviewer, reason)
    } else {
      if (is.null(node)) stop("No scientific proposal is ready; supply an annotation draft with revise or request a configured provider.", call. = FALSE)
      fresh <- .sc_ui_decide(root, project, action, reviewer, reason)
      if (continue) {
        result <- sc_run_continue(root, fresh$project_id, fresh$input_hash, fresh$revision, retry = FALSE)
        fresh <- sc_run_inspect(root)
        if (!identical(fresh$revision, result$revision)) stop("State changed after approved continuation; inspect again.", call. = FALSE)
      }
    }
  }
  out <- .sc_ui_object(root, fresh, TRUE)
  print(out)
  invisible(out)
}

#' Read a verified Seurat result or analysis checkpoint
#' @export
sc_result <- function(project, stage = c("final", "analysis")) {
  stage <- match.arg(stage); root <- .sc_ui_root(project)
  owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
  state <- .sc_run_load(root)
  name <- if (stage == "final") "output:output/seurat.rds" else "analysis"
  if (stage == "final" && !identical(state$status, "complete")) stop("Final result is unavailable until completion; request stage='analysis' explicitly for a saved provisional object.", call. = FALSE)
  if (is.null(state$files[[name]])) stop("No saved ", stage, " result exists.", call. = FALSE)
  .sc_project_unwrap(.sc_run_get(root, state, name))
}

#' @export
print.sc_analysis <- function(x, ...) {
  cat("Analysis:", x$project_dir, "\nStatus:", x$view$status, "Stage:", x$view$stage,
    "\nUse sc_review(x) to display the evidence and obtain a confirmation snapshot.\n")
  invisible(x)
}

#' @export
print.sc_review_snapshot <- function(x, ...) {
  .sc_ui_intact(x, TRUE)
  previous <- options(max.print = .Machine$integer.max)
  on.exit(options(previous), add = TRUE)
  cat("Review:", x$project_dir, "\nStatus:", x$view$status, "Stage:", x$view$stage,
    "\nDeclared study facts:\n")
  print(x$view$context)
  cat("Measured evidence:\n"); print(x$view$evidence)
  if (!is.null(x$view$computed_diagnostics)) {cat("Saved computed diagnostics:\n"); print(x$view$computed_diagnostics)}
  if (!is.null(x$view$strategy_review)) {cat("Complete strategy and local impact:\n"); print(x$view$strategy_review$details)}
  if (!is.null(x$view$annotation_review)) {cat("Complete annotation and supplied marker evidence:\n"); print(x$view$annotation_review$details)}
  if (identical(x$view$pending$kind, "external_transfer")) {cat("Exact external transfer preview (consent is separate from scientific review):\n"); print(x$view$pending)}
  if (!is.null(x$view$failure)) print(x$view$failure)
  if (!is.null(x$view$output)) print(x$view$output)
  if (!is.null(x$annotations)) {cat("Editable annotation table (blank labels require analyst input):\n"); print(x$annotations)}
  cat("Confirm only this snapshot. revise saves a new draft; approve saves a decision.\n",
    "continue=TRUE on scientific approval runs local work only. request is separate; no automatic retry.\n", sep = "")
  invisible(x)
}
