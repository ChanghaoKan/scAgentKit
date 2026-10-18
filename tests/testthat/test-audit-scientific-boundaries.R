# All examples are synthetic software controls; no external provider is used.
audit_harmony_fixture <- function() {
  roles <- list(donor = rep(paste0("d", 1:4), each = 8),
    condition = rep(c("control", "case"), each = 16),
    batch = rep(c("b1", "b2"), 16))
  evidence <- list(summary = list(declared_roles = as.list(setNames(names(roles), names(roles))),
    background_facts = list(design = list(technical_batch = TRUE))))
  choice <- list(method = "harmony", group_by_vars = "donor", theta = 2, lambda = 1,
    sigma = .1, max_iter = 3L, nclust = 4L,
    reason = "Explicit synthetic embedding-only review; condition inference uses unintegrated data.")
  list(roles = roles, evidence = evidence, choice = choice)
}

test_that("replicated nesting needs explicit embedding-only review and retains rank diagnostics", {
  withr::local_options(lifecycle_verbosity="quiet")
  f <- audit_harmony_fixture(); check <- scAgentKit:::.sc_run_harmony_choice
  default <- check(f$choice, f$evidence, f$roles)
  expect_false(default$executable)
  expect_identical(default$audit$per_factor_biology[[1]]$relation, "nested")
  expect_true(default$audit$per_factor_biology[[1]]$replicated_nested)
  f$choice$nested_biology <- "reviewed_embedding_only"
  reviewed <- check(f$choice, f$evidence, f$roles)
  expect_true(reviewed$executable)
  expect_false(reviewed$audit$joint_rank$full_rank)
  expect_true(reviewed$audit$reviewed_embedding_rank$full_rank)
  expect_true(reviewed$audit$per_factor_biology[[1]]$nested_embedding_reviewed)
  expect_match(paste(reviewed$audit$warnings, collapse = " "), "condition-effect inference")
  f$choice$nested_biology <- "block"
  expect_false(check(f$choice, f$evidence, f$roles)$executable)
  f$choice$nested_biology <- "silently_allow"
  expect_error(check(f$choice, f$evidence, f$roles), "nested_biology")
})

test_that("nesting exception cannot hide aliasing, unreplicated groups or redundant biology", {
  withr::local_options(lifecycle_verbosity="quiet")
  f <- audit_harmony_fixture(); check <- scAgentKit:::.sc_run_harmony_choice
  f$choice$nested_biology <- "reviewed_embedding_only"
  alias <- f$roles; alias$donor <- alias$condition
  expect_false(check(f$choice, f$evidence, alias)$executable)
  partial <- f$roles; partial$donor[partial$condition == "control"] <- "one_control"
  expect_false(check(f$choice, f$evidence, partial)$executable)
  redundant <- f$roles; redundant$treatment <- redundant$condition
  evidence <- f$evidence; evidence$summary$declared_roles$treatment <- "treatment"
  result <- check(f$choice, evidence, redundant)
  expect_false(result$executable)
  expect_false(result$audit$biological_rank$full_rank)
  expect_true("joint_design_rank_deficient" %in% vapply(result$blockers, `[[`, "", "code"))
  # A crossed technical batch remains the conservative default supported case.
  f$choice$group_by_vars <- "batch"; f$choice$nested_biology <- NULL
  crossed <- check(f$choice, f$evidence, f$roles)
  expect_true(crossed$executable)
  expect_identical(crossed$audit$per_factor_biology[[1]]$relation, "crossed")
  expect_true(crossed$audit$joint_rank$full_rank)
})

test_that("reference coverage exposes 1/1 versus 10/20 without assigning an identity", {
  withr::local_options(lifecycle_verbosity="quiet")
  counts <- Matrix::Matrix(matrix(1, 20, 4,
    dimnames = list(paste0("G", 1:20), paste0("C", 1:4))), sparse = TRUE)
  obj <- AgentSeurat(Seurat::CreateSeuratObject(counts))
  obj@params$markers_filtered <- data.frame(cluster = "0", gene = paste0("G", 1:10))
  reference <- data.frame(cell_type = c("single", rep("broad", 20)),
    marker = c("G1", paste0("G", 1:20)))
  before <- obj@data
  out <- annot_match_reference(obj, reference)
  matches <- out@params$reference_matches
  expect_identical(matches$cell_type, c("single", "broad"))
  expect_equal(matches$overlap_count, c(1, 10))
  expect_equal(matches$celltype_size, c(1, 20))
  expect_equal(matches$score, c(1, .5))
  expect_identical(out@data, before)
  expect_match(out@params$reference_match_interpretation$single_marker, "weak evidence")
  expect_match(out@params$reference_match_interpretation$annotation, "not an assigned identity")
  records <- scAgentKit:::.sc_run_annotation_candidate_records(matches)
  expect_equal(records[[1]]$overlap, 1)
  expect_equal(records[[2]]$referenceSize, 20)
})

