test_that("session policy canonicalizes disabled tools and binds transfer scope", {
  policy <- .sc_run_turn_policy(list(tools = "act_lookup", act_enabled = FALSE))
  expect_identical(policy$tools, list())
  expect_identical(.sc_run_turn_policy(policy), policy)
  expect_error(.sc_run_turn_policy(list(input_safety_factor = 1.1)))
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  state <- .sc_run_load(f$root)
  expect_true(.sc_run_turn_authorized(f$request, state$config))
  expect_false("cost_mode" %in% names(f$session))
  state$config$review$transfer_consent$react_scope$policy$max_steps <- 1L
  state$config$review$transfer_consent$hash <- .sc_run_provider_hash(
    state$config$review$transfer_consent[setdiff(names(state$config$review$transfer_consent), "hash")])
  expect_false(.sc_run_turn_authorized(f$request, state$config))
})

test_that("prepared wire uses Core 0.2, tools and frozen generation without executing tools", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  before <- .sc_run_load(f$root)
  prepared <- .sc_run_turn_prepare(f$request, f$provider)
  expect_equal(prepared$body$temperature, 0)
  expect_false(prepared$body$parallel_tool_calls)
  expect_length(prepared$body$tools, 4)
  expect_null(prepared$body$response_format)
  calls <- 0L
  out <- turn_call(f, fn = function(...) { calls <<- calls + 1L; turn_reply(tool = TRUE) })
  expect_identical(out$status, "ok"); expect_identical(out$delivery, "received")
  expect_equal(calls, 1L); expect_equal(out$cost_usd, 0)
  expect_identical(out$content$tool_calls[[1]]$`function`$name, "cluster_markers")
  expect_null(.sc_run_load(f$root)$pending)
  events <- .sc_run_load(f$root)$history
  expect_identical(events[seq_along(before$history)], before$history)
  expect_identical(vapply(tail(events, 2L), `[[`, character(1), "action"),
    c("provider_turn_dispatched", "provider_turn_completed"))
  cached <- turn_call(f, fn = function(...) stop("must not resend"))
  expect_true(cached$cached); expect_identical(cached$content, out$content)
  expect_identical(turn_call(f, retry = TRUE)$status, "retry_refused")
})

test_that("session authority is committed state, never a self hash or caller consent flag", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  fabricated <- f$request; fabricated$session$prompt_version <- "tampered.v1"
  fabricated$session$hash <- .sc_run_provider_hash(fabricated$session[setdiff(names(fabricated$session), "hash")])
  expect_error(turn_call(f, fabricated), "committed scientific session")
  expect_error(.sc_run_call(f$root, f$request, f$provider, function(...) turn_reply(), allow_external = TRUE), "external-transfer")
  state <- .sc_run_load(f$root); saved <- .sc_run_get(f$root, state, "analysis")
  saved$seurat_clusters[1] <- "1"; state <- .sc_run_put(f$root, state, "analysis", saved)
  .sc_run_save(f$root, state)
  expect_error(turn_call(f), "membership differs|committed scientific session")
})

test_that("strict authorization requires a saved exact payload receipt", {
  f <- turn_fixture(TRUE, FALSE); on.exit(unlink(f$root, recursive = TRUE))
  request <- f$request; request$approved_payload_hash <- .sc_run_request_hash(request, f$provider)
  expect_identical(turn_call(f, request)$status, "awaiting_external_approval")
  revision <- .sc_run_load(f$root)$revision
  expect_error(.sc_run_turn_approve(f$root, request, "reviewer", "Reviewed exact body.", revision + 1L))
  .sc_run_turn_approve(f$root, request, "reviewer", "Reviewed exact body.", revision)
  out <- turn_call(f, request)
  expect_identical(out$status, "ok"); expect_identical(out$authorization$mode, "strict")
  changed <- request; changed$messages[[2]]$content <- "Different aggregate."
  expect_identical(turn_call(f, changed)$status, "awaiting_external_approval")
})

test_that("whole-wire privacy checks nested escaped history, paths and identifiers", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  values <- list(f$cells[1], paste0("Cell ", f$cells[1]), "/private/input.rds",
    '{"cell_id":"private-cell-1"}', '{"text":"private\\u002dcell\\u002d1"}',
    '{"matrix":[[1,2],[3,4]]}', '{"text":"\\u002fprivate\\u002finput.rds"}',
    'bad \\u0070rivate-cell-1')
  for (value in values) {
    request <- f$request; request$messages[[1]]$content <- value
    expect_error(turn_call(f, request), class = "sc_run_turn_error")
  }
  expect_silent(.sc_run_turn_privacy(list(content = "TRAV14/DV4 and G1 are markers."),
    .sc_run_react_context(f$root), 10000))
})

