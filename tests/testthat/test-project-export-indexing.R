test_that("export integer reads retain literal ID joins after shuffled input", {
  cells <- c("z", "001", "a", "1", "NA", "cell space")
  genes <- c("Other", "CD3D", "CD3E", "KLRD1")
  counts <- matrix(seq_len(24), nrow = 4, dimnames = list(genes, cells))
  seu <- SeuratObject::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE))
  SeuratObject::LayerData(seu, layer = "data") <- log1p(counts)
  seu$seurat_clusters <- rep(c("B", "A"), 3)
  seu$percent.mt <- seq_along(cells)
  seu$source_label <- paste0("source:", cells)
  coordinates <- cbind(UMAP_1 = seq_along(cells), UMAP_2 = seq_along(cells) * 10)
  rownames(coordinates) <- cells
  seu[["umap"]] <- SeuratObject::CreateDimReducObject(embeddings = coordinates, key = "UMAP_", assay = "RNA")
  path <- tempfile()
  sc_project_export(seu[rev(genes), rev(cells)], path, "indexing", directed_clusters = "A", source_annotation = "source_label")
  project <- jsonlite::fromJSON(file.path(path, "project.json"), simplifyVector = FALSE)
  for (cell in project$cells) {
    i <- match(cell$cellId, cells)
    expect_equal(cell$qc$percent.mt, i)
    expect_identical(cell$clusterId, as.character(seu$seurat_clusters[i]))
  }
  for (point in project$embedding$points) {
    i <- match(point$cellId, cells)
    expect_equal(c(point$x, point$y), unname(coordinates[i, ]))
  }
  for (record in project$sourceAnnotation$values) expect_identical(record$value, paste0("source:", record$cellId))
  directed <- jsonlite::fromJSON(file.path(path, project$directed$clusters$A$path), simplifyVector = FALSE)
  for (cell in directed$cells) {
    for (gene in c("CD3D", "CD3E", "KLRD1")) {
      expect_equal(cell$counts[[gene]], unname(counts[gene, cell$cell_id]))
      expect_equal(cell$normalized[[gene]], unname(log1p(counts[gene, cell$cell_id])))
    }
    expect_null(cell$counts$CD3G)
    expect_null(cell$normalized$CD3G)
    expect_equal(cell$qc$percent.mt, match(cell$cell_id, cells))
  }
})
