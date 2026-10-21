# Frozen local execution context for a rule set that adds no filtering.
# This context is never a public proposal or provider payload field.
.sc_run_qc_scope_fail <- function() {
  stop("Retained QC scope or its committed input/history/artifact evidence changed; obtain a fresh review.", call. = FALSE)
}
.sc_run_qc_scope_hash <- function(context) .sc_run_hash(context[setdiff(names(context), "hash")])
.sc_run_qc_scope_fields <- function(value, fields) {
  is.list(value) && !is.null(names(value)) && !anyNA(names(value)) &&
    !anyDuplicated(names(value)) && setequal(names(value), fields)
}
.sc_run_qc_scope_digest <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && grepl("^[0-9a-f]{64}$", value)
}
.sc_run_qc_scope_sequence <- function(value) {
  is.integer(value) && length(value) == 1L && !is.na(value) && value >= 0L
}
.sc_run_qc_retained_scope_cells <- function(context, evidence) {
  cells <- evidence$metrics$cell_id
  if (is.null(context)) return(cells)
  fields <- c("schema", "input_hash", "evidence_hash", "counts_hash", "cell_hash", "features_hash",
    "history", "sources", "cell_ids", "hash")
  if (!.sc_run_qc_scope_fields(context, fields) ||
      !identical(context$schema, "scagentkit.qc.retained-scope.v1") ||
      !all(vapply(context[c("input_hash", "evidence_hash", "counts_hash", "cell_hash", "features_hash", "hash")],
        .sc_run_qc_scope_digest, logical(1))) ||
      !identical(context$hash, .sc_run_qc_scope_hash(context)) ||
      !identical(evidence$evidence_hash, .sc_run_qc_hash(evidence)) ||
      !identical(context$evidence_hash, evidence$evidence_hash) ||
      !identical(context$counts_hash, evidence$counts_hash) ||
      !identical(context$cell_hash, evidence$cell_hash) ||
      !identical(context$features_hash, evidence$features_hash) ||
      !.sc_run_qc_scope_fields(context$history, c("sequence", "head_hash")) ||
      !.sc_run_qc_scope_sequence(context$history$sequence) ||
      !.sc_run_qc_scope_digest(context$history$head_hash) ||
      !is.list(context$sources) || !is.null(names(context$sources)) || length(context$sources) > 2L ||
      !is.character(context$cell_ids) || anyNA(context$cell_ids) || anyDuplicated(context$cell_ids) ||
      !identical(context$cell_ids, cells[cells %in% context$cell_ids])) .sc_run_qc_scope_fail()
  stages <- character()
  for (source in context$sources) {
    if (!.sc_run_qc_scope_fields(source, c("stage", "event_sequence", "event_hash", "artifact", "cell_hash")) ||
        !is.character(source$stage) || length(source$stage) != 1L || is.na(source$stage) ||
        !source$stage %in% c("qc_apply", "strategy_selection") ||
        !.sc_run_qc_scope_sequence(source$event_sequence) || source$event_sequence < 1L ||
        source$event_sequence > context$history$sequence ||
        !.sc_run_qc_scope_digest(source$event_hash) || !.sc_run_qc_scope_digest(source$cell_hash) ||
        !.sc_run_qc_scope_fields(source$artifact, c("path", "sha256")) ||
        !.sc_run_qc_scope_digest(source$artifact$sha256) ||
        !is.character(source$artifact$path) || length(source$artifact$path) != 1L ||
        is.na(source$artifact$path) || !grepl("^checkpoints/[^/]+-[0-9a-f]{64}\\.rds$", source$artifact$path))
      .sc_run_qc_scope_fail()
    stages <- c(stages, source$stage)
  }
  if (!identical(stages, c("qc_apply", "strategy_selection")[c("qc_apply", "strategy_selection") %in% stages]))
    .sc_run_qc_scope_fail()
  context$cell_ids
}
.sc_run_qc_scope_read <- function(root, artifact) {
  if (!.sc_run_qc_scope_fields(artifact, c("path", "sha256")) ||
      !is.character(artifact$path) || length(artifact$path) != 1L || is.na(artifact$path) ||
      !grepl("^checkpoints/[^/]+-[0-9a-f]{64}\\.rds$", artifact$path) ||
      !.sc_run_qc_scope_digest(artifact$sha256)) .sc_run_qc_scope_fail()
  path <- file.path(root, artifact$path)
  if (!file.exists(path) || dir.exists(path) || nzchar(Sys.readlink(path)) ||
      nzchar(Sys.readlink(dirname(path))) || !identical(.sc_project_sha_file(path), artifact$sha256))
    .sc_run_qc_scope_fail()
  tryCatch(readRDS(path), error = function(e) .sc_run_qc_scope_fail())
}
.sc_run_qc_scope_prefix <- function(state, count) {
  if (!.sc_run_qc_scope_sequence(count) || count > length(state$history)) .sc_run_qc_scope_fail()
  history <- state$history[seq_len(count)]
  previous <- strrep("0", 64L)
  for (i in seq_along(history)) {
    event <- history[[i]]; hash <- event$hash; event$hash <- NULL
    if (!identical(event$sequence, i) || !identical(event$previous_hash, previous) ||
        !identical(hash, .sc_run_hash(event))) .sc_run_qc_scope_fail()
    previous <- hash
  }
  list(events = history, head_hash = previous)
}
.sc_run_qc_scope_sources <- function(root, state, evidence, history) {
  cells <- evidence$metrics$cell_id
  sources <- list(); retained <- cells
  selected <- lapply(c("qc_apply", "strategy_selection"), function(stage) {
    hits <- which(vapply(history, function(event) identical(event$action, "executed") &&
      identical(event$details$stage, stage), logical(1)))
    if (!length(hits)) NULL else history[[tail(hits, 1L)]]
  })
  if (!any(vapply(selected, Negate(is.null), logical(1)))) return(list(sources = sources, cell_ids = retained))
  input <- .sc_run_qc_scope_read(root, state$files$input)
  input_counts <- .sc_project_matrix(.sc_project_layer(input, evidence$summary$assay, evidence$summary$counts_layer, raw_counts = TRUE), "Retained-scope input counts", raw_counts = TRUE)
  if (!identical(colnames(input), cells) || !identical(rownames(input_counts), evidence$feature_ids) ||
      !identical(.sc_project_sparse_hash(.sc_project_matrix(input_counts[, cells, drop = FALSE], "Retained-scope input counts", raw_counts = TRUE)), evidence$counts_hash))
    .sc_run_qc_scope_fail()
  for (event in selected) {
    if (is.null(event)) next
    if (!identical(event$details$files$input, state$files$input) ||
        !identical(event$details$files$qc_evidence, state$files$qc_evidence)) .sc_run_qc_scope_fail()
    key <- if (identical(event$details$stage, "qc_apply")) "qc_object" else "strategy_selected"
    artifact <- event$details$files[[key]]
    object <- .sc_run_qc_scope_read(root, artifact)
    source_cells <- colnames(object)
    if (!is.character(source_cells) || !length(source_cells) || anyNA(source_cells) ||
        anyDuplicated(source_cells) || !identical(source_cells, cells[cells %in% source_cells])) .sc_run_qc_scope_fail()
    counts <- .sc_project_matrix(.sc_project_layer(object, evidence$summary$assay, evidence$summary$counts_layer, raw_counts = TRUE), "Retained-scope checkpoint counts", raw_counts = TRUE)
    if (!identical(rownames(counts), evidence$feature_ids) || !setequal(colnames(counts), source_cells) ||
        !identical(.sc_project_sparse_hash(counts),
          .sc_project_sparse_hash(.sc_project_matrix(input_counts[, source_cells, drop = FALSE], "Retained-scope input subset", raw_counts = TRUE)))) .sc_run_qc_scope_fail()
    sources <- append(sources, list(list(stage = event$details$stage, event_sequence = event$sequence,
      event_hash = event$hash, artifact = artifact, cell_hash = .sc_run_hash(source_cells))))
    retained <- retained[retained %in% source_cells]
  }
  list(sources = sources, cell_ids = retained)
}
.sc_run_qc_retained_scope <- function(root, state, evidence) {
  if (!identical(evidence$evidence_hash, .sc_run_qc_hash(evidence)) ||
      !.sc_run_qc_scope_digest(state$input_hash)) .sc_run_qc_scope_fail()
  count <- length(state$history)
  prefix <- .sc_run_qc_scope_prefix(state, count)
  retained <- .sc_run_qc_scope_sources(root, state, evidence, prefix$events)
  context <- list(schema = "scagentkit.qc.retained-scope.v1", input_hash = state$input_hash,
    evidence_hash = evidence$evidence_hash, counts_hash = evidence$counts_hash,
    cell_hash = evidence$cell_hash, features_hash = evidence$features_hash,
    history = list(sequence = count, head_hash = prefix$head_hash),
    sources = retained$sources, cell_ids = retained$cell_ids)
  context$hash <- .sc_run_qc_scope_hash(context)
  .sc_run_qc_retained_scope_cells(context, evidence)
  context
}
.sc_run_qc_retained_scope_verify <- function(root, state, context, evidence) {
  if (is.null(context)) .sc_run_qc_scope_fail()
  .sc_run_qc_retained_scope_cells(context, evidence)
  if (!identical(context$input_hash, state$input_hash)) .sc_run_qc_scope_fail()
  prefix <- .sc_run_qc_scope_prefix(state, context$history$sequence)
  if (!identical(prefix$head_hash, context$history$head_hash)) .sc_run_qc_scope_fail()
  retained <- .sc_run_qc_scope_sources(root, state, evidence, prefix$events)
  if (!identical(context$sources, retained$sources) || !identical(context$cell_ids, retained$cell_ids))
    .sc_run_qc_scope_fail()
  invisible(context)
}
.sc_run_qc_retained_scope_for_proposal <- function(root, state, proposal, evidence, kind) {
  if (!kind %in% c("qc", "strategy")) stop("Retained QC scope requires a QC or strategy proposal.", call. = FALSE)
  if (kind == "strategy" && identical(state$config$start_stage, "processed")) return(NULL)
  qc <- if (kind == "strategy") proposal$qc else proposal
  qc_evidence <- if (kind == "strategy") evidence$qc else evidence
  key <- if (kind == "strategy") "strategy_validated" else "qc_validated"
  old <- if (is.null(state$files[[key]])) NULL else .sc_run_get(root, state, key)
  prior <- if (kind == "strategy") old$qc_validated else old
  if (!is.null(prior) && .sc_run_qc_empty_rules(prior$proposal) && .sc_run_qc_empty_rules(qc)) {
    .sc_run_qc_retained_scope_verify(root, state, prior$retained_scope, qc_evidence)
    # Canonicalization validates omitted defaults and evidence before comparing
    # scientific choices; explanatory reasons do not select a new cell cohort.
    current <- if (kind == "strategy") .sc_run_strategy_validate(proposal, evidence, retained_scope = prior$retained_scope) else
      .sc_run_qc_validate(proposal, evidence, retained_scope = prior$retained_scope)
    current_qc <- if (kind == "strategy") current$qc_validated else current
    doublet_same <- kind == "qc" || identical(old$proposal$doublet$method, current$proposal$doublet$method)
    if (doublet_same && identical(.sc_run_qc_scientific_key(prior$proposal),
        .sc_run_qc_scientific_key(current_qc$proposal))) return(prior$retained_scope)
  }
  .sc_run_qc_retained_scope(root, state, qc_evidence)
}
.sc_run_qc_scope_for_publication <- function(root, state, validated, evidence, retained_scope = NULL) {
  saved <- validated$retained_scope
  if (is.null(saved) || (!is.null(retained_scope) && !identical(retained_scope, saved))) .sc_run_qc_scope_fail()
  .sc_run_qc_retained_scope_verify(root, state, saved, evidence)
  saved
}