test_that("one session chains ordinals globally and preserves history separately for each cluster", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  first <- turn_call(f, fn = function(...) turn_reply(tool = TRUE))
  second <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1 aggregate.")),
    "1", 2L, first$turn_response_hash)
  two <- turn_call(f, second)
  reset <- .sc_run_turn_request(f$session, f$request$messages, "0", 3L, two$turn_response_hash)
  expect_identical(turn_call(f, reset)$status, "invalid_sequence")
  resumed <- reset
  resumed$messages <- c(f$request$messages, list(first$turn_response$message,
    list(role = "tool", tool_call_id = "call_1", content = '{"markers":[]}')))
  expect_identical(turn_call(f, resumed)$status, "ok")
  duplicate <- .sc_run_turn_request(f$session, second$messages, "1", 4L, first$turn_response_hash)
  expect_identical(turn_call(f, duplicate)$status, "invalid_sequence")
})

test_that("self-rehashed cached response cannot replace the committed receipt", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  turn_call(f)
  path <- file.path(f$root, "provider", "ledger.json"); ledger <- .sc_run_provider_read(path)
  ledger$entries[[1]]$turn_response$message$content <- '{"draft":"changed"}'
  ledger$entries[[1]]$turn_response_hash <- .sc_run_provider_hash(ledger$entries[[1]]$turn_response)
  ledger$entries[[1]]$turn_outcome$response_hash <- ledger$entries[[1]]$turn_response_hash
  ledger$entries[[1]]$turn_outcome_hash <- .sc_run_provider_hash(ledger$entries[[1]]$turn_outcome)
  .sc_run_provider_write(ledger, path)
  expect_error(turn_call(f, fn = function(...) stop("must not resend")), "committed response")
})

test_that("cached response privacy is rechecked without another charge", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  first <- turn_call(f, fn = function(...) turn_reply("newly-protected-cache-fixture"))
  withr::local_envvar(c(DEEPSEEK_API_KEY = "newly-protected-cache-fixture"))
  cached <- turn_call(f, fn = function(...) stop("must not resend"))
  expect_true(cached$cached); expect_identical(cached$status, "private_payload")
  expect_null(cached$content); expect_null(cached$turn_response)
  expect_equal(cached$cost_usd, first$cost_usd)
  path <- file.path(f$root, "provider", "ledger.json")
  expect_false(grepl("newly-protected-cache-fixture", paste(readLines(path), collapse = ""), fixed = TRUE))
})

test_that("turns collect usage and configured cost after the response without preflight estimates", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  out <- turn_call(f, fn = function(...) turn_reply(input = 120))
  expect_identical(out$status, "ok"); expect_identical(out$cost_state, "known")
  expect_identical(out$cost_basis, "usage_configured_pricing"); expect_true(out$cost_estimated)
  expect_null(out$actual_cost_usd); expect_equal(out$usage$input_tokens, 120)
  expect_equal(out$cost_usd, .000048)
  expect_false(any(c("reservation_usd", "charged_or_held_usd", "cost_mode") %in% names(out)))
})

test_that("delivery states do not resend and unavailable usage does not invent a zero cost", {
  for (delivery in c("not_sent", "unknown", "received")) {
    f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    failure <- structure(list(message = "private error body /private/never-show", call = NULL,
      code = "invalid_response", delivery = delivery, usage = if (delivery == "received")
        list(input_tokens = 100, output_tokens = 10) else NULL),
      class = c("agentomics_turn_error", "error", "condition"))
    out <- turn_call(f, fn = function(...) stop(failure))
    expect_identical(out$delivery, delivery)
    expect_identical(out$cost_state, if (delivery == "unknown") "unknown" else "known")
    expect_false(grepl("private error body", out$error, fixed = TRUE))
    expect_true(turn_call(f, fn = function(...) stop("no repeat"))$cached)
  }
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
  out <- turn_call(f, fn = function(...) { x <- turn_reply(); x$usage <- NULL; x$raw_usage <- NULL; x })
  expect_identical(out$status, "ok"); expect_identical(out$cost_state, "unknown")
  expect_null(out$cost_usd)
  next_request <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1.")),
    "1", 2L, out$turn_response_hash)
  expect_identical(turn_call(f, next_request)$status, "ok")
})

