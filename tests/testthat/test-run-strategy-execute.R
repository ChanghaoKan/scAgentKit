strategy_execute_fixture <- function() {
  set.seed(7341)
  genes <- paste0("Gene", rev(seq_len(120)))
  cells <- c("01", "1", "NA", "cell space", paste0("literalCell", 5:96))
  counts <- matrix(stats::rpois(120L * 96L, lambda = 1), nrow = 120L,
                   dimnames = list(genes, cells))
  # Four planted expression programs plus stochastic background are a software
  # fixture, not biological identities or evidence of successful integration.
  for (program in seq_len(4L)) {
    gene_indices <- ((program - 1L) * 12L + 1L):(program * 12L)
    cell_indices <- ((program - 1L) * 24L + 1L):(program * 24L)
    counts[gene_indices, cell_indices] <- counts[gene_indices, cell_indices] +
      matrix(stats::rpois(12L * 24L, lambda = 6), nrow = 12L)
  }
  object <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE),
                                        min.cells = 0, min.features = 0)
  object$seurat_clusters <- factor(rep(c("01", "NA"), each = 48L),
                                     levels = c("NA", "01"))
  object$prior_annotation <- factor(rep(c("prior A", NA_character_), each = 48L),
                                      levels = c("prior A", "unused prior B"))
  object$sample <- rep(c("synthetic sample A", "synthetic sample B"), each = 48L)
  graph <- SeuratObject::as.Graph(Matrix::sparseMatrix(
    i = seq_len(96L), j = seq_len(96L), x = 1, dims = c(96L, 96L),
    dimnames = list(cells, cells)))
  SeuratObject::DefaultAssay(graph) <- "RNA"
  object[["prior_snn"]] <- graph
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
                 cluster_column = "new_strategy_clusters")
  plan <- list(
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
                     nfeatures = 50L, npcs = 10L, seed = 937L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "Synthetic fixture; no automatic integration requested."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
    umap = list(run = TRUE, n_neighbors = 10L))
  list(object = object, config = config, plan = plan)
}

