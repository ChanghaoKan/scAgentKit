test_that("named subset partitions report disappearing clusters and exact coverage", {
  reference <- c(a="0",b="0",c="1",d="1")
  x <- .sc_run_science_partition_compare(reference,c(a="a",b="a"))
  expect_equal(x$per_cluster[[2]]$coverage,0)
  expect_null(x$per_cluster[[2]]$best_jaccard)
  expect_error(.sc_run_science_partition_compare(reference,c(foreign="a")),"exact cell")
})
test_that("explicit expression panels distinguish missing and zero, align cells and preserve input", {
  x <- Matrix::Matrix(matrix(c(1,0,0,3, 0,0,2,0, 0,1,0,2),3,4,
    dimnames=list(c("G1","G2","G3"),letters[1:4])),sparse=TRUE)
  obj <- Seurat::CreateSeuratObject(x); obj$cluster <- c("0","0","1","1")
  obj <- Seurat::NormalizeData(obj,verbose=FALSE)
  before <- .sc_run_hash(obj)
  value <- .sc_run_expression_panels(obj,"RNA","counts","data","cluster",list(A=c("G1","ABSENT"),B="G2"),mixed_lineage=TRUE)
  expect_identical(value$missing_genes,"ABSENT")
  expect_identical(value$clusters[[1]]$genes[[1]]$pct_detected,1)
  expect_identical(value$clusters[[1]]$cross_sample_status,"unavailable")
  expect_identical(value$mixed_lineage[[1]]$status,"measured")
  expect_identical(.sc_run_hash(obj),before)
  expect_false(.sc_run_science_options(list())$resampling)
  expect_error(.sc_run_science_options(list(code="delete")),"Unsupported")
})
test_that("opted-in science review actually rebuilds partitions and five subsamples without authority mutation", {
  set.seed(17)
  counts <- Matrix::Matrix(matrix(rpois(120*80,4),120,80,
    dimnames=list(paste0("g",1:120),paste0("c",1:80))),sparse=TRUE)
  obj <- Seurat::CreateSeuratObject(counts)
  obj <- Seurat::NormalizeData(obj,verbose=FALSE)
  obj <- Seurat::FindVariableFeatures(obj,nfeatures=40,verbose=FALSE)
  obj <- Seurat::ScaleData(obj,verbose=FALSE)
  obj <- Seurat::RunPCA(obj,npcs=10,verbose=FALSE)
  plan <- list(analysis=list(normalization_method="LogNormalize",scale_factor=10000,nfeatures=40,npcs=10,seed=42L),
    pcs=list(method="fixed",ndim=5L),batch=list(method="none",reason="Software fixture"),
    clustering=list(resolution=.6,diagnostic_resolutions=c(.2,1.2)),umap=list(run=FALSE,n_neighbors=20L))
  obj$cluster <- unname(.sc_run_science_partition(obj,5,.6,42))
  obj@misc$strategy_execution$neighbors$pcs <- list(ndim=5L,policy="fixed",total_computed_pcs=10L)
  config <- list(assay="RNA",counts_layer="counts",normalized_layer="data",cluster_column="cluster",context=list(),
    scientific_review=list(pc_sensitivity=TRUE,resampling=TRUE,resolution_extension=TRUE))
  before <- .sc_run_hash(obj); seed <- .Random.seed
  value <- suppressWarnings(.sc_run_science_diagnostics(obj,config,plan))
  expect_identical(value$pc_sensitivity$status,"measured")
  expect_identical(value$pc_sensitivity$bounded_candidates,c(2L,5L,10L))
  expect_identical(value$resampling$status,"measured")
  expect_length(value$resampling$replicates,5)
  expect_true(all(vapply(value$resampling$replicates,function(x) x$shared_cells==64L,logical(1))))
  expect_identical(value$resolution_extension$status,"measured")
  expect_identical(.sc_run_hash(obj),before)
  expect_identical(.Random.seed,seed)
  expect_false(value$default_changed)
})
test_that("expression review joins shuffled literal cell IDs rather than canonical matrix positions", {
  x <- SeuratObject::pbmc_small
  before <- .sc_run_hash(x)
  result <- .sc_run_expression_panels(x,"RNA","counts","data","RNA_snn_res.1",list(B=c("MS4A1","CD79A")))
  expect_identical(result$status,"measured")
  expect_identical(.sc_run_hash(x),before)
})
