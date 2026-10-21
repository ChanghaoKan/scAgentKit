test_that("cluster tree preserves literal membership and adjacent transitions", {
  assignments <- list(`0.2` = c(`001`="0", `1`="0", `NA`="1", `space cell`="1"),
    `0.6` = c(`001`="a", `1`="b", `NA`="c", `space cell`="c"))
  result <- scAgentKit:::.sc_run_cluster_tree(assignments, c("A", "B", "A", "B"))
  expect_length(result$nodes, 5L)
  expect_length(result$edges, 3L)
  expect_equal(sum(vapply(result$edges, `[[`, integer(1), "cells")), 4)
  expect_equal(result$edges[[1]]$source_fraction, .5)
  expect_equal(result$edges[[1]]$target_fraction, 1)
  expect_match(result$interpretation, "not.*biological")
  expect_equal(sum(vapply(result$nodes[[1]]$sample_counts, `[[`, integer(1), "cells")), 2)
  bad <- assignments; names(bad[[2]]) <- rev(names(bad[[2]]))
  expect_error(scAgentKit:::.sc_run_cluster_tree(bad), "exact cell")
})

test_that("author and model selections must be an actually scanned value", {
  scan <- list(resolutions = c(.2, .4, .6))
  expect_invisible(scAgentKit:::.sc_run_cluster_selection(.4, scan))
  expect_error(scAgentKit:::.sc_run_cluster_selection(.5, scan), "actually scanned")
  expect_error(scAgentKit:::.sc_run_cluster_selection(NA_real_, scan), "actually scanned")
})

test_that("a measured sweep returns to the existing review and binds author selection", {
  # Reuse public synthetic software-control fixtures without sourcing their tests.
  fixture <- new.env(parent = globalenv())
  expressions <- parse(file.path("test-run-strategy-integration.R"))
  for (expr in expressions) if (is.call(expr) && identical(expr[[1]], as.name("<-"))) eval(expr, fixture)
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture$strategy_integration_begin(root, provider = list(name = "mock", model = "software-control", external = FALSE))
  fixture$strategy_integration_decide(root)
  initial <- sc_run_inspect(root)
  scanned <- suppressWarnings(sc_run_continue(root, initial$project_id, initial$input_hash, initial$revision))
  expect_identical(scanned$status, "awaiting_review")
  view <- sc_run_inspect(root)
  expect_identical(view$review_node$kind, "strategy")
  scan <- view$strategy_review$details$cluster_diagnostics
  expect_true(length(scan$tree$edges) > 0)
  expect_equal(scan$resolutions, c(.2, .4, .6))
  expect_length(scan$markers, 3)
  state0 <- scAgentKit:::.sc_run_load(root)
  evidence <- scAgentKit:::.sc_run_get(root, state0, "strategy_evidence")
  validate <- scAgentKit:::.sc_run_suggestion_validator("strategy", evidence, state0, scan)
  bad_model <- fixture$strategy_integration_plan(); bad_model$clustering$resolution <- .5
  expect_error(validate(bad_model), "actually scanned")
  expect_null(state0$files$markers)
  saved_scan <- scAgentKit:::.sc_run_get(root, state0, "cluster_scan")
  expect_true(identical(saved_scan$hash, scan$hash))
  before_model <- scAgentKit:::.sc_run_load(root)
  candidate <- sc_run_suggest(root, "preview", simulate = TRUE)
  expect_match(candidate$preview$user_prompt, "cluster_diagnostics", fixed = TRUE)
  expect_false(grepl("literalCell", candidate$preview$user_prompt, fixed = TRUE))
  act <- function(action, snapshot) sc_run_suggest(root, action,
    project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    expected_revision = snapshot$revision, suggestion_hash = snapshot$suggestion_hash,
    reviewer = "offline cluster QA", reason = "Explicit simulated proposal; not scientific approval.", simulate = TRUE)
  candidate <- act("approve", candidate)
  candidate <- act("request", candidate)
  expect_identical(candidate$status, "candidate")
  expect_identical(scAgentKit:::.sc_run_load(root)$pending, before_model$pending)
  expect_identical(scAgentKit:::.sc_run_load(root)$files$analysis, before_model$files$analysis)
  expect_null(scAgentKit:::.sc_run_load(root)$approved)
  expect_equal(candidate$response$cost_usd, 0)
  adopted <- act("adopt", candidate)
  expect_identical(adopted$status, "awaiting_review")
  expect_null(scAgentKit:::.sc_run_load(root)$approved)
  before <- scAgentKit:::.sc_run_load(root)$files$strategy_neighbors
  plan <- fixture$strategy_integration_plan(); plan$clustering$resolution <- .5
  expect_error(fixture$strategy_integration_revise(root, plan), "actually scanned")
  plan$clustering$resolution <- .6
  fixture$strategy_integration_revise(root, plan)
  fixture$strategy_integration_decide(root)
  done <- fixture$strategy_integration_continue(root)
  expect_identical(done$status, "awaiting_configuration")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files$strategy_neighbors, before)
  actual <- scAgentKit:::.sc_run_get(root, state, "analysis")
  expect_equal(actual@misc$strategy_execution$cluster$resolution, .6)
  expect_identical(as.character(actual[[]][[state$config$cluster_column]]),
    unname(actual@misc$strategy_execution$cluster$diagnostic_assignments[["0.6"]]))
  expect_true(!is.null(state$files$markers))
  found <- scAgentKit:::.sc_run_get(root, state, "markers")
  expect_identical(found$cluster_column, state$config$cluster_column)
  expect_true(all(found$markers$cluster %in% unique(as.character(actual[[]][[state$config$cluster_column]]))))
  # The same marker engine, same expression and selected membership give the
  # exact saved final table; no provisional .4 markers are reused after .6.
  recomputed <- suppressWarnings(scAgentKit:::.sc_run_markers(actual, state$config))
  expect_identical(found, recomputed)
})


test_that("failed scan marker evidence never publishes a selection review", {
  fixture <- new.env(parent = globalenv())
  expressions <- parse(file.path("test-run-strategy-integration.R"))
  for (expr in expressions) if (is.call(expr) && identical(expr[[1]], as.name("<-"))) eval(expr, fixture)
  testthat::local_mocked_bindings(.sc_run_markers = function(...) stop("Injected scan marker failure"), .package = "scAgentKit")
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture$strategy_integration_begin(root)
  fixture$strategy_integration_decide(root)
  snapshot <- sc_run_inspect(root)
  result <- suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash, snapshot$revision))
  expect_identical(result$status, "failed")
  state <- scAgentKit:::.sc_run_load(root)
  expect_null(state$files$cluster_scan)
  expect_null(state$files$markers)
  expect_null(state$pending)
  expect_null(scAgentKit:::.sc_run_get(root, state, "strategy_review")$details$cluster_diagnostics)
})


test_that("main entry requests a reviewed scan instead of recommending 0.5", {
  plan <- scAgentKit:::.sc_ui_plan(dimensions = c(2000L, 100L))
  expect_equal(plan$clustering$diagnostic_resolutions, c(.2, .4, .6, .8, 1))
  expect_true(any(grepl("not a recommendation", unlist(plan$risks), fixed = TRUE)))
})
