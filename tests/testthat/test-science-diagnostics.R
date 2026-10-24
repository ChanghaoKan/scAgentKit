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
test_that("cell-level panel review retains measured counts without calling high RNA a doublet", {
  x <- SeuratObject::pbmc_small
  value <- .sc_run_expression_panels(x,"RNA","counts","data","RNA_snn_res.1",list(B=c("MS4A1","CD79A"),T=c("CD3D","CD3E")),mixed_lineage=TRUE)
  expect_length(value$cell_quality,ncol(x))
  counts <- SeuratObject::LayerData(x,assay="RNA",layer="counts")
  expect_equal(vapply(value$cell_quality,`[[`,0,"total_umi"),as.numeric(Matrix::colSums(counts)))
  expect_true(all(vapply(value$cell_quality,function(row) identical(row$group,"unstratified"),logical(1))))
  expect_match(value$high_count_interpretation,"Flag-only")
  expect_error(sc_run(x,tempfile(),context=list(species="mouse"),strategy=TRUE,scientific_review=list(panels="blood")),"human species")
})

test_that("cross-sample opt-out retains separate declared-sample count flags", {
  object <- SeuratObject::pbmc_small
  object$sample <- rep(c("A", "B"), each = 40L)
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "RNA_snn_res.1", context = list(columns = list(sample = "sample")),
    scientific_review = list(panels = list(B = c("MS4A1", "CD79A")), cross_sample = FALSE))
  plan <- list(analysis = list(seed = 42), pcs = list(method = "fixed", ndim = 2L),
    batch = list(method = "none"), clustering = list(resolution = .5))
  object@misc$strategy_execution$neighbors$pcs <- 2L
  before <- .sc_run_hash(object)
  without <- .sc_run_science_diagnostics(object, config, plan)$expression
  config$scientific_review$cross_sample <- TRUE
  with <- .sc_run_science_diagnostics(object, config, plan)$expression
  expect_identical(without$cell_quality, with$cell_quality)
  expect_setequal(vapply(without$cell_quality, `[[`, "", "group"), c("A", "B"))
  expect_true(all(vapply(without$clusters, function(row) length(row$samples) == 0L, logical(1))))
  expect_true(all(vapply(with$clusters, function(row) length(row$samples) == 2L, logical(1))))
  expect_identical(lapply(without$clusters, `[[`, "genes"), lapply(with$clusters, `[[`, "genes"))
  config$scientific_review$cross_sample <- FALSE
  markers <- suppressWarnings(.sc_run_markers(object, config))
  expression <- attr(markers$marker_summary, "expression_review")
  expect_true(all(vapply(expression$clusters, function(row) length(row$samples) == 0L, logical(1))))
  expect_identical(expression$cell_quality, without$cell_quality)
  expect_identical(.sc_run_hash(object), before)
})

test_that("resampling propagates a rank-rejected PCA result without changing the approved request", {
  set.seed(8401)
  counts <- matrix(stats::rpois(100L * 100L, 10), 100L,
    dimnames = list(paste0("GENE", 1:100), paste0("cell", 1:100)))
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "review_clusters", context = list(), scientific_review = list(resampling = TRUE))
  plan <- list(analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
    nfeatures = 30L, npcs = 21L, seed = 17L), pcs = list(method = "fixed", ndim = 2L),
    batch = list(method = "none", reason = "Software fixture"),
    clustering = list(resolution = .5, diagnostic_resolutions = numeric()), umap = list(run = FALSE, n_neighbors = 30L))
  object <- suppressWarnings(.sc_run_strategy_basis(object, config, plan))
  expect_silent(.sc_run_strategy_pca_evidence(object, .sc_run_strategy_runtime_settings(plan), select = FALSE))
  object <- .sc_run_strategy_neighbors(object, config, plan)
  object <- .sc_run_strategy_cluster(object, config, plan)
  before <- .sc_run_hash(object); seed <- .Random.seed
  actual_check <- .sc_run_strategy_pca_evidence
  observed <- NULL
  testthat::local_mocked_bindings(.sc_run_strategy_pca_evidence = function(seu, settings, select = TRUE) {
    computed <- length(SeuratObject::Stdev(seu[["pca"]]))
    observed <<- list(requested = settings$analysis$npcs, computed = computed, cells = ncol(seu), select = select)
    # Inject a finite positive component below the existing rank threshold.
    # Delegate the decision to the real validator, independently of SVD roundoff.
    seu[["pca"]]@stdev[computed] <- 1e-30
    actual_check(seu, settings, select = select)
  }, .package = "scAgentKit")
  result <- suppressWarnings(.sc_run_science_diagnostics(object, config, plan))
  expect_identical(result$resampling$status, "unavailable")
  expect_match(result$resampling$reason, "seed 42.*numerical rank")
  expect_null(result$resampling$replicates)
  expect_equal(observed, list(requested = 21L, computed = 21L, cells = 80L, select = FALSE))
  expect_identical(.sc_run_hash(object), before); expect_identical(.Random.seed, seed)
})
