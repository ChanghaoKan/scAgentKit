audit_prior_object <- function() {
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  obj@data$seurat_clusters <- as.character(SeuratObject::Idents(obj@data))
  obj@data$celltype <- rep(c("SentinelTruthA","SentinelTruthB"),length.out=ncol(obj@data))
  obj@params$markers_filtered <- data.frame(cluster=unique(obj@data$seurat_clusters),
    gene="CD3D",pct.1=.9,pct.2=.1)
  obj@data$RNA_snn_res.0.2 <- rep(c("0","1"),length.out=ncol(obj@data))
  obj@data$RNA_snn_res.0.4 <- rep(c("0","1","2"),length.out=ncol(obj@data))
  obj
}

test_that("guided annotation metadata truth requires explicit opt-in and is recorded", {
  withr::local_options(lifecycle_verbosity="quiet")
  obj <- audit_prior_object(); prompts <- character()
  fn <- function(system_prompt,user_prompt) {prompts <<- c(prompts,system_prompt,user_prompt);NULL}
  default <- annot_llm_annotate(obj,fn,tissue="PBMC",verbose=FALSE,max_retries=0)
  expect_false(any(grepl("SentinelTruth",prompts)))
  expect_true(is.na(tail(default@decisions,1)[[1]]$params$metadata_prior_column))
  prompts <- character()
  opt <- annot_llm_annotate(obj,fn,tissue="PBMC",verbose=FALSE,max_retries=0,use_metadata_prior=TRUE)
  expect_true(any(grepl("SentinelTruth",prompts)))
  expect_identical(tail(opt@decisions,1)[[1]]$params$metadata_prior_column,"celltype")
  expect_true(tail(opt@decisions,1)[[1]]$params$use_metadata_prior)
  prompts <- character()
  independent <- annot_llm_annotate(obj,fn,tissue="PBMC",verbose=FALSE,max_retries=0,
    reference_mode="independent",use_metadata_prior=TRUE)
  expect_false(any(grepl("SentinelTruth",prompts)))
  expect_true(is.na(tail(independent@decisions,1)[[1]]$params$metadata_prior_column))
})

test_that("resolution metadata count prior requires explicit opt-in and is recorded", {
  withr::local_options(lifecycle_verbosity="quiet")
  obj <- audit_prior_object();prompts <- character()
  fn <- function(system_prompt,user_prompt) {prompts <<- c(prompts,system_prompt,user_prompt);NULL}
  default <- suppressWarnings(sc_resolution_recommend(obj,fn,"PBMC",vision=FALSE,max_retries=0))
  expect_null(tail(default@decisions,1)[[1]]$params$expected_n_celltypes)
  expect_true(is.na(tail(default@decisions,1)[[1]]$params$metadata_prior_column))
  opt <- suppressWarnings(sc_resolution_recommend(obj,fn,"PBMC",vision=FALSE,max_retries=0,use_metadata_prior=TRUE))
  expect_identical(tail(opt@decisions,1)[[1]]$params$metadata_prior_column,"celltype")
  expect_equal(tail(opt@decisions,1)[[1]]$params$expected_n_celltypes,c(3,3))
  expect_true(tail(opt@decisions,1)[[1]]$params$use_metadata_prior)
})
