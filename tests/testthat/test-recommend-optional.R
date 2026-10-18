optional_fixture <- function(technical = NULL, confounded = FALSE) {
  cells <- paste0("c", 1:40)
  roles <- list(batch = rep(c("A", "B"), each = 20),
    condition = if (confounded) rep(c("control", "case"), each = 20) else rep(c("control", "case"), 20))
  columns <- list(batch = "technical_run", condition = "biology")
  context <- list(species = "human", columns = columns, design = list(technical_batch = technical))
  list(evidence = list(summary = list(start_stage = "raw", declared_roles = columns,
    background_facts = context), private = list(cell_ids = cells, roles = roles)),
    validated = list(qc_validated = list(keep_cells = cells), proposal = list(batch = list(method = "none"))),
    config = list(context = context, recommendation_facts = list()))
}

test_that("optional steps never mistake unconfigured defaults for assessment", {
  f <- optional_fixture()
  doublet <- .sc_run_recommend_doublet(f$evidence, f$validated, f$config)
  batch <- .sc_run_recommend_batch(f$evidence, f$validated, f$config)
  expect_identical(doublet$id, "doublet")
  expect_identical(doublet$status, "insufficient_information")
  expect_false(identical(doublet$assessment, "assessed"))
  expect_true(length(doublet$missing) > 0)
  expect_identical(batch$status, "insufficient_information")
  expect_true(any(vapply(batch$missing, function(x) grepl("technical", x$field), logical(1))))
})

test_that("fixed doublet evidence reports capture predictions and exact pure QC intersections", {
  f <- optional_fixture()
  cells <- f$evidence$private$cell_ids
  f$evidence$private$doublet_record <- list(summary = list(status = "available", capture_stats = list()),
    cell_ids = cells, predicted_cells = cells[c(1, 2, 21)],
    capture_map = stats::setNames(rep(c("loadA", "loadB"), each = 20), cells))
  f$validated$qc_validated$keep_cells <- cells[-1]
  f$validated$selected_cells <- cells[-c(1, 2, 21)]
  out <- .sc_run_recommend_doublet(f$evidence, f$validated, f$config)
  expect_identical(out$assessment, "assessed")
  expect_length(out$completed$captures, 2)
  expect_equal(out$completed$captures[[1]]$predicted_doublets, 2)
  expect_equal(out$completed$captures[[1]]$predicted_after_qc, 1)
  expect_equal(out$completed$predicted_after_qc, 2)
  expect_equal(out$candidates[[2]]$changes$doublet$method, "remove_predicted")
  expect_true(out$candidates[[2]]$available)
  expect_true(any(grepl("approv", unlist(out$candidates[[2]]$reasons))))
  expect_false(any(cells %in% unlist(out))) # Public recommendation contains aggregates, never cell IDs.
})

test_that("technical absence or one technical level supports skipping correction", {
  f <- optional_fixture(FALSE)
  out <- .sc_run_recommend_batch(f$evidence, f$validated, f$config)
  expect_identical(out$status, "recommend_skip")
  expect_identical(out$assessment, "assessed")
  expect_equal(out$candidates[[1]]$changes$batch$method, "none")
  f <- optional_fixture(TRUE)
  f$evidence$private$roles$batch[] <- "one run"
  expect_identical(.sc_run_recommend_batch(f$evidence, f$validated, f$config)$status, "recommend_skip")
})

test_that("crossed technical design offers Harmony but fully confounded design cannot", {
  original <- utils::packageVersion
  testthat::local_mocked_bindings(packageVersion = function(pkg, ...) {
    if (pkg == "harmony") return(package_version("2.0.0"))
    original(pkg, ...)
  }, .package = "utils")
  f <- optional_fixture(TRUE)
  out <- .sc_run_recommend_batch(f$evidence, f$validated, f$config)
  expect_identical(out$status, "recommend_execute")
  expect_identical(out$assessment, "pending_computation")
  choice <- out$candidates[[2]]$changes$batch
  expect_equal(choice$method, "harmony")
  expect_equal(choice$group_by_vars, "technical_run")
  expect_true(out$candidates[[2]]$available)
  expect_true(.sc_run_harmony_choice(choice, f$evidence, f$evidence$private$roles)$executable)
  f <- optional_fixture(TRUE, TRUE)
  blocked <- .sc_run_recommend_batch(f$evidence, f$validated, f$config)
  expect_true(length(blocked$conflicts) > 0)
  expect_false(blocked$candidates[[2]]$available)
  expect_match(paste(unlist(blocked$conflicts), collapse = " "), "confound|rank")
})