test_that("approved adapters preserve source scope, labels and sparse counts through actual UMAP and clustering", {
  f <- strategy_execute_fixture()
  snapshot <- serialize(f$object, NULL, version = 2L)
  metadata <- f$object[[]]
  counts <- SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts", fast = FALSE)
  basis <- scAgentKit:::.sc_run_strategy_basis(f$object, f$config, f$plan)
  expect_identical(serialize(f$object, NULL, version = 2L), snapshot)
  expect_identical(colnames(basis), colnames(f$object))
  expect_identical(rownames(basis[["RNA"]]), rownames(f$object[["RNA"]]))
  expect_identical(basis[[]], metadata)
  expect_true(inherits(SeuratObject::LayerData(basis, assay = "RNA", layer = "counts"), "sparseMatrix"))
  expect_identical(SeuratObject::LayerData(basis, assay = "RNA", layer = "counts"), counts)
  expect_equal(ncol(SeuratObject::Embeddings(basis[["pca"]])), f$plan$analysis$npcs)
  hvg <- SeuratObject::VariableFeatures(basis[["RNA"]])
  scaled <- SeuratObject::LayerData(basis, assay = "RNA", layer = "scale.data", fast = FALSE)
  expect_length(hvg, f$plan$analysis$nfeatures)
  expect_setequal(rownames(scaled), hvg)
  expect_equal(nrow(scaled), f$plan$analysis$nfeatures)
  expect_lt(nrow(scaled), nrow(counts))
  expect_true(all(is.finite(scaled)))
  expect_match(basis@misc$strategy_execution$basis$pca$denominator, "computed PCs only")
  expect_match(basis@misc$strategy_execution$basis$pca$interpretation, "not proof")
  expect_false(any(c("method", "ndim", "threshold", "fraction_at_selected") %in%
                     names(basis@misc$strategy_execution$basis$pca)))

  # Seurat's first-session notice about its R-native UMAP default is cosmetic;
  # the adapter explicitly supplies uwot/cosine and the invariants are checked.
  neighbors <- suppressWarnings(scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan))
  expect_identical(neighbors[["prior_snn"]], f$object[["prior_snn"]])
  for (name in c("sc_strategy_nn", "sc_strategy_snn")) {
    expect_true(inherits(neighbors[[name]], "Graph"))
    expect_identical(rownames(neighbors[[name]]), colnames(f$object))
    expect_identical(colnames(neighbors[[name]]), colnames(f$object))
  }
  embedding <- SeuratObject::Embeddings(neighbors[["umap"]])
  expect_identical(rownames(embedding), colnames(f$object))
  expect_equal(ncol(embedding), 2L)
  expect_true(all(is.finite(embedding)))
  expect_identical(neighbors@misc$strategy_execution$neighbors$pcs$ndim, 5L)
  expect_false(neighbors@misc$strategy_execution$neighbors$original_graphs_used)

  output <- scAgentKit:::.sc_run_strategy_cluster(neighbors, f$config, f$plan)
  expect_identical(output[[]][, names(metadata), drop = FALSE], metadata)
  expect_identical(output$seurat_clusters, f$object$seurat_clusters)
  expect_identical(output$prior_annotation, f$object$prior_annotation)
  expect_identical(colnames(output), colnames(f$object))
  expect_identical(SeuratObject::LayerData(output, assay = "RNA", layer = "counts"), counts)
  expect_identical(serialize(f$object, NULL, version = 2L), snapshot)
  expect_true(all(!is.na(output$new_strategy_clusters)))
  expect_equal(length(output$new_strategy_clusters), ncol(f$object))
  audit <- output@misc$strategy_execution$cluster
  expect_identical(audit$method, "Louvain")
  expect_equal(audit$resolution, .4)
  expect_equal(vapply(audit$candidates, `[[`, numeric(1), "resolution"), c(.2, .4, .6))
  selected <- Filter(function(row) isTRUE(row$chosen), audit$candidates)
  expect_length(selected, 1L)
  expect_equal(selected[[1L]]$ari_vs_chosen, 1)
  expect_equal(selected[[1L]]$n_clusters, length(unique(output$new_strategy_clusters)))
  expect_equal(sum(unlist(selected[[1L]]$cluster_sizes)), ncol(f$object))
  for (row in audit$candidates) {
    expect_true(is.finite(row$ari_vs_chosen))
    expect_gte(row$ari_vs_chosen, -1)
    expect_lte(row$ari_vs_chosen, 1)
  }
  expect_match(audit$diagnostic_interpretation, "not proof")
  expect_false(any(c("optimal_resolution", "biologically_correct", "auto_selected") %in% names(audit)))
  expect_error(scAgentKit:::.sc_run_strategy_cluster(output, f$config, f$plan), "already exists|fresh")
})

test_that("computed-variance selection uses actual computed-PC variance and refuses a one-PC result", {
  f <- strategy_execute_fixture()
  f$plan$umap$run <- FALSE
  basis <- scAgentKit:::.sc_run_strategy_basis(f$object, f$config, f$plan)
  stdev <- SeuratObject::Stdev(basis[["pca"]])
  cumulative <- cumsum(stdev^2) / sum(stdev^2)
  # This threshold lies between the first two measured cumulative values.
  # The test does not assume a biological number of populations or PCs.
  f$plan$pcs <- list(method = "computed_variance", threshold = mean(cumulative[1:2]))
  output <- scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan)
  evidence <- output@misc$strategy_execution$neighbors$pcs
  expect_identical(evidence$ndim, 2L)
  expect_identical(evidence$available_pcs, 10L)
  expect_equal(evidence$fraction_per_pc, stdev^2 / sum(stdev^2))
  expect_equal(evidence$cumulative_fraction, cumulative)
  expect_equal(evidence$fraction_at_selected, cumulative[2L])
  expect_match(evidence$denominator, "not total expressed-gene variance")
  expect_false("umap" %in% names(output@reductions))
  f$plan$pcs$threshold <- cumulative[1L] / 2
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan), "only one PC|revise")
  f$plan$pcs <- list(method = "fixed", ndim = 11L)
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan), "available components|clipping")
  f$plan$pcs$ndim <- 2.5
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan), "invalid.*ndim")
  f$plan$pcs <- list(method = "fixed", ndim = 5L)
  no_variance <- basis
  no_variance[["pca"]] <- SeuratObject::CreateDimReducObject(
    embeddings = SeuratObject::Embeddings(basis[["pca"]]),
    loadings = SeuratObject::Loadings(basis[["pca"]]),
    stdev = rep(0, 10L), assay = "RNA", key = "PC_")
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(no_variance, f$config, f$plan),
               "positive-variance|finite")
  f$plan$umap <- list(run = TRUE, n_neighbors = ncol(basis))
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(basis, f$config, f$plan), "fewer than retained cells|clipping")
  expect_identical(colnames(basis), colnames(f$object))
})

