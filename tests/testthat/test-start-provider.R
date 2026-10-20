start_provider_clean_environment <- function() {
  withr::local_envvar(c(DEEPSEEK_API_KEY = "", XAI_API_KEY = "",
    SCAGENTKIT_START_TEST_KEY = ""), .local_envir = parent.frame())
}

test_that("startup detects one vendor and otherwise remains visibly manual", {
  start_provider_clean_environment()
  expect_message(x <- .sc_start_provider_setup(), "Manual mode")
  expect_identical(x$provider$name, "manual"); expect_equal(x$budget, 0)
  withr::local_envvar(c(DEEPSEEK_API_KEY = "synthetic-deepseek-fixture"))
  expect_message(x <- .sc_start_provider_setup(budget = .2, review = list(allow_external = TRUE)), NA)
  expect_identical(x$provider$name, "deepseek"); expect_equal(x$budget, .2)
  expect_true(x$review$allow_external)
  withr::local_envvar(c(XAI_API_KEY = "synthetic-grok-fixture"))
  messages <- capture.output(x <- .sc_start_provider_setup(), type = "message")
  expect_true(any(grepl("More than one provider key", messages)))
  expect_identical(x$provider$name, "manual")
  expect_message(x <- .sc_start_provider_setup("grok", budget = .1,
    review = list(allow_external = TRUE)), NA)
  expect_identical(x$provider$name, "grok")
  expect_false(grepl("synthetic-", .sc_run_provider_json(x), fixed = TRUE))
})

test_that("missing key and zero budget have explicit manual next steps", {
  start_provider_clean_environment()
  messages <- capture.output(x <- .sc_start_provider_setup("deepseek", budget = 1,
    review = list(allow_external = TRUE)), type = "message")
  expect_true(any(grepl("No key is available in DEEPSEEK_API_KEY", messages)))
  expect_identical(x$provider$name, "manual"); expect_equal(x$budget, 0)
  expect_false(x$review$allow_external)
  provider <- list(name = "openai_compatible", base_url = "https://offline.invalid/v1",
    model = "offline-model", api_key_env = "SCAGENTKIT_START_TEST_KEY")
  expect_message(x <- .sc_start_provider_setup(provider), "No key")
  expect_identical(x$provider$name, "manual")
  withr::local_envvar(c(DEEPSEEK_API_KEY = "synthetic-deepseek-fixture"))
  messages <- capture.output(x <- .sc_start_provider_setup(), type = "message")
  expect_false(any(grepl("budget is zero", messages)))
  expect_true(any(grepl("External transfer is disabled", messages)))
  expect_equal(x$budget, 1); expect_false(x$review$allow_external)
  expect_error(.sc_start_provider_setup(budget = -1), "budget")
  expect_error(.sc_start_provider_setup(review = list(preapprove_qc = TRUE)), "Startup review")
  expect_error(.sc_start_provider_setup(review = list(allow_external = "yes")), "Startup review")
})

test_that("reopening cannot silently replace saved provider or transfer policy", {
  start_provider_clean_environment()
  saved <- list(provider = .sc_run_provider_spec("deepseek")$metadata,
    budget = .2, review = list(allow_external = TRUE))
  # Saved project opens without the key, keeping the immutable provider facts.
  expect_identical(.sc_start_provider_setup(saved = saved), saved)
  expect_identical(.sc_start_provider_setup("deepseek", .2,
    list(allow_external = TRUE), saved), saved)
  expect_error(.sc_start_provider_setup("grok", saved = saved), "saved provider")
  expect_error(.sc_start_provider_setup(budget = .3, saved = saved), "saved provider")
  expect_error(.sc_start_provider_setup(budget = 1, saved = saved), "saved provider")
  expect_error(.sc_start_provider_setup(review = list(allow_external = FALSE), saved = saved), "saved provider")
})

test_that("creation displays the bounded annotation scope without another confirmation", {
  start_provider_clean_environment()
  review <- list(allow_external = TRUE, transfer_consent = list(mode = "project",
    confirmed = TRUE, reviewer = "fixture", reason = "Review aggregate transfer and cost.",
    categories = c("study_context", "aggregate_qc", "aggregate_markers",
      "aggregate_design", "aggregate_expression")))
  text <- paste(capture.output(value <- .sc_start_provider_setup(
    list(name = "mock", model = "offline"), budget = .8, review = review),
    type = "message"), collapse = " ")
  expect_match(text, "USD 0.8", fixed = TRUE)
  expect_match(text, "6 turns per cluster, 60 turns per session", fixed = TRUE)
  expect_match(text, "cluster_markers", fixed = TRUE)
  expect_match(text, "Saving a draft never approves it", fixed = TRUE)
  expect_match(text, "no monetary cap", fixed = TRUE)
  expect_identical(value$review, review)
  expect_equal(value$budget, .8)
})
