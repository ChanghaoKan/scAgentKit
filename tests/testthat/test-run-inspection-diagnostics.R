# Inspection projects are fresh synthetic controls. Counts refer to actual
# saved objects, never an expected proposal impact or inherited execution claim.
inspection_diagnostics_fixture <- function() {
  set.seed(419L)
  counts <- matrix(stats::rpois(81L * 80L, 2), nrow = 81L,
    dimnames = list(c("MT-CO1", paste0("InspectionGene", 2:81)),
      c("1", "001", "NA", "cell space", paste0("InspectionCell", 5:80))))
  counts[2:20, 1:40] <- counts[2:20, 1:40] + 15L
  counts[21:40, 41:80] <- counts[21:40, 41:80] + 15L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  object$sample <- rep(c("sample A", "sample B"), each = 40L)
  object$seurat_clusters <- rep(c("01", "NA"), each = 40L)
  object$private_note <- "PRIVATE_INSPECTION_NOTE"
  object
}
inspection_diagnostics_files <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!dir.exists(paths)]
  stats::setNames(vapply(paths, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(paths, nchar(root) + 2L))
}

test_that("inspection does not invent actual counts for older non-Seurat fixture checkpoints", {
  root <- tempfile("inspection-no-object-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  state <- scAgentKit:::.sc_run_put(root, list(files = list(), config = list(start_stage = "raw")),
    "input", list(n_cells = 1000000L, expected_retained = 999999L))
  actual <- scAgentKit:::.sc_run_stage_counts(root, state)
  expect_identical(actual$input$status, "unavailable")
  expect_identical(actual$input$source, "non_seurat_checkpoint")
  expect_null(actual$input$cells)
  expect_null(actual$input$artifact_sha256)
})

test_that("inspection exposes verified prefilter counts before any quality QC executes", {
  root <- tempfile("inspection-prefilter-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- inspection_diagnostics_fixture()
  counts <- SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  counts[, 1] <- 0
  SeuratObject::LayerData(object, assay = "RNA", layer = "counts") <- counts
  before <- serialize(object, NULL, version = 2L)
  run <- suppressWarnings(sc_run(object, root, strategy = TRUE,
    context = list(species = "human", tissue = "synthetic", columns = list(sample = "sample")),
    qc_mad = list(grouping = list(method = "column", column = "sample", declared_role = "sample",
      source = "Explicit synthetic quality groups."), prefilter = list(method = "min_counts",
      min_counts = 1L, preapproved = TRUE, source = "Remove only a preapproved synthetic zero-count cell."))))
  expect_identical(run$status, "awaiting_configuration")
  expect_identical(run$stage, "strategy_propose")
  files <- inspection_diagnostics_files(root)
  inspected <- sc_run_inspect(root)
  expect_identical(inspection_diagnostics_files(root), files)
  expect_identical(serialize(object, NULL, version = 2L), before)
  state <- scAgentKit:::.sc_run_load(root)
  actual <- inspected$computed_diagnostics$stage_counts
  expect_identical(actual$schema, "scagentkit.stage-counts.v1")
  expect_identical(actual$input, list(status = "saved", source = "input_checkpoint",
    artifact_sha256 = state$files$input$sha256, cells = 80))
  prefilter <- scAgentKit:::.sc_run_get(root, state, "prefilter")
  expect_identical(actual$prefilter, list(status = "saved", source = "verified_prefilter_record",
    artifact_sha256 = state$files$prefilter$sha256, method = "min_counts",
    original_cells = length(prefilter$cell_ids), eligible_cells = length(prefilter$keep_cells),
    excluded_cells = length(prefilter$excluded_cells)))
  expect_identical(actual$prefilter$eligible_cells, 79L)
  for (name in c("qc", "selection", "analysis", "output")) {
    expect_identical(actual[[name]]$status, "unavailable")
    expect_null(actual[[name]]$cells)
    expect_null(actual[[name]]$artifact_sha256)
  }
  expect_null(inspected$computed_diagnostics$all_pc_variance)
  expect_null(inspected$computed_diagnostics$cluster_candidates)
  public <- scAgentKit:::.sc_project_json(actual)
  for (private in c("InspectionCell", "cell space", "PRIVATE_INSPECTION_NOTE", "cell_ids", root))
    expect_false(grepl(private, public, fixed = TRUE))
  file <- file.path(root, state$files$input$path)
  saveRDS(object[, -1], file)
  expect_error(sc_run_inspect(root), "Saved input/evidence/checkpoint changed")
})

test_that("processed inspection distinguishes reused cells from executed QC and final output", {
  root <- tempfile("inspection-processed-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- suppressWarnings(Seurat::NormalizeData(inspection_diagnostics_fixture(), verbose = FALSE))
  # A source execution claim cannot populate any new calculation diagnostic.
  object@misc$strategy_execution <- list(basis = list(pca = list(available_pcs = 900L)),
    cluster = list(candidates = list(list(resolution = 99, n_clusters = 900L))))
  run <- suppressWarnings(sc_run(object, root, start_stage = "processed",
    processed_reason = "Use explicitly supplied normalized synthetic clusters.",
    context = list(species = "human", tissue = "synthetic", columns = list(sample = "sample"))))
  expect_identical(run$status, "awaiting_configuration")
  files <- inspection_diagnostics_files(root)
  inspected <- sc_run_inspect(root)
  expect_identical(inspection_diagnostics_files(root), files)
  state <- scAgentKit:::.sc_run_load(root)
  actual <- inspected$computed_diagnostics$stage_counts
  expect_identical(actual$analysis, list(status = "saved", source = "processed_reused_analysis_checkpoint",
    artifact_sha256 = state$files$analysis$sha256, cells = 80))
  for (name in c("qc", "selection")) {
    expect_identical(actual[[name]]$status, "processed_reused")
    expect_identical(actual[[name]]$source, "explicit_processed_input")
    expect_null(actual[[name]]$cells)
    expect_null(actual[[name]]$artifact_sha256)
  }
  expect_identical(actual$output$status, "unavailable")
  expect_null(actual$output$cells)
  expect_identical(actual$prefilter$status, "unavailable")
  expect_null(inspected$computed_diagnostics$all_pc_variance)
  expect_null(inspected$computed_diagnostics$cluster_candidates)
})
