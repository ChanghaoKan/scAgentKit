test_that("marker calculation follows seurat_clusters after an identity-changing sweep", {
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  obj <- suppressWarnings(sc_cluster_sweep(obj,resolutions=c(.1,1.2),plot_dir=tempfile()))
  SeuratObject::Idents(obj@data) <- "RNA_snn_res.0.1"
  expect_false(identical(as.character(SeuratObject::Idents(obj@data)),
    as.character(obj@data$seurat_clusters)))
  expected <- suppressWarnings(Seurat::FindAllMarkers(obj@data,
    group.by="seurat_clusters",only.pos=FALSE,min.pct=.25,logfc.threshold=0,verbose=FALSE))
  actual <- suppressWarnings(sc_find_markers(obj))
  expect_equal(actual@params$all_markers,expected,tolerance=1e-8)
})
