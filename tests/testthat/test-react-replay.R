test_that("offline replay re-executes evidence without dispatch or project writes", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  run <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  before <- .sc_project_sha_file(file.path(f$root, "state.rds"))
  testthat::local_mocked_bindings(req_perform = function(...) stop("No HTTP in replay"), .package = "httr2")
  result <- sc_react_replay(f$root)
  expect_true(result$matches, info = .sc_project_json(result$differences))
  expect_identical(result$proposal, run$proposal)
  expect_identical(result$api_calls, 0L)
  expect_identical(.sc_project_sha_file(file.path(f$root, "state.rds")), before)
  state <- .sc_run_load(f$root)
  state$status <- "complete"; state$stage <- "complete"
  .sc_run_save(f$root, state)
  expect_true(sc_react_replay(f$root)$matches)
  expect_error(.sc_run_react_context(f$root), "annotation")
})

test_that("replay preserves fallback and unknown-tool correction histories", {
  for (mode in c("invalid", "unknown_then_retry", "forever")) {
    f <- react_loop_fixture(list(mode = "all", max_steps_per_cluster = 3L))
    run <- .sc_run_react_refine(f$root, f$baseline, react_mock(mode))
    result <- sc_react_replay(f$root)
    expect_true(result$matches, info = paste(mode, .sc_project_json(result$differences)))
    expect_identical(result$proposal, run$proposal)
    unlink(f$root, recursive = TRUE)
  }
})

test_that("replay reports different computed tool evidence without rewriting the draft", {
  f <- react_loop_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  run <- .sc_run_react_refine(f$root, f$baseline, react_mock())
  state <- .sc_run_load(f$root)
  key <- paste0("react_cluster_", .sc_run_hash("0"))
  trace <- .sc_run_get(f$root, state, key)
  trace$tools[[1]]$response$result$markers[[1]]$avg_log2FC <- 999
  trace$tools[[1]]$response$result_hash <- .sc_run_hash(trace$tools[[1]]$response$result)
  state <- .sc_run_put(f$root, state, key, trace)
  run$traces[["0"]] <- state$files[[key]]
  state <- .sc_run_put(f$root, state, "annotation_react_run", run)
  .sc_run_save(f$root, state)
  result <- sc_react_replay(f$root)
  expect_false(result$matches)
  expect_true(any(vapply(result$differences, function(x) identical(x$component, "tool:1"), logical(1))))
  expect_identical(result$proposal, run$proposal)
})
