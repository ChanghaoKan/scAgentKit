provider_metadata_fixture <- function(external = FALSE) {
  root <- tempfile("provider-metadata-"); .sc_project_format_create(root)
  provider <- list(name = if (external) "testremote" else "mock", model = "fixture-model",
    external = external,
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

# The supported factory returns structured content, usage and safe metadata.
# Its HTTP execution is mocked in every caller of this helper.
provider_metadata_structured_factory <- function() {
  skip_if_not_installed("httr2")
  agentomicsCore::make_chat_fn_openai_compatible(
    base_url = "https://offline.invalid/v1", model = "fixture-model",
    api_key = "", api_key_env = "", supports_vision = FALSE,
    max_tokens = 64L, temperature = 0, timeout_secs = 5,
    structured_response = TRUE)
}
provider_metadata_http_fixture <- function(content = provider_metadata_json, finish = "stop", status = 200) {
  body <- if (status >= 400) list(id = "error-fixture-01",
    error = list(message = "Bearer fictional-sensitive-error-body")) else
    list(id = "chatcmpl-fixture-01", model = "fixture-model",
      choices = list(list(message = list(role = "assistant", content = content), finish_reason = finish)),
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
    out <- .sc_run_call(f$root, f$request, f$provider, fn, allow_external = TRUE)
    expect_identical(out$status, "truncated_response"); expect_null(out$content)
    expect_identical(out$raw, raw)
    expect_identical(out$response_audit$truncation, "provider_reported")
    expect_identical(out$response_audit$json_status,
      if (identical(raw, provider_metadata_json)) "ok" else "invalid_response")
    expect_identical(out$cost_state, "known"); expect_equal(out$cost_usd, 0.000024)
    expect_equal(out$usage$output_tokens, 7)
    cached <- .sc_run_call(f$root, f$request, f$provider)
    expect_true(cached$cached); expect_identical(cached$status, "truncated_response")
    expect_null(cached$content); expect_identical(calls, 1L)
    expect_length(.sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))$entries, 1L)
  }
})

test_that("content-only responses retain explicit unavailable metadata and a read-only cache", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) provider_metadata_json)
  expect_identical(out$response_metadata$availability, "unavailable")
  path <- file.path(f$root, "provider", "ledger.json")
  entry <- .sc_run_provider_read(path)$entries[[1]]
  expect_identical(entry$response_metadata$schema, "scagentkit.provider-response-metadata.v1")
  expect_identical(entry$response_metadata_hash, .sc_run_provider_hash(entry$response_metadata))
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

test_that("completed ledger entries require their metadata object and hash", {
  f <- provider_metadata_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  .sc_run_call(f$root, f$request, f$provider, function(...) provider_metadata_json)
  path <- file.path(f$root, "provider", "ledger.json")
  saved <- .sc_run_provider_read(path)
  for (fields in list("response_metadata", "response_metadata_hash",
      c("response_metadata", "response_metadata_hash"))) {
    ledger <- saved
    for (field in fields) ledger$entries[[1]][[field]] <- NULL
    .sc_run_provider_write(ledger, path)
    before <- readBin(path, "raw", file.info(path)$size)
    expect_error(.sc_run_provider_read(path), "metadata", info = paste(fields, collapse = ", "))
    expect_error(.sc_run_call(f$root, f$request, f$provider), "metadata")
    expect_identical(readBin(path, "raw", file.info(path)$size), before)
  }
  for (metadata in list("not an object", list(schema = "unsupported"))) {
    ledger <- saved
    ledger$entries[[1]]$response_metadata <- metadata
    ledger$entries[[1]]$response_metadata_hash <- .sc_run_provider_hash(metadata)
    .sc_run_provider_write(ledger, path)
    expect_error(.sc_run_provider_read(path), "metadata")
  }
})

