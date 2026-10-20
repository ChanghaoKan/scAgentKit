# Read-only display projection of committed state. Never an approval source.
.sc_run_react_audit <- function(root, state = NULL) {
  if (is.null(state)) state <- .sc_run_load(root)
  if (is.null(state$files$annotation_react_run)) return(NULL)
  run <- .sc_run_get(root, state, "annotation_react_run")
  active <- if (!is.null(state$files$annotation_react_citations))
    .sc_run_get(root, state, "annotation_react_citations") else NULL
  if (!is.null(active) && !identical(active$run_id, run$id))
    stop("Active citations belong to a different ReAct run.", call. = FALSE)
  preview <- function(value, limit = 4096L) {
    text <- .sc_project_json(value)
    # Limit Unicode characters as well as bytes; no truncation of authoritative
    # evidence or native provider history occurs in the saved checkpoint.
    truncated <- nchar(text, type = "bytes") > limit
    if (truncated) {
      text <- substr(text, 1L, limit)
      while (nchar(text, type = "bytes") > limit)
        text <- substr(text, 1L, nchar(text) - 1L)
    }
    list(text = text, truncated = truncated)
  }
  total <- function(turns, field) {
    values <- lapply(turns, function(x) x$usage[[field]])
    valid <- vapply(values, function(x) is.numeric(x) && length(x) == 1L &&
      is.finite(x) && x >= 0, logical(1))
    list(known = sum(unlist(values[valid], use.names = FALSE)),
      unknown_turns = sum(!valid))
  }
  clusters <- lapply(names(run$traces), function(id) {
    key <- paste0("react_cluster_", .sc_run_hash(id))
    if (!identical(state$files[[key]], run$traces[[id]]))
      stop("Trace projection does not match its committed state record.", call. = FALSE)
    trace <- .sc_run_get(root, state, key)
    if (!identical(trace$cluster_id, id) || !identical(trace$session_id, run$session$id))
      stop("Trace projection has a different session or cluster.", call. = FALSE)
    turns <- lapply(trace$turns, function(turn) turn[intersect(names(turn),
      c("request_hash", "response_hash", "status", "usage", "cost_usd", "cost_state", "delivery"))])
    tools <- lapply(seq_along(trace$tools), function(i) {
      call <- trace$tools[[i]]
      list(sequence = i, source = call$source, tool = call$tool,
        model_turn = call$model_turn,
        arguments = preview(call$arguments), success = isTRUE(call$response$ok),
        result_hash = .sc_run_hash(call$response),
        evidence_hash = call$response$result_hash,
        preview = preview(call$response),
        evidence_status = if (identical(call$tool, "gene_expression")) "untested_background" else
          if (identical(call$tool, "cluster_markers") && isTRUE(call$response$ok))
            "saved_statistical_markers" else "context_or_reference",
        scientific_approval = FALSE)
    })
    list(cluster_id = id, status = trace$status, fallback_reason = trace$fallback_reason,
      tool_calls = length(tools), model_turns = length(turns),
      tools = tools, turns = turns, conclusion = trace$result$row,
      citations = trace$result$citations,
      active_citations = if (is.null(active)) list() else
        Filter(function(x) identical(x$cluster_id, id), active$citations),
      risk_flags = trace$result$risk_flags,
      trace_sha256 = state$files[[key]]$sha256,
      scientific_approval = FALSE)
  })
  turns <- unlist(lapply(clusters, `[[`, "turns"), recursive = FALSE)
  known_cost <- vapply(turns, function(x) is.numeric(x$cost_usd) &&
    length(x$cost_usd) == 1L && is.finite(x$cost_usd) && x$cost_usd >= 0, logical(1))
  list(schema = "scagentkit.react-audit.v1", run_id = run$id,
    session_id = run$session$id, status = run$status,
    configuration = run$binding$policy, prompt_hash = run$binding$prompt_hash,
    clusters = clusters,
    summary = list(target_clusters = length(run$targets),
      completed_clusters = sum(vapply(clusters, function(x) identical(x$status, "completed"), logical(1))),
      tool_calls = sum(vapply(clusters, `[[`, integer(1), "tool_calls")),
      model_turns = length(turns),
      input_tokens = total(turns, "input_tokens"), output_tokens = total(turns, "output_tokens"),
      known_cost_usd = sum(vapply(turns[known_cost], `[[`, numeric(1), "cost_usd")),
      unknown_cost_turns = sum(!known_cost),
      fallbacks = lapply(Filter(function(x) !is.null(x$fallback_reason), clusters),
        function(x) x[c("cluster_id", "fallback_reason")])),
    boundary = "Saved evidence and draft rationale, not hidden model reasoning. Unknown usage/cost is not zero. This projection cannot approve or alter scientific results.")
}

.sc_run_react_export <- function(root, state) {
  audit <- .sc_run_react_audit(root, state)
  if (is.null(audit)) return(list())
  directory <- file.path(root, "annotation", "react")
  if (dir.exists(directory) && nzchar(Sys.readlink(directory)))
    stop("Trace export directory must not be a symbolic link.", call. = FALSE)
  if (dir.exists(file.path(root, "annotation")) && nzchar(Sys.readlink(file.path(root, "annotation"))))
    stop("Annotation export directory must not be a symbolic link.", call. = FALSE)
  records <- lapply(audit$clusters, function(cluster) {
    id <- cluster$cluster_id
    # Reserve the index and encoded namespace, including case-insensitive disks.
    filename <- if (grepl("^[0-9]{1,80}$", id)) id else
      paste0("cluster-", .sc_run_hash(id))
    relative <- file.path("annotation", "react", paste0(filename, ".json"))
    value <- list(schema = "scagentkit.react-cluster-export.v1",
      run_id = audit$run_id, session_id = audit$session_id,
      authority = "Committed state checkpoint; this JSON is a display projection.",
      cluster = cluster)
    .sc_run_atomic(value, file.path(root, relative), json = TRUE)
    list(cluster_id = id, path = relative,
      sha256 = .sc_project_sha_file(file.path(root, relative)),
      trace_sha256 = cluster$trace_sha256)
  })
  .sc_run_atomic(list(schema = "scagentkit.react-export-index.v1", run_id = audit$run_id,
    summary = audit$summary, clusters = records, authority = "state.rds"),
    file.path(directory, "index.json"), json = TRUE)
  records
}
