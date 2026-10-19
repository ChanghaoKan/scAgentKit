test_that("marker summaries rank fold change first and detection difference second", {
  markers <- data.frame(cluster="0",gene=c("HIGH_DIFF","HIGH_FC","TIE_LOW","TIE_HIGH"),
    avg_log2FC=c(2,5,3,3),pct.1=c(.9,.3,.5,.7),pct.2=c(.1,.2,.3,.2),p_val_adj=.001)
  before <- markers
  out <- .sc_marker_summary(markers,top_n=3,log2fc_cut=1,padj_cut=.05)$filtered
  expect_identical(out$gene,c("HIGH_FC","TIE_HIGH","TIE_LOW"))
  expect_identical(markers,before)
})

test_that("annotation query excludes shared symbols without filtering the full marker table", {
  env <- new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  seu <- env$pbmc_small; seu$seurat_clusters <- as.character(SeuratObject::Idents(seu))
  fixture <- data.frame(cluster="0",gene=c("RPL13A","RPS3","MT-CO1","RPS6KA1","CD3D"),
    avg_log2FC=c(10,9,8,3,2),pct.1=.8,pct.2=.1,p_val=.001,p_val_adj=.001)
  local_mocked_bindings(.sc_marker_test=function(...) fixture,.package="scAgentKit")
  out <- .sc_run_markers(seu,list())
  expect_identical(out$markers$gene,fixture$gene)
  expect_identical(out$marker_summary$gene,c("RPS6KA1","CD3D"))
  expect_identical(unlist(attr(out$marker_summary,"marker_pool")$exclusions$excluded_genes),c("RPL13A","RPS3","MT-CO1"))
  full <- .sc_run_markers(seu,list(markers=list(exclude_shared=FALSE)))
  expect_identical(full$marker_summary$gene,fixture$gene)
  explicit <- .sc_run_markers(seu,list(markers=list(exclude_shared=FALSE,exclude_genes="CD3D")))
  expect_false("CD3D" %in% explicit$marker_summary$gene)
  expect_true("CD3D" %in% explicit$markers$gene)
  expect_error(.sc_run_markers(seu,list(markers=list(exclude_shared=NA))),"exclude_shared")
})
