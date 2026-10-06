cycle_engine_fixture <- function() {
  set.seed(9013)
  s <- paste0("LiteralS", 1:12); g2m <- paste0("LiteralG2m", 1:12)
  genes <- c(rev(s), rev(g2m), paste0("Background", 1:120), paste0("Zero", 1:5))
  cells <- c("01", "1", "NA", "cell space", paste0("literal", 5:96))
  counts <- matrix(stats::rpois(length(genes) * length(cells), 2), nrow = length(genes),
                   dimnames = list(genes, cells))
  counts[s, 1:24] <- counts[s, 1:24] + 8L
  counts[g2m, 25:48] <- counts[g2m, 25:48] + 9L
  counts[s, 49:72] <- counts[s, 49:72] + 3L
  counts[g2m, 49:72] <- counts[g2m, 49:72] + 4L
  counts[paste0("Zero", 1:5), ] <- 0L
  object <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE),
                                      min.cells = 0, min.features = 0)
  # This source normalization intentionally differs from diagnostic 10k.
  object <- Seurat::NormalizeData(object, scale.factor = 1700, verbose = FALSE)
  object$S.Score <- seq_len(ncol(object)) / 100
  object$G2M.Score <- rep(-1, ncol(object))
  object$Phase <- factor(rep(c("old S", "old G1"), each = 48L),
                         levels = c("old G1", "old S", "unused"))
  object$CC.Difference <- factor(rep(c("literal NA", "literal 01"), each = 48L))
  object$Cell.Cycle1 <- factor(rep("protected control", ncol(object)))
  object$annotation <- factor(rep(c("prior A", NA_character_), each = 48L),
                              levels = c("prior A", "unused B"))
  object$sample <- rep(c("sample A", "sample B"), each = 48L)
  SeuratObject::Idents(object) <- object$sample
  gene_set <- sc_cycle_gene_set("human", s, g2m, source = "Synthetic software fixture",
                                version = "fixture-v1")
  context <- list(species = "Homo sapiens", columns = list(sample = "sample"))
  options <- scAgentKit:::.sc_run_cycle_options(context, list(gene_set = gene_set,
                         nbin = 4L, ctrl = 2L))
  config <- list(assay = "RNA", counts_layer = "counts", normalized_layer = "data",
                  cluster_column = "cycle_strategy_clusters", context = context,
                  cycle_diagnostics = options)
  plan <- list(
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
                      nfeatures = 45L, npcs = 8L, seed = 83L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "Fixture has no requested integration."),
    clustering = list(resolution = .4, diagnostic_resolutions = numeric()),
    umap = list(run = FALSE, n_neighbors = 10L),
    cycle = list(method = "none", reason = "Keep scores as local diagnostics."))
  list(object = object, gene_set = gene_set, config = config, plan = plan,
       s_genes = s, g2m_genes = g2m)
}

cycle_engine_resign_scores <- function(record, s, g2m) {
  columns <- record$summary$columns
  record$scores[[columns[["s_score"]]]] <- s
  record$scores[[columns[["g2m_score"]]]] <- g2m
  record$scores[[columns[["difference"]]]] <- s - g2m
  record$scores_hash <- scAgentKit:::.sc_run_hash(record$scores)
  record$evidence_hash <- scAgentKit:::.sc_run_cycle_hash(record)
  record
}

