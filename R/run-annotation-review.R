# Immutable local annotation evidence. Reading these saved tables never calls
# a provider or recomputes expression, markers, references or cluster membership.
.sc_run_annotation_review_hash <- function(record) {
  .sc_run_hash(record[setdiff(names(record), c("hash", "lifecycle"))])
}
.sc_run_annotation_review_summary <- function(record) {
  record[setdiff(names(record), c("details", "lifecycle"))]
}
.sc_run_annotation_review_provider <- function(metadata) {
  if (!is.list(metadata)) return(NULL)
  # No credentials, headers, raw transport object or function environments.
  output <- metadata[intersect(c("name", "model", "generation", "external"), names(metadata))]
  if (is.list(output$generation)) output$generation <- output$generation[intersect(
    c("temperature", "max_tokens", "timeout_secs", "seed", "top_p", "stop",
      "frequency_penalty", "presence_penalty", "thinking", "response_format", "reasoning_effort"),
    names(output$generation))]
  output
}
.sc_run_annotation_review_plain <- function(proposal) {
  list(schema = proposal$schema, annotations = proposal$annotations)
}
.sc_run_annotation_review_source <- function(root, state, evidence, proposal) {
  manual <- state$files$manual_annotation
  response <- state$files$annotation_response
  source <- list(kind = "unknown",
    configured_provider = .sc_run_annotation_review_provider(state$config$provider),
    manual = list(status = "not_recorded"),
    provider_response = list(status = "not_recorded"))
  if (!is.null(response)) {
    answer <- .sc_run_get(root, state, "annotation_response")
    historical <- tryCatch(.sc_run_annotation_validate(answer$content, evidence), error = function(e) NULL)
    metadata <- .sc_run_annotation_review_provider(answer$provider)
    historical_kind <- if (identical(metadata$name, "mock")) "mock" else
      if (is.character(metadata$name) && length(metadata$name) == 1L &&
          metadata$name %in% c("deepseek", "grok")) "model" else "provider_response"
    events <- Filter(function(event) identical(event$action, "proposal_received") &&
      !is.null(answer$request_hash) && identical(event$details$request_hash, answer$request_hash), state$history)
    source$provider_response <- list(status = answer$status, kind = historical_kind,
      artifact_sha256 = response$sha256,
      provider = metadata, request_hash = answer$request_hash, response_hash = answer$response_hash,
      cached = answer$cached,
      usage = if (is.list(answer$usage)) answer$usage[intersect(
        c("input_tokens", "output_tokens", "cached_tokens"), names(answer$usage))] else NULL,
      cost_usd = answer$cost_usd,
      proposal = if (is.null(historical)) NULL else .sc_run_annotation_review_plain(historical),
      matches_current = !is.null(historical) && identical(historical, proposal),
      recorded_events = lapply(events, function(event)
        list(sequence = event$sequence, created_at = event$created_at,
             action = event$action, request_hash = event$details$request_hash)))
    source$kind <- if (isTRUE(source$provider_response$matches_current)) historical_kind else "unknown"
  }
  if (!is.null(manual)) {
    original <- .sc_run_get(root, state, "manual_annotation")
    normalized <- .sc_run_annotation_validate(original, evidence)
    if (!identical(normalized, proposal))
      stop("Saved manual annotation does not match the review proposal.", call. = FALSE)
    events <- Filter(function(event) identical(event$action, "manual_proposal") &&
      identical(event$details$kind, "annotation"), state$history)
    source$manual <- list(status = "saved_manual_proposal", artifact_sha256 = manual$sha256,
      proposal_hash = .sc_run_hash(original),
      recorded_events = lapply(events, function(event) list(sequence = event$sequence,
        created_at = event$created_at, action = event$action,
        details = event$details[intersect(c("kind", "reviewer", "reason", "hash",
          "previous_proposal_hash", "previous_review_hash"), names(event$details))])))
    source$kind <- "manual"
  }
  adopted <- .sc_run_suggestion_source(root, state, "annotation", .sc_run_annotation_review_plain(proposal))
  if (!is.null(adopted)) {
    source$suggestion <- adopted
    if (isTRUE(adopted$matches_current)) {
      source$kind <- if (isTRUE(adopted$simulated)) "mock" else "provider_response"
      source$manual$status <- "analyst_adopted_typed_suggestion"
    }
  }
  source$interpretation <- paste(
    "Current source is based on saved proposal/response artifacts, not labels or configured model names.",
    "A configured provider alone is not evidence of a model call. Historical responses may differ from the current manual proposal.")
  actual_mode <- if (source$kind == "manual") "not_dispatched" else "unknown"
  if (!is.null(adopted) && isTRUE(adopted$matches_current))
    actual_mode <- if (isTRUE(adopted$simulated)) "not_dispatched" else evidence$summary$reference_mode
  if ((is.null(adopted) || !isTRUE(adopted$matches_current)) &&
      source$kind %in% c("model", "mock", "provider_response") && !is.null(state$files$annotation_request)) {
    request <- .sc_run_get(root, state, "annotation_request")
    request_evidence <- tryCatch(jsonlite::fromJSON(request$user_prompt, simplifyVector = FALSE)$evidence,
                                error = function(e) NULL)
    if (isTRUE(request_evidence$reference_mode %in% c("independent", "guided")))
      actual_mode <- request_evidence$reference_mode
  }
  source$reference_dependency <- actual_mode
  source$reference_prompt <- list(mode = actual_mode,
    planned_mode = evidence$summary$reference_mode,
    database_candidates_in_prompt = if (actual_mode %in% c("independent", "guided")) actual_mode == "guided" else NULL,
    interpretation = "Guided suggestions depend on supplied database candidates; independent means candidates were excluded by this coordinator, not independent biological validation.")
  if (!is.null(adopted) && isTRUE(adopted$matches_current))
    source$reference_prompt$simulated <- isTRUE(adopted$simulated)
  .sc_project_json_check(source)
  source
}
.sc_run_annotation_review_build <- function(root, state, validated, evidence, source = NULL) {
  input <- evidence$private$input_cells
  if (!is.data.frame(input) || !identical(names(input), c("cell_id", "cluster")) ||
      !is.character(input$cluster) || anyNA(input$cluster) || any(!nzchar(input$cluster)))
    stop("Annotation review requires exact saved cell IDs and literal cluster membership.", call. = FALSE)
  .sc_project_ids(input$cell_id, "Annotation review cell IDs")
  cluster_column <- evidence$private$cluster_column
  .sc_project_string(cluster_column, "annotation cluster_column")
  target <- state$config$annotation_column
  .sc_project_string(target, "annotation target column")
  checked <- .sc_run_annotation_validate(.sc_run_annotation_review_plain(validated), evidence)
  if (!inherits(validated, "sc_run_annotation_proposal") || !identical(validated, checked))
    stop("Validated annotation proposal or its exact cell membership changed.", call. = FALSE)
  ids <- vapply(evidence$summary$clusters, `[[`, character(1), "clusterId")
  if (!setequal(unique(input$cluster), ids))
    stop("Annotation review membership and evidence clusters differ.", call. = FALSE)
  markers <- unlist(lapply(evidence$summary$clusters, `[[`, "markers"), recursive = FALSE)
  markers <- .sc_project_records(markers,
    c("clusterId", "gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"), "marker_table", ids)
  candidates <- .sc_project_records(.sc_run_annotation_candidate_records(evidence$private$candidates),
    c("clusterId", "label", "score", "overlap", "referenceSize", "markers", "source"), "candidate_table", ids)
  all_candidates <- .sc_project_records(.sc_run_annotation_candidate_records(evidence$private$candidates_all),
    c("clusterId", "label", "score", "overlap", "referenceSize", "markers", "source"), "candidate_table", ids)
  provenance <- evidence$private$reference_provenance
  if (is.null(provenance)) provenance <- list(status = "provenance_unavailable")
  .sc_project_json_check(provenance)
  if (identical(provenance$status, "not_supplied") && (length(candidates) || length(all_candidates)))
    stop("Reference is marked absent but contains candidate records.", call. = FALSE)
  if (is.null(source)) source <- .sc_run_annotation_review_source(root, state, evidence, checked)
  reference_evidence <- evidence$private$reference_evidence
  if (is.null(reference_evidence)) {
    # Existing saved-evidence callers may have candidate tables without a new
    # symbol audit. Disclose that limit instead of inventing a new computation.
    reference_evidence <- list(provenance = c(provenance, list(symbol_audit = "not_recorded")),
      per_cluster = lapply(ids, function(id) {
        saved <- Filter(function(x) identical(x$clusterId, id), all_candidates)
        if (!length(saved)) saved <- Filter(function(x) identical(x$clusterId, id), candidates)
        best <- if (length(saved)) max(vapply(saved, `[[`, numeric(1), "score")) else 0
        saved <- lapply(saved, function(x) {
          x$tiedBest <- x$score > 0 && identical(x$score, best)
          x$formula <- "Saved marker coverage; canonical symbol audit unavailable."
          x
        })
        list(clusterId = id, status = if (length(saved)) "saved_legacy_candidates" else provenance$status,
          candidates = saved, all_candidates = saved, marker_symbols = list(status = "not_recorded"))
      }))
  }
  output_columns <- list(label = target, confidence = paste0(target, "_confidence"),
                         rationale = paste0(target, "_rationale"))
  rows <- lapply(seq_along(ids), function(i) {
    id <- ids[i]
    cluster <- evidence$summary$clusters[[i]]
    cells <- input$cell_id[input$cluster == id]
    if (!is.numeric(cluster$cellCount) || length(cluster$cellCount) != 1L ||
        !is.finite(cluster$cellCount) || cluster$cellCount != length(cells))
      stop("Annotation evidence cell counts disagree with exact membership.", call. = FALSE)
    row <- checked$annotations[[i]]
    supplied <- Filter(function(marker) identical(marker$clusterId, id), markers)
    cited <- unlist(row$markers, use.names = FALSE)
    supplied_genes <- vapply(supplied, `[[`, character(1), "gene")
    cited_stats <- supplied[match(cited, supplied_genes)]
    local <- Filter(function(candidate) identical(candidate$clusterId, id), candidates)
    local_all <- Filter(function(candidate) identical(candidate$clusterId, id), all_candidates)
    reference_status <- if (identical(provenance$status, "not_supplied")) "not_supplied" else
      if (identical(provenance$status, "provenance_unavailable")) "provenance_unavailable" else
        if (!length(local) && !length(local_all)) "no_candidates" else "available"
    list(clusterId = id, cell_count = length(cells), cell_ids = cells, proposal = row,
         cited_marker_stats = cited_stats, supplied_marker_stats = supplied,
         local_reference = list(status = reference_status, candidates = local,
           all_candidates = local_all, provenance = provenance),
         expression_assessment = list(per_cell_assessed = FALSE,
           source = "supplied differential marker statistics only"),
         negative_evidence = list(assessed = FALSE,
           reason = "No independent negative-expression or counterevidence assessment was supplied."),
         parent_context = .sc_run_child_context_assessment(row$label,
           evidence$summary$child_context, evidence$private$reference_options),
         joint_evidence = .sc_run_joint_evidence(row, cluster,
           reference_evidence, source,
           historical = .sc_run_annotation_history_row(evidence$private$historical, id, cluster),
           options = evidence$private$reference_options))
  })
  parameters <- list(cluster_column = cluster_column, target_column = target,
                     output_columns = output_columns, writeback_policy = "new_columns_only")
  list(schema = "scagentkit.annotation.review.v1", input_hash = state$input_hash,
       config_hash = state$config_hash, implementation_hash = state$implementation_hash,
       evidence_hash = .sc_run_hash(evidence),
       proposal_hash = .sc_run_hash(.sc_run_annotation_review_plain(checked)),
       rules_hash = .sc_run_hash(checked), cell_scope_hash = .sc_run_hash(input),
       parameters_hash = .sc_run_hash(parameters), target_column = target,
       cluster_column = cluster_column,
       details = list(input_cells = input, cell_count = nrow(input), cluster_count = length(ids),
         output_columns = output_columns, canonical_proposal = .sc_run_annotation_review_plain(checked),
         annotations = rows, source = source,
         child_context = evidence$summary$child_context,
         parent_context_database = evidence$private$child_context,
         statistic_units = list(avgLog2FC = "saved log2 fold change",
           pct1 = "fraction detected within this cluster, from the supplied test",
           pct2 = "fraction detected outside this cluster, from the supplied test",
           pAdj = "saved adjusted p-value", candidate_score = "saved local marker-overlap score; not a calibrated probability"),
         limitations = c(
           "Confidence strings are qualitative judgments, not calibrated probabilities.",
           "Absence from a supplied top-marker list is not evidence of absent or low expression.",
           "Only supplied marker statistics and saved local-reference matches are displayed; no new expression or negative-evidence assessment is performed.",
           "Database matches and model/manual suggestions are not identity ground truth; guided suggestions depend on the database and historical imports are not new calls.",
           "Exact cell IDs and local reference labels stay in this local review snapshot.",
           "Writeback adds fresh label, confidence and rationale columns; existing annotation columns are preserved.")))
}
.sc_run_annotation_review_publish <- function(root, state, validated, evidence) {
  record <- .sc_run_annotation_review_build(root, state, validated, evidence)
  record$hash <- .sc_run_annotation_review_hash(record)
  .sc_run_put(root, state, "annotation_review", record)
}
.sc_run_annotation_review_decisions <- function(state, record) {
  Filter(function(event) event$action %in% c("approved", "rejected") &&
    identical(event$details$kind, "annotation") &&
    identical(event$details$review_hash, record$hash), state$history)
}
.sc_run_annotation_review_undos <- function(state, decisions) {
  ids <- vapply(Filter(function(event) identical(event$action, "approved"), decisions),
                function(event) event$details$decision_id, character(1))
  Filter(function(event) identical(event$action, "annotation_undone") &&
    event$details$decision_id %in% ids, state$history)
}
.sc_run_annotation_review_verify <- function(root, state) {
  if (is.null(state$files$annotation_review))
    stop("Required annotation review is absent; obtain a fresh proposal.", call. = FALSE)
  record <- .sc_run_get(root, state, "annotation_review")
  if (!identical(record$schema, "scagentkit.annotation.review.v1") ||
      !identical(record$hash, .sc_run_annotation_review_hash(record)) ||
      !identical(state$config_hash, .sc_run_hash(state$config)) ||
      !identical(state$implementation_hash, .sc_run_implementation()) ||
      !identical(record$input_hash, state$input_hash) || !identical(record$config_hash, state$config_hash) ||
      !identical(record$implementation_hash, state$implementation_hash))
    stop("Annotation review/input/configuration/implementation fingerprint changed; review is stale.", call. = FALSE)
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  historical <- is.null(state$files$annotation_validated)
  if (historical) {
    undos <- .sc_run_annotation_review_undos(state, .sc_run_annotation_review_decisions(state, record))
    if (!length(undos) || (!is.null(state$pending) && identical(state$pending$kind, "annotation")) ||
        (!is.null(state$approved) && identical(state$approved$kind, "annotation")))
      stop("Annotation validation is absent without a matching audited undo.", call. = FALSE)
    validated <- .sc_run_annotation_validate(record$details$canonical_proposal, evidence)
  } else validated <- .sc_run_get(root, state, "annotation_validated")
  current <- .sc_run_annotation_review_build(root, state, validated, evidence,
    source = if (historical) record$details$source else NULL)
  current$hash <- .sc_run_annotation_review_hash(current)
  if (!identical(record, current))
    stop("Annotation review no longer matches evidence, proposal, source or exact cell scope.", call. = FALSE)
  node <- if (!is.null(state$pending) && identical(state$pending$kind, "annotation")) state$pending else
    if (!is.null(state$approved) && identical(state$approved$kind, "annotation")) state$approved else NULL
  if (!is.null(node) && (!isTRUE(.sc_run_check_binding(state, node)) || !identical(node$proposal, validated)))
    stop("Annotation review node binding changed; review is stale.", call. = FALSE)
  record
}
.sc_run_annotation_review_decision_details <- function(root, state, reviewer, reason) {
  .sc_project_string(reviewer, "reviewer"); .sc_project_string(reason, "reason")
  if (is.null(state$pending) || !identical(state$pending$kind, "annotation"))
    stop("No current annotation proposal awaits a decision.", call. = FALSE)
  record <- .sc_run_annotation_review_verify(root, state)
  list(proposal_hash = state$pending$hash, reviewer = reviewer, reason = reason, kind = "annotation",
       evidence_hash = state$pending$evidence_hash, input_hash = state$input_hash,
       config_hash = state$config_hash, implementation_hash = state$implementation_hash,
       decision_id = paste0("decision-", state$revision + 1L),
       review_hash = record$hash, parameters_hash = record$parameters_hash,
       rules_hash = record$rules_hash, cell_scope_hash = record$cell_scope_hash,
       target_column = record$target_column, review_path = state$files$annotation_review$path,
       revision_reviewed = state$revision)
}
.sc_run_annotation_review_view <- function(root, state) {
  if (is.null(state$files$annotation_review)) return(NULL)
  record <- .sc_run_annotation_review_verify(root, state)
  decisions <- .sc_run_annotation_review_decisions(state, record)
  undos <- .sc_run_annotation_review_undos(state, decisions)
  record$lifecycle <- list(status = state$status, stage = state$stage,
    current_proposal = !is.null(state$pending) && identical(state$pending$kind, "annotation"),
    executed = "annotation_apply" %in% state$completed && !length(undos),
    undone = length(undos) > 0L, decisions = decisions, undo_events = undos)
  record
}
