# Author declarations are typed data. Saving them revokes the initial draft,
# never approves it or computes replacement scientific evidence.
.sc_run_recommend_facts_object <- function(value, allowed, label) {
  if (!is.list(value) || is.object(value) || !length(value) || is.null(names(value)) ||
      anyNA(names(value)) || any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
      length(setdiff(names(value), allowed)))
    stop(label, " requires a nonempty object with supported unique fields.", call. = FALSE)
}
.sc_run_recommend_facts_typed <- function(facts) {
  .sc_run_recommend_facts_object(facts, c("columns", "batch", "doublet"), "Facts")
  text <- function(value, label, limit = 4000L) {
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !nzchar(trimws(value)) || nchar(value, type = "chars") > limit)
      stop(label, " must be nonempty bounded text.", call. = FALSE)
  }
  boolean <- function(value, label) {
    if (!is.logical(value) || length(value) != 1L || is.na(value))
      stop(label, " must be an explicit logical boolean.", call. = FALSE)
  }
  if ("columns" %in% names(facts)) {
    .sc_run_recommend_facts_object(facts$columns,
      c("sample", "qc_group", "capture", "batch", "group", "condition", "treatment", "donor"), "Facts columns")
    for (role in names(facts$columns)) text(facts$columns[[role]], paste0("columns.", role), 200L)
  }
  if ("batch" %in% names(facts)) {
    .sc_run_recommend_facts_object(facts$batch, c("technical_batch", "source"), "Batch facts")
    if ("technical_batch" %in% names(facts$batch)) boolean(facts$batch$technical_batch, "batch.technical_batch")
    if ("source" %in% names(facts$batch)) text(facts$batch$source, "batch.source")
  }
  if ("doublet" %in% names(facts)) {
    d <- facts$doublet
    .sc_run_recommend_facts_object(d, c("data_type", "technology", "input_source", "empty_droplets_removed", "full_called_cohort", "capture", "rate"), "Doublet facts")
    for (key in intersect(c("data_type", "technology", "input_source"), names(d))) text(d[[key]], paste0("doublet.", key))
    for (key in intersect(c("empty_droplets_removed", "full_called_cohort"), names(d))) boolean(d[[key]], paste0("doublet.", key))
    if ("capture" %in% names(d)) {
      .sc_run_recommend_facts_object(d$capture, c("method", "column", "id", "source"), "Doublet capture facts")
      for (key in names(d$capture)) text(d$capture[[key]], paste0("doublet.capture.", key))
      if (!is.null(d$capture$method) && !d$capture$method %in% c("column", "single"))
        stop("Unsupported doublet capture method.", call. = FALSE)
    }
    if ("rate" %in% names(d)) {
      .sc_run_recommend_facts_object(d$rate, c("method", "value", "source", "sd"), "Doublet rate facts")
      for (key in intersect(c("method", "source"), names(d$rate))) text(d$rate[[key]], paste0("doublet.rate.", key))
      if (!is.null(d$rate$method) && !d$rate$method %in% c("manual", "10x_standard"))
        stop("Unsupported doublet rate method.", call. = FALSE)
      if ("value" %in% names(d$rate)) .sc_run_doublet_rate_values(d$rate$value)
      if ("sd" %in% names(d$rate)) .sc_run_strategy_number(d$rate$sd, "doublet.rate.sd", 0, .5)
    }
  }
  invisible(facts)
}

