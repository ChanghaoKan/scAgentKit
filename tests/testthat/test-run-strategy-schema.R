# Synthetic evidence exercises policy/guard behavior, not biological batch
# correction performance. These tests make no provider calls or file exports.
strategy_schema_fixture <- function(cells = 40L, context = NULL, processed = FALSE) {
  genes <- c("MT-CO1", "MT-ND1", paste0("SyntheticGene", 3:80))
  values <- outer(seq_along(genes), seq_len(cells), function(g, c) (g + c) %% 3L + 1L)
  values[77:80, ] <- 0
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(genes, sprintf("CELLSECRET-%03d", seq_len(cells)))
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$sample_id <- rep(c("sample1", "sample2", "sample3", "sample4"), length.out = cells)
  seu$capture_id <- rep(c("capture1", "capture2"), each = ceiling(cells / 2L), length.out = cells)
  seu$technical_id <- rep(c("batch1", "batch2"), each = ceiling(cells / 2L), length.out = cells)
  seu$biological_id <- rep(c("Control", "Case"), length.out = cells)
  seu$private_personal_note <- "PERSONAL-METADATA-MUST-STAY-LOCAL"
  if (is.null(context)) context <- list(species = "human", tissue = "synthetic tissue",
    columns = list(sample = "sample_id", capture = "capture_id", batch = "technical_id", group = "biological_id"),
    design = list(type = "synthetic crossed software fixture", technical_batch = TRUE,
      notes = "This is a design declaration, not batch-effect validation."),
    research_goal = "Check resumable software policy guards.", notes = "Synthetic counts only.")
  if (processed) {
    SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
    seu$existing_clusters <- rep(c("01", "NA", "cluster space"), length.out = cells)
  }
  context <- scAgentKit:::.sc_run_context(context, seu)
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    start_stage = if (processed) "processed" else "qc", cluster_column = if (processed) "existing_clusters" else "sc_strategy_clusters",
    processed_reason = if (processed) "Synthetic exact normalized layer and literal clusters are supplied for reuse." else NULL)
  qc <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc)
  list(seu = seu, counts = counts, context = context, config = config, qc = qc, evidence = evidence)
}

strategy_schema_proposal <- function(processed = FALSE) {
  list(schema = "scagentkit.strategy.v1", rationale = "Review explicit supported methods on actual synthetic evidence.",
    risks = character(), inferences = character(),
    qc = if (processed) NULL else list(schema = "scagentkit.qc.v1", rationale = "Keep measured positive-count cells in this fixture.",
      risks = character(), filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = if (processed) NULL else list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 32L, npcs = 8L, seed = 11L),
    pcs = if (processed) NULL else list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No integration is requested in a synthetic software test."),
    clustering = if (processed) NULL else list(resolution = .4, diagnostic_resolutions = c(.2, .4, .6)),
    umap = if (processed) NULL else list(run = TRUE, n_neighbors = 10L))
}

strategy_schema_rehash <- function(evidence) {
  evidence$evidence_hash <- scAgentKit:::.sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])
  evidence
}

strategy_schema_hash_changes <- function(before, after) {
  names(before)[!vapply(names(before), function(name) identical(before[[name]], after[[name]]), logical(1))]
}

