.sc_run_react_fields <- function(value, fields) {
  if (!is.list(value) || is.object(value) || is.null(names(value)) ||
      anyDuplicated(names(value)) || !setequal(names(value), fields))
    .sc_run_react_error("invalid_draft", "The draft contains missing or unsupported fields.")
  invisible(TRUE)
}

.sc_run_react_baseline <- function(value, evidence) {
  .sc_run_react_fields(value, c("schema", "proposal", "risk_flags"))
  if (!identical(value$schema, "scagentkit.annotation-draft.v1"))
    .sc_run_react_error("invalid_draft", "The baseline needs its versioned risk envelope.")
  proposal <- .sc_run_annotation_response_validate(value$proposal, evidence)
  ids <- vapply(proposal$annotations, `[[`, character(1), "clusterId")
  if (!is.list(value$risk_flags) || !is.null(names(value$risk_flags)) ||
      length(value$risk_flags) != length(ids))
    .sc_run_react_error("invalid_draft", "Every baseline cluster needs a risk record.")
  seen <- character()
  for (record in value$risk_flags) {
    cluster <- record$cluster_id
    if (!is.character(cluster) || length(cluster) != 1L || is.na(cluster) ||
        !cluster %in% ids || cluster %in% seen)
      .sc_run_react_error("invalid_draft", "Duplicate or foreign baseline risk scope.")
    pool <- Filter(function(x) identical(x$clusterId, cluster), evidence$summary$clusters)[[1L]]$markers
    .sc_run_react_risks(record, cluster, paste0("pool:", vapply(pool, `[[`, character(1), "gene")))
    seen <- c(seen, cluster)
  }
  list(proposal = list(schema = proposal$schema, annotations = proposal$annotations),
    risk_flags = value$risk_flags[match(ids, seen)])
}

.sc_run_react_record_baseline <- function(root, state, answer) {
  parsed <- .sc_run_provider_parse(answer$raw)
  if (!identical(parsed$status, "ok"))
    .sc_run_react_error("invalid_binding", "The validated baseline response is unavailable.")
  checked <- .sc_run_react_baseline(parsed$content, .sc_run_get(root, state, "annotation_evidence"))
  if (!identical(checked$proposal, answer$content))
    .sc_run_react_error("invalid_binding", "Baseline projection differs from its validated response.")
  .sc_run_put(root, state, "annotation_baseline_risks", list(schema = "scagentkit.baseline-risks.v1",
    proposal_hash = .sc_run_hash(answer$content), request_hash = answer$request_hash,
    prompt = .sc_run_react_prompt("annotation-baseline-risk.v1")[c("version", "hash")],
    evidence = state$files$annotation_evidence, risk_flags = checked$risk_flags))
}

.sc_run_react_mock_turn <- function(messages, ...) {
  payload <- jsonlite::fromJSON(messages[[2L]]$content, simplifyVector = FALSE)
  cluster <- payload$cluster_id
  first <- !any(vapply(messages, function(x) identical(x$role, "tool"), logical(1)))
  if (first) return(list(schema_version = "agentomics.turn.v1", finish_reason = "tool_calls",
    message = list(role = "assistant", content = NULL, tool_calls = list(
      list(id = paste0("mock_", cluster), type = "function", `function` = list(
        name = "cluster_markers", arguments = .sc_project_json(list(cluster_id = cluster, n = 5L)))))),
    usage = list(input_tokens = 0, output_tokens = 0), raw_usage = list()))
  risks <- .sc_run_react_unassessed_risks(cluster)
  risks$fields <- lapply(risks$fields, function(x) { x$source <- "model"; x })
  final <- list(schema = "scagentkit.react-draft.v1",
    proposal = list(schema = "scagentkit.annotation.v1", annotations = list(
      list(clusterId = cluster, label = "Unknown", confidence = "low", markers = list(),
        rationale = "MOCK software control: tool:1 inspected; biological identity remains unassessed."))),
    citations = list(), risk_flags = risks)
  list(schema_version = "agentomics.turn.v1", finish_reason = "stop",
    message = list(role = "assistant", content = .sc_project_json(final)),
    usage = list(input_tokens = 0, output_tokens = 0), raw_usage = list())
}