test_that("missing pricing and inconsistent usage remain descriptive, not send gates", {
  f <- turn_fixture(TRUE, priced = FALSE); on.exit(unlink(f$root, recursive = TRUE))
  out <- turn_call(f)
  expect_identical(out$status, "ok"); expect_identical(out$cost_state, "unknown")
  expect_null(out$cost_usd)
  other <- turn_fixture(TRUE); on.exit(unlink(other$root, recursive = TRUE), add = TRUE)
  bad <- turn_reply(); bad$raw_usage$input_tokens <- 1
  out <- turn_call(other, fn = function(...) bad)
  expect_identical(out$status, "ok"); expect_identical(out$cost_state, "unknown")
  expect_identical(out$usage_status, "missing_or_inconsistent")
})

test_that("a received invalid response can advance to another cluster with a safe outcome receipt", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  failure <- structure(list(message = "unsafe error body", call = NULL, code = "invalid_response",
    delivery = "received", usage = list(input_tokens = 100, output_tokens = 10)),
    class = c("agentomics_turn_error", "error", "condition"))
  failed <- turn_call(f, fn = function(...) stop(failure))
  expect_identical(failed$status, "provider_response_error"); expect_null(failed$turn_response)
  next_request <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1.")),
    "1", 2L, failed$turn_outcome_hash)
  expect_identical(turn_call(f, next_request)$status, "ok")
})

test_that("post-hoc turns have no monetary cap while per-cluster limits remain enforced", {
  f <- turn_fixture(TRUE, FALSE); on.exit(unlink(f$root, recursive = TRUE))
  request <- f$request
  request$approved_payload_hash <- .sc_run_turn_approve(f$root, request, "reviewer",
    "Reviewed uncapped post-hoc cost and exact payload.", .sc_run_load(f$root)$revision)
  out <- turn_call(f, request, fn = function(...) { x <- turn_reply(); x$cost_usd <- 2; x })
  expect_identical(out$status, "ok"); expect_equal(out$cost_usd, 2)
  expect_false(any(c("reservation_usd", "charged_or_held_usd", "cost_mode") %in% names(out)))
  limited <- turn_fixture(policy = list(max_steps_per_cluster = 1L))
  on.exit(unlink(limited$root, recursive = TRUE), add = TRUE)
  first <- turn_call(limited)
  request <- .sc_run_turn_request(limited$session, c(limited$request$messages,
    list(first$turn_response$message, list(role = "user", content = "Another check."))),
    "0", 2L, first$turn_response_hash)
  expect_identical(turn_call(limited, request)$status, "session_limit")
})

test_that("Core's real HTTP adapter serializes the exact prepared wire without retaining credentials", {
  withr::local_envvar(c(DEEPSEEK_API_KEY = "synthetic-turn-key-do-not-retain"))
  wire <- NULL; calls <- 0L
  local_mocked_bindings(req_perform = function(req, ...) {
    calls <<- calls + 1L; wire <<- rawToChar(req$body$data)
    httr2::response(status_code = 200, method = "POST", url = req$url,
      headers = list(`content-type` = "application/json", authorization = "Bearer synthetic-response-header"),
      body = charToRaw(as.character(jsonlite::toJSON(list(id = "turn-http-fixture",
        model = "deepseek-flash", choices = list(list(message = list(role = "assistant", content = '{"draft":true}'),
          finish_reason = "stop")), usage = list(prompt_tokens = 100, completion_tokens = 10)), auto_unbox = TRUE))))
  }, .package = "httr2")
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  prepared <- .sc_run_turn_prepare(f$request, f$provider)
  out <- .sc_run_call(f$root, f$request, f$provider, allow_external = TRUE)
  expect_identical(out$status, "ok"); expect_identical(calls, 1L)
  expect_identical(wire, prepared$json)
  expect_identical(out$turn_payload$wire_json, wire)
  expect_false("cost_mode" %in% names(out))
  expect_false(grepl("synthetic-turn-key|synthetic-response-header", paste(readLines(
    file.path(f$root, "provider", "ledger.json")), collapse = "")))
})

test_that("crash recovery never sends an uncertain turn and restores only committed responses", {
  for (phase in c("after_dispatch", "after_response", "after_turn_commit")) {
    f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    calls <- 0L
    withr::with_options(list(scAgentKit.provider_crash = phase), expect_error(turn_call(f,
      fn = function(...) { calls <<- calls + 1L; turn_reply() }), "Injected provider interruption"))
    expect_identical(calls, if (phase == "after_dispatch") 0L else 1L)
    stored <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))$entries[[1]]
    expect_identical(stored$status, "dispatched")
    expect_identical(stored$cost_state, "unknown"); expect_null(stored$cost_usd)
    expect_identical(stored$response_metadata$availability, "unavailable")
    expect_null(stored$response_metadata_hash)
    restarted <- turn_call(f, fn = function(...) stop("restart must not dispatch"))
    expect_identical(restarted$status, if (phase == "after_turn_commit") "ok" else "delivery_uncertain")
    if (phase == "after_turn_commit") {
      expect_true(restarted$cached); expect_identical(restarted$cost_state, "known")
      expect_equal(restarted$cost_usd, .000042)
      expect_identical(restarted$response_metadata_hash, .sc_run_provider_hash(restarted$response_metadata))
      expect_null(restarted$response_audit)
    }
  }
})