test_that("cell-cycle defaults explicitly report small pools and score a larger synthetic pool", {
  withr::local_options(lifecycle_verbosity="quiet")
  gene_set <- sc_cycle_gene_set("human", paste0("G", 1:6), paste0("G", 7:12),
    source = "Synthetic default-capacity fixture", version = "v1")
  options <- scAgentKit:::.sc_run_cycle_options(list(species = "human"), list(gene_set = gene_set))
  expect_identical(options$nbin, 12L); expect_identical(options$ctrl, 5L)
  make_config <- function() list(assay = "RNA", counts_layer = "counts",
    context = list(species = "human"), cycle_diagnostics = options)
  set.seed(31415)
  make_object <- function(n) {
    counts <- matrix(rpois(n * 48L, 2), n, 48,
      dimnames = list(paste0("G", seq_len(n)), paste0("C", 1:48)))
    Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  }
  small <- make_object(24)
  small_record <- scAgentKit:::.sc_run_cycle_evidence(small, make_config())
  expect_identical(small_record$summary$status, "insufficient")
  expect_match(paste(small_record$summary$reasons, collapse = " "), "controls|bins")
  expect_identical(small_record$summary$options$nbin, 12L)
  expect_identical(small_record$summary$options$ctrl, 5L)
  large <- make_object(2400)
  large_record <- scAgentKit:::.sc_run_cycle_evidence(large, make_config())
  expect_identical(large_record$summary$status, "available")
  expect_gte(large_record$summary$control$min_control_pool, 5L)
  scores <- large_record$scores[[large_record$summary$columns[["s_score"]]]]
  expect_length(scores, 48L)
  expect_true(all(is.finite(scores)))
  expect_identical(large_record$summary$cohort$removed_cells, 0L)
})

test_that("reviewed nested execution retains PCA assays and separate before-after diagnostics", {
  withr::local_options(lifecycle_verbosity="quiet")
  skip_if_not_installed("harmony")
  f <- audit_harmony_fixture()
  f$choice$nested_biology <- "reviewed_embedding_only"
  cells <- paste0("C", 1:32)
  counts <- Matrix::Matrix(matrix((seq_len(100 * 32) %% 7) + 1, 100, 32,
    dimnames = list(paste0("G", 1:100), cells)), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts)
  object <- Seurat::NormalizeData(object, verbose = FALSE)
  for (role in names(f$roles)) object[[role]] <- f$roles[[role]]
  embedding <- matrix(sin(seq_len(32 * 4) / 7), 32, 4,
    dimnames = list(cells, paste0("PC_", 1:4)))
  object[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embedding,
    stdev = 4:1, key = "PC_", assay = "RNA")
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    cluster_column = "seurat_clusters", start_stage = "qc",
    context = list(columns = f$evidence$summary$declared_roles,
      design = list(technical_batch = TRUE)))
  plan <- list(analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 30L, npcs = 4L, seed = 77L),
    pcs = list(method = "fixed", ndim = 3L), batch = f$choice,
    clustering = list(resolution = .4, diagnostic_resolutions = numeric()),
    umap = list(run = FALSE, n_neighbors = 10L))
  calls <- 0L
  local_mocked_bindings(.sc_run_harmony_invoke = function(seu, choice, dims, seed, fixed_options) {
    calls <<- calls + 1L
    expect_identical(choice$nested_biology, "reviewed_embedding_only")
    after <- SeuratObject::Embeddings(seu[["pca"]])[, dims, drop = FALSE] + .01
    colnames(after) <- paste0("HARMONY_", seq_along(dims))
    seu[["harmony"]] <- SeuratObject::CreateDimReducObject(embeddings = after,
      key = "HARMONY_", assay = "RNA")
    seu
  }, .package = "scAgentKit")
  result <- scAgentKit:::.sc_run_strategy_batch(object, config, plan)
  expect_identical(calls, 1L)
  expect_identical(result[["pca"]], object[["pca"]])
  expect_identical(result[[]], object[[]])
  expect_identical(SeuratObject::LayerData(result, assay = "RNA", layer = "counts"), counts)
  record <- result@misc$strategy_execution$batch
  expect_false(record$design$joint_rank$full_rank)
  expect_true(record$design$reviewed_embedding_rank$full_rank)
  expect_length(record$diagnostics$technical_mixing, 1L)
  expect_length(record$diagnostics$biological_same_label, 1L)
  expect_identical(record$choice$nested_biology, "reviewed_embedding_only")
})
