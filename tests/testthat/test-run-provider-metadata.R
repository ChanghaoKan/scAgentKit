provider_metadata_fixture <- function(external = FALSE) {
  root <- tempfile("provider-metadata-"); dir.create(root)
  provider <- list(name = if (external) "testremote" else "mock", model = "fixture-model",
    external = external, reservation_usd = if (external) 0.05 else 0,
    generation = list(max_tokens = 64L))
  if (external) provider$pricing <- list(input_per_million = 1, output_per_million = 2)
  request <- list(system_prompt = "Return one typed QC decision.",
    user_prompt = "Public synthetic aggregate: 10 cells.", purpose = "qc",
    validator = function(x) {
      .decision_object(x, c("operation", "reason"))
      .decision_string(x$operation, "operation", "keep_all")
      .decision_string(x$reason, "reason")
      x
    })
  request$approved_payload_hash <- .sc_run_request_hash(request, provider)
  list(root = root, provider = provider, request = request)
}
provider_metadata_json <- '{"operation":"keep_all","reason":"Offline metadata fixture."}'

# Evaluate only the returned function expression from the installed constructor.
# The constructor, its environment-key reader and provider factories are never
# invoked. All variables here are synthetic, and httr2 is mocked before calls.
provider_metadata_legacy_closure <- function() {
  skip_if_not_installed("agentomicsCore")
  skip_if_not_installed("httr2")
  skip_if_not(packageVersion("agentomicsCore") == "0.1.1")
  constructor <- getExportedValue("agentomicsCore", "make_chat_fn_openai_compatible")
  expression <- tail(as.list(body(constructor)), 1L)[[1L]]
  fixture <- list2env(list(base_url = "https://offline.invalid/v1", model = "fixture-model",
    needs_key = FALSE, supports_vision = FALSE, warned_image = FALSE, max_tokens = 64L,
    temperature = 0, timeout_secs = 5, extra_body = NULL, extra_headers = NULL),
    parent = asNamespace("agentomicsCore"))
  eval(expression, envir = fixture)
}
provider_metadata_http_fixture <- function(content = provider_metadata_json, finish = "stop", status = 200) {
  body <- if (status >= 400) list(id = "error-fixture-01",
    error = list(message = "Bearer fictional-sensitive-error-body")) else
    list(id = "chatcmpl-fixture-01", model = "fixture-model",
      choices = list(list(message = list(content = content), finish_reason = finish)),
      usage = list(prompt_tokens = 10, completion_tokens = 7, prompt_cache_hit_tokens = 2))
  httr2::response(status_code = status, method = "POST",
    url = "https://offline.invalid/v1/chat/completions",
    headers = list(`content-type` = "application/json", `x-request-id` = "request-fixture-01",
      authorization = "Bearer fictional-sensitive-response-header"),
    body = charToRaw(as.character(jsonlite::toJSON(body, auto_unbox = TRUE))))
}

test_that("larger default cap preserves explicit user generation caps", {
  expect_equal(.sc_run_provider_spec("deepseek")$metadata$generation$max_tokens, 4096)
  expect_equal(.sc_run_provider_spec(list(name = "mock", generation = list(max_tokens = 1200L)))$
    metadata$generation$max_tokens, 1200)
})

test_that("structured metadata is allowlisted and unknown values never reach ledger", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  fn <- function(...) list(content = provider_metadata_json, finish_reason = "stop",
    http_status = 200, request_id = "request-safe-01", id = "response-safe-01",
    headers = list(authorization = "Bearer fictional-sensitive-header"),
    response_metadata = list(finish_reason = "stop", raw_body = "untrusted-body-marker",
      arbitrary = "untrusted-field-marker"))
  out <- .sc_run_call(f$root, f$request, f$provider, fn)
  expect_identical(out$status, "ok")
  expect_identical(names(out$response_metadata), c("schema", "availability", "finish_reason",
    "http_status", "request_id", "response_id"))
  expect_identical(out$response_metadata$availability, "available")
  expect_equal(out$response_metadata$http_status, 200)
  expect_identical(out$response_metadata$request_id, "request-safe-01")
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("fictional-sensitive|untrusted-body|untrusted-field|authorization", json))
  invalid <- .sc_run_provider_response_metadata(list(finish_reason = "untrusted-finish-marker",
    http_status = "200", request_id = "Bearer fictional-secret", id = list(not = "scalar")))
  expect_identical(invalid$availability, "unavailable")
  expect_null(invalid$finish_reason); expect_null(invalid$http_status)
  expect_null(invalid$request_id); expect_null(invalid$response_id)
})

