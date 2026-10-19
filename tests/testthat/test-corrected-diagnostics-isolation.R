test_that("unsupported corrected stability does not discard applicable cheap expression evidence", {
  obj <- SeuratObject::pbmc_small
  obj$cluster <- as.character(obj$RNA_snn_res.1)
  obj@misc$strategy_execution$neighbors$pcs <- 4L
  config <- list(assay="RNA",counts_layer="counts",normalized_layer="data",cluster_column="cluster",
    context=list(),scientific_review=list(pc_sensitivity=TRUE,resampling=TRUE,
      resolution_extension=TRUE,panels=list(B=c("MS4A1","CD79A","ABSENT"))))
  plan <- list(pcs=list(method="fixed",ndim=4L),batch=list(method="harmony"),
    cycle=list(method="none"),clustering=list(resolution=.6))
  testthat::local_mocked_bindings(.sc_run_science_partition=function(...) stop("Unsupported correction rerun was attempted"))
  before <- .sc_run_hash(obj)
  for (pipeline in c("harmony","full","difference")) {
    plan$batch$method <- if(pipeline=="harmony") "harmony" else "none"
    plan$cycle$method <- if(pipeline=="harmony") "none" else pipeline
    value <- .sc_run_science_diagnostics(obj,config,plan)
    for (key in c("pc_sensitivity","resampling","resolution_extension")) {
      expect_identical(value[[key]]$status,"unavailable")
      expect_match(value[[key]]$reason,"Harmony/cycle")
    }
    expect_identical(value$expression$status,"measured")
    expect_identical(value$expression$missing_genes,"ABSENT")
    expect_identical(value$provider_calls,0L)
    expect_false(value$default_changed)
    expect_identical(value$input_object_hash,before)
    expect_identical(value$hash,.sc_run_hash(value[names(value)!="hash"]))
  }
  calls<-0L
  testthat::local_mocked_bindings(
    .sc_run_science_partition=function(...) {calls<<-calls+1L;stats::setNames(as.character(obj$cluster),colnames(obj))},
    .sc_run_science_marker_consistency=function(...) list(status="measured"))
  plan$batch$method<-"none";plan$cycle$method<-"none"
  config$scientific_review$resampling<-FALSE
  config$scientific_review$resolution_extension<-FALSE
  ordinary<-.sc_run_science_diagnostics(obj,config,plan)
  expect_gt(calls,0L)
  expect_identical(ordinary$pc_sensitivity$status,"measured")
  expect_identical(ordinary$expression$status,"measured")
  expect_identical(.sc_run_hash(obj),before)
})
