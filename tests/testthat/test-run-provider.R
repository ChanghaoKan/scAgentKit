run_provider_fixture <- function(external = FALSE) {
  root <- tempfile("run-provider-"); dir.create(root)
  provider <- list(name = if (external) "testremote" else "mock", model = "test-v1",
    external = external, reservation_usd = if (external) 0.05 else 0)
  request <- list(system_prompt = "Return ONLY an approved typed JSON decision.",
    user_prompt = "Aggregate public QC: 100 cells, median features 800. No barcodes.",
    purpose = "qc_proposal", evidence_hash = paste(rep("a", 64), collapse = ""),
    validator = function(x) {
      x <- .decision_object(x, required = c("operation", "reason"))
      x$operation <- .decision_string(x$operation, "operation", "keep_all")
      x$reason <- .decision_string(x$reason, "reason")
      x
    })
  request$approved_payload_hash <- .sc_run_request_hash(request, provider)
  list(root = root, provider = provider, request = request)
}
run_provider_good <- '{"operation":"keep_all","reason":"Public aggregate reviewed; uncertain thresholds need review."}'

test_that("mock provider is headless and caches across calls without a function", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(system_prompt, user_prompt) { calls <<- calls + 1L; run_provider_good }
  first <- .sc_run_call(f$root, f$request, f$provider, fn)
  expect_identical(first$status, "ok")
  expect_identical(first$content$operation, "keep_all")
  expect_equal(first$cost_usd, 0)
  second <- .sc_run_call(f$root, f$request, f$provider)
  expect_true(second$cached); expect_identical(second$content, first$content)
  expect_identical(calls, 1L)
  ledger <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))
  expect_length(ledger$entries, 1L)
  expect_false(any(vapply(ledger$entries[[1]], is.function, logical(1))))
})

test_that("external dispatch requires approval of exact text and settings", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) { calls <<- calls + 1L; list(content = run_provider_good, cost_usd = 0.01) }
  denied <- .sc_run_call(f$root, f$request, f$provider, fn, budget = 1)
  expect_identical(denied$status, "awaiting_external_approval"); expect_identical(calls, 0L)
  changed <- f$request; changed$user_prompt <- paste(changed$user_prompt, "changed evidence")
  stale <- .sc_run_call(f$root, changed, f$provider, fn, 1, allow_external = TRUE)
  expect_identical(stale$status, "awaiting_external_approval")
  model <- f$provider; model$model <- "test-v2"
  expect_identical(.sc_run_call(f$root, f$request, model, fn, 1, TRUE)$status, "awaiting_external_approval")
  settings <- f$provider; settings$generation <- list(temperature = 0.5)
  expect_false(identical(.sc_run_request_hash(f$request, settings), f$request$approved_payload_hash))
  first <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)
  expect_identical(first$status, "ok"); expect_identical(calls, 1L)
  # Cached data needs no new transmission consent or runtime key.
  cached <- .sc_run_call(f$root, f$request, f$provider, budget = 0)
  expect_true(cached$cached); expect_identical(calls, 1L)
})

test_that("project budget reserves before dispatch and settles known usage", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  f$provider$pricing <- list(input_per_million = 2, output_per_million = 4, cached_input_per_million = 0.2)
  f$request$approved_payload_hash <- .sc_run_request_hash(f$request, f$provider)
  calls <- 0L
  fn <- function(...) {
    calls <<- calls + 1L
    during <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))$entries[[1L]]
    expect_identical(during$status, "dispatched")
    expect_equal(during$charged_or_held_usd, 0.05)
    list(content = run_provider_good, usage = list(prompt_tokens = 1000, completion_tokens = 100,
      prompt_cache_hit_tokens = 200), model = "reported-v1")
  }
  stop <- .sc_run_call(f$root, f$request, f$provider, fn, 0.04, TRUE)
  expect_identical(stop$status, "budget_stop"); expect_identical(calls, 0L)
  out <- .sc_run_call(f$root, f$request, f$provider, fn, 0.05, TRUE)
  expect_equal(out$cost_usd, 0.00204); expect_equal(out$charged_or_held_usd, 0.00204)
  expect_identical(out$model_reported, "reported-v1")
  request2 <- f$request; request2$user_prompt <- "Second aggregate"
  request2$approved_payload_hash <- .sc_run_request_hash(request2, f$provider)
  expect_identical(.sc_run_call(f$root, request2, f$provider, fn, 0.051, TRUE)$status, "budget_stop")
  expect_identical(calls, 1L)
})