test_that("gene sets require explicit species, provenance, and complete literal mapping", {
  expect_error(sc_cycle_gene_set("mouse"), "Mouse.*explicit|mouse.*explicit")
  expect_error(sc_cycle_gene_set("zebrafish"), "species|human|mouse|unsupported")
  expect_error(sc_cycle_gene_set("human", letters[1:6], letters[7:12]), "source")
  expect_error(sc_cycle_gene_set("mouse", letters[1:6], source = "fixture", version = "v1"), "both")
  literal <- stats::setNames(paste0("input", 1:12), LETTERS[1:12])
  mouse <- sc_cycle_gene_set("Mus musculus", LETTERS[1:6], LETTERS[7:12],
                              source = "Explicit mapping fixture", version = "v1",
                              symbol_mapping = literal)
  expect_identical(mouse$species, "mouse")
  expect_identical(mouse$s_genes, paste0("input", 1:6))
  expect_identical(mouse$canonical_s_genes, LETTERS[1:6])
  expect_identical(mouse$symbol_mapping, literal)
  expect_error(sc_cycle_gene_set("mouse", LETTERS[1:6], LETTERS[7:12],
                                  source = "fixture", version = "v1",
                                  symbol_mapping = literal[-1]), "one-to-one|every")
  duplicate <- literal; duplicate[2] <- duplicate[1]
  expect_error(sc_cycle_gene_set("mouse", LETTERS[1:6], LETTERS[7:12],
                                  source = "fixture", version = "v1",
                                  symbol_mapping = duplicate), "one-to-one")
  human <- sc_cycle_gene_set("Homo sapiens")
  expect_identical(human$source, "Seurat::cc.genes.updated.2019")
  expect_identical(human$version, "2019")
  expect_identical(human$package$data, "cc.genes.updated.2019")
  expect_gt(length(human$s_genes), 5L)
  expect_gt(length(human$g2m_genes), 5L)
  changed <- human; changed$s_genes[1] <- "unapproved replacement"
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"), list(gene_set = changed)), "intact")
})

test_that("diagnostics are opt-in with canonical matching species and declared prerequisites", {
  f <- cycle_engine_fixture()
  expect_null(scAgentKit:::.sc_run_cycle_options(list(), NULL))
  expect_null(scAgentKit:::.sc_run_cycle_options(list(), FALSE))
  expect_error(scAgentKit:::.sc_run_cycle_options(list(), list(gene_set = f$gene_set)), "explicit.*species")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "mouse"), list(gene_set = f$gene_set)), "species.*match")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"), TRUE), "gene_set")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"), list(gene_set = f$gene_set, search = TRUE)), "supported")
  defaults <- scAgentKit:::.sc_run_cycle_options(list(species = "human"), list(gene_set = f$gene_set))
  expect_identical(defaults$seed, 17L)
  expect_identical(defaults$nbin, 12L)
  expect_identical(defaults$ctrl, 5L)
  expect_identical(defaults$min_genes, 5L)
  expect_equal(defaults$min_fraction, .2)
  expect_equal(defaults$scale_factor, 10000)
  expect_identical(scAgentKit:::.sc_run_cycle_options(list(species = "human"), defaults), defaults)
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"), list(gene_set = f$gene_set, ctrl = 1.5)), "invalid")
})

