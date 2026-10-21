xai_session_fixture <- function() {
  f <- turn_fixture()
  state <- .sc_run_load(f$root)
  provider <- .sc_run_provider_spec(list(name = "grok", model = "grok-4.7",
    generation = list(max_tokens = 64, reasoning_effort = "high")))$metadata
  state$config$provider <- provider
  state$config$review$allow_external <- TRUE
  state$config$review$transfer_consent <- .sc_run_transfer_options(list(
    mode = "project", confirmed = TRUE, reviewer = "fixture", reason = "Read-only native session.",
    categories = c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression")),
    provider)
  state$config_hash <- .sc_run_hash(state$config)
  .sc_run_save(f$root, state)
  f$provider <- provider
  f$session <- .sc_run_turn_session(f$root, "native-fixture.v1", strrep("b", 64))
  f$request <- .sc_run_turn_request(f$session, list(
    list(role = "system", content = "Use local evidence."),
    list(role = "user", content = "Inspect cluster 0.")), "0", 1L)
  f
}
xai_session_reply <- function(tool = FALSE, mode = "completed") {
  output <- list(list(type = "reasoning", id = "r1", summary = list(),
    encrypted_content = "opaque/bytes/do-not-rewrite"))
  message <- if (tool) list(role = "assistant", content = NULL, tool_calls = list(
    list(id = "c1", type = "function", `function` = list(name = "cluster_markers",
      arguments = '{"cluster_id":"0","n":5}')))) else
    list(role = "assistant", content = '{"draft":true}')
  output <- c(output, list(if (tool) list(type = "function_call", call_id = "c1",
    name = "cluster_markers", arguments = '{"cluster_id":"0","n":5}') else
    list(type = "message", role = "assistant",
      content = list(list(type = "output_text", text = message$content)))))
  list(schema_version = "agentomics.turn.v2", message = message,
    finish_reason = if (mode != "completed") mode else if (tool) "tool_calls" else "stop",
    protocol = list(schema = "xai.responses.v1", output = output, status = mode,
      incomplete_details = if (mode == "incomplete") list(reason = "max_output_tokens") else NULL),
    usage = list(input_tokens = 32, output_tokens = 9, cached_tokens = 12,
      reasoning_tokens = 110, total_tokens = 151),
    raw_usage = list(input_tokens = 32, output_tokens = 9, total_tokens = 151,
      input_tokens_details = list(cached_tokens = 12),
      output_tokens_details = list(reasoning_tokens = 110), cost_in_usd_ticks = 123456789),
    metadata = list(model = "grok-4.7", http_status = 200))
}

test_that("native session binds endpoint generation and provisional qualification", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  p <- .sc_run_turn_prepare(f$request, f$provider)
  expect_identical(p$payload$endpoint, "https://api.x.ai/v1/responses")
  expect_identical(p$body$input, f$request$messages)
  expect_false(p$body$store)
  expect_equal(p$body$temperature, 0)
  expect_identical(p$body$reasoning$effort, "high")
  expect_identical(f$session$capability_profile$qualification, "synthetic_smoke_verified")
  expect_null(p$body$previous_response_id)
})

test_that("native full history and ciphertext are bound to committed receipts", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  first <- turn_call(f, fn = function(...) xai_session_reply(TRUE))
  expect_identical(first$status, "ok")
  expect_equal(first$cost_usd, 123456789 / 1e10)
  expect_identical(first$cost_basis, "provider_reported")
  expect_false(first$cost_estimated)
  expect_equal(first$raw_usage$output_tokens_details$reasoning_tokens, 110)
  history <- c(f$request$messages, first$turn_response$protocol$output,
    list(list(type = "function_call_output", call_id = "c1", output = '{"markers":[]}')))
  request <- .sc_run_turn_request(f$session, history, "0", 2L, first$turn_response_hash)
  altered <- request; altered$messages[[3]]$encrypted_content <- "changed"
  expect_identical(turn_call(f, altered)$status, "invalid_sequence")
  altered <- request; altered$messages[[3]]$summary <- list(list(type = "summary_text",
    text = "Changed native text"))
  expect_identical(turn_call(f, altered)$status, "invalid_sequence")
  final <- turn_call(f, request, fn = function(input, ...) {
    expect_identical(input, history)
    xai_session_reply()
  })
  expect_identical(final$status, "ok")
  cached <- turn_call(f, request, fn = function(...) stop("never resend"))
  expect_true(cached$cached)
  expect_identical(cached$turn_response$protocol, final$turn_response$protocol)
})