test_that("missing usage keeps conservative hold and never repeats an unknown call", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L; fn <- function(...) { calls <<- calls + 1L; run_provider_good }
  first <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)
  expect_identical(first$status, "ok"); expect_identical(first$cost_state, "unknown")
  expect_equal(first$charged_or_held_usd, 0.05)
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$cached)
  request2 <- f$request; request2$user_prompt <- "Second aggregate"
  request2$approved_payload_hash <- .sc_run_request_hash(request2, f$provider)
  expect_identical(.sc_run_call(f$root, request2, f$provider, fn, 1, TRUE)$status, "accounting_hold")
  expect_identical(calls, 1L)
})

test_that("provider errors are cached redacted and unknown dispatch is not retried", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) { calls <<- calls + 1L; stop("HTTP body contains Bearer unsafe-token-123456") }
  failed <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)
  expect_identical(failed$status, "delivery_uncertain")
  expect_false(grepl("unsafe-token", failed$error))
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$cached)
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE, retry = TRUE)$status, "retry_refused")
  expect_identical(calls, 1L)
  ledger <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))
  ledger$entries[[1]]$status <- "dispatched"
  .sc_run_provider_write(ledger, file.path(f$root, "provider", "ledger.json"))
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$status, "accounting_hold")
  expect_identical(calls, 1L)
})

test_that("empty malformed unsupported and code responses are recoverable failures", {
  bad <- list(NULL, "", "not JSON", "```json\n{}\n```", "[]",
    '{"operation":"eval_r","reason":"Run arbitrary code."}',
    '{"operation":"keep_all","reason":"ok","r_code":"system()"}',
    '{"operation":"keep_all","operation":"keep_all","reason":"ok"}')
  for (raw in bad) {
    f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    calls <- 0L; fn <- function(...) { calls <<- calls + 1L; raw }
    out <- .sc_run_call(f$root, f$request, f$provider, fn)
    expect_true(out$status %in% c("invalid_response", "empty_response"))
    expect_null(out$content)
    again <- .sc_run_call(f$root, f$request, f$provider, fn)
    expect_true(again$cached); expect_identical(calls, 1L)
    good <- .sc_run_call(f$root, f$request, f$provider, function(...) run_provider_good, retry = TRUE)
    expect_identical(good$status, "ok"); expect_identical(good$attempt, 2L)
  }
})

test_that("cached response is revalidated without charging or calling again", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  expect_identical(.sc_run_call(f$root, f$request, f$provider, function(...) run_provider_good)$status, "ok")
  f$request$validator <- function(x) stop("Unsupported operation under the current validation schema.")
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) stop("must not call"))
  expect_true(out$cached); expect_identical(out$status, "invalid_response")
  expect_match(out$error, "Unsupported operation")
})

test_that("per-project dispatch lock prevents nested and duplicate callers", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  fn <- function(...) {
    nested <- .sc_run_call(f$root, f$request, f$provider, function(...) stop("must not call"))
    expect_identical(nested$status, "provider_busy")
    run_provider_good
  }
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn)$status, "ok")
  expect_false(dir.exists(file.path(f$root, "provider", ".dispatch-lock")))
})

test_that("ledger corruption and altered response fail closed", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  .sc_run_call(f$root, f$request, f$provider, function(...) run_provider_good)
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path); ledger$entries[[1]]$raw <- '{"changed":true}'
  .sc_run_provider_write(ledger, path)
  expect_error(.sc_run_call(f$root, f$request, f$provider), "hash mismatch")
  writeLines("broken JSON", path)
  expect_error(.sc_run_call(f$root, f$request, f$provider), "ledger is invalid")
})

test_that("configuration has no credential fields or closure persistence", {
  expect_error(.sc_run_provider_spec(list(name = "deepseek", api_key = "unsafe")), "credentials")
  expect_error(.sc_run_provider_spec(list(name = "mock", generation = list(r_code = "system()"))), "Unsupported")
  expect_error(.sc_run_provider_spec(list(name = "deepseek", external = FALSE)), "external")
  expect_error(.sc_run_provider_spec(list(name = "custom", reservation_usd = 0)), "positive")
  expect_error(.sc_run_provider_spec(list(name = "mock", generation = list(max_tokens = 1.5))), "integer")
  deepseek <- .sc_run_provider_spec("deepseek")
  expect_identical(deepseek$metadata$model, "deepseek-flash")
  expect_identical(deepseek$metadata$generation$thinking$type, "disabled")
  expect_null(deepseek$fn)
  expect_identical(.sc_run_provider_spec("grok")$metadata$model, "grok-4.20-0309-non-reasoning")
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  withr::local_envvar(DEEPSEEK_API_KEY = "secret-known-value-123456")
  fn <- local({ api_key <- "closure-key-not-to-be-serialized"; function(...) run_provider_good })
  .sc_run_call(f$root, f$request, f$provider, fn)
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("closure-key|secret-known-value|validator|chat_fn", json))
  expect_error(.sc_run_call(f$root, within(f$request, user_prompt <- "secret-known-value-123456"), f$provider, fn), "Credential-like request")
})

