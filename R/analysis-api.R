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
.sc_ui_plan <- function(edits = list(), base = NULL, dimensions = NULL, mad = NULL, pc_limits = NULL, diagnostic_policy = NULL) {
  if (!is.list(edits) || (length(edits) && (is.null(names(edits)) ||
      anyDuplicated(names(edits)) || anyNA(names(edits))))) stop("plan must be a named list. Supply the choices you want to revise, then inspect the refreshed review before approving.", call. = FALSE)
  allowed <- c("rationale", "risks", "qc", "qc_preset", "analysis", "pcs", "batch", "resolution", "diagnostic_resolutions", "umap", "cycle", "doublet", "choice_reasons")
  if (length(setdiff(names(edits), allowed))) stop("Unknown plan fields: ", paste(setdiff(names(edits), allowed), collapse = ", "), call. = FALSE)
  new_draft <- is.null(base)
  if (new_draft) {
    nfeatures <- as.integer(min(2000L, dimensions[[1]], if (is.null(pc_limits)) Inf else pc_limits$nonconstant_normalized_features))
    npcs <- min(50L, nfeatures - 1L, dimensions[[2]] - 1L)
    base <- list(schema = "scagentkit.strategy.v1",
      rationale = "Editable software starting draft. Review input QC and study facts before approval.",
      risks = list("Starting drafts and standard analysis parameters do not establish completed QC or scientific suitability.",
        "Resolution 0.5 is a provisional scan starting value, not a recommendation. Review the measured cluster tree before final author selection."),
      inferences = list(), qc = list(schema = "scagentkit.qc.v1",
        rationale = "Unfiltered keep-all starting draft: no cell is removed without a reviewed QC choice. Inspect distributions and candidate impacts before approval.",
        risks = list("No study-specific quality threshold has been established. Raw MEX input does not establish completed empty-droplet calling."),
        filters = list(list(op = "range", metric = "nCount", min = 0))),
      analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
        nfeatures = nfeatures, npcs = npcs, seed = 17L),
      pcs = list(method = "computed_top50", threshold = .80),
      batch = list(method = "none", reason = "No batch correction selected; technical provenance requires explicit review."),
      clustering = list(resolution = .5, diagnostic_resolutions = c(.2, .4, .6, .8, 1)),
      umap = list(run = TRUE, n_neighbors = min(30L, dimensions[[2]] - 1L)))
  }
  for (name in intersect(names(edits), c("rationale", "batch", "umap", "cycle", "doublet", "choice_reasons"))) {
    if (name == "umap" && is.logical(edits[[name]]) && length(edits[[name]]) == 1L)
      base$umap$run <- edits[[name]] else base[[name]] <- edits[[name]]
  }
  if ("risks" %in% names(edits)) base$risks <- as.list(edits$risks)
  if ("analysis" %in% names(edits)) {
    if (!is.list(edits$analysis) || is.null(names(edits$analysis)) ||
        length(setdiff(names(edits$analysis), c(names(base$analysis),"hvg_method","hvg_column")))) stop("Unknown analysis settings. Use the supported fields in the displayed plan and resubmit the draft.", call. = FALSE)
    base$analysis[names(edits$analysis)] <- edits$analysis
  }
  if (new_draft) {
    if (!"npcs" %in% names(edits$analysis))
      base$analysis$npcs <- as.integer(min(50L, base$analysis$nfeatures - 1L, dimensions[[2]] - 1L))
    base$risks <- c(base$risks, list(paste0("PCA request: ", base$analysis$npcs,
      " components (target at most 50; requested HVGs ", base$analysis$nfeatures,
      "; selected cells ", dimensions[[2]], "). This is a dimension/nonconstant-feature upper bound, not a numerical rank proof. Zero-variance selected HVGs or PCs remain blocking errors; execution never clips the approved request.",
      if (!is.null(pc_limits)) paste0(" LogNormalize(scale.factor=", pc_limits$scale_factor,
        ") found ", pc_limits$nonconstant_normalized_features, " nonconstant of ", pc_limits$total_features,
        " genes; normalized variance must exceed 128 * .Machine$double.eps * pmax(1, mean(normalized_value^2)).") else ""),
      "The 80% PC candidate divides cumulative variance by the sum for the first at most 50 actually computed PCs, not total expression or HVG variance. Fewer computed PCs are explicitly a truncated reference, not proof that total variance reached 80%; this is an empirical review option, not an optimal PC count."))
  }
  if ("pcs" %in% names(edits)) base$pcs <- if (is.numeric(edits$pcs))
    list(method = "fixed", ndim = edits$pcs) else edits$pcs
  if ("resolution" %in% names(edits)) base$clustering$resolution <- edits$resolution
  if ("diagnostic_resolutions" %in% names(edits)) base$clustering["diagnostic_resolutions"] <- list(edits$diagnostic_resolutions)
  fallback <- if (new_draft) .sc_run_default_mad_choice(mad) else NULL
  if (new_draft) base$qc$rationale <- paste(if (isTRUE(fallback$eligible)) "Conservative AND3 starting draft." else base$qc$rationale, fallback$reason)
  mad_rule <- if (!is.null(mad)) list(op = "mad_preset", preset_id = if (new_draft) fallback$preset_id else "keep_all", panel_hash = mad$panel_hash) else {
    existing <- Filter(function(rule) identical(rule$op, "mad_preset"), base$qc$rules)
    if (length(existing)) existing[[1L]] else NULL
  }
  if ("qc_preset" %in% names(edits)) {
    if (is.null(mad_rule)) stop("qc_preset requires the saved MAD candidate panel.", call. = FALSE)
    .sc_project_string(edits$qc_preset, "qc_preset")
    mad_rule$preset_id <- edits$qc_preset
  }
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
  if (!is.null(mad_rule)) {
    ranges <- if (identical(base$qc$schema, "scagentkit.qc.v1")) base$qc$filters else
      Filter(function(rule) !identical(rule$op, "mad_preset"), base$qc$rules)
    base$qc <- list(schema = "scagentkit.qc.rules.v1", rationale = base$qc$rationale,
      risks = base$qc$risks, remove_if = "any", rules = c(ranges, list(mad_rule)))
  }
  if (new_draft && !"choice_reasons" %in% names(edits)) base$choice_reasons <- .sc_run_default_choice_reasons(
    if (length(intersect(names(edits), c("qc", "qc_preset")))) "Explicit caller QC draft; review measured applicability and exact retained cells before approval." else fallback$reason,
    diagnostic_policy$doublet_mode)
  base
}
.sc_ui_mad_setup <- function(context) .sc_run_mad_group_defaults(context)

