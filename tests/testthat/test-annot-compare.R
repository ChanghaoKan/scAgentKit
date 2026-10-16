compare_object <- function(cells) {
  counts <- Matrix::Matrix(matrix(1, 3, length(cells), dimnames = list(paste0("G", 1:3), cells)), sparse = TRUE)
  AgentSeurat(Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0))
}

test_that("stripped barcodes that repeat across samples are never used to align", {
  obj <- compare_object(c("S1_AAA", "S1_CCC", "S2_AAA", "S2_CCC"))
  ref <- c(X_AAA = "T", Y_AAA = "B", X_CCC = "NK", Y_CCC = "Mono")
  expect_error(scAgentKit:::.align_external_celltype(obj, ref), "repeat across samples")
})

test_that("unique stripped barcodes still align", {
  obj <- compare_object(c("S1_AAA", "S1_CCC", "S2_GGG", "S2_TTT"))
  ref <- c(AAA = "T", CCC = "B", GGG = "NK", TTT = "Mono")
  out <- scAgentKit:::.align_external_celltype(obj, ref)
  expect_identical(unname(out), c("T", "B", "NK", "Mono"))
})
