facts_fixture_functions <- function() {
  fixture <- new.env(parent = globalenv())
  for (expr in parse("test-recommend-workspace.R"))
    if (is.call(expr) && identical(expr[[1]], as.name("<-"))) eval(expr, fixture)
  fixture
}

test_that("explicit initial sample facts enable grouped MAD without implicit pooling approval or deletion", {
  fixture <- facts_fixture_functions()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  sc_analyze(fixture$recommend_workspace_input(), root,
    context = list(species = "human", tissue = "software fixture", research_goal = "Explicit sample facts"))
  .sc_run_call(root, list(system_prompt = "Return JSON.", user_prompt = "Synthetic aggregate.",
    purpose = "strategy"), provider = "mock", chat_fn = function(...) '{"draft":true}')
  old <- .sc_run_load(root)
  receipts <- grep("^provider_request_", names(old$files), value = TRUE)
  expect_length(receipts, 1L)
  expect_null(old$config$qc_mad)
  expect_null(old$config$context$columns$sample)
  out <- fixture$recommend_workspace_facts(root, list(columns = list(sample = "sample")))
  saved <- .sc_run_load(root)
  expect_identical(out$status, "ready")
  expect_identical(saved$config$qc_mad$grouping$column, "sample")
  expect_identical(saved$config$qc_mad$grouping$declared_role, "sample")
  expect_identical(saved$files$input, old$files$input)
  expect_identical(saved$files[receipts], old$files[receipts])
  expect_silent(.sc_run_provider_recover_ledger(root, saved,
    .sc_run_provider_read(file.path(root, "provider", "ledger.json")), file.path(root, "provider", "ledger.json")))
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

test_that("doublet guard aligns radix-sorted counts with literal input cells and physical captures", {
  cells <- paste0("c", 1:240)
  counts <- matrix(2L, 200L, 240L, dimnames = list(paste0("g", 1:200), cells))
  low <- seq(122L, 240L, by = 2L)
  counts[, low] <- 0L; counts[1:100, low] <- 1L
  input <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  input$physical <- rep(c("loadA", "loadB"), each = 120L)
  context <- list(species = "human", columns = list(capture = "physical"))
  options <- .sc_run_doublet_options(context, list(data_type = "scrna_droplet",
    technology = "declared_droplet_other", input_source = "Author called cells", empty_droplets_removed = TRUE,
    capture = list(method = "column", column = "physical", source = "Author loading record"),
    rate = list(method = "manual", value = .05, source = "Sourced expected rate"), nfeatures = 200L))
  config <- list(context = context, assay = "RNA", counts_layer = "counts", doublet_diagnostics = options,
    prefilter = list(method = "min_counts", min_counts = 200L, source = "Explicit author software test", preapproved = TRUE))
  prefilter <- .sc_run_prefilter_evidence(input, config)
  guarded <- .sc_run_recommend_facts_doublet_guard(input, config)
  expect_equal(vapply(guarded$capture_counts, `[[`, integer(1), "pre_score_cells"), c(120L, 60L))
  expected <- vapply(c("loadA", "loadB"), function(id)
    sum(cells[input$physical == id] %in% prefilter$keep_cells), integer(1))
  expect_identical(vapply(guarded$capture_counts, `[[`, integer(1), "pre_score_cells"), unname(expected))
  expect_equal(vapply(guarded$capture_counts, `[[`, numeric(1), "low_read_cells"), c(0, 0))
  reversed <- input[, rev(cells)]
  again <- .sc_run_recommend_facts_doublet_guard(reversed, config)
  by_capture <- function(x) x$capture_counts[order(vapply(x$capture_counts, `[[`, character(1), "capture"))]
  expect_identical(by_capture(guarded), by_capture(again))
  expect_false(guarded$ready)
})

test_that("explicit method switches prune only incompatible old facts and retain other declarations", {
  fixture <- facts_fixture_functions()
  input <- fixture$recommend_workspace_input()
  declaration <- list(data_type = "scrna_droplet", technology = "10x_chromium_standard",
    input_source = "Author called cells", empty_droplets_removed = TRUE, full_called_cohort = TRUE,
    capture = list(method = "single", id = "old_capture", source = "Author capture record"),
    rate = list(method = "manual", value = .05, source = "Author rate record"))
  config <- list(context = list(species = "human"), assay = "RNA", counts_layer = "counts",
    recommendation_facts = list(doublet = declaration))
  patch <- list(doublet = list(capture = list(method = "column", column = "capture"),
    rate = list(method = "10x_standard", source = "Documented complete-cohort rule")))
  changed <- .sc_run_recommend_facts_config(list(config = config), patch, input)
  expect_null(changed$recommendation_facts$doublet$capture$id)
  expect_null(changed$recommendation_facts$doublet$rate$value)
  expect_identical(changed$recommendation_facts$doublet$input_source, declaration$input_source)
  expect_identical(changed$context$columns$capture, "capture")
  contradictory <- patch; contradictory$doublet$capture$id <- "also_a_single_capture"
  expect_error(.sc_run_recommend_facts_config(list(config = config), contradictory, input), "single capture ID")
  contradictory <- patch; contradictory$doublet$rate$value <- .05
  expect_error(.sc_run_recommend_facts_config(list(config = config), contradictory, input), "manual rate value")
  # A pre-existing canonical configuration supplies only its original author
  # facts when the new editable facts object has not yet been saved.
  config$recommendation_facts <- NULL
  config$doublet_diagnostics <- .sc_run_doublet_options(config$context, declaration)
  inherited <- .sc_run_recommend_facts_config(list(config = config),
    list(doublet = list(input_source = "Corrected provenance")), input)
  expect_identical(inherited$recommendation_facts$doublet$data_type, declaration$data_type)
  expect_identical(inherited$recommendation_facts$doublet$capture, declaration$capture)
  expect_identical(inherited$recommendation_facts$doublet$input_source, "Corrected provenance")
  expect_null(inherited$recommendation_facts$doublet$seed)
  expect_null(inherited$doublet_diagnostics) # The unsupported cohort never enables a new scorer.
})

test_that("existing noneditable doublet algorithm settings survive single author-fact corrections", {
  captured <- NULL
  testthat::local_mocked_bindings(.sc_run_doublet_versions = function() list(
    scDblFinder = "1.26.7", xgboost = "3.1.0", SingleCellExperiment = "1.0.0",
    SummarizedExperiment = "1.0.0", S4Vectors = "1.0.0", BiocParallel = "1.0.0"),
    .sc_run_recommend_facts_doublet_guard = function(input, config) {
      captured <<- config$doublet_diagnostics
      list(ready = FALSE, reasons = list("Unsupported fixture cohort; do not score"), capture_counts = list(), scoring_executed = FALSE)
    }, .package = "scAgentKit")
  fixture <- facts_fixture_functions()
  input <- fixture$recommend_workspace_input()
  context <- list(species = "human")
  original <- .sc_run_doublet_options(context, list(data_type = "scrna_droplet",
    technology = "declared_droplet_other", input_source = "Original author input", empty_droplets_removed = TRUE,
    capture = list(method = "single", id = "one", source = "Author loading record"),
    rate = list(method = "manual", value = .05, source = "Author sourced rate"),
    nfeatures = 200L, seed = 321L, column_prefix = "prior_doublet", dims = 10L, artificial_doublets = 600L))
  config <- list(context = context, assay = "RNA", counts_layer = "counts", doublet_diagnostics = original)
  out <- .sc_run_recommend_facts_config(list(config = config),
    list(doublet = list(input_source = "Corrected author provenance")), input)
  for (key in c("column_prefix", "seed", "nfeatures", "dims", "artificial_doublets", "iter", "clusters")) {
    expect_identical(captured[[key]], original[[key]], info = key)
    expect_null(out$recommendation_facts$doublet[[key]], info = key)
  }
  expect_identical(captured$input_source, "Corrected author provenance")
  expect_null(out$doublet_diagnostics)
  # The first guard intentionally disabled the diagnostic. A second correction
  # must still retain its original noneditable algorithm settings.
  second <- .sc_run_recommend_facts_config(list(config = out),
    list(doublet = list(input_source = "Second author correction")), input)
  for (key in c("column_prefix", "seed", "nfeatures", "dims", "artificial_doublets", "iter", "clusters")) {
    expect_identical(captured[[key]], original[[key]], info = key)
    expect_identical(second$recommendation_doublet_settings[[key]], original[[key]], info = key)
    expect_null(second$recommendation_facts$doublet[[key]], info = key)
  }
  expect_null(second$doublet_diagnostics)
  expect_error(.sc_run_recommend_facts_typed(list(recommendation_doublet_settings = list(seed = 99))), "supported")
})

test_that("an initial dependency gap preserves settings for later ready preparation", {
  dependency_available <- FALSE
  captured <- NULL
  testthat::local_mocked_bindings(.sc_run_doublet_versions = function() list(
    scDblFinder = if (dependency_available) "1.26.7" else NA_character_, xgboost = "3.1.0",
    SingleCellExperiment = "1.0.0", SummarizedExperiment = "1.0.0", S4Vectors = "1.0.0", BiocParallel = "1.0.0"),
    .sc_run_recommend_facts_doublet_guard = function(input, config) {
      captured <<- config$doublet_diagnostics
      list(ready = FALSE, reasons = list("Unsupported fixture cohort"), capture_counts = list(), scoring_executed = FALSE)
    }, .package = "scAgentKit")
  fixture <- facts_fixture_functions()
  input <- fixture$recommend_workspace_input()
  context <- list(species = "human")
  original <- .sc_run_doublet_options(context, list(data_type = "scrna_droplet",
    technology = "declared_droplet_other", input_source = "Original author input", empty_droplets_removed = TRUE,
    capture = list(method = "single", id = "one", source = "Author loading record"),
    rate = list(method = "manual", value = .05, source = "Author sourced rate"),
    nfeatures = 200L, seed = 321L, column_prefix = "prior_doublet"))
  config <- list(context = context, assay = "RNA", counts_layer = "counts", doublet_diagnostics = original)
  first <- .sc_run_recommend_facts_config(list(config = config),
    list(doublet = list(input_source = "Corrected during dependency gap")), input)
  expect_null(first$doublet_diagnostics)
  expect_null(captured)
  expect_identical(first$recommendation_doublet_settings$seed, original$seed)
  dependency_available <- TRUE
  second <- .sc_run_recommend_facts_config(list(config = first),
    list(doublet = list(input_source = "Corrected after dependency availability")), input)
  expect_identical(captured$seed, original$seed)
  expect_identical(captured$nfeatures, original$nfeatures)
  expect_identical(captured$column_prefix, original$column_prefix)
  expect_null(second$doublet_diagnostics)
})
