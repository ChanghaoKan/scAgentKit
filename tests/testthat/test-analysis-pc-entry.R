test_that("entry PC draft uses the existing top50 internal variance policy", {
  draft <- .sc_ui_plan(dimensions = c(2500L, 500L))
  expect_identical(draft$analysis$npcs, 50L)
  expect_identical(draft$pcs, list(method = "computed_top50", threshold = .80))
  expect_match(paste(draft$risks, collapse = " "), "not total")
  small <- .sc_ui_plan(dimensions = c(5L, 40L))
  expect_identical(small$analysis$npcs, 4L)
  expect_match(paste(small$risks, collapse = " "), "4")
  fewer <- .sc_ui_plan(list(analysis = list(nfeatures = 3L)), dimensions = c(100L, 40L))
  expect_identical(fewer$analysis$npcs, 2L)
})

test_that("normalized nonconstant genes constrain the visible default request without dense rank claims", {
  set.seed(702L)
  counts <- matrix(rpois(5L * 40L, 5), 5L, 40L,
    dimnames = list(paste0("G", seq_len(5L)), paste0("C", seq_len(40L))))
  counts <- rbind(counts, constantZero = 0)
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  config <- list(assay = "RNA", counts_layer = "counts")
  limits <- .sc_ui_pc_limits(seu, config, 10000)
  expect_identical(limits$nonconstant_normalized_features, 5L)
  expect_identical(limits$total_features, 6L)
  expect_match(limits$interpretation, "not a numerical rank")
  draft <- .sc_ui_plan(dimensions = dim(seu), pc_limits = limits)
  expect_identical(draft$analysis$nfeatures, 5L)
  expect_identical(draft$analysis$npcs, 4L)
  expect_equal(nrow(seu), 6L)
  fixed <- .sc_ui_plan(list(analysis = list(npcs = 8L)), dimensions = dim(seu), pc_limits = limits)
  expect_identical(fixed$analysis$npcs, 8L) # never silently repair an explicit request
  constant <- Seurat::CreateSeuratObject(Matrix::Matrix(matrix(1, 6, 40, dimnames = dimnames(counts)), sparse = TRUE), min.cells = 0, min.features = 0)
  expect_error(.sc_ui_pc_limits(constant, config, 10000), "Fewer than three.*nonconstant")
})

test_that("the default candidate retains exact 80 percent crossing and unsupported one-PC states", {
  equal <- .sc_run_pc_candidates(rep(1, 50L))
  expect_identical(equal$candidates$p80$ndim, 40L)
  dominated <- .sc_run_pc_candidates(c(3, 1))
  expect_false(dominated$candidates$p80$supported)
  expect_identical(dominated$candidates$p80$ndim, 1L)
  for (bad in list(c(0, 1), c(NA_real_, 1), c(Inf, 1)))
    expect_error(.sc_run_pc_candidates(bad), "finite, strictly positive")
})


test_that("numerically rank deficient approved PCA blocks rather than silently clipping", {
  cells <- paste0("C", seq_len(30L))
  counts <- Matrix::Matrix(matrix(1, 5L, 30L,
    dimnames = list(paste0("G", 1:5), cells)), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  embeddings <- matrix(seq_len(60L), 30L, 2L,
    dimnames = list(cells, c("PC_1", "PC_2")))
  seu[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
    stdev = c(3, 1e-16), key = "PC_", assay = "RNA")
  settings <- list(analysis = list(npcs = 2L, nfeatures = 5L),
    pcs = list(method = "fixed", ndim = 2L))
  expect_error(.sc_run_strategy_pca_evidence(seu, settings), "numerical rank.*no clipping")
  expect_identical(SeuratObject::Stdev(seu[["pca"]]), c(3, 1e-16))
})
