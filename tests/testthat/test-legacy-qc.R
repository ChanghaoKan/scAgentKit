legacy_qc_object <- function(n = 120L, hb_reads = 3L) {
  set.seed(11)
  genes <- c("MT-CO1", "RPL3", "RPS6", "HBB", paste0("GENE", 1:60))
  counts <- matrix(rpois(length(genes) * n, 4), nrow = length(genes),
    dimnames = list(genes, sprintf("cell%03d", seq_len(n))))
  counts["HBB", ] <- 0L
  counts["HBB", seq_len(hb_reads)] <- 1L
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  seu$batch <- rep(c("b1", "b2"), length.out = n)
  AgentSeurat(seu)
}

test_that("legacy qc_mad skips a zero-MAD metric instead of removing every expressing cell", {
  obj <- qc_add_metrics(legacy_qc_object(), species = "human")
  before <- ncol(obj@data)
  out <- qc_mad(obj, metrics = "percent.hb")
  expect_identical(ncol(out@data), before)
})

test_that("legacy qc_mad accepts fractional nmad and keeps NA-group cells", {
  obj <- qc_add_metrics(legacy_qc_object(), species = "human")
  obj@data$batch[1:5] <- NA
  out <- qc_mad(obj, nmad = 2.5, group_by = "batch", metrics = "nCount_RNA")
  expect_s4_class(out, "AgentSeurat")
  wide <- qc_mad(obj, nmad = 100, group_by = "batch", metrics = "nCount_RNA")
  expect_identical(ncol(wide@data), ncol(obj@data))
})

test_that("qc_remove_genes detects species instead of silently defaulting to mouse", {
  obj <- legacy_qc_object()
  out <- qc_remove_genes(obj)
  expect_false(any(c("MT-CO1", "RPL3", "RPS6", "HBB") %in% rownames(out@data)))
})

test_that("Ensembl mouse identifiers are not detected as human", {
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(matrix(1, 3, 3,
    dimnames = list(c("ENSMUSG00000000001", "ENSMUSG00000000028", "ENSMUSG00000000031"), paste0("c", 1:3))),
    sparse = TRUE), min.cells = 0, min.features = 0)
  expect_identical(scAgentKit:::.detect_species(seu), "mouse")
})