.sc_run_recommend_facts_config <- function(state, facts, input) {
  .sc_run_recommend_facts_typed(facts)
  old <- state$config$recommendation_facts
  if (is.null(old)) old <- list()
  declared <- state$config$doublet_diagnostics
  algorithm_keys <- c("column_prefix", "seed", "nfeatures", "dims", "artificial_doublets", "iter", "clusters")
  # Diagnostics may be disabled by an unavailable dependency or input guard.
  # Retain the author's algorithm settings independently across later edits.
  settings <- state$config$recommendation_doublet_settings
  if (is.null(settings) && is.list(declared)) settings <- declared[intersect(algorithm_keys, names(declared))]
  if (is.list(declared)) {
    keys <- intersect(c("data_type", "technology", "input_source", "empty_droplets_removed",
      "full_called_cohort", "capture", "rate"), names(declared))
    old <- utils::modifyList(list(doublet = declared[keys]), old, keep.null = TRUE)
  }
  # A newly declared method replaces only incompatible historical fields.
  # Contradictions explicitly supplied in the same patch remain and are rejected.
  method <- facts$doublet$capture$method
  if (identical(method, "column")) old$doublet$capture$id <- NULL
  if (identical(method, "single")) old$doublet$capture$column <- NULL
  if (identical(facts$doublet$rate$method, "10x_standard")) old$doublet$rate$value <- NULL
  merged <- utils::modifyList(old, facts, keep.null = TRUE)
  .sc_run_recommend_facts_typed(merged)
  config <- state$config
  config$recommendation_doublet_settings <- settings
  context <- config$context
  for (role in names(merged$columns)) context$columns[[role]] <- merged$columns[[role]]
  capture <- merged$doublet$capture
  if (identical(capture$method, "column") && !is.null(capture$column)) {
    if (!is.null(merged$columns$capture) && !identical(merged$columns$capture, capture$column))
      stop("Explicit capture metadata columns conflict; correct the author declarations together.", call. = FALSE)
    context$columns$capture <- capture$column
  }
  if (identical(capture$method, "single") && (!is.null(capture$column) || !is.null(context$columns$capture)))
    stop("A single-capture declaration conflicts with an explicitly mapped capture column.", call. = FALSE)
  if (identical(capture$method, "column") && !is.null(capture$id))
    stop("Column capture facts cannot also declare a single capture ID.", call. = FALSE)
  if (identical(merged$doublet$rate$method, "10x_standard") && !is.null(merged$doublet$rate$value))
    stop("Standard-10x rate facts cannot also supply a manual rate value.", call. = FALSE)
  if (!is.null(merged$batch$technical_batch)) {
    if (is.null(merged$batch$source)) stop("batch.source must record the author declaration provenance.", call. = FALSE)
    context$design$technical_batch <- merged$batch$technical_batch
  }
  context <- .sc_run_context(context, input)
  metadata <- input[[]]
  for (role in names(context$columns)) {
    values <- metadata[[context$columns[[role]]]]
    if (any(!nzchar(trimws(as.character(values))))) stop("Declared metadata column contains blank role labels.", call. = FALSE)
  }
  if (!is.null(context$columns$batch) && context$columns$batch %in%
      unlist(context$columns[intersect(c("capture", "group", "condition", "treatment"), names(context$columns))], use.names = FALSE))
    stop("Technical batch metadata column conflicts with capture or biological roles; do not reinterpret those roles as correction targets.", call. = FALSE)
  config$context <- context
  if (!is.null(config$input_policy)) config$metadata_transfer_policy <- .sc_run_metadata_transfer_policy(input, context)
  if (isTRUE(config$input_policy$automatic_metadata))
    config$metadata_role_draft <- .sc_run_metadata_roles(input, context, select_single = FALSE)$summary
  if (isTRUE(config$input_policy$automatic_mad) && is.null(config$qc_mad) &&
      length(intersect(names(facts$columns), c("sample", "qc_group")))) {
    prepared_mad <- .sc_run_mad_group_defaults(context)
    if (!identical(prepared_mad, FALSE)) {
      config$prefilter <- .sc_run_prefilter_options(NULL)
      config$qc_mad <- .sc_run_mad_options(context, prepared_mad)
    }
  }
  config$recommendation_facts <- merged
  if (!is.null(config$qc_mad)) {
    if (length(intersect(names(facts$columns), c("sample", "qc_group")))) {
      role <- if (!is.null(context$columns$qc_group)) "qc_group" else "sample"
      config$qc_mad$grouping <- list(method = "column", column = context$columns[[role]],
        declared_role = role, source = "Explicit initial author facts; grouping changes require fresh MAD evidence and review.")
    }
    group <- config$qc_mad$grouping
    if (identical(group$method, "column")) config$qc_mad$grouping$column <- context$columns[[group$declared_role]]
    config$qc_mad <- .sc_run_mad_options(context, config$qc_mad)
  }
  if (length(merged$doublet) && !identical(config$input_policy$doublet_mode, "off")) {
    config$doublet_diagnostics <- NULL
    preparation <- .sc_run_recommend_doublet_options(config)
    if (isTRUE(preparation$ready)) {
      options <- preparation$options
      # Facts may correct provenance without silently changing the original
      # author's explicit, noneditable classifier settings or output columns.
      if (is.list(settings)) for (key in intersect(algorithm_keys, names(settings)))
        options[[key]] <- settings[[key]]
      config$doublet_diagnostics <- .sc_run_doublet_options(context, options)
      config$recommendation_doublet_settings <- config$doublet_diagnostics[algorithm_keys]
    }
  } else if (!is.null(config$doublet_diagnostics)) {
    config$doublet_diagnostics <- .sc_run_doublet_options(context, config$doublet_diagnostics)
  }
  if (!is.null(config$doublet_diagnostics)) {
    guard <- tryCatch(.sc_run_recommend_facts_doublet_guard(input, config),
      error = function(e) list(ready = FALSE, reasons = list(conditionMessage(e)),
        capture_counts = list(), scoring_executed = FALSE))
    config$recommendation_doublet_preparation <- guard
    if (!isTRUE(guard$ready)) config$doublet_diagnostics <- NULL
  } else config$recommendation_doublet_preparation <- NULL
  .sc_project_json_check(config)
  config
}

