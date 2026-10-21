test_that("process probes distinguish absence from permission and probe failures", {
  yes <- function(...) TRUE
  no <- function(...) FALSE
  error <- function(...) stop("Operation not permitted")
  expect_identical(.sc_run_process_status(123L, yes, error), "alive")
  expect_identical(.sc_run_process_status(123L, no, yes), "absent")
  expect_identical(.sc_run_process_status(123L, error, yes), "absent")
  expect_identical(.sc_run_process_status(123L, no, no), "unknown")
  expect_identical(.sc_run_process_status(123L, error, no), "unknown")
  expect_identical(.sc_run_process_status(123L, no, error), "unknown")
  expect_identical(.sc_run_process_status(NA_integer_, yes, yes), "unknown")
  expect_identical(.sc_run_process_status(-1L, yes, yes), "unknown")
  expect_identical(.sc_run_process_status(Sys.getpid()), "alive")
})

test_that("unknown local process status retains the exact run and provider locks", {
  root <- tempfile(); .sc_project_format_create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  owner <- .sc_run_lock(root)
  provider <- file.path(root, "provider", ".dispatch-lock")
  dir.create(provider, recursive = TRUE)
  writeLines("provider authority unchanged", file.path(provider, "owner.json"))
  before <- readBin(file.path(root, ".run-lock", "owner.rds"), "raw", n = 100000)
  testthat::local_mocked_bindings(.sc_run_process_status = function(...) "unknown", .package = "scAgentKit")
  expect_error(sc_run_unlock(root, owner$token, "Simulated permission failure"), "status is unknown.*lock retained")
  expect_identical(readBin(file.path(root, ".run-lock", "owner.rds"), "raw", n = 100000), before)
  expect_identical(readLines(file.path(provider, "owner.json")), "provider authority unchanged")
  expect_error(sc_run_unlock(root, "wrong-token", "Simulated permission failure"), "token mismatch")
})

test_that("only explicit OS absence can confirm a failed signal probe", {
  skip_on_os("windows")
  denied <- function(...) structure("kill: 123: Operation not permitted", status = 1L)
  missing <- function(...) structure("kill: 123: No such process", status = 1L)
  success <- function(...) character()
  unknown <- function(...) structure("unexpected probe failure", status = 2L)
  expect_false(.sc_run_process_absent(123L, denied))
  expect_true(.sc_run_process_absent(123L, missing))
  expect_false(.sc_run_process_absent(123L, success))
  expect_false(.sc_run_process_absent(123L, unknown))
})

test_that("confirmed absence permits explicit recovery and records the reason", {
  root <- tempfile(); .sc_project_format_create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  owner <- .sc_run_lock(root)
  saved <- new.env()
  testthat::local_mocked_bindings(
    .sc_run_process_status = function(...) "absent",
    .sc_run_load = function(...) list(history = list(), revision = 0L),
    .sc_run_save = function(root, state) { saved$state <- state; invisible(state) },
    .package = "scAgentKit")
  expect_true(sc_run_unlock(root, owner$token, "Owner termination independently verified"))
  expect_false(dir.exists(file.path(root, ".run-lock")))
  expect_identical(saved$state$history[[1]]$action, "lock_recovered")
  expect_identical(saved$state$history[[1]]$details$owner, owner)
  expect_identical(saved$state$history[[1]]$details$reason, "Owner termination independently verified")
})

test_that("lock creation failures identify writable project requirement without stealing", {
  root <- tempfile(); .sc_project_format_create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  # Clone only the function environment for controlled filesystem failures;
  # never change actual permissions or replace namespace/base functions.
  mocked_lock <- function(bindings) {
    fn <- .sc_run_lock
    environment(fn) <- list2env(bindings, parent = environment(fn))
    fn
  }
  create_denied <- mocked_lock(list(dir.create = function(...) FALSE))
  expect_error(create_denied(root), "Cannot create lock staging directory.*parent project.*must be writable.*recorded project path.*reapprove")
  expect_false(dir.exists(file.path(root, ".run-lock")))
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "project-format.json")
  write_denied <- mocked_lock(list(saveRDS = function(...) stop("simulated disk failure")))
  expect_error(write_denied(root), "Cannot write lock owner record.*must be writable")
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "project-format.json")
  rename_denied <- mocked_lock(list(file.rename = function(...) FALSE))
  expect_error(rename_denied(root), "Cannot publish project lock.*must be writable")
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "project-format.json")
  owner <- .sc_run_lock(root)
  expect_error(create_denied(root), "Project is locked")
  expect_identical(readRDS(file.path(root, ".run-lock", "owner.rds")), owner)
})