test_that("native opacity never exempts visible text or fabricated history", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  context <- .sc_run_react_context(f$root)
  value <- xai_session_reply()
  value$protocol$output[[1]]$summary <- list(list(type = "summary_text", text = f$cells[1]))
  expect_identical(.sc_run_turn_response(value, f$request, context, f$provider)$status, "private_payload")
  value <- xai_session_reply(); value$message$content <- '{"invented":true}'
  expect_identical(.sc_run_turn_response(value, f$request, context, f$provider)$status, "invalid_response")
  request <- f$request
  request$messages <- c(request$messages, xai_session_reply()$protocol$output)
  expect_identical(turn_call(f, request)$status, "invalid_sequence")
  request <- f$request; request$messages[[2]]$content <- f$cells[1]
  expect_error(turn_call(f, request), class = "sc_run_turn_error")
})

test_that("native incomplete refusal and missing cost stay explicit without retry", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  context <- .sc_run_react_context(f$root)
  value <- xai_session_reply(mode = "incomplete")
  expect_identical(.sc_run_turn_response(value, f$request, context, f$provider)$status, "truncated_response")
  value <- xai_session_reply(); value$finish_reason <- "refusal"
  value$message["content"] <- list(NULL)
  value$protocol$output[[2]]$content <- list(list(type = "refusal", refusal = "Cannot answer."))
  expect_identical(.sc_run_turn_response(value, f$request, context, f$provider)$status, "provider_refusal")
  value <- xai_session_reply(); value$raw_usage$cost_in_usd_ticks <- NULL
  out <- turn_call(f, fn = function(...) value)
  expect_identical(out$status, "ok")
  expect_identical(out$cost_state, "unknown")
  expect_null(out$cost_usd)
  expect_identical(turn_call(f, retry = TRUE)$status, "retry_refused")
})

test_that("native cached ciphertext cannot be replaced even with a new self hash", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  turn_call(f, fn = function(...) xai_session_reply(TRUE))
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path)
  entry <- ledger$entries[[1]]
  entry$turn_response$protocol$output[[1]]$encrypted_content <- "replacement"
  entry$turn_response_hash <- .sc_run_provider_hash(entry$turn_response)
  entry$turn_outcome$response_hash <- entry$turn_response_hash
  entry$turn_outcome_hash <- .sc_run_provider_hash(entry$turn_outcome)
  ledger$entries[[1]] <- entry
  .sc_run_provider_write(ledger, path)
  expect_error(turn_call(f, fn = function(...) stop("never resend")), "committed response")
})

test_that("native unknown delivery is durable and never automatically repeated", {
  f <- xai_session_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) { calls <<- calls + 1L; stop("Synthetic transport interruption") }
  expect_identical(turn_call(f, fn = fn)$status, "delivery_uncertain")
  expect_identical(turn_call(f, fn = fn)$status, "delivery_uncertain")
  expect_equal(calls, 1L)
})

test_that("native ReAct loop retains complete output items and stages verified drafts", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  provider <- .sc_run_provider_spec(list(name = "grok", model = "grok-4.7",
    generation = list(max_tokens = 2048, reasoning_effort = "high")))$metadata
  state$config$provider <- provider
  state$config$review <- list(allow_external = TRUE, transfer_consent =
    .sc_run_transfer_options(list(mode = "project", confirmed = TRUE, reviewer = "fixture",
      reason = "Synthetic native loop.", react = state$config$react,
      categories = c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression")),
      provider))
  state$config_hash <- .sc_run_hash(state$config); .sc_run_save(f$root, state)
  histories <- list()
  fn <- function(input, ...) {
    histories[[length(histories) + 1L]] <<- input
    cluster <- jsonlite::fromJSON(input[[2]]$content, simplifyVector = FALSE)$cluster_id
    first <- !any(vapply(input, function(x) identical(x$type, "function_call_output"), logical(1)))
    out <- xai_session_reply(first)
    if (first) {
      args <- .sc_project_json(list(cluster_id = cluster, n = 50L))
      out$message$tool_calls[[1]]$`function`$arguments <- args
      out$protocol$output[[2]]$arguments <- args
    } else {
      out$message$content <- .sc_project_json(react_final(cluster))
      out$protocol$output[[2]]$content[[1]]$text <- out$message$content
    }
    out
  }
  out <- .sc_run_react_refine(f$root, f$baseline, fn)
  expect_identical(out$status, "completed")
  expect_identical(out$proposal$annotations[[1]]$label, "T cell")
  expect_length(histories, 4L)
  expect_identical(histories[[2]][[3]]$encrypted_content, "opaque/bytes/do-not-rewrite")
  expect_identical(tail(histories[[2]], 1L)[[1]]$type, "function_call_output")
  expect_null(.sc_run_load(f$root)$approved)
  replay <- sc_react_replay(f$root)
  expect_true(replay$matches, info = .sc_project_json(replay$differences))
  expect_identical(replay$proposal, out$proposal)
})
