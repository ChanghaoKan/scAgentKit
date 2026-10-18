facts_fixture_functions <- function() {
  fixture <- new.env(parent = globalenv())
  for (expr in parse("test-recommend-workspace.R"))
    if (is.call(expr) && identical(expr[[1]], as.name("<-"))) eval(expr, fixture)
  fixture
}

test_that("explicit initial sample facts replace pooled MAD grouping without approval or deletion", {
  fixture <- facts_fixture_functions()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  sc_analyze(fixture$recommend_workspace_input(), root,
    context = list(species = "human", tissue = "software fixture", research_goal = "Explicit sample facts"))
  old <- .sc_run_load(root)
  expect_identical(old$config$qc_mad$grouping$method, "single")
  out <- fixture$recommend_workspace_facts(root, list(columns = list(sample = "sample")))
  saved <- .sc_run_load(root)
  expect_identical(out$status, "ready")
  expect_identical(saved$config$qc_mad$grouping$column, "sample")
  expect_identical(saved$config$qc_mad$grouping$declared_role, "sample")
  expect_identical(saved$files$input, old$files$input)
  expect_length(saved$approvals, 0L)
  expect_null(saved$pending)
  archive <- .sc_run_get(root, saved, "recommendation_facts_archive")$revisions[[1L]]
  expect_identical(archive$config, old$config)
  expect_identical(archive$files$strategy_review, old$files$strategy_review)
  expect_identical(archive$pending, old$pending)
  next_view <- suppressWarnings(sc_run_continue(root, out$project_id, out$input_hash, out$revision))
  expect_identical(next_view$status, "awaiting_review")
  new <- .sc_run_load(root)
  expect_identical(new$config$context$columns$sample, "sample")
  expect_identical(.sc_run_get(root, new, "qc_mad")$options$grouping$method, "column")
  expect_identical(new$files$input, old$files$input)
  expect_length(new$approvals, 0L)
  expect_null(new$files$qc_object)
})

test_that("complete doublet facts on an unsupported small cohort do not enable scoring or block fresh review", {
  testthat::local_mocked_bindings(.sc_run_doublet_versions = function() list(
    scDblFinder = "1.26.7", xgboost = "3.1.0", SingleCellExperiment = "1.0.0",
    SummarizedExperiment = "1.0.0", S4Vectors = "1.0.0", BiocParallel = "1.0.0"),
    .sc_run_doublet_evidence = function(...) stop("The classifier must not execute for this unsupported cohort"),
    .package = "scAgentKit")
  fixture <- facts_fixture_functions()
  root <- fixture$recommend_workspace_begin(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  facts <- list(doublet = list(data_type = "scrna_droplet", technology = "10x_chromium_standard",
    input_source = "Author called-cell input", empty_droplets_removed = TRUE, full_called_cohort = TRUE,
    capture = list(method = "column", column = "capture", source = "Author loading manifest"),
    rate = list(method = "10x_standard", source = "Documented complete-cohort rule")))
  out <- fixture$recommend_workspace_facts(root, facts)
  saved <- .sc_run_load(root)
  expect_null(saved$config$doublet_diagnostics)
  expect_identical(saved$config$context$columns$capture, "capture")
  expect_false(saved$config$recommendation_doublet_preparation$ready)
  expect_false(saved$config$recommendation_doublet_preparation$scoring_executed)
  expect_true(any(grepl("100", unlist(saved$config$recommendation_doublet_preparation$reasons))))
  expect_identical(saved$config$recommendation_facts$doublet, facts$doublet)
  expect_length(saved$approvals, 0L)
  next_view <- suppressWarnings(sc_run_continue(root, out$project_id, out$input_hash, out$revision))
  expect_identical(next_view$status, "awaiting_review")
  expect_null(.sc_run_load(root)$files$doublet_diagnostics)
  expect_length(.sc_run_load(root)$approvals, 0L)
})

test_that("facts preflight protects existing metadata and incomplete rate maps without running a scorer", {
  fixture <- facts_fixture_functions()
  input <- fixture$recommend_workspace_input()
  options <- .sc_run_doublet_options(list(species = "human"), list(data_type = "scrna_droplet",
    technology = "declared_droplet_other", input_source = "Author called cells", empty_droplets_removed = TRUE,
    capture = list(method = "single", id = "one", source = "Author loading record"),
    rate = list(method = "manual", value = .05, source = "Author sourced assumption")))
  config <- list(context = list(species = "human"), assay = "RNA", counts_layer = "counts", doublet_diagnostics = options)
  input[[.sc_run_doublet_columns(options$column_prefix)[[1L]]]] <- 1
  out <- .sc_run_recommend_facts_doublet_guard(input, config)
  expect_false(out$ready)
  expect_match(out$reasons[[1L]], "already exist")
  expect_true(all(input[[.sc_run_doublet_columns(options$column_prefix)[[1L]]]][, 1] == 1))
  config$doublet_diagnostics$rate$value <- c(wrong_loading_unit = .05)
  clean <- fixture$recommend_workspace_input()
  expect_error(.sc_run_recommend_facts_doublet_guard(clean, config), "cover every literal capture")
})
