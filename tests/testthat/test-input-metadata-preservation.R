input_metadata_fixture <- function() {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  seu <- env$pbmc_small
  seu$sc_annotation <- rep(c("prior-A", "prior-B"), each = 40)
  seu$sc_annotation_confidence <- "old-confidence"
  seu$sc_annotation_rationale <- "Prior result, not new evidence."
  seu@misc$scagentkit_input_metadata <- "Prior user-owned misc value."
  seu
}

test_that("metadata preservation is separate, collision safe and exactly keyed", {
  seu <- input_metadata_fixture(); original <- .sc_run_hash(seu)
  checked <- .sc_run_input(seu, input_policy = list(preserve_metadata = TRUE))
  key <- checked$diagnostics$preserved_metadata$key
  expect_identical(key, "scagentkit_input_metadata.1")
  expect_identical(checked$seu@misc$scagentkit_input_metadata, seu@misc$scagentkit_input_metadata)
  record <- .sc_run_preserved_metadata_verify(checked$seu, key)
  expect_identical(record$metadata, seu[[]])
  expect_identical(record$cell_id_map$input_cell_id, colnames(seu))
  expect_identical(record$cell_id_map$analysis_cell_id, colnames(seu))
  expect_identical(record$column_map$input_field, names(seu[[]]))
  expect_identical(.sc_run_hash(seu), original)
  expect_error(.sc_run_annotation_target(checked$seu, "sc_annotation", "seurat_clusters"), "already exist")
  expect_identical(.sc_run_annotation_target(checked$seu, "sc_annotation", "seurat_clusters", key)[["label"]], "sc_annotation")
  expect_error(.sc_run_annotation_target(checked$seu, "seurat_clusters", "seurat_clusters", key), "conflict")
  changed <- checked$seu; changed@misc[[key]]$metadata$sc_annotation[[1L]] <- "modified"
  expect_error(.sc_run_annotation_target(changed, "sc_annotation", "seurat_clusters", key), "changed")
  changed <- checked$seu; changed@misc[[key]]$cell_id_map$analysis_cell_id[[1L]] <- "foreign"
  expect_error(.sc_run_preserved_metadata_verify(changed, key), "changed")
})

test_that("new project stores the preservation receipt without approving prior annotations", {
  source <- tempfile(fileext = ".rds"); root <- tempfile()
  on.exit(unlink(c(source, root), recursive = TRUE))
  seu <- input_metadata_fixture(); saveRDS(seu, source); before <- .sc_project_sha_file(source)
  expect_error(sc_run(source, tempfile()), "already exist")
  view <- sc_run(source, root, input_policy = list(preserve_metadata = TRUE))
  state <- .sc_run_load(root)
  expect_length(state$approvals, 0L)
  expect_null(state$files$analysis)
  record <- .sc_run_preserved_metadata_verify(.sc_run_get(root, state, "input"), state$config$input_policy$metadata_key)
  expect_identical(record$metadata, seu[[]])
  expect_identical(.sc_project_sha_file(source), before)
  events <- Filter(function(event) identical(event$action, "input_metadata_preserved"), state$history)
  expect_length(events, 1L)
  expect_identical(events[[1L]]$details$hash, record$hash)
  expect_identical(sc_run_inspect(root)$status, view$status)
})

preservation_review <- function(...) {
  invisible(capture.output(value <- sc_review(...)))
  value
}

test_that("three human approvals can write new labels while all prior metadata stays recoverable", {
  input <- input_metadata_fixture(); before <- .sc_run_hash(input); root <- tempfile()
  on.exit(unlink(root, recursive = TRUE))
  project <- sc_analyze(input, root,
    context = list(species = "human", tissue = "Public PBMC", columns = list(sample = "orig.ident")),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  initial <- preservation_review(project)
  measured <- suppressWarnings(preservation_review(initial, "approve", reviewer = "human-test",
    reason = "Reviewed public fixture initial strategy.", continue = TRUE))
  measured <- preservation_review(measured)
  annotation <- suppressWarnings(preservation_review(measured, "approve", reviewer = "human-test",
    reason = "Reviewed measured fixture PC and resolution evidence.", continue = TRUE))
  labels <- annotation$annotations
  labels$label <- "Unknown"; labels$confidence <- "low"
  labels$rationale <- "New software-control abstention; prior labels do not establish identity."
  labels$markers <- ""
  proposal <- preservation_review(annotation, "revise", annotations = labels,
    reviewer = "human-test", reason = "Stage new Unknown labels for explicit review.")
  done <- suppressWarnings(preservation_review(proposal, "approve", reviewer = "human-test",
    reason = "Reviewed the complete new annotations.", continue = TRUE))
  expect_identical(done$view$status, "complete")
  result <- sc_result(done); state <- .sc_run_load(root)
  preserved <- .sc_run_preserved_metadata_verify(result, state$config$input_policy$metadata_key)
  expect_identical(preserved$metadata, input[[]])
  expect_true(all(result$sc_annotation == "Unknown"))
  expect_identical(preserved$metadata$sc_annotation, input[[]]$sc_annotation)
  expect_identical(result@misc$scagentkit_input_metadata, input@misc$scagentkit_input_metadata)
  expect_identical(.sc_run_hash(input), before)
  expect_identical(colnames(result), colnames(input))
  expect_length(state$approvals, 3L)
})
