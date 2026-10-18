test_that("NULL and thrown delivery outcomes are never resent by legacy callers", {
  markers <- data.frame(gene="CD3D", avg_log2FC=2, pct.1=.9, pct.2=.1)
  counts <- matrix(3, 2, 8, dimnames=list(c("CD3D", "CD3E"), paste0("c",1:8)))
  obj <- AgentSeurat(Seurat::CreateSeuratObject(Matrix::Matrix(counts,sparse=TRUE)))
  obj@data$seurat_clusters <- rep("0",8)
  obj@params$markers_filtered <- cbind(cluster="0", markers)
  scored <- data.frame(column="sample", n_levels=2, median_size=4,
    smallest_size=4, name_match=TRUE, looks_biological=FALSE, score=4)
  pbmc_small <- SeuratObject::pbmc_small
  callers <- list(
    annotation=function(fn) annot_llm_annotate(obj, fn, tissue="PBMC", max_retries=2, verbose=FALSE),
    parser=function(fn) scAgentKit:::.call_with_retry(fn,"s","u",2),
    ensemble=function(fn) scAgentKit:::.ensemble_annotate(fn,"s","u",n_samples=1,max_retries=2),
    pcs=function(fn) scAgentKit:::.pcs_call_with_retry(fn,"s","u",c(2L,3L),2),
    resolution=function(fn) scAgentKit:::.resolution_call_with_retry(fn,"s","u",max_retries=2,res_values=c(.2,.4)),
    batch=function(fn) scAgentKit:::.llm_pick_batch_var(scored,fn,max_retries=2),
    subcluster=function(fn) scAgentKit:::.annotate_one_subcluster_with_llm("T", "0",8,1,markers,"PBMC",chat_fn=fn,max_retries=2),
    # This assertion concerns delivery count; the legacy auto-resolution
    # fallback can itself error after an absent decision.
    subset_resolution=function(fn) try(scAgentKit:::.auto_resolution_for_subset(
      pbmc_small,fn,"T","PBMC",n_pcs=2,max_retries=2,verbose=FALSE),silent=TRUE)
  )
  for (kind in c("NULL", "error")) for (name in names(callers)) {
    calls <- 0L
    fn <- function(...) { calls <<- calls+1L; if(kind=="error") stop("delivery unknown"); NULL }
    suppressWarnings(callers[[name]](fn))
    expect_identical(calls,1L,info=paste(name,kind))
  }
})