test_that("finish reason length rejects even complete JSON and preserves accounting and cache", {
  for (raw in c('{"operation":"keep_all","reason":"unfinished', provider_metadata_json)) {
    f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    calls <- 0L
    fn <- function(...) {
      calls <<- calls + 1L
      list(content = raw, finish_reason = "length", http_status = 200, request_id = "request-01",
        usage = list(input_tokens = 10, output_tokens = 7, cached_tokens = 2))
    }
    out <- .sc_run_call(f$root, f$request, f$provider, fn, budget = 1, allow_external = TRUE)
    expect_identical(out$status, "truncated_response"); expect_null(out$content)
    expect_identical(out$raw, raw)
    expect_identical(out$response_audit$truncation, "provider_reported")
    expect_identical(out$response_audit$json_status,
      if (identical(raw, provider_metadata_json)) "ok" else "invalid_response")
    expect_identical(out$cost_state, "known"); expect_equal(out$cost_usd, 0.000024)
    expect_equal(out$usage$output_tokens, 7)
    cached <- .sc_run_call(f$root, f$request, f$provider, budget = 0)
    expect_true(cached$cached); expect_identical(cached$status, "truncated_response")
    expect_null(cached$content); expect_identical(calls, 1L)
    expect_length(.sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))$entries, 1L)
  }
})

test_that("old ledger metadata is unknown and invalid JSON is never repaired", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) provider_metadata_json)
  expect_identical(out$response_metadata$availability, "unavailable")
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path)
  ledger$entries[[1]]$response_metadata <- NULL
  ledger$entries[[1]]$response_metadata_hash <- NULL
  ledger$entries[[1]]$response_audit <- NULL
  .sc_run_provider_write(ledger, path)
  before <- readBin(path, "raw", file.info(path)$size)
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_true(cached$cached); expect_identical(cached$status, "ok")
  expect_identical(cached$response_metadata$availability, "unavailable")
  expect_identical(readBin(path, "raw", file.info(path)$size), before)
  truncated <- .sc_run_provider_response_result('{"operation":"keep_all"', usage = list(output_tokens = 64), max_tokens = 64)
  expect_identical(truncated$status, "invalid_response"); expect_null(truncated$content)
  expect_identical(truncated$response_audit$truncation, "suspected_output_cap")
  expect_null(truncated$response_metadata$finish_reason)
})

test_that("cached response metadata changes are detected", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  .sc_run_call(f$root, f$request, f$provider,
    function(...) list(content = provider_metadata_json, finish_reason = "length"))
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path)
  ledger$entries[[1]]$response_metadata$finish_reason <- "stop"
  .sc_run_provider_write(ledger, path)
  expect_error(.sc_run_call(f$root, f$request, f$provider), "metadata hash mismatch")
})

test_that("character metadata attributes are supported without copying other attributes", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  response <- structure(provider_metadata_json, response_metadata = list(finish_reason = "stop",
    status_code = 201, request_id = "request-attr-01"), headers = "fictional-sensitive-header")
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) response)
  expect_identical(out$status, "ok"); expect_equal(out$response_metadata$http_status, 201)
  expect_identical(out$response_metadata$request_id, "request-attr-01")
  expect_null(attributes(out$raw))
  snapshot <- tempfile(fileext = ".rds"); on.exit(unlink(snapshot), add = TRUE)
  saveRDS(out, snapshot)
  expect_false(grepl("fictional-sensitive-header", .sc_run_provider_json(readRDS(snapshot)), fixed = TRUE))
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("fictional-sensitive-header", json, fixed = TRUE))
})