test_that("durable dispatch requires metadata but allows an absent hash until settlement", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  withr::with_options(list(scAgentKit.provider_crash = "after_dispatch"),
    expect_error(.sc_run_call(f$root, f$request, f$provider, function(...) {
      calls <<- calls + 1L; provider_metadata_json
    }, allow_external = TRUE), "Injected provider interruption"))
  expect_identical(calls, 0L)
  path <- file.path(f$root, "provider", "ledger.json")
  saved <- .sc_run_provider_read(path)
  entry <- saved$entries[[1]]
  expect_identical(entry$status, "dispatched")
  expect_identical(entry$response_metadata$availability, "unavailable")
  expect_null(entry$response_metadata_hash)
  expect_identical(.sc_run_call(f$root, f$request, f$provider)$status, "delivery_uncertain")

  ledger <- saved
  ledger$entries[[1]]$response_metadata_hash <- .sc_run_provider_hash(entry$response_metadata)
  .sc_run_provider_write(ledger, path)
  expect_identical(.sc_run_provider_read(path)$entries[[1]]$status, "dispatched")
  ledger$entries[[1]]$response_metadata_hash <- strrep("0", 64)
  .sc_run_provider_write(ledger, path)
  expect_error(.sc_run_provider_read(path), "metadata hash mismatch")
  ledger <- saved; ledger$entries[[1]]$response_metadata <- NULL
  .sc_run_provider_write(ledger, path)
  expect_error(.sc_run_provider_read(path), "metadata")
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
  list(name = "mock", model = "fixture-model", external = FALSE,
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
  proposal <- list(schema = "scagentkit.qc.rules.v1", rationale = "Synthetic fixture review.",
    risks = list("No biological conclusion."),
    remove_if = "any", rules = list(list(op = "range", metric = "nCount", min = 1, max = NULL, group = NULL)))
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

test_that("all built-in single-request factories receive structured response settings", {
  captured <- list()
  callback <- function(...) provider_metadata_json
  factory <- function(name) {
    force(name)
    function(...) { captured[[name]] <<- list(...); callback }
  }
  testthat::local_mocked_bindings(
    chat_deepseek = factory("deepseek"), chat_grok = factory("grok"),
    make_chat_fn_openai_compatible = factory("openai_compatible"), .package = "agentomicsCore")
  for (name in c("deepseek", "grok", "openai_compatible")) {
    provider <- list(name = name, model = "fixture-model", api_key_env = "SCAGENTKIT_FACTORY_TEST_KEY",
      generation = list(max_tokens = 64L, temperature = 0.25, timeout_secs = 5, seed = 7L))
    if (name == "openai_compatible") provider$base_url <- "https://offline.invalid/v1"
    spec <- .sc_run_provider_spec(provider)
    expect_identical(.sc_run_provider_fn(spec), callback)
    args <- captured[[name]]
    expect_identical(args$structured_response, TRUE, info = name)
    expect_identical(args$model, "fixture-model")
    expect_identical(args$api_key_env, "SCAGENTKIT_FACTORY_TEST_KEY")
    expect_equal(args$max_tokens, 64); expect_equal(args$temperature, 0.25)
    expect_equal(args$timeout_secs, 5); expect_equal(args$extra_body$seed, 7)
    expect_identical(args$extra_body$response_format, list(type = "json_object"))
    if (name == "deepseek") expect_identical(args$extra_body$thinking, list(type = "disabled"))
    if (name == "grok") expect_identical(args$vision, FALSE)
    if (name == "openai_compatible") {
      expect_identical(args$base_url, provider$base_url)
      expect_identical(args$supports_vision, FALSE)
    }
  }
  expect_setequal(names(captured), c("deepseek", "grok", "openai_compatible"))
  expect_identical(.sc_run_provider_fn(.sc_run_provider_spec(chat_fn = callback)), callback)
})

test_that("current structured factory rejects mocked HTTP truncation without automatic resend", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  fn <- provider_metadata_structured_factory()
  token_env <- agentomicsCore::token_state; before <- token_env$records
  on.exit(token_env$records <- before, add = TRUE)
  calls <- 0L
  out <- httr2::with_mocked_responses(function(req) {
    calls <<- calls + 1L
    provider_metadata_http_fixture(finish = "length")
  }, .sc_run_call(f$root, f$request, f$provider, fn, allow_external = TRUE))
  expect_identical(out$status, "truncated_response"); expect_null(out$content)
  expect_equal(out$response_metadata$http_status, 200)
  expect_identical(out$response_metadata$finish_reason, "length")
  expect_identical(out$response_metadata$request_id, "request-fixture-01")
  expect_identical(out$response_metadata$response_id, "chatcmpl-fixture-01")
  expect_identical(out$cost_state, "known"); expect_equal(out$cost_usd, 0.000024)
  expect_equal(out$usage$output_tokens, 7)
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_identical(cached$status, "truncated_response"); expect_true(cached$cached)
  expect_identical(calls, 1L)
  expect_false(grepl("fictional-sensitive-response-header", .sc_run_provider_json(out), fixed = TRUE))
})

test_that("current structured factory reports received HTTP errors without copying body or headers", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  fn <- provider_metadata_structured_factory()
  calls <- 0L
  out <- httr2::with_mocked_responses(function(req) {
    calls <<- calls + 1L
    provider_metadata_http_fixture(status = 429)
  }, .sc_run_call(f$root, f$request, f$provider, fn, allow_external = TRUE))
  expect_identical(out$status, "provider_response_error")
  expect_identical(out$delivery, "received")
  expect_equal(out$response_metadata$http_status, 429)
  expect_identical(out$response_metadata$request_id, "request-fixture-01")
  expect_identical(out$cost_state, "unknown"); expect_null(out$cost_usd)
  expect_null(out$raw); expect_null(out$content)
  json <- paste(readLines(file.path(f$root, "provider", "ledger.json")), collapse = "\n")
  expect_false(grepl("fictional-sensitive|error.message|authorization", json))
  cached <- .sc_run_call(f$root, f$request, f$provider)
  expect_true(cached$cached); expect_identical(cached$status, "provider_response_error")
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn,
    allow_external = TRUE, retry = TRUE)$status, "retry_refused")
  expect_identical(calls, 1L)
})