test_that("strategy evidence preserves user facts and local sparse source while exposing only aggregate requests", {
  f <- strategy_schema_fixture(); before <- f$seu
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc)
  expect_identical(f$seu, before)
  expect_identical(e$summary$background_facts$species, "human")
  expect_identical(e$summary$background_facts$tissue, "synthetic tissue")
  expect_identical(e$summary$background_facts$columns, f$context$columns)
  expect_identical(e$summary$background_facts$design, f$context$design)
  expect_identical(e$summary$background_facts$research_goal, f$context$research_goal)
  expect_identical(e$summary$missing_facts, character())
  expect_identical(e$summary$declared_roles, f$context$columns)
  expect_identical(e$summary$quality, f$qc$summary)
  expect_identical(e$qc, f$qc)
  expect_identical(e$private$cell_ids, colnames(f$seu))
  expect_s4_class(e$private$feature_detection, "sparseMatrix")
  expect_identical(e$private$feature_detection, f$counts[e$private$feature_ids, e$private$cell_ids, drop = FALSE] > 0)
  expect_equal(e$summary$input$expressed_features, 76)
  expect_identical(e$evidence_hash, scAgentKit:::.sc_run_hash(e[setdiff(names(e), "evidence_hash")]))
  prompt <- scAgentKit:::.sc_run_request("strategy", e$summary, f$config)
  expect_identical(prompt$purpose, "strategy")
  expect_false(grepl("CELLSECRET|cell_ids|feature_detection|private_personal_note|PERSONAL-METADATA", prompt$user_prompt))
  expect_false(grepl("SyntheticGene|MT-CO1", prompt$user_prompt))
  expect_true(grepl("synthetic tissue", prompt$user_prompt, fixed = TRUE))
  expect_match(prompt$user_prompt, "batch_group_audit")
})

test_that("missing background and roles remain missing and inferences cannot overwrite declarations", {
  f <- strategy_schema_fixture(context = list())
  expect_setequal(f$evidence$summary$missing_facts,
    c("species", "tissue", "design", "research_goal", "columns.sample", "columns.capture", "columns.batch", "columns.group"))
  expect_length(f$evidence$summary$declared_roles, 0L)
  expect_length(f$evidence$private$roles, 0L)
  expect_null(f$evidence$summary$background_facts$species)
  expect_null(f$evidence$summary$background_facts$design)
  expect_identical(f$evidence$summary$batch_group_audit$status, "missing_information")
  p <- strategy_schema_proposal(); p$inferences <- "Model hypothesis: human blood, which remains unverified."
  validated <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_true(validated$executable)
  expect_identical(validated$applicability$user_facts, f$evidence$summary$background_facts)
  expect_null(validated$applicability$user_facts$species)
  expect_identical(validated$applicability$inferences, p$inferences)
  expect_match(paste(validated$applicability$warnings, collapse = " "), "No sample.*No capture.*No batch")
  expect_match(paste(validated$applicability$warnings, collapse = " "), "Technical batch provenance.*not.*declared")
  p$background_facts <- list(species = "human")
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, f$evidence), "supported named fields")
  context <- strategy_schema_fixture()$context; context$design$technical_batch <- FALSE
  nontechnical <- strategy_schema_fixture(context = context)
  validated <- scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), nontechnical$evidence)
  expect_true(validated$executable)
  expect_identical(validated$applicability$user_facts$design$technical_batch, FALSE)
  expect_match(paste(validated$applicability$warnings, collapse = " "), "no technical correction is inferred")
})

test_that("actual declared batch and biological groups determine rank independently of column names", {
  f <- strategy_schema_fixture()
  audit <- f$evidence$summary$batch_group_audit
  expect_identical(f$context$columns$batch, "technical_id")
  expect_identical(f$context$columns$group, "biological_id")
  expect_identical(audit$status, "crossed_design")
  expect_true(audit$full_rank)
  expect_equal(audit$design_rank, 3)
  expect_equal(audit$design_columns, 3)
  expect_false(audit$complete_confounding)
  expect_equal(sum(vapply(audit$table, `[[`, integer(1), "cells")), ncol(f$seu))
  expect_equal(sum(vapply(audit$sample_batch_sizes, `[[`, integer(1), "cells")), ncol(f$seu))
  f$seu$biological_id <- ifelse(f$seu$technical_id == "batch1", "Control", "Case")
  qc <- scAgentKit:::.sc_run_qc_evidence(f$seu, f$context)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, qc)
  audit <- evidence$summary$batch_group_audit
  expect_identical(audit$status, "complete_confounding")
  expect_true(audit$complete_confounding)
  expect_false(audit$full_rank)
  expect_equal(audit$design_rank, 2)
  expect_equal(audit$connected_components, 2)
  validated <- scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), evidence)
  expect_true(validated$executable) # explicitly choosing no correction remains supported
  expect_match(paste(validated$applicability$warnings, collapse = " "), "could erase biology")
  condition_context <- f$context
  condition_context$columns$group <- NULL
  condition_context$columns$condition <- "biological_id"
  condition_config <- f$config; condition_config$context <- condition_context
  qc <- scAgentKit:::.sc_run_qc_evidence(f$seu, condition_context)
  fallback <- scAgentKit:::.sc_run_strategy_evidence(f$seu, condition_config, qc)
  expect_identical(fallback$summary$batch_group_audit$group_role, "condition")
  expect_false(fallback$summary$batch_group_audit$full_rank)
})