test_that("metadata scalar attributes cannot enter coordinator RDS snapshots", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  private_fixture <- new.env(parent = emptyenv())
  private_fixture$marker <- "PRIVATE_METADATA_ATTRIBUTE_FIXTURE"
  with_private_attribute <- function(x) structure(x, private_fixture = private_fixture)
  response <- list(content = provider_metadata_json,
    finish_reason = with_private_attribute("stop"),
    http_status = with_private_attribute(200L),
    request_id = with_private_attribute("request-safe-01"),
    id = with_private_attribute("response-safe-01"))
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) response)
  expect_identical(out$status, "ok")
  expected <- list(schema = "scagentkit.provider-response-metadata.v1",
    availability = "available", finish_reason = "stop", http_status = 200L,
    request_id = "request-safe-01", response_id = "response-safe-01")
  expect_identical(out$response_metadata, expected)
  for (field in c("finish_reason", "http_status", "request_id", "response_id"))
    expect_null(attributes(out$response_metadata[[field]]), info = field)
  snapshot <- tempfile(fileext = ".rds"); on.exit(unlink(snapshot), add = TRUE)
  saveRDS(out, snapshot)
  restored <- readRDS(snapshot)
  expect_identical(restored$response_metadata, expected)
  expect_false(grepl("PRIVATE_METADATA_ATTRIBUTE_FIXTURE",
    rawToChar(serialize(restored, NULL, ascii = TRUE)), fixed = TRUE))
})

provider_metadata_attribute_fixture <- function(value) {
  private_fixture <- new.env(parent = emptyenv())
  private_fixture$marker <- "PRIVATE_CONFIG_ATTRIBUTE_FIXTURE"
  private_function <- function() marker
  environment(private_function) <- private_fixture
  attach <- function(x) {
    if (is.null(x)) return(NULL)
    if (is.list(x)) {
      x <- lapply(x, attach)
    } else if (length(x) == 1L) names(x) <- "fixture-scalar-name"
    structure(x, private_fixture = list(marker = private_fixture$marker,
      environment = private_fixture, callback = private_function))
  }
  list(value = attach(value), marker = private_fixture$marker)
}

provider_metadata_config_fixture <- function() {
  list(name = "mock", model = "fixture-model", external = FALSE, reservation_usd = 0,
    api_key_env = "SCAGENTKIT_ATTRIBUTE_FIXTURE_KEY",
    pricing = list(input_per_million = 1, output_per_million = 2,
      cached_input_per_million = 0.5),
    generation = list(temperature = 0.25, max_tokens = 64L, timeout_secs = 5,
      seed = 7L, top_p = 0.75, frequency_penalty = 0, presence_penalty = 0.1,
      thinking = list(type = "enabled"), response_format = list(type = "json_object"),
      reasoning_effort = "low"))
}

test_that("provider configuration attributes are discarded without changing values or inputs", {
  plain <- provider_metadata_config_fixture()
  fixture <- provider_metadata_attribute_fixture(plain)
  before <- serialize(fixture$value, NULL, version = 2L)
  expected <- .sc_run_provider_spec(plain)$metadata
  metadata <- .sc_run_provider_spec(fixture$value)$metadata
  expect_identical(metadata, expected)
  expect_identical(.sc_run_provider_json(metadata), .sc_run_provider_json(expected))
  request <- list(system_prompt = "Return JSON.", user_prompt = "Public synthetic aggregate.")
  expect_identical(.sc_run_request_hash(request, fixture$value), .sc_run_request_hash(request, plain))
  expect_identical(serialize(fixture$value, NULL, version = 2L), before)
  expect_false(grepl(fixture$marker, rawToChar(serialize(metadata, NULL, ascii = TRUE)), fixed = TRUE))

  invalid <- plain; invalid$endpoint <- "https://offline.invalid/v1"
  expect_error(.sc_run_provider_spec(invalid), "configuration accepts only")
  invalid <- plain; invalid$external <- "FALSE"
  expect_error(.sc_run_provider_spec(invalid), "external.*TRUE or FALSE")
  invalid <- plain; invalid$generation$max_tokens <- "64"
  expect_error(.sc_run_provider_spec(invalid), "Invalid provider max_tokens")
  invalid <- plain; invalid$generation$thinking <- list(type = "unsupported")
  expect_error(.sc_run_provider_spec(invalid), "Unsupported provider thinking")
  invalid <- plain; invalid$generation$reasoning_effort <- function() "low"
  expect_error(.sc_run_provider_spec(invalid), "Unsupported reasoning_effort")
})

