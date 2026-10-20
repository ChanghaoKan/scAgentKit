#' Replay saved annotation evidence without a provider
#' @param project Saved project directory, pending annotation or completed.
#' @param output_dir Optional new directory for the replay report; NULL returns it.
#' @return A versioned report with reconstructed draft and explicit differences.
#'   No API request, scientific approval or project-state write is performed.
#' @export
sc_react_replay <- function(project, output_dir = NULL) {
  root <- .sc_run_root(project)
  state <- .sc_run_load(root)
  before <- .sc_project_sha_file(file.path(root, "state.rds"))
  if (is.null(state$files$annotation_react_run))
    stop("This project has no saved ReAct session to replay.", call. = FALSE)
  run <- .sc_run_get(root, state, "annotation_react_run")
  if (!identical(run$status, "completed"))
    stop("Finish or recover the saved session before replaying its final draft.", call. = FALSE)
  context <- .sc_run_react_context(root, state, replay = TRUE)
  if (!is.null(run$session) && (!identical(run$session$binding, context$binding) ||
      !identical(run$session$input_hash, context$input_hash)))
    stop("Replay inputs differ from the saved session.", call. = FALSE)
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  evidence <- .sc_run_react_reference_view(.sc_run_get(root, state, "annotation_evidence"), state)
  runtime <- NULL
  on.exit(.sc_run_react_worker_close(runtime), add = TRUE)
  differences <- list()
  add <- function(cluster, component, reason) {
    differences[[length(differences) + 1L]] <<-
      list(cluster_id = cluster, component = component, reason = reason)
  }
  equal <- function(a, b) identical(.sc_run_provider_json(a), .sc_run_provider_json(b))
  proposal <- run$baseline
  clusters <- lapply(run$completed, function(id) {
    key <- paste0("react_cluster_", .sc_run_hash(id))
    if (!identical(run$traces[[id]], state$files[[key]]))
      stop("The saved trace is not the committed state checkpoint.", call. = FALSE)
    trace <- .sc_run_get(root, state, key)
    if (!identical(trace$cluster_id, id) || !identical(trace$session_id, run$session$id))
      stop("The saved trace belongs to another cluster or session.", call. = FALSE)
    start <- length(differences)
    messages <- head(trace$messages, 2L)
    used <- character(); last <- NULL
    for (turn in trace$turns) {
      if (is.null(turn$request_hash) && identical(turn$delivery, "not_sent") &&
          !identical(turn$status, "ok") && identical(trace$status, "fallback") &&
          identical(trace$fallback_reason, turn$status)) {
        add(id, "preflight", "Saved preflight rejection has no dispatched-turn receipt; its original environment-dependent cause cannot be replayed.")
        next
      }
      matches <- Filter(function(x) identical(x$request_hash, turn$request_hash), ledger$entries)
      if (length(matches) != 1L) stop("A saved turn has no unique ledger receipt.", call. = FALSE)
      entry <- matches[[1L]]
      receipt_key <- paste0("provider_turn_", turn$request_hash)
      saved <- .sc_run_get(root, state, receipt_key)
      linked <- any(vapply(state$history, function(event)
        event$action %in% c("provider_turn_completed", "provider_reconciled") &&
          identical(event$details$request_hash, saved$request_hash) &&
          identical(event$details$outcome_hash, saved$turn_outcome_hash) &&
          identical(event$details$checkpoint, state$files[[receipt_key]]), logical(1)))
      if (!linked || !equal(entry, saved) || !identical(entry$session_id, run$session$id) ||
          !identical(entry$cluster_id, id) || !identical(entry$status, turn$status) ||
          !identical(entry$turn_response_hash, turn$response_hash))
        stop("The turn, ledger and committed receipt disagree.", call. = FALSE)
      wire <- jsonlite::fromJSON(entry$turn_payload$wire_json, simplifyVector = FALSE)
      native <- identical(run$session$capability_profile$native_protocol, "xai.responses.v1")
      history <- if (native) wire$input else wire$messages
      if (!equal(messages, history)) add(id, "history", "Outgoing history differs from the reconstructed append-only sequence.")
      prior <- Filter(function(x) identical(x$session_id, run$session$id) &&
        x$ordinal < entry$ordinal, ledger$entries)
      .sc_run_turn_sequence(list(session = run$session, ordinal = entry$ordinal,
        cluster_id = id, previous_response_hash = entry$previous_response_hash),
        prior, list(body = wire))
      if (!identical(entry$status, "ok")) next
      # A received response can arrive after the deadline without entering history.
      appended <- if (native) entry$turn_response$protocol$output else list(entry$turn_response$message)
      if (identical(trace$fallback_reason, "cluster_timeout") &&
          identical(turn, tail(trace$turns, 1L)[[1L]]) &&
          equal(trace$messages, messages)) next
      messages <- append(messages, appended)
      last <- entry$turn_response$message
      for (call in last$tool_calls) {
        found <- Filter(function(x) identical(x$call_id, call$id), trace$tools)
        if (!length(found)) next # saved step/time limit stopped before execution
        if (length(found) != 1L || call$id %in% used)
          stop("Tool call IDs are duplicated in this saved trajectory.", call. = FALSE)
        tool <- found[[1L]]; used <- c(used, call$id)
        arguments <- tryCatch(jsonlite::fromJSON(call$`function`$arguments,
          simplifyVector = FALSE), error = function(e) NULL)
        if (!identical(tool$tool, call$`function`$name) || !equal(tool$arguments, arguments))
          stop("Saved tool arguments differ from the model response.", call. = FALSE)
        enabled <- tool$tool %in% unlist(run$session$policy$tools, use.names = FALSE)
        if (enabled && (is.null(runtime) || !runtime$process$is_alive()))
          runtime <<- .sc_run_react_worker_start(context, run$session$policy$tool_timeout_seconds)
        actual <- if (enabled) .sc_run_react_worker_call(runtime, tool$tool, arguments,
          timeout = run$session$policy$tool_timeout_seconds) else
          list(ok = FALSE, error = list(code = "disabled_or_unknown_tool",
            message = "The requested tool is not enabled in this session."))
        fields <- union(setdiff(names(actual), "cached"), setdiff(names(tool$response), "cached"))
        if (!equal(actual[fields], tool$response[fields]))
          add(id, tool$source, "Re-executed tool evidence differs; cache-hit flags are ignored.")
        content <- .sc_project_json(list(source = tool$source, evidence = tool$response))
        messages <- append(messages, list(if (native)
          list(type = "function_call_output", call_id = call$id, output = content) else
          list(role = "tool", tool_call_id = call$id, content = content)))
      }
    }
    if (length(used) != length(trace$tools)) add(id, "tools", "Some saved tool results have no matching model call.")
    if (!equal(messages, trace$messages)) add(id, "history", "Final saved message sequence differs from replay.")
    checked <- if (identical(trace$status, "completed")) {
      parsed <- tryCatch(jsonlite::fromJSON(last$content, simplifyVector = FALSE), error = identity)
      tryCatch(.sc_run_react_validate(parsed, run$baseline, evidence, id, trace, run$session),
        error = function(e) { add(id, "citations", conditionMessage(e)); NULL })
    } else if (identical(trace$status, "fallback")) {
      list(row = Filter(function(x) identical(x$clusterId, id), run$baseline$annotations)[[1L]],
        citations = Filter(function(x) identical(x$cluster_id, id), run$baseline_citations),
        risk_flags = .sc_run_react_baseline_risk(run, id))
    } else stop("A completed run contains an unfinished cluster.", call. = FALSE)
    if (!equal(checked, trace$result)) add(id, "draft", "Revalidated result differs from the saved cluster draft.")
    if (!is.null(checked)) proposal$annotations[[match(id,
      vapply(proposal$annotations, `[[`, character(1), "clusterId"))]] <<- checked$row
    list(cluster_id = id, matches = length(differences) == start,
      fallback_reason = trace$fallback_reason, tool_calls = length(used))
  })
  if (!equal(proposal, run$proposal)) add(NULL, "draft", "Reconstructed annotation table differs from the saved ReAct table.")
  if (!is.null(runtime) && runtime$process$is_alive()) .sc_run_react_worker_check(runtime, final = TRUE)
  else .sc_run_react_snapshot(context)
  if (!identical(before, .sc_project_sha_file(file.path(root, "state.rds"))))
    stop("The project changed during replay; retry on a stable saved snapshot.", call. = FALSE)
  report <- list(schema = "scagentkit.react-replay.v1", run_id = run$id,
    state_sha256 = before, matches = !length(differences), clusters = clusters,
    differences = differences, proposal = proposal, api_calls = 0L,
    boundary = "Original ReAct draft only; later human edits and approvals are not replayed. Timing-dependent tool failures can differ and are reported.")
  if (!is.null(output_dir)) {
    if (file.exists(output_dir)) stop("Choose a new replay output directory.", call. = FALSE)
    .sc_run_atomic(report, file.path(output_dir, "replay.json"), json = TRUE)
  }
  report
}
