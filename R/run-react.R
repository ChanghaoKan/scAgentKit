.sc_run_react_prompt <- function(version = "annotation-react.v1") {
  if (!version %in% c("annotation-react.v1", "annotation-baseline-risk.v1"))
    stop("Unsupported annotation prompt version.", call. = FALSE)
  path <- system.file("prompts", paste0(version, ".txt"), package = "scAgentKit")
  if (!nzchar(path)) stop("The versioned annotation prompt is unavailable.", call. = FALSE)
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(version = version, hash = .sc_run_hash(text), text = text)
}

.sc_run_react_targets <- function(baseline, evidence, policy, options) {
  if (policy$mode == "off") return(character())
  ids <- vapply(baseline$annotations, `[[`, character(1), "clusterId")
  if (policy$mode == "all") return(sort(ids, method = "radix"))
  selected <- vapply(baseline$annotations, function(row) row$confidence == "low" ||
    tolower(trimws(row$label)) %in% c("unknown", "unannotated"), logical(1))
  conflicts <- if (policy$act_enabled) .sc_run_annotation_candidate_comparison(baseline, evidence, options) else list()
  conflict_ids <- vapply(Filter(function(x) x$status %in%
    c("unresolved_label_difference", "lineage_disagreement") || identical(x$reason, "best_label_tie"),
    conflicts), `[[`, character(1), "clusterId")
  sort(unique(c(ids[selected], conflict_ids)), method = "radix")
}

.sc_run_react_baseline_risk <- function(run, cluster) {
  found <- Filter(function(x) identical(x$cluster_id, cluster), run$baseline_risks$risk_flags)
  if (length(found) == 1L) found[[1L]] else
    .sc_run_react_risks(NULL, cluster, character(), legacy = TRUE)
}

.sc_run_react_fallback_all <- function(root, run, reason) {
  for (cluster in setdiff(run$targets, run$completed)) {
    row <- Filter(function(x) identical(x$clusterId, cluster), run$baseline$annotations)[[1L]]
    trace <- list(schema = "scagentkit.react-trace.v1", session_id = run$session$id,
      cluster_id = cluster, baseline = row, status = "fallback", fallback_reason = reason,
      tools = list(), turns = list(), result = list(row = row,
        citations = Filter(function(x) identical(x$cluster_id, cluster), run$baseline_citations),
        risk_flags = .sc_run_react_baseline_risk(run, cluster)))
    run$completed <- c(run$completed, cluster)
    run <- .sc_run_react_save(root, run, trace, action = "react_cluster_completed")
  }
  run$status <- "completed"; run$fallback_reason <- reason
  .sc_run_react_save(root, run, action = "react_completed")
}

.sc_run_react_save <- function(root, run, trace = NULL, action = "react_progress") {
  state <- .sc_run_load(root, verify = FALSE)
  if (!is.null(trace)) {
    key <- paste0("react_cluster_", .sc_run_hash(trace$cluster_id))
    state <- .sc_run_put(root, state, key, trace)
    run$traces[[trace$cluster_id]] <- state$files[[key]]
  }
  if (identical(action, "react_completed")) {
    citations <- unlist(lapply(run$proposal$annotations, function(row) {
      record <- run$traces[[row$clusterId]]
      if (!is.null(record)) readRDS(file.path(root, record$path))$result$citations else
        Filter(function(x) identical(x$cluster_id, row$clusterId), run$baseline_citations)
    }), recursive = FALSE)
    if (is.null(citations)) citations <- list()
    state <- .sc_run_put(root, state, "annotation_react_citations",
      list(schema = "scagentkit.react-citations.v1", run_id = run$id, citations = unname(citations)))
  }
  state <- .sc_run_put(root, state, "annotation_react_run", run)
  state <- .sc_run_event(state, action, list(run_id = run$id, session_id = run$session$id,
    cluster_id = trace$cluster_id, cluster_status = trace$status,
    fallback_reason = trace$fallback_reason, trace = if (is.null(trace)) NULL else state$files[[key]],
    scientific_approval = FALSE))
  .sc_run_save(root, state)
  run
}