.sc_ui_pc_limits <- function(seu, config, scale_factor) {
  scale_factor <- .sc_run_strategy_number(scale_factor, "analysis$scale_factor", 0, open_min = TRUE)
  normalized <- Seurat::NormalizeData(seu, assay = config$assay,
    normalization.method = "LogNormalize", scale.factor = scale_factor, verbose = FALSE)
  values <- .sc_project_layer(normalized, config$assay, "data")
  n <- ncol(values)
  if (n < 2L) stop("PCA diagnostics require at least two selected cells.", call. = FALSE)
  # Sparse moments avoid a dense all-gene/cell matrix and a large QR. A
  # conservative cancellation tolerance makes near-constant values explicit.
  second <- as.numeric(Matrix::rowSums(values * values)) / n
  means <- as.numeric(Matrix::rowSums(values)) / n
  variance <- second - means * means
  tolerance <- 128 * .Machine$double.eps * pmax(1, second)
  nonconstant <- is.finite(variance) & variance > tolerance
  if (sum(nonconstant) < 3L)
    stop("Fewer than three finite nonconstant LogNormalize features remain after proposed QC; revise input or QC before approval.", call. = FALSE)
  list(total_features = as.integer(nrow(values)), selected_cells = as.integer(n),
    nonconstant_normalized_features = as.integer(sum(nonconstant)), scale_factor = scale_factor,
    variance_tolerance = "128 * .Machine$double.eps * pmax(1, mean(normalized_value^2))",
    interpretation = "A nonconstant LogNormalize feature/dimension bound, not a numerical rank proof of the scaled-HVG PCA matrix; exact execution still rejects constant selected HVGs or nonpositive PCs.")
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
                       chat_fn = NULL, budget = NULL, review = list(allow_external = FALSE),
                       sample_id = NULL, matrix_kind = NULL, cell_metadata = NULL,
                       feature_key = c("name", "id"), doublet = c("auto", "off", "flag", "remove"), ...) {
  imported <- .sc_ui_tenx_input(input, context, sample_id, matrix_kind, cell_metadata, match.arg(feature_key))
  input <- imported$input; context <- imported$context
  if (imported$imported) {
    transport <- tempfile("scagentkit-tenx-",fileext=".rds")
    on.exit(unlink(transport),add=TRUE)
    saveRDS(input,transport,version=2L);input<-transport
  }
  extra <- list(...)
  if (is.null(budget) && !is.null(review$transfer_consent) && !identical(extra$cost_mode, "posthoc"))
    stop("Project transfer consent requires an explicit USD cap after reviewing data categories; supply budget=1 or another chosen cap.", call. = FALSE)
  selected_budget <- .sc_run_new_budget(provider, budget, chat_fn)
  provider <- selected_budget$provider; budget <- selected_budget$budget
  chat_fn <- selected_budget$chat_fn
  if (is.null(extra$reference_review)) extra$reference_review <- list()
  extra$reference_review$strict_scope <- TRUE
  # Only a new modern project gets the private default. Explicit reference=NULL
  # remains an opt-out; the coordinator saves the selected table as an artifact.
  if (!"reference" %in% names(extra)) {
    extra$reference <- .sc_ui_act_default(context)
    private_provenance <- .sc_ui_act_provenance(extra$reference)
    if (length(private_provenance)) {
      if (is.null(extra$reference_review$provenance)) extra$reference_review$provenance <- list()
      extra$reference_review$provenance <- utils::modifyList(private_provenance, extra$reference_review$provenance)
    }
  }
  if(identical(extra$reference_review$ai_mode,"guided"))
    stop("The first modern annotation draft must be independent marker-only. Inspect its reference comparison before staging the optional one-time guided review.",call.=FALSE)
  doublet <- match.arg(doublet)
  plan_fields <- names(plan)
  plan_fields[plan_fields %in% c("resolution", "diagnostic_resolutions")] <- "clustering"
  plan_fields[plan_fields == "qc_preset"] <- "qc"
  defaults <- list(require_three_gates = !("diagnostic_resolutions" %in% names(plan) && is.null(plan$diagnostic_resolutions)),
    protected_strategy_fields = unique(plan_fields), preserve_metadata = TRUE, automatic_metadata = TRUE, automatic_mad = !"qc_mad" %in% names(extra),
    automatic_cycle = !"cycle_diagnostics" %in% names(extra),
    doublet_mode = if (identical(extra$doublet_diagnostics, FALSE)) "off" else doublet)
  if ("input_policy" %in% names(extra)) {
    invisible(.sc_run_input_policy(extra$input_policy))
    defaults[names(extra$input_policy)] <- extra$input_policy
  }
  extra$input_policy <- .sc_run_input_policy(defaults)
  source_context <- context
  metadata_input <- if (is.character(input) && length(input) == 1L) readRDS(input) else input
  if (inherits(metadata_input, "Seurat") && extra$input_policy$automatic_metadata)
    context <- .sc_run_metadata_roles(metadata_input, context, select_single = TRUE)$context
  blocked <- c("strategy", "strategy_proposal", "qc_proposal", "annotation_proposal", "analysis", "start_stage")
  if (length(intersect(names(extra), blocked))) stop("Use plan for raw analysis settings; advanced entries remain available through sc_run().", call. = FALSE)
  if (!"qc_mad" %in% names(extra)) extra$qc_mad <- .sc_ui_mad_setup(context)
  # Configuring a provider must not remove the local reviewable rule draft.
  # Configured-provider dispatch belongs to the suggestion channel. Preserve
  # the existing explicit in-memory chat_fn contract for advanced R callers.
  if (is.null(plan) && is.null(chat_fn)) plan <- list()
  proposal <- NULL
  if (is.null(provider) || !is.null(plan)) {
    object <- metadata_input
    dimensions <- dim(object)
    if (length(dimensions) != 2L) stop("input must be a counts matrix, Seurat object or its RDS path.", call. = FALSE)
    panel <- NULL
    if (!is.null(extra$qc_mad) && !identical(extra$qc_mad, FALSE)) {
      # Construct the ordinary immutable panel on a copy so the first draft can
      # bind its exact hash. sc_run independently recreates and verifies it.
      config <- list(context = context, assay = if (is.null(extra$assay)) "RNA" else extra$assay,
        counts_layer = if (is.null(extra$counts_layer)) "counts" else extra$counts_layer,
        qc_mad = extra$qc_mad, doublet_diagnostics = extra$doublet_diagnostics,
        prefilter = .sc_run_prefilter_options(extra$qc_mad$prefilter))
      checked <- .sc_run_input(object, context, config$assay, config$counts_layer)
      config$context <- checked$context
      config$qc_mad <- .sc_run_mad_options(config$context, extra$qc_mad[setdiff(names(extra$qc_mad), "prefilter")])
      qc <- .sc_run_qc_evidence(checked$seu, config$context, config$assay, config$counts_layer)
      prefilter <- .sc_run_prefilter_evidence(checked$seu, config)
      panel <- .sc_run_mad_evidence(checked$seu, config, qc, prefilter_record = prefilter)
    }
    edits <- if (is.null(plan)) list() else plan
    proposal <- .sc_ui_plan(edits, dimensions = dimensions, mad = panel, diagnostic_policy = extra$input_policy)
    if (!is.null(panel)) {
      qc$mad_record <- panel; qc$summary$mad <- panel$summary
      qc$evidence_hash <- .sc_run_qc_hash(qc)
      selected <- .sc_run_qc_validate(proposal$qc, qc)$keep_cells
      selected_object <- checked$seu[, selected]
    } else {
      config <- list(assay = if (is.null(extra$assay)) "RNA" else extra$assay,
        counts_layer = if (is.null(extra$counts_layer)) "counts" else extra$counts_layer)
      checked <- .sc_run_input(object, context, config$assay, config$counts_layer)
      qc <- .sc_run_qc_evidence(checked$seu, checked$context, config$assay, config$counts_layer)
      selected <- .sc_run_qc_validate(proposal$qc, qc)$keep_cells
      selected_object <- checked$seu[, selected]
    }
    limits <- .sc_ui_pc_limits(selected_object, config, proposal$analysis$scale_factor)
    proposal <- .sc_ui_plan(edits, dimensions = dim(selected_object), mad = panel, pc_limits = limits, diagnostic_policy = extra$input_policy)
  }
  do.call(sc_run, c(list(input = input, project_dir = project_dir, context = source_context, strategy = TRUE,
    strategy_proposal = proposal, provider = provider, chat_fn = chat_fn,
    budget = budget, review = review), extra))
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
      if (identical(provider$name, "manual")) stop("This project has no configured provider. Continue with local manual review, or create a new project with an available provider key and explicit transfer policy.", call. = FALSE)
      if (!identical(.sc_run_provider_spec(provider, chat_fn)$metadata, provider)) stop("Provider settings changed. Restore the saved provider/model settings or create a new project.", call. = FALSE)
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
      if (!is.null(plan) && is.null(project$plan)) stop("No displayed strategy draft; use the advanced typed strategy entry. Inspect sc_review() and supply a complete supported plan before approval.", call. = FALSE)
      proposal <- if (!is.null(plan)) .sc_ui_plan(plan, base = project$plan) else .sc_ui_annotation(annotations)
      # Lock once to bind first drafts as strictly as revisions. The public
      # sc_run_propose lacks a revision argument, so never call it blindly.
      owner <- .sc_run_lock(root); on.exit(.sc_run_release(root, owner), add = TRUE)
      state <- .sc_run_load(root); .sc_ui_current(root, state, project)
      if (!is.null(plan)) {
        if (is.null(project$plan)) stop("No displayed strategy draft; use the advanced typed strategy entry. Inspect sc_review() and supply a complete supported plan before approval.", call. = FALSE)
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

# Bounded presentation only: the sealed snapshot and saved records stay complete.
.sc_ui_print_summary <- function(value) {
  text <- utils::capture.output(utils::str(value, max.level = 2L, list.len = 6L,
    vec.len = 4L, give.attr = FALSE, width = 100L, strict.width = "cut"))
  cat(paste(substr(head(text, 40L), 1L, 160L), collapse = "\n"), "\n", sep = "")
  if (length(text) > 40L) cat("[Summary limited to 40 lines; inspect the full snapshot field.]\n")
}

#' @export
print.sc_review_snapshot <- function(x, ...) {
  .sc_ui_intact(x, TRUE)
  cat("Review:", x$project_dir, "\nStatus:", x$view$status, "Stage:", x$view$stage,
    "\nBounded summary; complete evidence is available as snapshot$view and snapshot$annotations.\n",
    "Use the object returned by sc_review() as snapshot; inspect details before approving.\n",
    "Declared study facts:\n")
  .sc_ui_print_summary(x$view$context)
  fields <- c(evidence = "Measured evidence", computed_diagnostics = "Saved computed diagnostics",
    strategy_review = "Strategy and local impact", annotation_review = "Annotation and supplied marker evidence",
    failure = "Failure", output = "Output")
  for (field in names(fields)) if (!is.null(x$view[[field]])) {
    cat(fields[[field]], " [snapshot$view$", field, "]:\n", sep = "")
    value <- x$view[[field]]
    if (field %in% c("strategy_review", "annotation_review")) value <- value$details
    .sc_ui_print_summary(value)
  }
  if (identical(x$view$pending$kind, "external_transfer")) {
    cat("External transfer summary; exact payload in snapshot$view$pending (separate consent):\n")
    .sc_ui_print_summary(x$view$pending)
  }
  if (!is.null(x$annotations)) {
    cat("Editable annotation table [snapshot$annotations; blank labels require analyst input]:\n")
    .sc_ui_print_summary(x$annotations)
  }
  cat("Confirm only this snapshot. revise saves a new draft; approve saves a decision.\n",
    "continue=TRUE on scientific approval runs local work only. request is separate; no automatic retry.\n", sep = "")
  invisible(x)
}
