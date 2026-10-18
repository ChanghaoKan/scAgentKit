test_that("high-level science options survive empty resolution grids and require measured review", {
  input <- SeuratObject::pbmc_small; before <- .sc_run_hash(input); root <- tempfile()
  x <- sc_analyze(input,root,context=list(species="human",tissue="Blood",research_goal="Software entry control"),
    plan=list(analysis=list(nfeatures=100L,npcs=6L),pcs=4L,diagnostic_resolutions=NULL,umap=FALSE),
    scientific_review=list(pc_sensitivity=TRUE,panels=list(B=c("MS4A1","CD79A"))))
  shown <- suppressMessages(sc_review(x))
  next_review <- suppressWarnings(sc_review(shown,"approve",reviewer="test",reason="Explicit diagnostic computation",continue=TRUE))
  state <- .sc_run_load(root)
  expect_identical(state$pending$kind,"strategy")
  expect_false(is.null(state$files$cluster_scan))
  scan <- .sc_run_get(root,state,"cluster_scan")
  expect_identical(scan$scientific_diagnostics$pc_sensitivity$status,"measured")
  expect_identical(scan$scientific_diagnostics$expression$status,"measured")
  expect_false(is.null(state$config$scientific_review))
  expect_null(state$files$annotation_validated)
  expect_identical(.sc_run_hash(input),before)
})