.sc_run_recommend_facts_doublet_guard <- function(input, config) {
  options <- config$doublet_diagnostics
  if (any(.sc_run_doublet_columns(options$column_prefix) %in% names(input[[]])))
    return(list(ready = FALSE, reasons = list("Doublet output metadata columns already exist in the original input; they are preserved. Prepare a separately reviewed configuration with fresh output columns."), capture_counts = list(), scoring_executed = FALSE))
  cells <- colnames(input)
  counts <- .sc_project_layer(input, config$assay, config$counts_layer, raw_counts = TRUE)
  if (anyDuplicated(colnames(counts)) || !setequal(colnames(counts), cells))
    stop("Doublet prerequisite counts must cover the exact literal input cell IDs.", call. = FALSE)
  counts <- counts[, cells, drop = FALSE]
  captures <- .sc_run_doublet_captures(input, options, cells)
  .sc_run_doublet_resolve_rates(options, captures) # Validate the literal per-capture map, without scoring.
  totals <- as.numeric(Matrix::colSums(counts))
  prefilter <- .sc_run_prefilter_options(config$prefilter)
  eligible <- if (identical(prefilter$method, "min_counts")) cells[totals >= prefilter$min_counts] else cells
  reasons <- list()
  groups <- lapply(unique(unname(captures)), function(id) {
    original <- cells[captures == id]
    selected <- original[original %in% eligible]
    features <- sum(Matrix::rowSums(counts[, selected, drop = FALSE]) > 0)
    low <- sum(totals[match(selected, cells)] < 200)
    if (length(original) < 100L || length(selected) < 100L)
      reasons <<- c(reasons, list(paste0("Capture ", id, " has fewer than 100 original or prefilter-eligible cells; no partial scoring is supported.")))
    if (low) reasons <<- c(reasons, list(paste0("Capture ", id, " has ", low, " pre-score cells below 200 raw counts; no silent filtering is permitted.")))
    if (features < options$nfeatures) reasons <<- c(reasons, list(paste0("Capture ", id, " has fewer expressed features than declared nfeatures; no clipping is permitted.")))
    if (options$dims >= min(length(selected), features)) reasons <<- c(reasons, list(paste0("Capture ", id, " cannot support the declared dimensions.")))
    list(capture = id, original_cells = length(original), pre_score_cells = length(selected),
      expressed_features = features, low_read_cells = low)
  })
  if (!length(reasons)) {
    .sc_run_doublet_dependencies()
    .sc_run_doublet_classifier_adapter() # Verify callable namespaces and audited source without invoking the algorithm.
  }
  list(ready = !length(reasons), reasons = reasons, capture_counts = groups, scoring_executed = FALSE)
}

.sc_run_recommend_facts_save <- function(root, state, facts, reviewer, reason) {
  if (!.sc_run_recommend_fact_editable(state))
    stop("Facts can be edited only at the initial unapproved raw strategy review; existing approval or execution closes this boundary.", call. = FALSE)
  input <- .sc_run_get(root, state, "input")
  config <- .sc_run_recommend_facts_config(state, facts, input)
  # Validation above must finish before creating any versioned audit artifact.
  previous <- if (is.null(state$files$recommendation_facts_archive)) list() else
    .sc_run_get(root, state, "recommendation_facts_archive")$revisions
  record <- list(config = state$config, config_hash = state$config_hash,
    files = state$files, pending = state$pending, approved = state$approved,
    nodes = state$nodes, completed = state$completed, revision = state$revision,
    reviewer = reviewer, reason = reason, supplied_facts = facts,
    policy = "Historical declarations and artifacts only; no approval or computation is copied to the new facts.")
  state <- .sc_run_put(root, state, "recommendation_facts_archive", list(revisions = append(previous, list(record))))
  preserve <- intersect(c("input", "reference", "annotation_history_input", "manual_strategy", "manual_annotation", "recommendation_facts_archive"), names(state$files))
  invalidated <- state$files[setdiff(names(state$files), preserve)]
  state$files <- state$files[preserve]
  old_config_hash <- state$config_hash
  state$config <- config; state$config_hash <- .sc_run_hash(config)
  state$pending <- NULL; state$approved <- NULL; state$failure <- NULL; state$output <- NULL
  state$strategy_return <- NULL; state$strategy_authorizations <- NULL
  state$suggestion <- NULL; state$transfer_hashes <- character()
  state$completed <- character(); state$nodes <- list()
  state$stage <- if (!is.null(config$qc_mad)) "prefilter" else "strategy_evidence"
  state$status <- "ready"; state$nodes[[state$stage]] <- "PLANNED"
  state$recommendation_rebuild <- list(refresh_mad = !is.null(config$qc_mad),
    previous_config_hash = old_config_hash, reason = "Rebind the retained draft to fresh fact-specific evidence; no automatic cell removal.")
  state <- .sc_run_event(state, "author_facts_saved", list(reviewer = reviewer, reason = reason,
    previous_config_hash = old_config_hash, config_hash = state$config_hash,
    facts = config$recommendation_facts, archived_files = invalidated,
    boundary = "Facts saved only. Explicit Continue/resume rebuilds evidence; the new complete strategy requires fresh approval."))
  .sc_run_save(root, state)
  state
}
