test_that("preparation aligns shuffled counts, metadata and normalized values by ID", {
  set.seed(102)
  counts <- matrix(sample.int(48L * 16L), 48L, 16L,
    dimnames = list(sample(sprintf("gene%02d", 1:48)),
                    sample(sprintf("cell%02d", 1:16))))
  counts <- Matrix::Matrix(counts, sparse = TRUE)
  canonical <- counts[sort(rownames(counts)), sort(colnames(counts)), drop = FALSE]
  expected <- Seurat::NormalizeData(counts, verbose = FALSE)
  metadata <- data.frame(source_id = paste0("source:", colnames(counts)),
    numeric_tag = seq_len(ncol(counts)) * 7L, row.names = colnames(counts))

  # Exercise both the current Assay5 and the supported pre-existing Assay
  # representation, rather than relying on a constructor's default ordering.
  for (assay_version in c("v5", "v3")) {
    withr::local_options(Seurat.object.assay.version = assay_version)
    object <- Seurat::CreateSeuratObject(counts = counts, meta.data = metadata)
    # A stale data layer with independently shuffled IDs must be replaced.
    SeuratObject::LayerData(object, assay = "RNA", layer = "data") <-
      expected[rev(rownames(expected)), rev(colnames(expected)), drop = FALSE] * 2
    before <- object
    expect_equal(scAgentKit:::.sc_project_layer(object, "RNA", "counts", TRUE), canonical)
    prepared <- suppressWarnings(sc_project_prepare(object,
      nfeatures = 24, npcs = 3, dims = 1:3, run_umap = FALSE, seed = 102))
    expect_identical(object, before)
    expect_identical(colnames(prepared), colnames(object))
    expect_identical(rownames(prepared), rownames(object))
    expect_equal(SeuratObject::LayerData(prepared, assay = "RNA", layer = "counts"), counts)
    actual <- SeuratObject::LayerData(prepared, assay = "RNA", layer = "data")
    expect_equal(actual[rownames(expected), colnames(expected), drop = FALSE], expected)
    expect_identical(prepared@meta.data[colnames(counts), c("source_id", "numeric_tag")], metadata)
    expect_equal(scAgentKit:::.sc_project_layer(prepared, "RNA", "data"),
      expected[rownames(canonical), colnames(canonical), drop = FALSE])
  }
})