.sc_run_react_risk_values <- function() list(
  doublet_risk = c("not_assessed", "not_detected", "suspected"),
  batch_status = c("not_applicable", "insufficient_evidence", "fully_confounded",
    "no_effect_detected", "effect_detected_design_supported"),
  qc_celltype_concern = c("not_assessed", "not_detected", "suspected"),
  cycle_concern = c("not_assessed", "not_detected", "suspected"),
  ambient_suspected = c("not_assessed", "not_detected", "suspected"))

.sc_run_react_unassessed_risks <- function(cluster) {
  list(schema = "risk_flags.v1", stage = "annotation",
    cluster_id = cluster, fields = lapply(names(.sc_run_react_risk_values()), function(name) list(
      name = name, value = if (name == "batch_status") "insufficient_evidence" else "not_assessed",
      assessment_status = "not_assessed", source = "unassessed", evidence_ids = list())))
}

.sc_run_react_risks <- function(value, cluster, evidence_ids) {
  choices <- .sc_run_react_risk_values()
  .sc_run_react_fields(value, c("schema", "stage", "cluster_id", "fields"))
  if (!identical(value$schema, "risk_flags.v1") || !identical(value$stage, "annotation") ||
      !identical(value$cluster_id, cluster))
    .sc_run_react_error("invalid_draft", "Risk records must match this annotation cluster.")
  if (!is.list(value$fields) || !is.null(names(value$fields)) || length(value$fields) != length(choices))
    .sc_run_react_error("invalid_draft", "All five structured risk fields are required.")
  seen <- character()
  for (field in value$fields) {
    .sc_run_react_fields(field, c("name", "value", "assessment_status", "source", "evidence_ids"))
    scalar <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
    if (!scalar(field$name) || !field$name %in% names(choices) || field$name %in% seen ||
        !scalar(field$value) || !field$value %in% choices[[field$name]] ||
        !scalar(field$assessment_status) ||
        !field$assessment_status %in% c("assessed", "not_assessed", "not_applicable") ||
        !identical(field$source, "model") || !is.list(field$evidence_ids) ||
        !is.null(names(field$evidence_ids)) ||
        !all(vapply(field$evidence_ids, scalar, logical(1))))
      .sc_run_react_error("invalid_draft", "A structured risk enumeration is invalid.")
    ids <- unlist(field$evidence_ids, use.names = FALSE)
    if (anyDuplicated(ids) || any(!ids %in% evidence_ids))
      .sc_run_react_error("invalid_draft", "Risk evidence IDs must refer to current pool or tool evidence.")
    batch <- field$name == "batch_status"
    compatible <- switch(field$assessment_status,
      not_assessed = field$value == if (batch) "insufficient_evidence" else "not_assessed",
      not_applicable = field$value == if (batch) "not_applicable" else "not_assessed",
      assessed = if (batch) field$value != "not_applicable" else field$value != "not_assessed")
    if (!compatible || (field$assessment_status == "assessed" && !length(ids)))
      .sc_run_react_error("invalid_draft", "Risk value, assessment status and evidence do not agree.")
    seen <- c(seen, field$name)
  }
  value
}