test_that("disconnected crossed blocks missing roles and insufficient levels produce explicit design limitations", {
  audit <- scAgentKit:::.sc_run_strategy_batch_audit(list(
    batch = rep(c("b1", "b2", "b3", "b4"), each = 2),
    group = rep(c("g1", "g2", "g3", "g4"), 2)))
  expect_identical(audit$status, "rank_deficient")
  expect_false(audit$full_rank)
  expect_false(audit$complete_confounding)
  expect_equal(audit$connected_components, 2)
  expect_equal(audit$design_rank, 6)
  expect_equal(audit$design_columns, 7)
  missing_group <- scAgentKit:::.sc_run_strategy_batch_audit(list(batch = c("b1", "b2")))
  expect_identical(missing_group$status, "missing_information")
  expect_match(missing_group$reason, "No group/condition")
  single_batch <- scAgentKit:::.sc_run_strategy_batch_audit(list(batch = rep("only", 4), group = c("a", "b", "a", "b")))
  expect_identical(single_batch$status, "single_batch")
  expect_match(single_batch$reason, "no between-batch correction")
  single_group <- scAgentKit:::.sc_run_strategy_batch_audit(list(batch = c("b1", "b2"), group = c("only", "only")))
  expect_identical(single_group$status, "single_group")
  expect_match(single_group$reason, "not assessable")
  overlapping <- scAgentKit:::.sc_run_strategy_batch_audit(list(batch = c("b1", "b1", "b2"), group = c("g1", "g2", "g2")))
  expect_identical(overlapping$status, "incomplete_overlap")
  expect_true(overlapping$full_rank)
})

test_that("high-cardinality disconnected design audits observed pairs without allocating a dense level matrix", {
  # A dense batch-by-group table would contain 64 million entries; the observed
  # design contains only 8,000 edges. This fixture checks the sparse-size result.
  n <- 8000L
  audit <- scAgentKit:::.sc_run_strategy_batch_audit(list(
    batch = paste0("technical", seq_len(n)), group = paste0("biological", seq_len(n))))
  expect_length(audit$table, n)
  expect_equal(audit$connected_components, n)
  expect_equal(audit$design_rank, n)
  expect_equal(audit$design_columns, 2 * n - 1L)
  expect_false(audit$full_rank)
  expect_true(audit$complete_confounding)
  expect_lt(as.numeric(utils::object.size(audit)), 25 * 1024^2)
})

test_that("projected QC retention re-audits the observed design rather than reusing input crossing", {
  f <- strategy_schema_fixture()
  f$seu$technical_id <- c(rep("batch1", 15), rep("batch2", 20), rep("batch1", 5))
  f$seu$biological_id <- c(rep("Control", 15), rep("Case", 15), rep("Control", 5), rep("Case", 5))
  counts <- SeuratObject::LayerData(f$seu, assay = "RNA", layer = "counts")
  counts[1L, 31:40] <- counts[1L, 31:40] + 1000
  SeuratObject::LayerData(f$seu, assay = "RNA", layer = "counts") <- counts
  qc <- scAgentKit:::.sc_run_qc_evidence(f$seu, f$context)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, qc)
  expect_true(evidence$summary$batch_group_audit$full_rank)
  p <- strategy_schema_proposal(); p$qc$filters[[1L]]$max <- 500
  validated <- scAgentKit:::.sc_run_strategy_validate(p, evidence)
  expect_equal(validated$applicability$retained_cells, 30)
  expect_identical(validated$qc_validated$keep_cells, colnames(f$seu)[1:30])
  expect_identical(validated$applicability$batch_group_audit$status, "complete_confounding")
  expect_false(validated$applicability$batch_group_audit$full_rank)
  expect_equal(sum(vapply(validated$applicability$batch_group_audit$table, `[[`, integer(1), "cells")), 30)
})