test_that("current structured transport failure retains unknown delivery without resend", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  fn <- provider_metadata_structured_factory()
  calls <- 0L
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls <<- calls + 1L; stop("fictional-sensitive-transport-detail")
  }, .package = "httr2")
  out <- .sc_run_call(f$root, f$request, f$provider, fn, allow_external = TRUE)
  expect_identical(out$status, "delivery_uncertain")
  expect_identical(out$delivery, "unknown")
  expect_identical(out$cost_state, "unknown"); expect_null(out$cost_usd)
  expect_true(.sc_run_call(f$root, f$request, f$provider, fn, allow_external = TRUE)$cached)
  expect_identical(.sc_run_call(f$root, f$request, f$provider, fn,
    allow_external = TRUE, retry = TRUE)$status, "retry_refused")
  expect_identical(calls, 1L)
  expect_false(grepl("fictional-sensitive", .sc_run_provider_json(out), fixed = TRUE))
})

test_that('raw usage retains provider numeric details but excludes arbitrary secrets', {
 raw <- list(prompt_tokens=10,completion_tokens=7,total_tokens=17,
  prompt_cache_hit_tokens=2,prompt_cache_miss_tokens=8,
  completion_tokens_details=list(reasoning_tokens=3),authorization='Bearer never-persist',
  prompt_tokens_details=list(cached_tokens=2,secret='do-not-copy'))
 safe <- .sc_run_provider_raw_usage(raw)
 expect_equal(safe$prompt_tokens,10)
 expect_equal(safe$completion_tokens_details$reasoning_tokens,3)
 expect_equal(safe$prompt_tokens_details,list(cached_tokens=2))
 expect_null(safe$authorization)
 expect_false(grepl('never-persist|do-not-copy|secret',jsonlite::toJSON(safe)))
 f<-provider_metadata_fixture();on.exit(unlink(f$root,recursive=TRUE))
 out<-.sc_run_call(f$root,f$request,f$provider,function(...)list(content=provider_metadata_json,raw_usage=raw))
 expect_identical(out$raw_usage,safe)
 expect_equal(.sc_run_provider_read(file.path(f$root,'provider','ledger.json'))$entries[[1]]$raw_usage,safe)
})

test_that("current structured factory retains raw numeric usage without HTTP headers", {
  fn <- provider_metadata_structured_factory()
  token_env <- agentomicsCore::token_state; before <- token_env$records
  on.exit(token_env$records <- before, add = TRUE)
  value <- httr2::with_mocked_responses(function(req) provider_metadata_http_fixture(),
    fn("Offline system.", "Offline user."))
  expect_equal(value$raw_usage, list(prompt_tokens = 10, completion_tokens = 7, prompt_cache_hit_tokens = 2))
  expect_false(grepl("fictional-sensitive|authorization", .sc_run_provider_json(value)))
})

test_that("raw usage scalar attributes cannot persist private environments", {
  private <- new.env(); private$key <- "PRIVATE_USAGE_ATTRIBUTE_TEST"
  safe <- .sc_run_provider_raw_usage(list(prompt_tokens = structure(10, secret = private)))
  expect_null(attributes(safe$prompt_tokens))
  expect_false(grepl("PRIVATE_USAGE_ATTRIBUTE_TEST", rawToChar(serialize(safe, NULL, ascii = TRUE)), fixed = TRUE))
})

test_that("received text errors preserve delivery and usage accounting", {
  f <- provider_metadata_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  failure <- structure(list(message = "Do not preserve private HTTP body", call = NULL,
    delivery = "received", code = "invalid_response", usage = list(input_tokens = 10, output_tokens = 7),
    raw_usage = list(prompt_tokens = 10, completion_tokens = 7),
    metadata = list(http_status = 200, request_id = "received-text-fixture")),
    class = c("agentomics_turn_error", "error", "condition"))
  out <- .sc_run_call(f$root, f$request, f$provider, function(...) stop(failure), allow_external = TRUE)
  expect_identical(out$delivery, "received")
  expect_identical(out$status, "provider_response_error")
  expect_identical(out$response_audit$json_status, "received_invalid")
  expect_identical(out$cost_state, "known"); expect_equal(out$cost_usd, .000024)
  expect_equal(out$response_metadata$http_status, 200)
  expect_false(grepl("private HTTP", out$error, fixed = TRUE))
  expect_true(.sc_run_call(f$root, f$request, f$provider, allow_external = TRUE)$cached)
})
