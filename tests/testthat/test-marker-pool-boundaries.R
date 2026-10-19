test_that("main marker pool keeps strict FC p-adjusted and top-30 boundaries", {
  withr::local_options(lifecycle_verbosity="quiet")
  good<-data.frame(cluster="0",gene=paste0("G",1:31),avg_log2FC=2,p_val_adj=.001,
    pct.1=seq(.99,.69,length.out=31),pct.2=.1)
  boundary<-good[1:3,];boundary$gene<-c("FC_EQUAL","FC_BELOW","PADJ_EQUAL")
  boundary$avg_log2FC<-c(1,.99,2);boundary$p_val_adj<-c(.001,.001,.05)
  full<-rbind(good,boundary)
  result<-sc_markers_summary(full,output_path=NULL)
  expect_identical(as.character(result$gene),paste0("G",1:30))
  expect_false(any(c("G31",boundary$gene) %in% result$gene))
  expect_identical(nrow(full),34L)
})

test_that("both native pct columns contribute via maximum not an AND prefilter", {
  obj<-SeuratObject::pbmc_small
  SeuratObject::Idents(obj)<-rep(c("0","1"),length.out=ncol(obj))
  testthat::local_mocked_bindings(FoldChange=function(...) data.frame(
    pct.1=c(.25,0,.249,.25),pct.2=c(0,.25,.249,.25),
    row.names=c("INSIDE_ONLY","OUTSIDE_ONLY","BELOW","BOTH")),.package="Seurat")
  value<-.sc_run_marker_background(obj,"RNA",list(logfc_threshold=0,only_pos=FALSE,min_pct=.25))
  expect_setequal(value[["0"]],c("INSIDE_ONLY","OUTSIDE_ONLY","BOTH"))
  expect_identical(value[["0"]],value[["1"]])
})

test_that("native marker pool provenance reaches saved annotation evidence", {
  withr::local_options(lifecycle_verbosity="quiet")
  obj<-SeuratObject::pbmc_small
  obj$seurat_clusters<-as.character(SeuratObject::Idents(obj))
  result<-suppressWarnings(.sc_run_markers(obj,list()))
  policy<-attr(result$marker_summary,"marker_pool")
  expect_identical(policy$status,"recorded")
  expect_identical(policy$parameters$top_n,30L)
  expect_identical(policy$parameters$log2fc_cut,1)
  evidence<-.sc_run_annotation_evidence(obj,result,list())
  expect_identical(evidence$summary$marker_pool,policy)
  restored<-unserialize(serialize(evidence,NULL))
  expect_identical(restored$summary$marker_pool,policy)
  supplied<-result$marker_summary;attr(supplied,"marker_pool")<-NULL
  expect_identical(.sc_run_annotation_evidence(obj,supplied,list())$summary$marker_pool$status,"unrecorded")
})