test_that("unsupported code cycle doublet and integration actions fail closed while manual is explicitly blocked", {
  e <- strategy_schema_fixture()$evidence
  for (field in c("code", "cycle", "doublet", "cell_cycle", "subcluster")) {
    p <- strategy_schema_proposal(); p[[field]] <- "system('unsupported arbitrary code')"
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "unsupported operations|supported named fields")
  }
  for (method in c("cycle_regression", "doublet_removal", "arbitrary_R")) {
    p <- strategy_schema_proposal(); p$batch$method <- method
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "unsupported.*coordinated strategy")
  }
  p <- strategy_schema_proposal(); p$batch$method <- "harmony"
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "supported named fields")
  p <- strategy_schema_proposal(); p$analysis$vars_to_regress <- c("S.Score", "G2M.Score")
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "supported named fields")
  p <- strategy_schema_proposal(); p$qc$filters[[1L]]$op <- "delete_cycling"
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "only op='range'")
  p <- strategy_schema_proposal(); p$batch$method <- "manual"
  validated <- scAgentKit:::.sc_run_strategy_validate(p, e)
  expect_false(validated$executable)
  expect_identical(validated$blockers[[1L]]$code, "manual_required")
  expect_identical(validated$blockers[[1L]]$operation, "batch")
  expect_match(validated$blockers[[1L]]$message, "analyst.*before execution")
  expect_true(all(c("cycle_regression", "cycling_cell_deletion", "doublet_scoring", "doublet_removal") %in% validated$applicability$unsupported))
})

test_that("parameter bounds reject fractional impossible and silently clipped settings", {
  e <- strategy_schema_fixture()$evidence
  changes <- list(
    function(p) {p$analysis$normalization_method <- "SCTransform"; p},
    function(p) {p$analysis$scale_factor <- 0; p},
    function(p) {p$analysis$nfeatures <- 81L; p},
    function(p) {p$analysis$nfeatures <- 3.5; p},
    function(p) {p$analysis$npcs <- 32L; p},
    function(p) {p$analysis$npcs <- 2.5; p},
    function(p) {p$analysis$seed <- -1; p},
    function(p) {p$analysis$seed <- 1.5; p},
    function(p) {p$pcs$ndim <- 9L; p},
    function(p) {p$pcs$ndim <- 1L; p},
    function(p) {p$pcs$ndim <- 2.5; p},
    function(p) {p$pcs$threshold <- .8; p},
    function(p) {p$clustering$resolution <- 2.1; p},
    function(p) {p$clustering$resolution <- 0; p},
    function(p) {p$clustering$diagnostic_resolutions <- rep(.4, 2); p},
    function(p) {p$clustering$diagnostic_resolutions <- seq(.1, .6, .1); p},
    function(p) {p$umap$run <- 1; p},
    function(p) {p$umap$n_neighbors <- 40L; p},
    function(p) {p$umap$n_neighbors <- 2L; p},
    function(p) {p$umap$n_neighbors <- 3.5; p},
    function(p) {p$rationale <- strrep("x", 4001L); p},
    function(p) {p$inferences <- list(species = "human"); p})
  for (change in changes)
    expect_error(scAgentKit:::.sc_run_strategy_validate(change(strategy_schema_proposal()), e))
  p <- strategy_schema_proposal(); p$pcs <- list(method = "computed_variance", threshold = .8)
  validated <- scAgentKit:::.sc_run_strategy_validate(p, e)
  expect_identical(validated$proposal$pcs, list(method = "computed_variance", threshold = .8))
  for (threshold in c(0, 1, -1, Inf)) {
    p$pcs$threshold <- threshold
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "pcs\\$threshold")
  }
  p <- strategy_schema_proposal(); p$pcs <- list(method = "elbow_guess", ndim = 5)
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "Unsupported PC selection")
  p <- strategy_schema_proposal(); p$clustering$diagnostic_resolutions <- list(.6, .2, .4)
  expect_identical(scAgentKit:::.sc_run_strategy_validate(p, e)$proposal$clustering$diagnostic_resolutions, c(.2, .4, .6))
})