# Internal coordinator entry. Baseline is already schema-validated; this never
# approves a proposal. Completed clusters and exact pending requests are durable.
.sc_run_react_refine <- function(root, baseline, turn_fn = NULL, project_lock_owner = NULL) {
  root <- .sc_run_root(root)
  if (is.null(project_lock_owner)) {
    project_lock_owner <- .sc_run_lock(root)
    on.exit(.sc_run_release(root, project_lock_owner), add = TRUE)
  }
  state <- .sc_run_load(root)
  if (is.null(turn_fn) && identical(state$config$provider$name, "mock"))
    turn_fn <- .sc_run_react_mock_turn
  policy <- .sc_run_turn_policy(state$config$react)
  evidence <- .sc_run_get(root, state, "annotation_evidence")
  if (is.null(baseline)) return(list(status = "baseline_unavailable", proposal = NULL,
    reason = "No validated baseline is available; continue with manual annotation."))
  checked <- .sc_run_annotation_response_validate(baseline, evidence)
  baseline <- list(schema = checked$schema, annotations = checked$annotations)
  prompt <- .sc_run_react_prompt()
  run_binding <- list(baseline_hash = .sc_run_hash(baseline), evidence = state$files$annotation_evidence,
    input_hash = state$input_hash,
    files = state$files[intersect(c("input", "analysis", "markers", "reference",
      "doublet_diagnostics", "cycle_diagnostics"), names(state$files))],
    config_hash = state$config_hash, implementation_hash = state$implementation_hash,
    policy = policy, prompt_hash = prompt$hash)
  id <- .sc_run_hash(run_binding)
  run <- if (!is.null(state$files$annotation_react_run))
    .sc_run_get(root, state, "annotation_react_run") else NULL
  if (!is.null(run) && !identical(run$id, id))
    .sc_run_react_error("invalid_binding", "A different baseline or configuration requires a new reviewed annotation scope.")
  if (!is.null(run) && identical(run$status, "completed")) return(run)
  if (is.null(run)) {
    run <- list(schema = "scagentkit.react-run.v1", id = id, binding = run_binding,
      baseline = baseline, proposal = baseline, session = NULL, status = "running",
      baseline_risks = if (!is.null(state$files$annotation_baseline_risks))
        .sc_run_get(root, state, "annotation_baseline_risks") else NULL,
      targets = .sc_run_react_targets(baseline, evidence, policy, state$config$reference_review),
      traces = list(), completed = character(), tool_calls = 0L)
    run$baseline_citations <- unlist(lapply(baseline$annotations, function(row) {
      pool <- Filter(function(x) identical(x$clusterId, row$clusterId), evidence$summary$clusters)[[1L]]$markers
      supplied <- lapply(row$markers, function(gene)
        list(cluster_id = row$clusterId, gene = gene, source = "pool"))
      .sc_run_react_citations(supplied, row, pool, NULL, NULL)
    }), recursive = FALSE)
    if (is.null(run$baseline_citations)) run$baseline_citations <- list()
    run <- .sc_run_react_save(root, run, action = "react_baseline_saved")
  }
  if (!length(run$targets)) {
    run$status <- "completed"
    return(.sc_run_react_save(root, run, action = "react_completed"))
  }
  supported <- tryCatch({ .sc_run_turn_factory(state$config$provider); TRUE },
    error = function(e) FALSE)
  if (!supported) {
    return(.sc_run_react_fallback_all(root, run, "unsupported_provider"))
  }
  context <- .sc_run_react_context(root)
  runtime <- tryCatch(.sc_run_react_worker_start(context, timeout = policy$tool_timeout_seconds),
    error = function(e) {
      if (inherits(e, "sc_run_react_error") && e$code %in% c("invalid_binding", "invalid_evidence")) stop(e)
      if (is.null(e$code)) e$code <- "worker_unavailable"
      e
    })
  if (inherits(runtime, "error")) return(.sc_run_react_fallback_all(root, run, runtime$code))
  on.exit(.sc_run_react_worker_close(runtime), add = TRUE)
  if (is.null(run$session)) {
    run$session <- .sc_run_turn_session(root, prompt$version, prompt$hash, policy,
      project_lock_owner = project_lock_owner, react_runtime = runtime)
    run <- .sc_run_react_save(root, run, action = "react_started")
  }
  session <- run$session
  for (cluster in setdiff(run$targets, run$completed)) {
    trace <- if (!is.null(run$traces[[cluster]])) readRDS(file.path(root, run$traces[[cluster]]$path)) else NULL
    if (is.null(trace)) {
      row <- Filter(function(x) identical(x$clusterId, cluster), baseline$annotations)[[1L]]
      pool <- Filter(function(x) identical(x$clusterId, cluster), evidence$summary$clusters)[[1L]]
      payload <- list(cluster_id = cluster, context = state$config$context,
        baseline = row, pool = pool, reference_mode = if (policy$act_enabled) "available_via_tool" else "disabled")
      trace <- list(schema = "scagentkit.react-trace.v1", session_id = session$id,
        input_hash = session$input_hash, cluster_id = cluster, baseline = row,
        status = "running", deadline = as.numeric(Sys.time()) + policy$cluster_timeout_seconds,
        messages = list(list(role = "system", content = prompt$text),
          list(role = "user", content = .sc_project_json(payload))),
        tools = list(), turns = list(), pending_request = NULL, pending_calls = list(), fallback_reason = NULL)
      run <- .sc_run_react_save(root, run, trace)
    }
    repeat {
      .sc_run_react_worker_check(runtime)
      remaining <- trace$deadline - as.numeric(Sys.time())
      if (remaining <= .001) { trace$fallback_reason <- "cluster_timeout"; break }
      if (!length(trace$pending_calls)) {
      if (is.null(trace$pending_request)) {
        ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
        prior <- Filter(function(x) identical(x$session_id, session$id), ledger$entries)
        if (length(prior) >= policy$max_steps || length(trace$turns) >= policy$max_steps_per_cluster) {
          trace$fallback_reason <- "step_limit"; break
        }
        last <- if (length(prior)) tail(prior, 1L)[[1L]] else NULL
        previous <- if (!is.null(last$turn_response_hash)) last$turn_response_hash else last$turn_outcome_hash
        request <- .sc_run_turn_request(session, trace$messages, cluster, length(prior) + 1L, previous)
        request$timeout_seconds <- remaining
        request$deadline <- trace$deadline
        request$approved_payload_hash <- .sc_run_request_hash(request, state$config$provider)
        trace$pending_request <- request
        run <- .sc_run_react_save(root, run, trace)
      }
      answer <- tryCatch(.sc_run_call(root, trace$pending_request, state$config$provider, turn_fn,
        budget = state$config$budget, allow_external = isTRUE(state$config$review$allow_external),
        project_lock_owner = project_lock_owner, react_runtime = runtime),
        sc_run_turn_error = function(e) {
          if (e$code %in% c("invalid_session", "invalid_receipt")) stop(e)
          list(status = e$code, delivery = "not_sent")
        })
      if (identical(answer$status, "awaiting_external_approval")) {
        run$status <- "awaiting_external_approval"
        return(.sc_run_react_save(root, run, trace, action = "react_transfer_required"))
      }
      trace$turns <- append(trace$turns, list(list(request_hash = answer$request_hash,
        response_hash = answer$turn_response_hash, status = answer$status,
        usage = answer$usage, raw_usage = answer$raw_usage, cost_usd = answer$cost_usd,
        cost_state = answer$cost_state, delivery = answer$delivery)))
      trace$pending_request <- NULL
      if (!identical(answer$status, "ok")) {
        trace$fallback_reason <- if (identical(answer$provider_error_code, "cluster_timeout"))
          "cluster_timeout" else answer$status
        break
      }
      if (as.numeric(Sys.time()) > trace$deadline) { trace$fallback_reason <- "cluster_timeout"; break }
      native <- identical(session$capability_profile$native_protocol, "xai.responses.v1")
      trace$messages <- append(trace$messages, if (native) answer$turn_response$protocol$output else
        list(answer$turn_response$message))
      calls <- answer$content$tool_calls
      if (!length(calls)) {
        parsed <- tryCatch(jsonlite::fromJSON(answer$content$content, simplifyVector = FALSE), error = identity)
        valid <- tryCatch(.sc_run_react_validate(parsed, baseline, evidence, cluster, trace, session), error = identity)
        if (inherits(valid, "error")) { trace$fallback_reason <- "invalid_draft"; break }
        trace$result <- valid; trace$status <- "completed"
        break
      }
      trace$pending_calls <- calls
      run <- .sc_run_react_save(root, run, trace)
      } else calls <- trace$pending_calls
      for (call in calls) {
        if (length(trace$tools) >= policy$max_steps_per_cluster || run$tool_calls >= policy$max_steps) {
          trace$fallback_reason <- "step_limit"; break
        }
        remaining <- trace$deadline - as.numeric(Sys.time())
        if (remaining <= .001) { trace$fallback_reason <- "cluster_timeout"; break }
        arguments <- tryCatch(jsonlite::fromJSON(call$`function`$arguments, simplifyVector = FALSE),
          error = function(e) NULL)
        enabled <- call$`function`$name %in% unlist(policy$tools, use.names = FALSE)
        result <- if (enabled) .sc_run_react_worker_call(runtime, call$`function`$name,
          arguments, timeout = min(policy$tool_timeout_seconds, remaining)) else
          list(ok = FALSE, error = list(code = "disabled_or_unknown_tool",
            message = "The requested tool is not enabled in this session."))
        number <- length(trace$tools) + 1L
        trace$tools <- append(trace$tools, list(list(call_id = call$id, source = paste0("tool:", number),
          tool = call$`function`$name, arguments = arguments, response = result)))
        run$tool_calls <- run$tool_calls + 1L
        content <- .sc_project_json(list(source = paste0("tool:", number), evidence = result))
        item <- if (identical(session$capability_profile$native_protocol, "xai.responses.v1"))
          list(type = "function_call_output", call_id = call$id, output = content) else
          list(role = "tool", tool_call_id = call$id, content = content)
        trace$messages <- append(trace$messages, list(item))
        trace$pending_calls <- trace$pending_calls[-1L]
        run <- .sc_run_react_save(root, run, trace)
        if (identical(result$error$code, "timeout")) { trace$fallback_reason <- "tool_timeout"; break }
      }
      if (!is.null(trace$fallback_reason)) break
      run <- .sc_run_react_save(root, run, trace)
      .sc_run_crash("react:turn")
    }
    if (!is.null(trace$fallback_reason)) {
      trace$status <- "fallback"; trace$result <- list(row = trace$baseline,
        citations = Filter(function(x) identical(x$cluster_id, cluster), run$baseline_citations),
        risk_flags = .sc_run_react_baseline_risk(run, cluster))
    }
    .sc_run_react_worker_check(runtime, final = TRUE)
    where <- match(cluster, vapply(run$proposal$annotations, `[[`, character(1), "clusterId"))
    run$proposal$annotations[[where]] <- trace$result$row
    run$completed <- c(run$completed, cluster)
    run <- .sc_run_react_save(root, run, trace, action = "react_cluster_completed")
    .sc_run_crash("react:cluster")
    if (!runtime$process$is_alive() && length(setdiff(run$targets, run$completed))) {
      runtime <- tryCatch(.sc_run_react_worker_start(context, timeout = policy$tool_timeout_seconds),
        error = function(e) {
          if (inherits(e, "sc_run_react_error") && e$code %in% c("invalid_binding", "invalid_evidence")) stop(e)
          if (is.null(e$code)) e$code <- "worker_unavailable"
          e
        })
      if (inherits(runtime, "error")) return(.sc_run_react_fallback_all(root, run, runtime$code))
      on.exit(.sc_run_react_worker_close(runtime), add = TRUE)
    }
  }
  .sc_run_react_worker_check(runtime, final = TRUE)
  run$status <- "completed"
  .sc_run_react_save(root, run, action = "react_completed")
}