test_that("provider configuration attributes cannot reach real run state or export projections", {
  root <- tempfile("provider-config-state-"); on.exit(unlink(root, recursive = TRUE))
  fixture <- provider_metadata_attribute_fixture(provider_metadata_config_fixture())
  before <- serialize(fixture$value, NULL, version = 2L)
  counts <- matrix(rep(c(1L, 3L, 5L, 2L), 8L), nrow = 4L,
    dimnames = list(c("MT-CO1", "GENE2", "GENE3", "GENE4"), paste0("fixture-cell-", 1:8)))
  counts <- Matrix::Matrix(counts, sparse = TRUE)
  input_before <- serialize(counts, NULL, version = 2L)
  proposal <- list(schema = "scagentkit.qc.v1", rationale = "Synthetic fixture review.",
    risks = list("No biological conclusion."),
    filters = list(list(op = "range", metric = "nCount", min = 1, max = NULL, group = NULL)))
  calls <- 0L
  out <- sc_run(counts, root, context = list(species = "human"), provider = fixture$value,
    chat_fn = function(...) { calls <<- calls + 1L; .sc_run_provider_json(proposal) })
  expect_identical(out$status, "awaiting_review"); expect_identical(calls, 1L)
  state <- .sc_run_load(root)
  expected <- .sc_run_provider_spec(provider_metadata_config_fixture())$metadata
  expect_identical(state$config$provider, expected)
  expect_identical(.sc_run_get(root, state, "qc_response")$provider, expected)
  received <- Filter(function(event) identical(event$action, "proposal_received"), state$history)
  expect_length(received, 1L)
  expect_identical(received[[1L]]$details$provider, expected)
  expect_identical(serialize(fixture$value, NULL, version = 2L), before)
  expect_identical(serialize(counts, NULL, version = 2L), input_before)

  # Use the same projection and serializer as final coordinator exports without
  # approving QC or starting analysis solely for this persistence regression.
  .sc_run_atomic(state$config, file.path(root, "output", "parameters.json"), json = TRUE)
  projection <- .sc_run_annotation_review_provider(state$config$provider)
  expect_identical(projection, .sc_run_annotation_review_provider(expected))
  expect_false(grepl(fixture$marker, rawToChar(serialize(projection, NULL, ascii = TRUE)), fixed = TRUE))
  for (path in list.files(root, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE))
    expect_false(grepl(fixture$marker, rawToChar(serialize(readRDS(path), NULL, ascii = TRUE)), fixed = TRUE),
      info = basename(path))
  for (path in list.files(root, pattern = "\\.json$", recursive = TRUE, full.names = TRUE))
    expect_false(grepl(fixture$marker, paste(readLines(path, warn = FALSE), collapse = "\n"), fixed = TRUE),
      info = basename(path))
})

test_that("validator result attributes are discarded before returning and saving content", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  plain <- list(operation = "keep_all", reason = "Offline metadata fixture.",
    audit = list(values = list(7L, 0.5, TRUE, "safe", NULL), vector = c(1L, 2L)))
  fixture <- provider_metadata_attribute_fixture(plain)
  before <- serialize(fixture$value, NULL, version = 2L)
  f$request$validator <- function(x) fixture$value
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) provider_metadata_json)
  expect_identical(out$status, "ok"); expect_identical(out$content, plain)
  expect_identical(serialize(fixture$value, NULL, version = 2L), before)
  snapshot <- file.path(f$root, "validator-snapshot.rds")
  .sc_run_atomic(out, snapshot)
  restored <- readRDS(snapshot)
  expect_identical(restored$content, plain)
  expect_false(grepl(fixture$marker, rawToChar(serialize(restored, NULL, ascii = TRUE)), fixed = TRUE))
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl(fixture$marker, json, fixed = TRUE))
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_true(cached$cached); expect_identical(cached$content, plain)
  expect_false(grepl(fixture$marker, rawToChar(serialize(cached, NULL, ascii = TRUE)), fixed = TRUE))
  expect_identical(serialize(fixture$value, NULL, version = 2L), before)
  expect_identical(.sc_run_provider_parse(provider_metadata_json,
    validator = function(x) structure(x, class = "unsupported"))$status, "invalid_response")
  expect_identical(.sc_run_provider_parse(provider_metadata_json,
    validator = function(x) list(callback = function() NULL))$status, "invalid_response")
})