test_that("full-input reference uses sparse counts and preserves source metadata, layers, identities, and RNG", {
  f <- cycle_engine_fixture()
  snapshot <- serialize(f$object, NULL, version = 2L)
  set.seed(13); before_seed <- .Random.seed
  record <- scAgentKit:::.sc_run_cycle_evidence(f$object, f$config)
  expect_identical(.Random.seed, before_seed)
  expect_identical(serialize(f$object, NULL, version = 2L), snapshot)
  expect_identical(record$summary$status, "available")
  expect_identical(record$summary$reference, "fixed_full_input")
  expect_false(record$summary$refit_after_qc)
  expect_identical(record$summary$normalization$method, "LogNormalize")
  expect_equal(record$summary$normalization$scale_factor, 10000)
  expect_equal(record$summary$cohort$removed_cells, 0)
  expect_identical(record$scores$cell_id, colnames(f$object))
  expect_false(any(paste0("Zero", 1:5) %in% record$expressed_pool))
  expect_identical(record$summary$scoring$search, FALSE)
  expect_identical(record$summary$scoring$set_ident, FALSE)
  expect_identical(record$summary$gene_set$hash, f$gene_set$gene_set_hash)
  expect_identical(record$options_hash, scAgentKit:::.sc_run_hash(f$config$cycle_diagnostics))
  expect_silent(scAgentKit:::.sc_run_cycle_verify(record))
  expect_false(any(c("cell_id", "scores", "cell_ids", "count_cell_hashes") %in% names(record$summary)))

  counts <- scAgentKit:::.sc_project_layer(f$object, "RNA", "counts", raw_counts = TRUE)
  reference <- Seurat::CreateSeuratObject(counts = counts[, colnames(f$object), drop = FALSE],
                                         min.cells = 0, min.features = 0)
  reference <- Seurat::NormalizeData(reference, scale.factor = 10000, verbose = FALSE)
  reference <- Seurat::CellCycleScoring(reference, s.features = f$s_genes,
                   g2m.features = f$g2m_genes, assay = "RNA", pool = record$expressed_pool,
                   slot = "data", seed = 17L, nbin = 4L, ctrl = 2L, search = FALSE, set.ident = FALSE)
  columns <- record$summary$columns
  expect_equal(record$scores[[columns[["s_score"]]]], unname(reference$S.Score))
  expect_equal(record$scores[[columns[["g2m_score"]]]], unname(reference$G2M.Score))
  expect_equal(record$scores[[columns[["difference"]]]], unname(reference$S.Score - reference$G2M.Score))
  expect_equal(record$scores[[columns[["phase"]]]], as.character(reference$Phase))
  attached <- scAgentKit:::.sc_run_cycle_attach(f$object, record)
  expect_identical(attached[[]][, names(f$object[[]]), drop = FALSE], f$object[[]])
  expect_identical(SeuratObject::Idents(attached), SeuratObject::Idents(f$object))
  expect_identical(SeuratObject::LayerData(attached, assay = "RNA", layer = "counts"),
                   SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts"))
  expect_identical(SeuratObject::LayerData(attached, assay = "RNA", layer = "data"),
                   SeuratObject::LayerData(f$object, assay = "RNA", layer = "data"))
  expect_true(inherits(SeuratObject::LayerData(attached, assay = "RNA", layer = "counts"), "sparseMatrix"))
  expect_error(scAgentKit:::.sc_run_cycle_attach(attached, record), "already exists|fresh")
  expect_error(scAgentKit:::.sc_run_cycle_evidence(attached, f$config), "already exists|fresh")
})

test_that("post-QC attachment reuses exact fixed scores and rejects changed sources or provenance", {
  f <- cycle_engine_fixture()
  record <- scAgentKit:::.sc_run_cycle_evidence(f$object, f$config)
  retained <- colnames(f$object)[c(4, 2, 30:70)]
  subset <- f$object[, retained]
  attached <- scAgentKit:::.sc_run_cycle_attach(subset, record)
  expected <- record$scores[match(colnames(subset), record$cell_ids), unname(record$summary$columns), drop = FALSE]
  rownames(expected) <- colnames(subset)
  expect_identical(attached[[]][, unname(record$summary$columns), drop = FALSE], expected)
  expect_identical(colnames(attached), colnames(subset))
  expect_equal(ncol(attached), length(retained))
  changed <- subset
  counts <- SeuratObject::LayerData(changed, assay = "RNA", layer = "counts", fast = FALSE)
  counts[1, 1] <- counts[1, 1] + 1
  SeuratObject::LayerData(changed, assay = "RNA", layer = "counts") <- counts
  expect_error(scAgentKit:::.sc_run_cycle_attach(changed, record), "raw counts.*changed")
  changed_record <- record; changed_record$scores[1, 2] <- 999
  expect_error(scAgentKit:::.sc_run_cycle_attach(subset, changed_record), "evidence.*changed")
  changed_record <- record; changed_record$gene_set$source <- "another source"
  expect_error(scAgentKit:::.sc_run_cycle_verify(changed_record), "evidence.*changed")
  renamed <- Seurat::RenameCells(subset, new.names = paste0("unknown", seq_len(ncol(subset))))
  expect_error(scAgentKit:::.sc_run_cycle_attach(renamed, record), "match.*reference")
})

test_that("missing, nonexpressed, and infeasible control-bin evidence is Unknown with no filtering", {
  f <- cycle_engine_fixture()
  missing_config <- f$config
  missing_config$cycle_diagnostics <- scAgentKit:::.sc_run_cycle_options(f$config$context,
    list(gene_set = sc_cycle_gene_set("human", paste0("absentS", 1:10), paste0("absentG", 1:10),
                                     source = "Missing fixture", version = "v1")))
  cases <- list(missing = missing_config)
  insufficient_bins <- f$config; insufficient_bins$cycle_diagnostics$nbin <- 1000L
  cases$bins <- insufficient_bins
  insufficient_controls <- f$config; insufficient_controls$cycle_diagnostics$ctrl <- 1000L
  cases$controls <- insufficient_controls
  zero_config <- f$config
  zero_config$cycle_diagnostics <- scAgentKit:::.sc_run_cycle_options(f$config$context,
    list(gene_set = sc_cycle_gene_set("human", paste0("Zero", 1:5), f$g2m_genes,
                                     source = "Zero fixture", version = "v1")))
  cases$nonexpressed <- zero_config
  for (config in cases) {
    record <- scAgentKit:::.sc_run_cycle_evidence(f$object, config)
    expect_identical(record$summary$status, "insufficient")
    expect_equal(record$summary$cohort$unknown_cells, ncol(f$object))
    expect_true(all(record$scores[[record$summary$columns[["phase"]]]] == "Unknown"))
    expect_true(all(is.na(record$scores[[record$summary$columns[["s_score"]]]])))
    expect_true(all(is.na(record$scores[[record$summary$columns[["g2m_score"]]]])))
    attached <- scAgentKit:::.sc_run_cycle_attach(f$object, record)
    expect_identical(colnames(attached), colnames(f$object))
    none <- scAgentKit:::.sc_run_cycle_validate_choice(list(method = "none", reason = "Insufficient reference."),
                                                      record, colnames(f$object))
    expect_length(none$regressors, 0L)
    for (method in c("full", "difference"))
      expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = method, reason = "Fixture."),
                                                             record, colnames(f$object)), "insufficient")
  }
  tied_counts <- Matrix::Matrix(matrix(1L, nrow = 24L, ncol = 30L,
                      dimnames = list(c(f$s_genes, f$g2m_genes), paste0("tied", 1:30))), sparse = TRUE)
  tied <- Seurat::CreateSeuratObject(tied_counts, min.cells = 0, min.features = 0)
  tied_record <- scAgentKit:::.sc_run_cycle_evidence(tied, f$config)
  expect_identical(tied_record$summary$status, "insufficient")
  expect_match(paste(tied_record$summary$reasons, collapse = " "), "bin")
})

