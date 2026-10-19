input_layer_fixture <- function() {
  set.seed(19)
  counts <- matrix(rpois(8 * 30, 3), nrow = 8,
    dimnames = list(paste0("GENE", 1:8), paste0("cell-", 1:30)))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  seu$sample <- rep(c("A", "B"), each = 15)
  SeuratObject::LayerData(seu, layer = "data") <- log1p(SeuratObject::LayerData(seu, layer = "counts"))
  seu
}

test_that("same-assay layer joins retain source values, metadata, other assays and source object", {
  seu <- input_layer_fixture()
  other <- seu[["RNA"]]; SeuratObject::Key(other) <- "other_"
  seu[["OTHER"]] <- other
  original <- .sc_run_hash(seu)
  split <- seu; split[["RNA"]] <- split(split[["RNA"]], f = split$sample)
  before <- .sc_run_hash(split)
  checked <- .sc_run_input(split, list(species = "human", columns = list(sample = "sample")))
  expect_identical(.sc_run_hash(split), before)
  expect_identical(checked$seu[[]], seu[[]])
  expect_identical(checked$seu[["OTHER"]], seu[["OTHER"]])
  expect_equal(.sc_project_layer(checked$seu, "RNA", "counts"), .sc_project_layer(seu, "RNA", "counts"))
  expect_equal(.sc_project_layer(checked$seu, "RNA", "data"), .sc_project_layer(seu, "RNA", "data"))
  expect_length(checked$diagnostics$input_transforms, 2L)
  expect_true(all(vapply(checked$diagnostics$input_transforms, function(x) x$exact_value_and_coverage_check, logical(1))))
  expect_true("scagentkit_layer_joins" %in% names(checked$seu@misc))
  expect_length(.sc_run_input(checked$seu)$diagnostics$input_transforms, 0L)
  expect_identical(.sc_run_hash(seu), original)
})

test_that("mixed exact/split, overlapping, incomplete and different-feature layers fail closed", {
  seu <- input_layer_fixture()
  counts <- SeuratObject::LayerData(seu, layer = "counts")
  mixed <- seu
  SeuratObject::LayerData(mixed, layer = "counts.extra") <- counts
  expect_error(.sc_run_input(mixed), "Exact and split")
  for (mode in c("overlap", "incomplete", "features")) {
    parts <- list(A = counts[, 1:15], B = counts[, 16:30])
    if (mode == "overlap") parts$B <- counts[, 15:30]
    if (mode == "incomplete") parts$B <- counts[, 16:29]
    if (mode == "features") parts$B <- parts$B[-1, , drop = FALSE]
    candidate <- seu
    if (mode == "incomplete") expect_warning(
      candidate[["RNA"]] <- SeuratObject::CreateAssay5Object(counts = parts), "Different cells")
    else candidate[["RNA"]] <- SeuratObject::CreateAssay5Object(counts = parts)
    expect_error(.sc_run_input(candidate), if (mode == "features") "different feature sets" else "every object cell exactly once")
  }
  # The strict output reader itself must still reject split layers.
  candidate <- seu; candidate[["RNA"]] <- split(candidate[["RNA"]], f = candidate$sample)
  expect_error(.sc_project_identity(candidate), "Exact layer|Split")
})

test_that("a split RDS keeps its original file receipt and records verified joins in history", {
  seu <- input_layer_fixture(); seu[["RNA"]] <- split(seu[["RNA"]], f = seu$sample)
  source <- tempfile(fileext = ".rds"); root <- tempfile()
  on.exit(unlink(c(source, root), recursive = TRUE))
  saveRDS(seu, source); before <- .sc_project_sha_file(source)
  view <- sc_run(source, root, context = list(species = "human", columns = list(sample = "sample")))
  state <- .sc_run_load(root)
  expect_identical(state$source$rds_sha256, before)
  expect_identical(.sc_project_sha_file(source), before)
  events <- Filter(function(event) identical(event$action, "input_layers_joined"), state$history)
  expect_length(events, 1L); expect_length(events[[1L]]$details$transforms, 2L)
  expect_false(events[[1L]]$details$source_replaced)
  expect_length(state$approvals, 0L)
  expect_equal(.sc_project_layer(.sc_run_get(root, state, "input"), "RNA", "counts"),
    .sc_project_matrix(SeuratObject::LayerData(input_layer_fixture(), layer = "counts"), "source", TRUE))
  expect_identical(sc_run_inspect(root)$status, view$status)
})
