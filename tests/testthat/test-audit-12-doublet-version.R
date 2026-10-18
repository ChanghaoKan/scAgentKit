test_that("unsupported installed classifier is rejected during dependency preflight with guidance", {
  withr::local_options(lifecycle_verbosity="quiet")
  versions <- list(scDblFinder="1.26.9",xgboost="3.2.1.1")
  message <- tryCatch({scAgentKit:::.sc_run_doublet_classifier_versions_verify(versions);"no error"},error=conditionMessage)
  for (part in c("1.26.9","1.26.7","1.22.0","isolated")) expect_match(message,part,fixed=TRUE)
  detector_calls <- 0L
  testthat::local_mocked_bindings(
    .sc_run_strategy_runtime_dependencies=function(...) invisible(TRUE),
    .sc_run_doublet_classifier_installed_versions=function() versions,
    .sc_run_doublet_classifier_functions=function(...) {detector_calls <<- detector_calls+1L;stop("must not inspect classifier")},
    .package="scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_dependencies(),"1.26.9",fixed=TRUE)
  legacy <- AgentSeurat(list(capture=SeuratObject::pbmc_small))
  expect_error(qc_doublet(legacy),"1.26.9",fixed=TRUE)
  expect_identical(detector_calls,0L)
})
