

test_that("current coordinator internals do not emit entry-point deprecations", {
  withr::local_options(lifecycle_verbosity="warning")
  obj <- SeuratObject::pbmc_small
  obj$seurat_clusters <- as.character(SeuratObject::Idents(obj))
  markers <- data.frame(cluster=unique(obj$seurat_clusters),gene="MS4A1",
    avg_log2FC=2,pct.1=.9,pct.2=.1,p_val_adj=.001)
  notices <- list()
  withCallingHandlers(scAgentKit:::.sc_run_annotation_evidence(obj,markers,
    context=list(species="human",tissue="blood"),
    reference=data.frame(cell_type="B cell",marker="MS4A1",species="human",tissue="blood")),
    warning=function(w) if(inherits(w,"lifecycle_warning_deprecated")) {
      notices[[length(notices)+1L]] <<- w;invokeRestart("muffleWarning")
    })
  expect_length(notices,0)
})