# The caller supplies the current, state-bound trace, never model-reported
# statistics. Only tested cluster-vs-rest marker results admit new citations.
.sc_run_react_citations <- function(citations, row, pool, trace, session) {
  if (!is.list(citations) || !is.null(names(citations)))
    .sc_run_react_error("invalid_draft", "Citations must be an array.")
  verified <- list()
  for (citation in citations) {
    .sc_run_react_fields(citation, c("cluster_id", "gene", "source"))
    if (!identical(citation$cluster_id, row$clusterId) ||
        !is.character(citation$gene) || length(citation$gene) != 1L || is.na(citation$gene) ||
        !is.character(citation$source) || length(citation$source) != 1L || is.na(citation$source))
      .sc_run_react_error("invalid_draft", "Invalid citation scope.")
    gene <- citation$gene
    if (identical(citation$source, "pool")) {
      match <- Filter(function(x) identical(x$gene, gene), pool)
      if (length(match) != 1L)
        .sc_run_react_error("invalid_draft", "The cited gene is not in this cluster's original pool.")
      stats <- match[[1L]]
    } else {
      if (!grepl("^tool:[1-9][0-9]*$", citation$source) ||
          !identical(trace$session_id, session$id) || !identical(trace$cluster_id, row$clusterId))
        .sc_run_react_error("invalid_draft", "The citation does not belong to the current cluster session.")
      index <- as.integer(sub("^tool:", "", citation$source))
      if (is.na(index) || index > length(trace$tools))
        .sc_run_react_error("invalid_draft", "The cited tool call does not exist.")
      call <- trace$tools[[index]]; answer <- call$response
      if (!identical(answer$tool, "cluster_markers") || !isTRUE(answer$ok) ||
          !identical(answer$input_hash, session$input_hash) ||
          !identical(answer$result_hash, .sc_run_hash(answer$result)) ||
          !identical(answer$arguments$cluster_id, row$clusterId) ||
          !identical(answer$result$cluster_id, row$clusterId) ||
          !identical(answer$result$source, "saved_FindAllMarkers"))
        .sc_run_react_error("invalid_draft", "Only this cluster's tested marker tool results support citations.")
      found <- Filter(function(x) identical(x$gene, gene), answer$result$markers)
      if (length(found) != 1L)
        .sc_run_react_error("invalid_draft", "The cited gene was not returned by this tool call.")
      m <- found[[1L]]
      scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
      if (!all(vapply(m[c("padj", "avg_log2FC", "pct1", "pct2")], scalar, logical(1))) ||
          !identical(m$excluded, FALSE) || m$padj >= .05 ||
          m$avg_log2FC <= 0 || m$pct1 <= m$pct2)
        .sc_run_react_error("invalid_draft", "The tool citation fails the saved statistical eligibility rule.")
      stats <- list(gene = gene, avgLog2FC = m$avg_log2FC, pct1 = m$pct1,
        pct2 = m$pct2, pAdj = m$padj)
    }
    verified <- append(verified, list(c(citation, list(statistics = stats))))
  }
  genes <- vapply(verified, `[[`, character(1), "gene")
  if (anyDuplicated(genes) || !setequal(genes, unlist(row$markers, use.names = FALSE)))
    .sc_run_react_error("invalid_draft", "Every cited marker needs exactly one verified source.")
  verified
}

.sc_run_react_validate <- function(value, baseline, evidence, cluster, trace, session) {
  .sc_run_react_fields(value, c("schema", "proposal", "citations", "risk_flags"))
  if (!identical(value$schema, "scagentkit.react-draft.v1"))
    .sc_run_react_error("invalid_draft", "Unsupported ReAct draft envelope.")
  .sc_run_react_fields(value$proposal, c("schema", "annotations"))
  if (!identical(value$proposal$schema, "scagentkit.annotation.v1") ||
      !is.list(value$proposal$annotations) || !is.null(names(value$proposal$annotations)) ||
      length(value$proposal$annotations) != 1L ||
      !identical(value$proposal$annotations[[1L]]$clusterId, cluster))
    .sc_run_react_error("invalid_draft", "Return exactly the current cluster in the annotation.v1 proposal.")
  row <- value$proposal$annotations[[1L]]
  ids <- vapply(evidence$summary$clusters, `[[`, character(1), "clusterId")
  index <- match(cluster, ids); pool <- evidence$summary$clusters[[index]]$markers
  verified <- .sc_run_react_citations(value$citations, row, pool, trace, session)
  augmented <- evidence
  extra <- Filter(function(x) !identical(x$source, "pool"), verified)
  for (citation in extra) if (!citation$gene %in% vapply(pool, `[[`, character(1), "gene"))
    augmented$summary$clusters[[index]]$markers <- append(
      augmented$summary$clusters[[index]]$markers, list(citation$statistics))
  proposal <- baseline
  where <- match(cluster, vapply(proposal$annotations, `[[`, character(1), "clusterId"))
  proposal$annotations[[where]] <- row
  validated <- .sc_run_annotation_response_validate(proposal, augmented)
  evidence_ids <- c(paste0("pool:", vapply(pool, `[[`, character(1), "gene")),
    if (length(trace$tools)) paste0("tool:", seq_along(trace$tools)))
  risks <- .sc_run_react_risks(value$risk_flags, cluster, evidence_ids)
  list(row = validated$annotations[[where]], citations = verified, risk_flags = risks)
}