test_that("insufficient retained cells expressed features layers mitochondrial evidence and dependencies are actionable", {
  e <- strategy_schema_fixture(cells = 20L)$evidence
  expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), "at least 21")
  f <- strategy_schema_fixture()
  sparse <- f$counts; sparse[3:80, ] <- 0
  SeuratObject::LayerData(f$seu, assay = "RNA", layer = "counts") <- sparse
  qc <- scAgentKit:::.sc_run_qc_evidence(f$seu, f$context)
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, qc)
  expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), "Fewer than three genes")
  no_species <- strategy_schema_fixture(context = list(tissue = "synthetic"))
  p <- strategy_schema_proposal(); p$qc$filters <- list(list(op = "range", metric = "percent_mt", max = 20))
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, no_species$evidence), "unavailable")
  f <- strategy_schema_fixture(); alternate <- f$config; alternate$counts_layer <- "missing"
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, alternate, f$qc), "Exact layer|layer")
  alternate <- f$config; alternate$normalized_layer <- "alternate.data"
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, alternate, f$qc)
  expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), "select normalized_layer='data'")
  e <- f$evidence; e$summary$input$counts_layer <- "counts.explicit"; e <- strategy_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), "canonical counts_layer='counts'")
  for (package in c("Seurat", "SeuratObject")) {
    e <- f$evidence; e$summary$dependencies[[package]]$available <- FALSE; e <- strategy_schema_rehash(e)
    expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), paste0("Required dependency '", package, "' is unavailable"))
  }
  e <- f$evidence; e$summary$dependencies$harmony$available <- FALSE; e <- strategy_schema_rehash(e)
  p <- strategy_schema_proposal()
  p$batch <- list(method = "harmony", group_by_vars = "technical_id", theta = 2,
    lambda = 1, sigma = .1, max_iter = 20L, nclust = 10L,
    reason = "Explicit crossed synthetic technical factor, with a repairable optional runtime dependency.")
  validated <- scAgentKit:::.sc_run_strategy_validate(p, e)
  expect_true(validated$executable)
  expect_identical(validated$proposal$batch$method, "harmony")
  expect_false(e$summary$dependencies$harmony$available)
  # Valid design and parameters remain reviewable when the optional package
  # needs installation. The real runtime guard stops before correction; a
  # caller must repair that dependency explicitly, never substitute none.
  expect_true(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e)$executable)
})

test_that("altered evidence or source cannot produce a valid stale strategy", {
  f <- strategy_schema_fixture()
  e <- f$evidence; e$summary$background_facts$species <- "mouse"
  expect_error(scAgentKit:::.sc_run_strategy_validate(strategy_schema_proposal(), e), "evidence changed")
  qc <- f$qc; qc$metrics$nCount[1L] <- 99
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, qc), "intact actual QC evidence")
  altered <- f$seu
  counts <- SeuratObject::LayerData(altered, assay = "RNA", layer = "counts"); counts[1L, 1L] <- counts[1L, 1L] + 1
  SeuratObject::LayerData(altered, assay = "RNA", layer = "counts") <- counts
  expect_error(scAgentKit:::.sc_run_strategy_evidence(altered, f$config, f$qc), "counts/features differ")
  # Seurat subsetting preserves source order even for a reversed selector.
  # Rename through its public API to exercise an actually changed literal ID order.
  renamed <- SeuratObject::RenameCells(f$seu, new.names = rev(colnames(f$seu)))
  expect_error(scAgentKit:::.sc_run_strategy_evidence(renamed, f$config, f$qc), "source cells differ")
})

