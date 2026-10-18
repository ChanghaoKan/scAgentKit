test_that("first annotation submissions bind evidence and remain separate from approval", {
  data("pbmc_small", package = "SeuratObject", envir = environment())
  pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(pbmc_small))
  path <- tempfile()
  suppressWarnings(sc_run(pbmc_small, path, start_stage = "processed",
    processed_reason = "Public software fixture, not a biological annotation example", provider = NULL))
  view <- sc_run_inspect(path)
  preparation <- view$annotation_preparation
  expect_identical(preparation$schema, "scagentkit.annotation-preparation.v1")
  expect_null(view$review_node)
  expect_null(view$pending)
  expect_gt(length(preparation$clusters), 0L)
  original <- .sc_project_sha_file(file.path(path, "state.rds"))
  expect_identical(sc_run_inspect(path)$annotation_preparation, preparation)
  expect_identical(.sc_project_sha_file(file.path(path, "state.rds")), original)
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(preparation$clusters,
    function(cluster) list(clusterId = cluster$clusterId, label = "Unknown", confidence = "low",
      rationale = "Analyst explicitly retains unresolved software-fixture populations.", markers = list())))
  args <- list(project_dir = path, project_id = view$project_id, input_hash = view$input_hash,
    expected_revision = view$revision, evidence_hash = preparation$evidence_hash, proposal = proposal,
    reviewer = "offline reviewer", reason = "Explicit unresolved proposal for software testing", request_id = "first-worksheet")
  invalid <- args; invalid$proposal$annotations[[1]]$label <- ""
  expect_error(do.call(sc_run_prepare_annotation, invalid))
  expect_identical(.sc_project_sha_file(file.path(path, "state.rds")), original)
  for (field in c("project_id", "input_hash", "evidence_hash", "expected_revision")) {
    invalid <- args; invalid[[field]] <- switch(field, project_id = "foreign", expected_revision = args$expected_revision + 1, paste(rep("0", 64), collapse = ""))
    expect_error(do.call(sc_run_prepare_annotation, invalid))
    expect_identical(.sc_project_sha_file(file.path(path, "state.rds")), original)
  }
  owner <- .sc_run_lock(path)
  expect_error(do.call(sc_run_prepare_annotation, args), "locked")
  .sc_run_release(path, owner)
  saved <- do.call(sc_run_prepare_annotation, args)
  expect_identical(saved$status, "awaiting_review")
  expect_identical(saved$review_node$kind, "annotation")
  expect_null(saved$annotation_preparation)
  expect_null(saved$output)
  expect_false("annotation_apply" %in% saved$completed)
  state_hash <- .sc_project_sha_file(file.path(path, "state.rds"))
  expect_identical(do.call(sc_run_prepare_annotation, args)$revision, saved$revision)
  expect_identical(.sc_project_sha_file(file.path(path, "state.rds")), state_hash)
  invalid <- args; invalid$reason <- "Different payload"
  expect_error(do.call(sc_run_prepare_annotation, invalid), "reused")
  stale <- args; stale$request_id <- "another-request"
  expect_error(do.call(sc_run_prepare_annotation, stale), "Stale")
  sc_run_approve(path, saved$pending$hash, "offline reviewer", "Reviewed the unresolved result")
  expect_identical(suppressWarnings(sc_run_resume(path))$status, "complete")
})
