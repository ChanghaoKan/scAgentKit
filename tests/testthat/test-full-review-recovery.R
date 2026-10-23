test_that("lost or rolled-back ledgers recover committed turns without dispatch", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  calls <- 0L
  fn <- function(...) {calls <<- calls + 1L; turn_reply()}
  withr::with_options(list(scAgentKit.provider_crash = "after_turn_commit"),
    expect_error(turn_call(f, fn = fn), "committed response"))
  ledger_path <- file.path(f$root, "provider", "ledger.json")
  unlink(ledger_path)
  one <- turn_call(f, fn = fn)
  expect_true(one$cached); expect_identical(one$status, "ok"); expect_equal(calls, 1L)
  request <- .sc_run_turn_request(f$session, list(list(role = "user", content = "Cluster 1.")),
    "1", 2L, one$turn_response_hash)
  two <- turn_call(f, request, fn)
  ledger <- .sc_run_provider_read(ledger_path)
  ledger$entries <- ledger$entries[2L] # Surviving suffix: recovery must restore sequence as well as rows.
  .sc_run_provider_write(ledger, ledger_path)
  expect_true(turn_call(f, fn = fn)$cached)
  next_request <- .sc_run_turn_request(f$session,
    c(f$request$messages, list(one$turn_response$message, list(role = "user", content = "Review this aggregate again."))),
    "0", 3L, two$turn_response_hash)
  expect_identical(turn_call(f, next_request, fn)$status, "ok")
  expect_equal(calls, 3L)
  expect_equal(sum(vapply(.sc_run_load(f$root)$history, function(event)
    identical(event$action, "provider_turn_dispatched"), logical(1))), 3L)
})

test_that("missing ledgers cannot authorize unresolved structured or ordinary sends", {
  for (structured in c(TRUE, FALSE)) {
    f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    request <- if (structured) f$request else list(system_prompt = "Return JSON.",
      user_prompt = "Synthetic aggregate.", purpose = "annotation")
    calls <- 0L
    fn <- function(...) {calls <<- calls + 1L; if (structured) turn_reply() else '{"draft":true}'}
    call <- function() .sc_run_call(f$root, request, f$provider, fn)
    withr::with_options(list(scAgentKit.provider_crash = "after_dispatch"),
      expect_error(call(), "durable dispatch"))
    unlink(file.path(f$root, "provider", "ledger.json"))
    expect_identical(call()$status, "delivery_uncertain")
    expect_equal(calls, 0L)
  }
})

test_that("ordinary requests recover exact committed attempts and preserve retry ordering", {
  f <- turn_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  request <- list(system_prompt = "Return JSON.", user_prompt = "Synthetic aggregate.", purpose = "annotation")
  calls <- 0L
  fn <- function(...) {calls <<- calls + 1L; if (calls == 1L) 'invalid' else '{"draft":true}'}
  first <- .sc_run_call(f$root, request, f$provider, fn)
  expect_identical(first$status, "invalid_response")
  second <- .sc_run_call(f$root, request, f$provider, fn, retry = TRUE)
  expect_identical(second$status, "ok")
  path <- file.path(f$root, "provider", "ledger.json")
  ledger <- .sc_run_provider_read(path); ledger$entries <- ledger$entries[2L]
  .sc_run_provider_write(ledger, path)
  recovered <- .sc_run_call(f$root, request, f$provider, fn)
  expect_true(recovered$cached); expect_equal(recovered$attempt, 2L); expect_equal(calls, 2L)
  unlink(path)
  expect_identical(.sc_run_call(f$root, request, f$provider, fn)$content, second$content)
  expect_equal(calls, 2L)
})

test_that("orphan checkpoints must decode to the expected object before publication", {
  root <- tempfile(); .sc_project_format_create(root)
  on.exit(unlink(root, recursive = TRUE))
  state <- list(files = list()); expected <- list(cell = "001", count = 1L)
  written <- .sc_run_put(root, state, "qc_object", expected)
  expect_identical(.sc_run_put(root, state, "qc_object", expected), written)
  path <- file.path(root, written$files$qc_object$path)
  saveRDS(list(cell = "001", count = 10001L), path, version = 2L)
  expect_error(.sc_run_put(root, state, "qc_object", expected), "expected object hash")
  expect_null(state$files$qc_object)
})

test_that("a failed provider owner write leaves no published or staging lock", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  lock <- file.path(root, ".dispatch-lock")
  original <- .sc_run_provider_write
  testthat::local_mocked_bindings(.sc_run_provider_write = function(value, path) {
    if (basename(path) == "owner.json") stop("Injected owner write failure")
    original(value, path)
  }, .package = "scAgentKit")
  expect_error(.sc_run_provider_lock(lock), "owner write failure")
  expect_false(dir.exists(lock))
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0L)
  testthat::local_mocked_bindings(.sc_run_provider_write = original, .package = "scAgentKit")
  token <- .sc_run_provider_lock(lock)
  expect_type(token, "character")
  expect_null(.sc_run_provider_lock(lock))
  .sc_run_provider_release(lock, "foreign")
  expect_true(dir.exists(lock))
  .sc_run_provider_release(lock, token)
  expect_false(dir.exists(lock))
})