test_that("calculation dependencies invalidate exactly affected downstream policy components", {
  e <- strategy_schema_fixture()$evidence; p <- strategy_schema_proposal()
  before <- scAgentKit:::.sc_run_strategy_validate(p, e)$dependency_hashes
  expect_identical(names(before), c("qc", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$clustering$resolution <- .8
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), "clustering")
  changed <- p; changed$pcs$ndim <- 6L
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), c("pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$analysis$scale_factor <- 5000
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), c("basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$qc$filters[[1L]]$min <- 2
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), names(before))
  changed <- p; changed$umap$n_neighbors <- 11L
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), "umap")
  changed <- p; changed$batch$method <- "manual"
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(strategy_schema_hash_changes(before, after), c("batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$rationale <- "New strategy explanation."
  changed$risks <- "New disclosed uncertainty."; changed$inferences <- "New hypothesis, not a fact."
  changed$qc$rationale <- "New QC explanation."; changed$qc$risks <- "New QC uncertainty."
  changed$batch$reason <- "New reason for the same no-correction decision."
  after <- scAgentKit:::.sc_run_strategy_validate(changed, e)$dependency_hashes
  expect_identical(after, before)
  changed_evidence <- e; changed_evidence$summary$background_facts$design$notes <- "New explanatory design note."
  changed_evidence <- strategy_schema_rehash(changed_evidence)
  expect_false(identical(changed_evidence$evidence_hash, e$evidence_hash))
  expect_identical(scAgentKit:::.sc_run_strategy_validate(p, changed_evidence)$dependency_hashes, before)
})

test_that("processed strategy reuses exact source facts and requires explicit NULL computation settings", {
  f <- strategy_schema_fixture(processed = TRUE); before <- f$seu
  p <- strategy_schema_proposal(processed = TRUE)
  validated <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_true(validated$executable)
  expect_true(validated$applicability$processed_reuse)
  expect_null(validated$qc_validated)
  expect_equal(validated$applicability$retained_cells, ncol(f$seu))
  expect_identical(f$seu, before)
  expect_identical(f$evidence$private$reused_cluster_column, "existing_clusters")
  expect_identical(f$evidence$private$reused_clusters, as.character(f$seu$existing_clusters))
  expect_equal(f$evidence$summary$input$reused_cluster_count, 3)
  expect_identical(f$evidence$summary$input$processed_reason, f$config$processed_reason)
  expect_true(f$evidence$summary$input$normalized_layer_available)
  expect_identical(f$evidence$summary$capabilities$normalization, "reuse_only")
  expect_true("harmony_execution" %in% f$evidence$summary$capabilities$unsupported)
  changed <- p
  changed$batch <- list(method = "harmony", group_by_vars = "technical_id", theta = 2,
    lambda = 1, sigma = .1, max_iter = 20L, nclust = 10L,
    reason = "A processed foundation cannot acquire coordinated raw-entry Harmony implicitly.")
  blocked <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  expect_false(blocked$executable)
  expect_true("processed_harmony_unsupported" %in%
    vapply(blocked$blockers, `[[`, character(1), "code"))
  expect_identical(f$seu, before)
  for (field in c("qc", "analysis", "pcs", "clustering", "umap")) {
    changed <- p; changed[[field]] <- strategy_schema_proposal()[[field]]
    expect_error(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence), "must be explicit NULL")
  }
  missing <- p; missing["qc"] <- NULL
  expect_error(scAgentKit:::.sc_run_strategy_validate(missing, f$evidence), "supported named fields")
  config <- f$config; config$normalized_layer <- "missing"
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc), "exact normalized layer")
  config <- f$config; config$cluster_column <- "missing"
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc), "complete literal cluster column")
  expect_error(scAgentKit:::.sc_run_input(f$seu, f$context, start_stage = "processed", cluster_column = "existing_clusters"), "processed_reason")
})