test_that("inapplicable layers, counts, dimensions and missing checkpoints fail before silent repairs", {
  f <- strategy_execute_fixture()
  no_counts <- f$object
  SeuratObject::LayerData(no_counts, assay = "RNA", layer = "data") <-
    log1p(SeuratObject::LayerData(no_counts, assay = "RNA", layer = "counts"))
  suppressWarnings(no_counts[["RNA"]]$counts <- NULL)
  expect_error(scAgentKit:::.sc_run_strategy_basis(no_counts, f$config, f$plan), "Exact layer.*counts.*unavailable")
  wrong_layer <- f$config; wrong_layer$counts_layer <- "data"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, wrong_layer, f$plan), "exact counts and data")
  wrong_assay <- f$config; wrong_assay$assay <- "not-present"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, wrong_assay, f$plan), "absent|ambiguous")
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object[, seq_len(20L)], f$config, f$plan), "at least 21|clipping")
  excessive_genes <- f$plan; excessive_genes$analysis$nfeatures <- nrow(f$object) + 1L
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, excessive_genes), "exceeds available genes|clipping")
  excessive_pcs <- f$plan; excessive_pcs$analysis$npcs <- excessive_pcs$analysis$nfeatures
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, excessive_pcs), "strictly fewer")
  fractional_pcs <- f$plan; fractional_pcs$analysis$npcs <- 3.5
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, fractional_pcs), "invalid.*npcs")
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(f$object, f$config, f$plan), "PCA.*unavailable|basis checkpoint")
  expect_error(scAgentKit:::.sc_run_strategy_cluster(f$object, f$config, f$plan), "graph|Graph|not found|Cannot find")
  tiny_umap <- f$plan; tiny_umap$umap$n_neighbors <- 2L
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(f$object, f$config, tiny_umap), "invalid.*n_neighbors")
  malformed <- f$plan; malformed$analysis$normalization_method <- "SCTransform"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, malformed), "only LogNormalize")
  malformed <- f$plan; malformed$clustering$diagnostic_resolutions <- c(.1, .2, .3, .4, .5, .6)
  expect_error(scAgentKit:::.sc_run_strategy_cluster(f$object, f$config, malformed), "at most five")
})

test_that("manual or unsupported integration and arbitrary executable parameters cannot pass adapters", {
  f <- strategy_execute_fixture()
  manual <- f$plan; manual$batch$method <- "manual"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, manual), "pending analyst boundary")
  harmony <- f$plan; harmony$batch$method <- "harmony"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, harmony), "supported named fields")
  arbitrary <- f$plan; arbitrary$analysis$r_code <- "system('must never be evaluated')"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, arbitrary), "unsupported analysis parameters")
  unsupported_regression <- f$plan; unsupported_regression$analysis$vars_to_regress <- "S.Score"
  expect_error(scAgentKit:::.sc_run_strategy_basis(f$object, f$config, unsupported_regression), "unsupported analysis parameters")
  unsupported_method <- f$plan; unsupported_method$pcs$method <- "visual_llm"
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(f$object, f$config, unsupported_method), "fixed.*computed_variance.*computed_top50")
  bad_resolution <- f$plan; bad_resolution$clustering$resolution <- 0
  expect_error(scAgentKit:::.sc_run_strategy_cluster(f$object, f$config, bad_resolution), "invalid.*resolution")
  invalid_variance <- f$plan; invalid_variance$pcs <- list(method = "computed_variance", threshold = 1)
  expect_error(scAgentKit:::.sc_run_strategy_neighbors(f$object, f$config, invalid_variance), "strictly between")
  expect_false("new_strategy_clusters" %in% names(f$object[[]]))
})
