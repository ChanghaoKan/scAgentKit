test_that("provider defaults supply pricing without monetary policy fields", {
  p <- .sc_run_provider_defaults("deepseek")
  expect_equal(p$provider$pricing, list(cached_input_per_million = .006,
    input_per_million = .30, output_per_million = 1.20))
  expect_setequal(names(p), c("provider", "chat_fn"))
  expect_false(any(c("budget", "reservation_usd", "cost_mode") %in% names(p$provider)))
  custom <- list(name = "deepseek", pricing = list(input_per_million = .4,
    output_per_million = 1.3, cached_input_per_million = .01))
  expect_equal(.sc_run_provider_defaults(custom)$provider$pricing[names(custom$pricing)], custom$pricing)
  expect_null(.sc_run_provider_defaults(list(name = "deepseek", model = "another-model"))$provider$pricing)
  expect_null(.sc_run_provider_defaults(list(name = "deepseek", generation = list(max_tokens = 8192)))$provider$pricing)
  withr::local_envvar(c(DEEPSEEK_API_KEY = "", XAI_API_KEY = ""))
  x <- suppressMessages(.sc_start_provider_setup("deepseek"))
  expect_setequal(names(x), c("provider", "review"))
  expect_identical(x$provider$name, "deepseek"); expect_false(x$review$allow_external)
  consent <- list(mode = "project", confirmed = TRUE, reviewer = "offline",
    reason = "Review aggregate transfer.", categories = c("study_context", "aggregate_qc"))
  approved <- suppressMessages(.sc_start_provider_setup("deepseek",
    review = list(allow_external = TRUE, transfer_consent = consent)))
  expect_true(approved$review$allow_external)
})

test_that("provider defaults keep custom callbacks and obsolete amounts are rejected", {
  callback <- function(system_prompt, user_prompt) "offline callback"
  selected <- .sc_run_provider_defaults(callback)
  expect_identical(selected$chat_fn, callback)
  expect_identical(selected$provider$name, "custom")
  expect_null(selected$provider$pricing)
  for (name in c("sc_start", "sc_analyze", "sc_run", ".sc_start_provider_setup",
      ".sc_run_provider_defaults", ".sc_run_transfer_options", ".sc_run_call")) {
    expect_false(any(c("budget", "cost_mode") %in% names(formals(get(name)))))
  }
  expect_error(.sc_run_provider_defaults("deepseek", budget = 1), "unused argument")
  expect_error(.sc_start_provider_setup("deepseek", budget = 1), "unused argument")
  expect_error(sc_run(NULL, tempfile(), cost_mode = "posthoc"), "unused argument")
})

test_that("transfer consent binds recipient, categories and current receipt schema", {
  provider <- .sc_run_provider_defaults("deepseek")$provider
  consent <- list(mode = "project", confirmed = TRUE, reviewer = "offline",
    reason = "Confirm aggregate scope.", categories = c("study_context", "aggregate_qc",
      "aggregate_markers", "aggregate_design", "aggregate_expression"))
  config <- list(provider = provider, review = list(allow_external = TRUE,
    transfer_consent = .sc_run_transfer_options(consent, provider)))
  request <- .sc_run_request("strategy", list(), config)
  expect_true(.sc_run_transfer_authorized(request, config))
  expect_false("cost_mode" %in% names(config$review$transfer_consent))
  expect_false("cost_mode" %in% names(config$review$transfer_consent$react_scope))
  old <- config; old$review$transfer_consent$schema <- "scagentkit.transfer-consent.v1"
  old$review$transfer_consent$hash <- NULL
  old$review$transfer_consent$hash <- .sc_run_provider_hash(old$review$transfer_consent)
  expect_false(.sc_run_transfer_authorized(request, old))
  config$provider$model <- "other-model"
  expect_false(.sc_run_transfer_authorized(request, config))
})