test_that("credential-like response is discarded and absent provider supports manual mode", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  withr::local_envvar(DEEPSEEK_API_KEY = "secret-known-value-123456")
  out <- .sc_run_call(f$root, f$request, f$provider,
    function(...) '{"operation":"keep_all","reason":"secret-known-value-123456"}')
  expect_identical(out$status, "secret_detected"); expect_null(out$raw)
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("secret-known-value", json))
  expect_identical(.sc_run_call(f$root, f$request)$status, "needs_provider")
})

test_that("crashes before or after response hold durable reservation without resending", {
  withr::local_options(list(scAgentKit.provider_crash = NULL))
  for (hook in c("after_dispatch", "after_response")) {
    f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    calls <- 0L
    fn <- function(...) { calls <<- calls + 1L; list(content = run_provider_good, cost_usd = 0.01) }
    options(scAgentKit.provider_crash = hook)
    expect_error(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE), "Injected provider interruption")
    options(scAgentKit.provider_crash = NULL)
    ledger <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))
    expect_equal(ledger$entries[[1]]$charged_or_held_usd, 0.05)
    expect_identical(ledger$entries[[1]]$status, "dispatched")
    before <- calls
    expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$status, "accounting_hold")
    expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE, retry = TRUE)$status, "retry_refused")
    expect_identical(calls, before)
    expect_identical(calls, if (hook == "after_dispatch") 0L else 1L)
  }
})

test_that("exceeded reservation or generation usage pauses cache and new calls", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  fn <- function(...) list(content = run_provider_good, cost_usd = 0.06)
  out <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)
  expect_identical(out$status, "budget_stop"); expect_true(out$accounting_issue)
  again <- .sc_run_call(f$root, f$request, f$provider, budget = 1)
  expect_true(again$cached); expect_identical(again$status, "budget_stop")
  request2 <- f$request; request2$user_prompt <- "Second aggregate"
  request2$approved_payload_hash <- .sc_run_request_hash(request2, f$provider)
  expect_identical(.sc_run_call(f$root, request2, f$provider, fn, 1, TRUE)$status, "accounting_hold")
})

test_that("existing agentomicsCore token recorder supplies provider usage", {
  skip_if_not_installed("agentomicsCore")
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  f$provider$pricing <- list(input_per_million = 2, output_per_million = 4)
  f$request$approved_payload_hash <- .sc_run_request_hash(f$request, f$provider)
  token_env <- agentomicsCore::token_state
  records <- token_env$records
  on.exit(token_env$records <- records, add = TRUE)
  fn <- function(...) {
    agentomicsCore::token_record("mock:remote", "provider-returned-v1", 1000, 200,
      cached_tokens = NA_integer_, call_type = "qc_proposal")
    run_provider_good
  }
  out <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)
  expect_identical(out$cost_state, "known")
  expect_equal(out$usage$input_tokens, 1000)
  expect_equal(out$usage$output_tokens, 200)
  expect_equal(out$cost_usd, 0.0028)
  expect_identical(out$model_reported, "provider-returned-v1")
})

test_that("an explicitly accounted invalid remote response can retry once on request", {
  f <- run_provider_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) {
    calls <<- calls + 1L
    list(content = if (calls == 1L) "bad response" else run_provider_good, cost_usd = 0.01)
  }
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$status, "invalid_response")
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE)$cached)
  expect_identical(calls, 1L)
  out <- .sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE, retry = TRUE)
  expect_identical(out$status, "ok"); expect_identical(out$attempt, 2L)
  expect_identical(calls, 2L)
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn, 1, TRUE, retry = TRUE)$cached)
  expect_identical(calls, 2L)
  ledger <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))
  expect_equal(sum(vapply(ledger$entries, function(x) x$charged_or_held_usd, numeric(1))), 0.02)
})

test_that("local transient failures need explicit retry and replacement locks survive release", {
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) { calls <<- calls + 1L; if (calls == 1L) stop("Local mock failed") else run_provider_good }
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn)$status, "provider_error")
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn)$cached)
  expect_identical(calls, 1L)
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn, retry = TRUE)$status, "ok")
  expect_identical(calls, 2L)
  lock <- file.path(f$root, "provider", ".dispatch-lock"); dir.create(lock)
  .sc_run_provider_write(list(token = "replacement"), file.path(lock, "owner.json"))
  .sc_run_provider_release(lock, "old-owner")
  expect_true(dir.exists(lock))
  .sc_run_provider_release(lock, "replacement")
  expect_false(dir.exists(lock))
})