test_that("regression validates the actual retained finite variance and design rank", {
  f <- cycle_engine_fixture()
  record <- scAgentKit:::.sc_run_cycle_evidence(f$object, f$config)
  cells <- colnames(f$object)
  for (method in c("none", "full", "difference")) {
    choice <- scAgentKit:::.sc_run_cycle_validate_choice(list(method = method, reason = "Explicit fixture choice."), record, cells)
    expect_identical(choice$method, method)
    expect_identical(choice$evidence_hash, record$evidence_hash)
    expect_equal(choice$applicability$retained_cells, length(cells))
  }
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "full", reason = "", regressors = "other"), record, cells), "exactly")
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "auto", reason = "Fixture."), record, cells), "explicitly")
  s <- rep(0, length(cells)); s[11:length(cells)] <- seq_len(length(cells) - 10L)
  constant_subset <- cycle_engine_resign_scores(record, s, sin(seq_along(cells)))
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "full", reason = "Fixture."),
                                                         constant_subset, cells[1:10]), "variance")
  rank_deficient <- cycle_engine_resign_scores(record, seq_along(cells) * 1.0, seq_along(cells) * 2.0)
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "full", reason = "Fixture."), rank_deficient, cells), "rank deficient")
  difference <- scAgentKit:::.sc_run_cycle_validate_choice(list(method = "difference", reason = "Fixture."), rank_deficient, cells)
  expect_identical(difference$regressors, "sc_cycle_CC.Difference")
  zero_difference <- cycle_engine_resign_scores(record, seq_along(cells) * 1.0, seq_along(cells) * 1.0)
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "difference", reason = "Fixture."), zero_difference, cells), "variance")
  nonfinite <- cycle_engine_resign_scores(record, rep(NA_real_, length(cells)), rep(NA_real_, length(cells)))
  expect_error(scAgentKit:::.sc_run_cycle_validate_choice(list(method = "full", reason = "Fixture."), nonfinite, cells), "finite")
})