test_that("missing optional package leaves none usable without claiming correction assessed", {
  original <- utils::packageVersion
  testthat::local_mocked_bindings(packageVersion = function(pkg, ...) {
    if (pkg == "harmony") stop("harmony is not installed")
    original(pkg, ...)
  }, .package = "utils")
  f <- optional_fixture(TRUE)
  out <- .sc_run_recommend_batch(f$evidence, f$validated, f$config)
  expect_true(out$candidates[[1]]$available)
  expect_false(out$candidates[[2]]$available)
  expect_identical(out$assessment, "pending_computation")
  expect_true(any(grepl("not installed", unlist(out$candidates[[2]]$reasons))))
})

test_that("doublet preparation names missing facts and never guesses physical captures", {
  config <- list(context = list(species = "human", columns = list(sample = "sample")),
    recommendation_facts = list(doublet = list(data_type = "scrna_droplet",
      technology = "10x_chromium_standard", input_source = "Author filtered count matrix",
      empty_droplets_removed = TRUE, full_called_cohort = TRUE,
      capture = list(method = "column", source = "Author loading manifest"),
      rate = list(method = "10x_standard", source = "Supported documented formula"))))
  out <- .sc_run_recommend_doublet_options(config)
  expect_false(out$ready)
  expect_true("doublet.capture.column" %in% vapply(out$missing, `[[`, character(1), "field"))
  expect_null(out$options)
  config$recommendation_facts$doublet$data_type <- "snrna"
  expect_true(any(grepl("outside", unlist(.sc_run_recommend_doublet_options(config)$blockers))))
  config$recommendation_facts$doublet$data_type <- "scrna_droplet"
  config$recommendation_facts$doublet$empty_droplets_removed <- FALSE
  expect_true(any(grepl("cell calling", unlist(.sc_run_recommend_doublet_options(config)$blockers))))
})

test_that("complete supported preparation remains pending and cannot materialize removal", {
  testthat::local_mocked_bindings(.sc_run_doublet_versions = function() list(
    scDblFinder = "1.26.7", xgboost = "3.1.0", SingleCellExperiment = "1.0.0",
    SummarizedExperiment = "1.0.0", S4Vectors = "1.0.0", BiocParallel = "1.0.0"), .package = "scAgentKit")
  f <- optional_fixture()
  f$evidence$private$cell_ids <- paste0("c", 1:240)
  f$validated$qc_validated$keep_cells <- f$evidence$private$cell_ids
  f$config$recommendation_facts$doublet <- list(data_type = "scrna_droplet",
    technology = "10x_chromium_standard", input_source = "Author called-cell matrix",
    empty_droplets_removed = TRUE, full_called_cohort = TRUE,
    capture = list(method = "column", column = "physical_load", source = "Author loading manifest"),
    rate = list(method = "10x_standard", source = "Documented full-called-capture rule"))
  before <- f
  preparation <- .sc_run_recommend_doublet_options(f$config)
  expect_true(preparation$ready)
  expect_identical(preparation$options$capture$column, "physical_load")
  expect_length(preparation$missing, 0L)
  out <- .sc_run_recommend_doublet(f$evidence, f$validated, f$config)
  expect_identical(out$status, "recommend_execute")
  expect_identical(out$assessment, "pending_computation")
  expect_length(out$completed, 0L)
  expect_false(out$candidates[[1]]$available)
  expect_length(out$candidates[[1]]$changes, 0L)
  expect_identical(f, before)
  f$evidence$private$cell_ids <- paste0("c", 1:40)
  unsupported <- .sc_run_recommend_doublet(f$evidence, f$validated, f$config)
  expect_identical(unsupported$status, "recommend_skip")
  expect_identical(unsupported$assessment, "unavailable")
  expect_true(any(grepl("100 cells", unlist(unsupported$reasons))))
})

test_that("fixed unsupported evidence does not become a scored keep/removal recommendation", {
  f <- optional_fixture()
  cells <- f$evidence$private$cell_ids
  f$evidence$private$doublet_record <- list(summary = list(status = "unsupported",
    reasons = list("Fewer than 100 cells per capture; no classifier executed.")),
    cell_ids = cells, predicted_cells = character(), capture_map = stats::setNames(rep("load", 40), cells))
  out <- .sc_run_recommend_doublet(f$evidence, f$validated, f$config)
  expect_identical(out$assessment, "unavailable")
  expect_length(out$completed, 0L)
  expect_true(out$candidates[[1]]$available)
  expect_equal(out$candidates[[1]]$changes$doublet$method, "keep")
  expect_true(any(grepl("100 cells", unlist(out$reasons))))
})