test_that("guarded 0.1.1 adapter preserves transport formals and captures only allowed HTTP metadata", {
  original <- provider_metadata_legacy_closure()
  original_body <- body(original)
  adapted <- .sc_run_provider_adapter(original, version = "0.1.1")
  expect_identical(formals(adapted), formals(original)); expect_identical(body(original), original_body)
  token_env <- agentomicsCore::token_state; before <- token_env$records
  on.exit(token_env$records <- before, add = TRUE)
  requests <- list()
  fixture <- provider_metadata_http_fixture()
  result <- httr2::with_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    fixture
  }, list(original("system", "user"), adapted("system", "user")))
  expect_identical(as.character(result[[1]]), as.character(result[[2]]))
  expect_length(requests, 2L)
  for (field in c("url", "method", "headers", "body", "options"))
    expect_identical(requests[[1]][[field]], requests[[2]][[field]], info = field)
  metadata <- attr(result[[2]], "response_metadata", exact = TRUE)
  expect_equal(metadata$http_status, 200)
  expect_identical(metadata$finish_reason, "stop")
  expect_identical(metadata$request_id, "request-fixture-01")
  expect_identical(metadata$response_id, "chatcmpl-fixture-01")
  expect_false(grepl("fictional-sensitive-response-header", .sc_run_provider_json(metadata), fixed = TRUE))
  expect_error(.sc_run_provider_adapter(original, version = "future-unrecognized"), "does not recognize")
  expect_error(.sc_run_provider_adapter(function(...) "wrong shape", version = "0.1.1"), "does not recognize")
})

test_that("mock HTTP adapter length response is not accepted or automatically sent again", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  adapted <- .sc_run_provider_adapter(provider_metadata_legacy_closure(), version = "0.1.1")
  token_env <- agentomicsCore::token_state; before <- token_env$records
  on.exit(token_env$records <- before, add = TRUE)
  calls <- 0L
  out <- httr2::with_mocked_responses(function(req) {
    calls <<- calls + 1L
    provider_metadata_http_fixture(finish = "length")
  }, .sc_run_call(f$root, f$request, f$provider, adapted, 1, TRUE))
  expect_identical(out$status, "truncated_response"); expect_null(out$content)
  expect_equal(out$response_metadata$http_status, 200)
  expect_identical(out$response_metadata$finish_reason, "length")
  expect_identical(out$cost_state, "known"); expect_equal(out$cost_usd, 0.000024)
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_identical(cached$status, "truncated_response"); expect_true(cached$cached)
  expect_identical(calls, 1L)
})

test_that("HTTP error status survives as safe typed error while body and usage stay conservative", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  adapted <- .sc_run_provider_adapter(provider_metadata_legacy_closure(), version = "0.1.1")
  calls <- 0L
  out <- httr2::with_mocked_responses(function(req) {
    calls <<- calls + 1L
    provider_metadata_http_fixture(status = 429)
  }, .sc_run_call(f$root, f$request, f$provider, adapted, 1, TRUE))
  expect_identical(out$status, "delivery_uncertain")
  expect_equal(out$response_metadata$http_status, 429)
  expect_identical(out$response_metadata$request_id, "request-fixture-01")
  expect_identical(out$cost_state, "unknown"); expect_equal(out$charged_or_held_usd, 0.05)
  expect_null(out$raw); expect_null(out$content)
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("fictional-sensitive|error.message|authorization", json))
  expect_identical(.sc_run_call(f$root, f$request, f$provider, adapted, 1, TRUE, retry = TRUE)$status, "retry_refused")
  expect_identical(calls, 1L)
})