test_that("three approved methods reuse normalization and HVGs and preserve every source cell", {
  f <- cycle_engine_fixture()
  cycle <- scAgentKit:::.sc_run_cycle_evidence(f$object, f$config)
  before <- serialize(f$object, NULL, version = 2L)
  preprocessed <- scAgentKit:::.sc_run_strategy_preprocess(f$object, f$config, f$plan)
  normalized <- SeuratObject::LayerData(preprocessed, assay = "RNA", layer = "data", fast = FALSE)
  hvg <- SeuratObject::VariableFeatures(preprocessed[["RNA"]])
  preprocessing <- preprocessed@misc$strategy_execution$preprocess
  expect_identical(preprocessed[[]], f$object[[]])
  expect_false("pca" %in% names(preprocessed@reductions))
  methods <- c("none", "full", "difference")
  for (method in methods) {
    plan <- f$plan; plan$cycle <- list(method = method, reason = "Explicit software fixture choice.")
    basis <- scAgentKit:::.sc_run_strategy_basis(preprocessed, f$config, plan, preprocessed = TRUE,
                                                cycle_record = cycle)
    expect_identical(colnames(basis), colnames(f$object))
    expect_identical(basis[[]][, names(f$object[[]]), drop = FALSE], f$object[[]])
    expect_identical(SeuratObject::LayerData(basis, assay = "RNA", layer = "data", fast = FALSE), normalized)
    expect_identical(SeuratObject::VariableFeatures(basis[["RNA"]]), hvg)
    expect_identical(basis@misc$strategy_execution$preprocess, preprocessing)
    expect_identical(basis@misc$strategy_execution$basis$cycle_method, method)
    expected <- switch(method, none = character(), full = c("sc_cycle_S.Score", "sc_cycle_G2M.Score"),
                        difference = "sc_cycle_CC.Difference")
    expect_identical(basis@misc$strategy_execution$basis$regressors, expected)
    expect_identical(basis@misc$strategy_execution$basis$primitives, c("Seurat::ScaleData", "Seurat::RunPCA"))
    expect_identical(SeuratObject::LayerData(basis, assay = "RNA", layer = "counts"),
                     SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts"))
  }
  expect_identical(serialize(f$object, NULL, version = 2L), before)
  changed <- preprocessed
  SeuratObject::VariableFeatures(changed[["RNA"]]) <- rev(hvg)
  expect_error(scAgentKit:::.sc_run_strategy_basis(changed, f$config, f$plan, preprocessed = TRUE, cycle_record = cycle),
               "Preprocessed.*changed|incompatible")
  legacy_config <- f$config; legacy_config$cycle_diagnostics <- NULL
  legacy_plan <- f$plan; legacy_plan$cycle <- NULL
  legacy <- scAgentKit:::.sc_run_strategy_basis(f$object, legacy_config, legacy_plan)
  expect_null(legacy@misc$strategy_execution$preprocess)
  expect_null(legacy@misc$strategy_execution$basis$cycle)
  expect_identical(legacy[[]], f$object[[]])
})

test_that("legacy regression defaults to a true no-op and mouse scoring fails before unsafe matching", {
  f <- cycle_engine_fixture()
  wrapped <- AgentSeurat(f$object)
  before <- serialize(wrapped, NULL, version = 2L)
  expect_identical(sc_cellcycle_regress(wrapped), wrapped)
  expect_identical(sc_cellcycle_regress(wrapped, mode = "none"), wrapped)
  expect_error(sc_cellcycle_score(wrapped, species = "mouse"), "Mouse.*explicit|mouse.*explicit")
  expect_error(sc_cellcycle_score(wrapped, species = "rat"), "species|unsupported|human|mouse")
  expect_error(sc_cellcycle_score(wrapped, species = "mouse", s_genes = paste0("missingS", 1:5),
                                  g2m_genes = paste0("missingG", 1:5), source = "Literal mouse fixture", version = "v1"),
               "Insufficient literal")
  expect_error(sc_cellcycle_score(wrapped, species = "human", s_genes = f$s_genes,
                                  g2m_genes = f$g2m_genes, source = "Fixture", version = "v1"),
               "already exist|fresh")
  expect_identical(serialize(wrapped, NULL, version = 2L), before)
})