test_that("configured credential environment is covered in all persisted provider fields", {
  secret <- "randomvalue47192materialwithoutprefix"
  withr::local_envvar(TEST_PROVIDER_SECRET = secret)
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f$provider$api_key_env <- "TEST_PROVIDER_SECRET"
  f$request$approved_payload_hash <- .sc_run_request_hash(f$request, f$provider)
  expect_identical(.sc_run_provider_redact(secret, "TEST_PROVIDER_SECRET"), "[REDACTED]")
  metadata <- f$provider; metadata$model <- secret
  expect_error(.sc_run_provider_spec(metadata), "Credential-like provider metadata")
  bad_request <- f$request; bad_request$user_prompt <- paste("Aggregate", secret)
  expect_error(.sc_run_request_hash(bad_request, f$provider), "Credential-like request")
  bad_request <- f$request; bad_request$purpose <- secret
  expect_error(.sc_run_request_hash(bad_request, f$provider), "Credential-like request purpose")
  response <- jsonlite::toJSON(list(operation = "keep_all", reason = secret), auto_unbox = TRUE)
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) response)
  expect_identical(out$status, "secret_detected"); expect_null(out$raw); expect_null(out$content)
  path <- file.path(f$root, "provider", "ledger.json")
  expect_false(grepl(secret, paste(readLines(path), collapse = "\n"), fixed = TRUE))

  # Neither a provider error body nor returned model ID may leak the custom key.
  next_request <- f$request; next_request$user_prompt <- "Second safe aggregate"
  next_request$approved_payload_hash <- .sc_run_request_hash(next_request, f$provider)
  error <- .sc_run_call(f$root, next_request, f$provider, function(...) stop(secret))
  expect_identical(error$status, "provider_error")
  expect_false(grepl(secret, error$error, fixed = TRUE))
  next_request$user_prompt <- "Third safe aggregate"
  next_request$approved_payload_hash <- .sc_run_request_hash(next_request, f$provider)
  model <- .sc_run_call(f$root, next_request, f$provider,
    function(...) list(content = run_provider_good, model = secret))
  expect_identical(model$status, "ok"); expect_null(model$model_reported)
  expect_false(grepl(secret, paste(readLines(path), collapse = "\n"), fixed = TRUE))

  # A validator cannot introduce a key into parsed content or its error audit.
  next_request$user_prompt <- "Fourth safe aggregate"
  next_request$approved_payload_hash <- .sc_run_request_hash(next_request, f$provider)
  next_request$validator <- function(x) stop(paste("Validation failed", secret))
  validation <- .sc_run_call(f$root, next_request, f$provider, function(...) run_provider_good)
  expect_identical(validation$status, "invalid_response")
  expect_match(validation$error, "\\[REDACTED\\]")
  next_request$user_prompt <- "Fifth safe aggregate"
  next_request$approved_payload_hash <- .sc_run_request_hash(next_request, f$provider)
  next_request$validator <- function(x) { x$reason <- secret; x }
  content <- .sc_run_call(f$root, next_request, f$provider, function(...) run_provider_good)
  expect_identical(content$status, "secret_detected"); expect_null(content$content)
  expect_false(grepl(secret, paste(readLines(path), collapse = "\n"), fixed = TRUE))
})

test_that("escaped credentials are discarded after JSON decoding including cached responses", {
  secret <- 'arbitrary-key-with-"quotes"-and-\\slashes'
  withr::local_envvar(TEST_PROVIDER_SECRET = secret)
  f <- run_provider_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f$provider$api_key_env <- "TEST_PROVIDER_SECRET"
  f$request$approved_payload_hash <- .sc_run_request_hash(f$request, f$provider)
  raw <- as.character(jsonlite::toJSON(list(operation = "keep_all", reason = secret), auto_unbox = TRUE))
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) raw)
  expect_identical(out$status, "secret_detected"); expect_null(out$raw)
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path)
  expect_null(ledger$entries[[1]]$raw); expect_null(ledger$entries[[1]]$content)
  # Simulate an older cache created before the configured environment was known.
  ledger$entries[[1]]$status <- "ok"
  ledger$entries[[1]]$raw <- raw
  ledger$entries[[1]]$response_hash <- .sc_run_provider_hash(raw)
  .sc_run_provider_write(ledger, path)
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_true(cached$cached); expect_identical(cached$status, "secret_detected")
  expect_null(cached$raw)
  ledger <- .sc_run_provider_read(path)
  expect_null(ledger$entries[[1]]$raw); expect_null(ledger$entries[[1]]$content)
})