test_that("interrupted turns reconcile and recover metadata without changing the predecessor", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  withr::with_options(list(scAgentKit.provider_crash = "after_dispatch"),
    expect_error(turn_call(f, fn = function(...) { calls <<- calls + 1L; turn_reply() }),
      "Injected provider interruption"))
  path <- file.path(f$root, "provider", "ledger.json")
  original <- .sc_run_provider_read(path)
  before <- original$entries[[1]]
  predecessor_hash <- .sc_run_provider_hash(before)
  expect_null(before$response_metadata_hash)
  reconciled <- sc_run_provider_reconcile(f$root, before$request_hash, 0, "offline QA",
    "Confirmed no transmission after interruption.", delivery = "not_sent")
  expect_identical(reconciled$status, "reconciled_no_response")
  expect_identical(reconciled$reconciliation$previous_entry_hash, predecessor_hash)
  expect_identical(reconciled$response_metadata, before$response_metadata)
  expect_identical(reconciled$response_metadata_hash, .sc_run_provider_hash(before$response_metadata))
  expect_null(reconciled$response_audit)
  expect_null(reconciled$completed_at)
  state <- .sc_run_load(f$root)
  receipt <- .sc_run_get(f$root, state, paste0("provider_turn_", before$request_hash))
  expect_identical(receipt$response_metadata_hash, reconciled$response_metadata_hash)
  expect_identical(receipt$reconciliation$previous_entry_hash, predecessor_hash)
  expect_identical(.sc_run_provider_read(path)$entries[[1]]$response_metadata_hash,
    reconciled$response_metadata_hash)
  # Recreate a crash after committing reconciliation but before writing its ledger.
  .sc_run_provider_write(original, path)
  recovered <- turn_call(f, fn = function(...) { calls <<- calls + 1L; stop("must not dispatch") })
  expect_true(recovered$cached)
  expect_identical(recovered$status, "reconciled_no_response")
  expect_identical(recovered$response_metadata_hash, reconciled$response_metadata_hash)
  expect_identical(recovered$reconciliation$previous_entry_hash, predecessor_hash)
  expect_identical(.sc_run_provider_read(path)$entries[[1]]$response_metadata_hash,
    reconciled$response_metadata_hash)
  expect_identical(calls, 0L)
})

test_that("manual reconciliation records the invoice without imposing a new cost cap", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  first <- turn_call(f, fn = function(...) { x <- turn_reply(); x$usage <- NULL; x$raw_usage <- NULL; x })
  expect_identical(first$status, "ok"); expect_identical(first$cost_state, "unknown")
  known <- sc_run_provider_reconcile(f$root, first$request_hash, 2, "reviewer", "Verified the billing receipt.")
  expect_equal(known$actual_cost_usd, 2); expect_identical(known$cost_basis, "analyst_confirmed_invoice")
  expect_false(known$cost_estimated)
  next_request <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1.")),
    "1", 2L, known$turn_response_hash)
  expect_identical(turn_call(f, next_request)$status, "ok")
  expect_true(turn_call(f)$cached)
})

test_that("interrupted reconciliation restores only the exact previously committed ledger entry", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  unresolved <- turn_call(f, fn = function(...) { x <- turn_reply(); x$usage <- NULL; x$raw_usage <- NULL; x })
  path <- file.path(f$root, "provider", "ledger.json")
  prior <- .sc_run_provider_read(path)
  sc_run_provider_reconcile(f$root, unresolved$request_hash, .0001, "reviewer", "Verified the invoice.")
  .sc_run_provider_write(prior, path)
  recovered <- turn_call(f, fn = function(...) stop("must not dispatch"))
  expect_true(recovered$cached); expect_equal(recovered$actual_cost_usd, .0001)
  expect_identical(recovered$cost_basis, "analyst_confirmed_invoice")
  prior$entries[[1]]$cost_state <- "known"
  prior$entries[[1]]$cost_usd <- 123
  .sc_run_provider_write(prior, path)
  expect_error(turn_call(f), "committed response")
})

