test_that("default review policy keeps rebuilding experiments opt-in", {
  expect_null(.sc_run_science_options(NULL))
  options <- .sc_run_science_options(list())
  for (key in c("pc_sensitivity", "resampling", "resolution_extension")) expect_false(options[[key]])
  enabled <- .sc_run_science_options(list(pc_sensitivity=TRUE, resampling=TRUE, resolution_extension=TRUE))
  for (key in c("pc_sensitivity", "resampling", "resolution_extension")) expect_true(enabled[[key]])
  plan <- .sc_ui_plan(dimensions=c(2000L,100L))
  expect_identical(plan$pcs, list(method="computed_top50", threshold=.8))
  expect_identical(plan$clustering$diagnostic_resolutions,c(.2,.4,.6,.8,1))
  expect_null(plan$analysis$hvg_method)
  explicit <- .sc_ui_plan(list(analysis=list(hvg_method="sample_consensus",hvg_column="sample")),
    dimensions=c(2000L,100L))
  expect_identical(explicit$analysis$hvg_method,"sample_consensus")
})

test_that("classic defaults use declared species and tissue without guessing", {
  blood <- .sc_run_basic_expression_options(list(species="Homo sapiens",tissue="PBMC"))
  expect_identical(blood$status,"available")
  expect_identical(blood$panels,.sc_run_classic_panels("blood"))
  expect_identical(.sc_run_basic_expression_options(list(species="human",tissue="pancreas"))$panel_set,"pancreas")
  for (context in list(list(),list(species="mouse",tissue="Blood"),
      list(species="human",tissue="Unknown"),list(species="human",tissue="blood-like tumour"))) {
    result <- .sc_run_basic_expression_options(context)
    expect_identical(result$status,"unavailable")
    expect_length(result$panels,0L)
    expect_match(result$reason,"No applicable")
  }
})

test_that("default raw entry retains scan tree and classic evidence without optional rebuilds", {
  testthat::local_mocked_bindings(.sc_run_science_diagnostics=function(...) stop("Unexpected optional rebuild"))
  input <- SeuratObject::pbmc_small
  before <- .sc_run_hash(input)
  root <- tempfile()
  x <- sc_analyze(input,root,context=list(species="human",tissue="Blood",research_goal="Default software control"),
    plan=list(analysis=list(nfeatures=100L,npcs=6L),umap=FALSE),
    reference=data.frame(cell_type=c("B","B","T","T"),marker=c("MS4A1","CD79A","CD3D","CD3E"),
      species="human",tissue="blood"))
  state <- .sc_run_load(root)
  expect_null(state$config$scientific_review)
  expect_identical(state$config$basic_expression_review$panel_set,"blood")
  expect_identical(state$pending$proposal$plan$pcs$method,"computed_top50")
  for (i in 1:2) {
    view <- sc_run_inspect(root)
    expect_identical(view$pending$kind,"strategy")
    sc_run_approve(root,view$pending$hash,reviewer="test",reason="Software policy control",expected_revision=view$revision)
    approved <- sc_run_inspect(root)
    suppressWarnings(sc_run_continue(root,approved$project_id,approved$input_hash,approved$revision))
  }
  state <- .sc_run_load(root)
  expect_false(identical(state$status,"failed"), info=if(is.null(state$failure)) "" else state$failure$message)
  scan <- .sc_run_get(root,state,"cluster_scan")
  expect_length(scan$resolutions,6L)
  expect_false(is.null(scan$tree))
  expect_null(scan$scientific_diagnostics)
  evidence <- .sc_run_get(root,state,"annotation_evidence")
  expression <- evidence$private$expression_review
  expect_identical(expression$status,"measured")
  expect_true("TRAC" %in% expression$missing_genes)
  expect_false("cited_marker_review" %in% names(expression$panels))
  expect_null(expression$mixed_lineage)
  expect_true(all(vapply(expression$clusters,function(row) identical(row$cross_sample_status,"unavailable"),logical(1))))
  gene <- expression$clusters[[1]]$genes[[1]]
  expect_true(is.finite(gene$mean_log_normalized))
  expect_true(gene$pct_detected>=0 && gene$pct_detected<=1)
  expect_false(is.null(evidence$private$reference_evidence))
  expect_true(any(vapply(evidence$private$reference_evidence$per_cluster,
    function(row) identical(row$enrichment$status,"measured"),logical(1))))
  absent <- state$config
  absent$basic_expression_review$panels <- list(only="ABSENT_CLASSIC_GENE")
  unavailable <- attr(.sc_run_markers(.sc_run_get(root,state,"analysis"),absent)$marker_summary,"expression_review")
  expect_identical(unavailable$status,"unavailable")
  expect_identical(unavailable$missing_genes,"ABSENT_CLASSIC_GENE")
  expect_match(unavailable$reason,"None of the declared")
  expect_identical(.sc_run_hash(input),before)
})