.sc_run_react_reference_view <- function(evidence, state) {
  if (is.null(state$config$react) || isTRUE(state$config$react$act_enabled)) return(evidence)
  evidence$summary$reference_candidates <- NULL
  evidence$summary$reference_comparison <- NULL
  evidence$summary$reference_mode <- "independent"
  evidence$private$candidates <- NULL
  evidence$private$candidates_all <- NULL
  provenance <- list(status = "unassessed", reason = "ACT disabled by recorded configuration")
  evidence$private$reference_provenance <- provenance
  evidence$private$reference_evidence <- list(provenance = provenance,
    per_cluster = lapply(evidence$summary$clusters, function(x)
      list(clusterId = x$clusterId, status = "unassessed", candidates = list(),
        all_candidates = list(), marker_symbols = list(status = "unassessed"))))
  evidence
}

# Only previously verified (cluster, gene) pairs enter review. Editing a label,
# confidence or reason preserves them; deleting a citation removes its authority.
.sc_run_react_review_evidence <- function(root, state, evidence = NULL) {
  if (is.null(evidence)) evidence <- .sc_run_get(root, state, "annotation_evidence")
  evidence <- .sc_run_react_reference_view(evidence, state)
  if (is.null(state$files$annotation_react_citations)) return(evidence)
  active <- .sc_run_get(root, state, "annotation_react_citations")
  run <- .sc_run_get(root, state, "annotation_react_run")
  if (!identical(run$id, active$run_id) ||
      !identical(run$binding$evidence, state$files$annotation_evidence) ||
      !identical(run$binding$files, state$files[names(run$binding$files)]) ||
      !identical(run$binding$config_hash, state$config_hash))
    .sc_run_react_error("invalid_binding", "Annotation citations no longer match their saved evidence.")
  ids <- vapply(evidence$summary$clusters, `[[`, character(1), "clusterId")
  for (cluster in ids) {
    citations <- Filter(function(x) identical(x$cluster_id, cluster), active$citations)
    if (!length(citations)) next
    trace <- if (is.null(run$traces[[cluster]])) NULL else
      readRDS(file.path(root, run$traces[[cluster]]$path))
    index <- match(cluster, ids); pool <- evidence$summary$clusters[[index]]$markers
    row <- list(clusterId = cluster, markers = lapply(citations, `[[`, "gene"))
    supplied <- lapply(citations, function(x) x[c("cluster_id", "gene", "source")])
    verified <- .sc_run_react_citations(supplied, row, pool, trace, run$session)
    for (citation in verified) if (!citation$gene %in% vapply(pool, `[[`, character(1), "gene")) {
      marker <- citation$statistics
      marker$clusterId <- cluster; marker$source <- citation$source
      evidence$summary$clusters[[index]]$markers <- append(evidence$summary$clusters[[index]]$markers, list(marker))
    }
  }
  evidence
}

.sc_run_react_retain_citations <- function(root, state, proposal) {
  if (is.null(state$files$annotation_react_citations)) return(state)
  active <- .sc_run_get(root, state, "annotation_react_citations")
  keep <- Filter(function(citation) {
    row <- Filter(function(x) identical(x$clusterId, citation$cluster_id), proposal$annotations)
    length(row) == 1L && citation$gene %in% unlist(row[[1L]]$markers, use.names = FALSE)
  }, active$citations)
  if (identical(keep, active$citations)) return(state)
  active$citations <- keep
  .sc_run_put(root, state, "annotation_react_citations", active)
}