test_that("a fabricated withheld projection cannot become a successful cached draft", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  turn_call(f)
  path <- file.path(f$root, "provider", "ledger.json"); ledger <- .sc_run_provider_read(path)
  ledger$entries[[1]]$withheld_response_hash <- ledger$entries[[1]]$turn_response_hash
  ledger$entries[[1]]$turn_response <- NULL; ledger$entries[[1]]$turn_response_hash <- NULL
  ledger$entries[[1]]$content <- list(role = "assistant", content = '{"forged":true}')
  ledger$entries[[1]]$status <- "ok"
  .sc_run_provider_write(ledger, path)
  cached <- turn_call(f, fn = function(...) stop("must not resend"))
  expect_identical(cached$status, "private_payload"); expect_null(cached$content)
})

test_that("one transport call cannot exceed its session cluster time allowance", {
  f <- turn_fixture(policy = list(cluster_timeout_seconds = 2))
  on.exit(unlink(f$root, recursive = TRUE))
  prepared <- .sc_run_turn_prepare(f$request, f$provider)
  expect_equal(prepared$args$timeout_secs, 2)
  out <- turn_call(f, fn = function(..., timeout_secs) {
    expect_equal(timeout_secs, 2)
    turn_reply()
  })
  expect_identical(out$status, "ok")
})

test_that("post-hoc turn costs do not block independent single requests", {
  for (known in c(TRUE, FALSE)) {
    f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    out <- turn_call(f, fn = function(...) {
      x <- turn_reply()
      if (known) x$cost_usd <- 2 else { x$usage <- NULL; x$raw_usage <- NULL }
      x
    })
    expect_identical(out$cost_state, if (known) "known" else "unknown")
    request <- list(system_prompt = "Return aggregate JSON.", user_prompt = "Four cells.", purpose = "qc")
    request$approved_payload_hash <- .sc_run_request_hash(request, f$provider)
    calls <- 0L
    answer <- .sc_run_call(f$root, request, f$provider, function(...) {
      calls <<- calls + 1L; list(content = '{"ok":true}', cost_usd = .001)
    }, allow_external = TRUE)
    expect_identical(answer$status, "ok"); expect_equal(calls, 1L)
  }
})

test_that("delivery cannot be changed independently of its committed receipt", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  failure <- structure(list(message = "network unknown", call = NULL, code = "transport_error", delivery = "unknown"),
    class = c("agentomics_turn_error", "error", "condition"))
  first <- turn_call(f, fn = function(...) stop(failure))
  path <- file.path(f$root, "provider", "ledger.json"); ledger <- .sc_run_provider_read(path)
  ledger$entries[[1]]$delivery <- "received"; ledger$entries[[1]]$status <- "provider_response_error"
  .sc_run_provider_write(ledger, path)
  next_request <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1.")),
    "1", 2L, first$turn_outcome_hash)
  calls <- 0L
  expect_error(turn_call(f, next_request, fn = function(...) { calls <<- calls + 1L; turn_reply() }), "committed response")
  expect_identical(calls, 0L)
})

test_that("output cap rejection remains rejected on cached reads without a monetary stop", {
  f <- turn_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  first <- turn_call(f, fn = function(...) turn_reply(output = 100))
  expect_identical(first$status, "invalid_response"); expect_null(first$content)
  cached <- turn_call(f, fn = function(...) stop("must not send"))
  expect_true(cached$cached); expect_identical(cached$status, "invalid_response")
  expect_null(cached$content); expect_null(cached$turn_response)
})

test_that("persisted deadlines bound resumed dispatch without changing payload consent", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  request <- f$request
  request$timeout_seconds <- 60
  request$deadline <- as.numeric(Sys.time()) + 10
  hash <- .sc_run_request_hash(request, f$provider)
  Sys.sleep(.02)
  expect_identical(.sc_run_request_hash(request, f$provider), hash)
  actual <- NULL
  out <- turn_call(f, request, function(timeout_secs, ...) {
    actual <<- timeout_secs; turn_reply()
  })
  expect_identical(out$status, "ok")
  expect_gt(actual, 0); expect_lt(actual, 10)
  expect_equal(out$effective_timeout_seconds, actual)
  expired <- turn_fixture(); on.exit(unlink(expired$root, recursive = TRUE), add = TRUE)
  request <- expired$request; request$deadline <- as.numeric(Sys.time()) - 1
  out <- turn_call(expired, request, function(...) stop("must not send"))
  expect_identical(out$delivery, "not_sent")
  expect_identical(out$provider_error_code, "cluster_timeout")
  expect_equal(out$cost_usd, 0)
})
