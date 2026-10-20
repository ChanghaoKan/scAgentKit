compatible_provider <- function() list(name = "openai_compatible", model = "offline-fixture",
  base_url = "https://provider.invalid/v1", api_key_env = "SCAGENTKIT_COMPATIBLE_TEST_KEY",
  pricing = list(input_per_million = 1, output_per_million = 2))
compatible_request <- function(provider) {
  request <- list(system_prompt = "Return a JSON object.",
    user_prompt = "Public aggregate: 80 cells.", purpose = "strategy")
  request$approved_payload_hash <- .sc_run_request_hash(request, provider)
  request
}

test_that("generic endpoint is explicit, credential free and bound to exact consent", {
  provider <- compatible_provider()
  metadata <- .sc_run_provider_spec(provider)$metadata
  expect_identical(metadata$base_url, provider$base_url)
  expect_true(metadata$external)
  expect_identical(.sc_run_provider_spec(metadata)$metadata, metadata)
  expect_null(.sc_run_provider_spec("deepseek")$metadata$base_url)
  for (url in c("http://provider.invalid/v1", "https://user:password@provider.invalid/v1",
      "https://provider.invalid/v1?key=secret", "https://provider.invalid/#secret", "https://127.0.0.1/v1")) {
    changed <- provider; changed$base_url <- url
    expect_error(.sc_run_provider_spec(changed), "HTTPS hostname")
  }
  for (field in c("model", "api_key_env", "base_url")) {
    changed <- provider; changed[[field]] <- NULL
    expect_error(.sc_run_provider_spec(changed))
  }
  request <- compatible_request(provider)
  for (field in c("base_url", "api_key_env", "model")) {
    changed <- provider
    changed[[field]] <- switch(field, base_url = "https://other.invalid/v1",
      api_key_env = "SCAGENTKIT_OTHER_TEST_KEY", model = "other-model")
    expect_false(identical(.sc_run_request_hash(request, changed), request$approved_payload_hash))
  }
  changed <- provider; changed$external <- FALSE
  expect_error(.sc_run_provider_spec(changed), "external")
})

test_that("generic provider retains no-key, budget and exact-transfer barriers", {
  withr::local_envvar(c(SCAGENTKIT_COMPATIBLE_TEST_KEY = ""))
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  provider <- compatible_provider(); request <- compatible_request(provider)
  expect_identical(.sc_run_call(root, request, provider, budget = 1)$status, "awaiting_external_approval")
  expect_identical(.sc_run_call(root, request, provider, budget = .01, allow_external = TRUE)$status, "budget_stop")
  expect_identical(.sc_run_call(root, request, provider, budget = 1, allow_external = TRUE)$status, "needs_provider")
  expect_length(.sc_run_provider_read(file.path(root, "provider", "ledger.json"))$entries, 0)
  changed <- provider; changed$base_url <- "https://other.invalid/v1"
  calls <- 0L
  expect_identical(.sc_run_call(root, request, changed, function(...) {
    calls <<- calls + 1L; '{"valid":true}'
  }, budget = 1, allow_external = TRUE)$status, "awaiting_external_approval")
  expect_identical(calls, 0L)
})

test_that("existing agentomicsCore generic factory works with mocked HTTP only", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("agentomicsCore")
  withr::local_envvar(c(SCAGENTKIT_COMPATIBLE_TEST_KEY = "synthetic-compatible-fixture-secret"))
  calls <- 0L; content <- '{"valid":true}'
  testthat::local_mocked_bindings(req_perform = function(req, ...) {
    calls <<- calls + 1L
    expect_identical(req$url, "https://provider.invalid/v1/chat/completions")
    httr2::response(status_code = 200, method = "POST", url = req$url,
      headers = list(`content-type` = "application/json"),
      body = charToRaw(as.character(jsonlite::toJSON(list(id = "fixture-response",
        choices = list(list(message = list(role = "assistant", content = content), finish_reason = "stop")),
        usage = list(prompt_tokens = 10, completion_tokens = 5)), auto_unbox = TRUE))))
  }, .package = "httr2")
  provider <- compatible_provider(); request <- compatible_request(provider)
  for (valid in c(TRUE, FALSE)) {
    root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
    content <- if (valid) '{"valid":true}' else '{invalid JSON'
    answer <- .sc_run_call(root, request, provider, budget = 1, allow_external = TRUE)
    expect_identical(answer$status, if (valid) "ok" else "invalid_response")
    expect_identical(answer$response_metadata$finish_reason, "stop")
    expect_false(grepl("synthetic-compatible-fixture-secret", paste(readLines(
      file.path(root, "provider", "ledger.json")), collapse = ""), fixed = TRUE))
    cached <- .sc_run_call(root, request, provider, budget = 0)
    expect_true(cached$cached)
  }
  expect_identical(calls, 2L)
})
