# Synthetic counts check executable policy and evidence boundaries. They are not
# biological evidence for when regression is appropriate and make no AI calls.
cycle_schema_fixture <- function(insufficient = FALSE, processed = FALSE,
                                 retained_constant = FALSE) {
  s_genes <- paste0("CycleSecretS", seq_len(12L))
  g2m_genes <- paste0("CycleSecretG", seq_len(12L))
  genes <- c(s_genes, g2m_genes, paste0("PrivateBackground", seq_len(120L)))
  cells <- sprintf("CYCLE-CELL-SECRET-%03d", seq_len(40L))
  values <- outer(seq_along(genes), seq_along(cells),
    function(g, c) 1 + (g * g + 3 * g * c + c * c) %% 19)
  values[seq_len(12L), ] <- values[seq_len(12L), ] +
    rep((seq_along(cells) %% 7L)^2, each = 12L)
  values[13:24, ] <- values[13:24, ] +
    rep(((seq_along(cells) %/% 7L) %% 6L)^2, each = 12L)
  if (retained_constant) {
    values[, 1:25] <- rep(values[, 1L], 25L)
    values[length(genes), 26:40] <- values[length(genes), 26:40] + 5000
  }
  if (insufficient) values[seq_len(24L), ] <- 0
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(genes, cells)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$private_note <- "PRIVATE-CYCLE-METADATA"
  if (processed) {
    SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
    seu$existing_clusters <- rep(c("01", "NA", "cluster space"), length.out = length(cells))
  }
  context <- scAgentKit:::.sc_run_context(list(species = "human", tissue = "synthetic tissue",
    design = list(type = "synthetic cycle schema fixture", technical_batch = FALSE),
    research_goal = "Verify cycle strategy guards on synthetic counts."), seu)
  geneset <- scAgentKit::sc_cycle_gene_set("human", s_genes = s_genes,
    g2m_genes = g2m_genes, source = "Synthetic software fixture", version = "1")
  options <- scAgentKit:::.sc_run_cycle_options(context,
    list(gene_set = geneset, column_prefix = "sc_test_cycle", seed = 17L,
      nbin = 4L, ctrl = 2L))
  config <- list(context = context, assay = "RNA", counts_layer = "counts",
    normalized_layer = "data", start_stage = if (processed) "processed" else "qc",
    cluster_column = if (processed) "existing_clusters" else "sc_strategy_clusters",
    processed_reason = if (processed) "Reuse explicitly supplied synthetic processed analysis." else NULL,
    cycle_diagnostics = options)
  qc <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  record <- scAgentKit:::.sc_run_cycle_evidence(seu, config)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc, record)
  list(seu = seu, counts = counts, context = context, config = config,
    qc = qc, record = record, evidence = evidence)
}

cycle_schema_proposal <- function(processed = FALSE, method = NULL) {
  proposal <- list(schema = "scagentkit.strategy.v1",
    rationale = "Review cycle diagnostics and explicit supported analysis on synthetic counts.",
    risks = character(), inferences = character(),
    qc = if (processed) NULL else list(schema = "scagentkit.qc.v1",
      rationale = "Retain measured positive-count cells.", risks = character(),
      filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = if (processed) NULL else list(normalization_method = "LogNormalize",
      scale_factor = 10000, nfeatures = 32L, npcs = 8L, seed = 11L),
    pcs = if (processed) NULL else list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No technical integration is requested."),
    clustering = if (processed) NULL else list(resolution = .4),
    umap = if (processed) NULL else list(run = FALSE, n_neighbors = 10L))
  if (!is.null(method)) proposal$cycle <- list(method = method,
    reason = "Explicit synthetic policy choice for software validation.")
  proposal
}

cycle_schema_rehash <- function(evidence) {
  evidence$evidence_hash <- scAgentKit:::.sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])
  evidence
}

cycle_schema_hash_changes <- function(before, after) {
  names(before)[!vapply(names(before), function(name) identical(before[[name]], after[[name]]), logical(1))]
}

test_that("gene-set declarations require literal species and explicit custom provenance", {
  human <- scAgentKit::sc_cycle_gene_set("human")
  expect_identical(human$source, "Seurat::cc.genes.updated.2019")
  expect_identical(human$version, "2019")
  expect_identical(human$package$data, "cc.genes.updated.2019")
  expect_true(length(human$s_genes) >= 5L)
  expect_true(length(human$g2m_genes) >= 5L)
  expect_null(human$symbol_mapping)
  expect_error(scAgentKit::sc_cycle_gene_set("mouse"), "explicit.*literal|explicit.*versioned")
  expect_error(scAgentKit::sc_cycle_gene_set("zebrafish"), "species|human|mouse")
  expect_error(scAgentKit::sc_cycle_gene_set("human", s_genes = "S1"), "both")
  expect_error(scAgentKit::sc_cycle_gene_set("human", s_genes = "S1", g2m_genes = "G1"), "source")
  expect_error(scAgentKit::sc_cycle_gene_set("human", s_genes = "S1", g2m_genes = "G1",
    source = "fixture", version = " "), "nonempty")
  mouse <- scAgentKit::sc_cycle_gene_set("mouse", s_genes = c("S1", "S2"),
    g2m_genes = c("G1", "G2"), source = "Explicit synthetic mouse lists", version = "1")
  expect_identical(mouse$species, "mouse")
  expect_identical(mouse$s_genes, c("S1", "S2"))
  expect_error(scAgentKit:::.sc_run_cycle_options(list(), list(gene_set = human)), "explicit context\\$species")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "mouse"),
    list(gene_set = human)), "species.*match")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"),
    list(gene_set = mouse)), "species.*match")
  expect_error(scAgentKit:::.sc_run_cycle_options(list(species = "human"),
    list(gene_set = human, code = "arbitrary()")), "supported diagnostic options")
})

test_that("cycle evidence is immutable full-input data and only aggregates enter requests", {
  f <- cycle_schema_fixture(); before <- f$seu
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc, f$record)
  expect_identical(f$seu, before)
  expect_identical(e$summary$cycle_diagnostics, f$record$summary)
  expect_identical(e$private$cycle_record, f$record)
  expect_identical(f$record$summary$status, "available")
  expect_identical(f$record$summary$reference, "fixed_full_input")
  expect_false(f$record$summary$refit_after_qc)
  expect_equal(f$record$summary$cohort$removed_cells, 0)
  expect_identical(f$record$scores$cell_id, colnames(f$seu))
  expect_identical(names(f$record$summary$columns), c("s_score", "g2m_score", "phase", "difference"))
  expect_true(all(grepl("^sc_test_cycle_", f$record$summary$columns)))
  expect_identical(e$summary$capabilities$cycle, c("cycle_scoring", "none", "full", "difference"))
  expect_false(any(c("cycle_scoring", "cycle_regression") %in% e$summary$capabilities$unsupported))
  expect_true(all(c("cycling_cell_deletion", "doublet_scoring", "doublet_removal",
    "subclustering") %in% e$summary$capabilities$unsupported))
  expect_false("harmony_execution" %in% e$summary$capabilities$unsupported)
  expect_true("harmony" %in% e$summary$capabilities$batch)
  request <- scAgentKit:::.sc_run_request("strategy", e$summary, f$config)
  expect_match(request$user_prompt, "cycle_diagnostics")
  expect_false(grepl("CYCLE-CELL-SECRET|CycleSecret|PrivateBackground|PRIVATE-CYCLE-METADATA|cell_ids|count_cell_hashes|canonical_s_genes", request$user_prompt))
  expect_identical(e$evidence_hash, scAgentKit:::.sc_run_hash(e[setdiff(names(e), "evidence_hash")]))
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc), "missing or changed|missing|absent")
  bad <- f$record; bad$scores[[bad$summary$columns[["s_score"]]]][1L] <- 999
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc, bad), "changed|inconsistent")
  config <- f$config; config$cycle_diagnostics$seed <- 18L
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc, f$record), "options differ")
  config <- f$config; config$context$species <- "mouse"
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc, f$record), "species.*match")
  altered <- f$seu
  counts <- SeuratObject::LayerData(altered, assay = "RNA", layer = "counts")
  counts[1L, 1L] <- counts[1L, 1L] + 1
  SeuratObject::LayerData(altered, assay = "RNA", layer = "counts") <- counts
  qc <- scAgentKit:::.sc_run_qc_evidence(altered, f$context)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(altered, f$config, qc, f$record), "Cycle evidence source")
  renamed <- SeuratObject::RenameCells(f$seu, new.names = rev(colnames(f$seu)))
  qc <- scAgentKit:::.sc_run_qc_evidence(renamed, f$context)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(renamed, f$config, qc, f$record), "Cycle evidence source")
})

test_that("enabled cycle defaults to none while available full and difference use approved score columns", {
  f <- cycle_schema_fixture()
  validated <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), f$evidence)
  expect_identical(validated$proposal$cycle$method, "none")
  expect_match(validated$proposal$cycle$reason, "diagnostics only", ignore.case = TRUE)
  expect_identical(validated$cycle$regressors, character())
  expect_identical(validated$applicability$cycle$scoring_status, "available")
  expect_equal(validated$applicability$cycle$retained_cells, ncol(f$seu))
  expect_identical(validated$cycle$evidence_hash, f$record$evidence_hash)
  columns <- f$record$summary$columns
  full <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(method = "full"), f$evidence)
  difference <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(method = "difference"), f$evidence)
  expect_identical(full$cycle$regressors, unname(columns[c("s_score", "g2m_score")]))
  expect_identical(difference$cycle$regressors, unname(columns[["difference"]]))
  expect_equal(full$applicability$cycle$design_rank, 3)
  expect_equal(difference$applicability$cycle$design_rank, 2)
  expect_true(all(full$applicability$cycle$regressor_variance > 0))
  expect_true(full$executable)
  expect_true(difference$executable)
})

test_that("insufficient diagnostic coverage retains Unknown cells and supports only none regression", {
  f <- cycle_schema_fixture(insufficient = TRUE)
  expect_identical(f$record$summary$status, "insufficient")
  expect_equal(f$record$summary$coverage$S$expressed, 0)
  expect_equal(f$record$summary$coverage$G2M$expressed, 0)
  expect_true(all(f$record$scores[[f$record$summary$columns[["phase"]]]] == "Unknown"))
  expect_true(all(is.na(f$record$scores[[f$record$summary$columns[["s_score"]]]])))
  expect_equal(f$record$summary$cohort$input_cells, ncol(f$seu))
  expect_equal(f$record$summary$cohort$removed_cells, 0)
  for (method in c("full", "difference"))
    expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(method = method),
      f$evidence), "reference is insufficient")
  for (method in list(NULL, "none")) {
    validated <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(method = method), f$evidence)
    expect_true(validated$executable)
    expect_identical(validated$proposal$cycle$method, "none")
    expect_identical(validated$qc_validated$keep_cells, colnames(f$seu))
    expect_identical(validated$applicability$cycle$scoring_status, "insufficient")
  }
})

test_that("retained-cell variance is checked after actual QC without refitting diagnostics", {
  f <- cycle_schema_fixture(retained_constant = TRUE)
  expect_identical(f$record$summary$status, "available")
  p <- cycle_schema_proposal(method = "none")
  p$qc$filters[[1L]]$max <- max(f$qc$metrics$nCount[1:25])
  validated <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(validated$qc_validated$keep_cells, colnames(f$seu)[1:25])
  expect_equal(validated$applicability$cycle$retained_cells, 25)
  expect_identical(validated$cycle$evidence_hash, f$record$evidence_hash)
  expect_false(validated$applicability$cycle$refit_after_qc)
  for (method in c("full", "difference")) {
    p$cycle$method <- method
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, f$evidence), "zero or unavailable variance|rank deficient")
  }
})

test_that("cycle plans reject empty untyped code and deletion fields even when diagnostics are enabled", {
  e <- cycle_schema_fixture()$evidence
  invalid <- list(NULL, list(), "full", list(method = "none"),
    list(method = "none", reason = ""), list(method = "none", reason = " "),
    list(method = 1, reason = "typed"), list(method = c("none", "full"), reason = "typed"),
    list(method = "none", reason = list("text")), list(method = "none", reason = NA_character_),
    list(method = "arbitrary_R", reason = "unsupported"),
    list(method = "delete_cycling", reason = "unsupported"),
    list(method = "none", reason = "typed", vars_to_regress = "S.Score"),
    list(method = "none", reason = "typed", code = "system('arbitrary')"))
  for (choice in invalid) {
    p <- cycle_schema_proposal(); p["cycle"] <- list(choice)
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "Cycle choice|cycle\\$|unsupported|nonempty")
  }
  for (field in c("code", "cell_cycle", "doublet", "subcluster")) {
    p <- cycle_schema_proposal(); p[[field]] <- list(method = "none", reason = "unsupported")
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "supported named fields")
  }
  p <- cycle_schema_proposal(); p$analysis$vars_to_regress <- "sc_test_cycle_S.Score"
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "supported named fields")
  p <- cycle_schema_proposal(); p$qc$filters[[1L]]$op <- "delete_cycling"
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "only op='range'")
  p <- cycle_schema_proposal(); p$risks <- list(); p$inferences <- list()
  expect_identical(scAgentKit:::.sc_run_strategy_validate(p, e)$proposal$risks, character())
  p <- cycle_schema_proposal(); p$cycle <- list(method = "none", method = "full", reason = "duplicate")
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "exactly method and reason")
})

test_that("processed entry exposes diagnostics and none while preserving its foundation", {
  f <- cycle_schema_fixture(processed = TRUE); before <- f$seu
  expect_true("harmony_execution" %in% f$evidence$summary$capabilities$unsupported)
  expect_false("harmony" %in% f$evidence$summary$capabilities$batch)
  validated <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(processed = TRUE), f$evidence)
  expect_true(validated$applicability$processed_reuse)
  expect_identical(validated$proposal$cycle$method, "none")
  expect_null(validated$qc_validated)
  expect_equal(validated$applicability$cycle$retained_cells, ncol(f$seu))
  expect_identical(f$evidence$summary$capabilities$cycle, c("cycle_scoring", "none"))
  expect_true("cycle_regression" %in% f$evidence$summary$capabilities$unsupported)
  expect_identical(f$seu, before)
  for (method in c("full", "difference"))
    expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(TRUE, method),
      f$evidence), "reuses its analysis foundation")
})

test_that("cycle calculation dependencies preserve preprocessing and fixed scores on method revisions", {
  f <- cycle_schema_fixture(); p <- cycle_schema_proposal(method = "none")
  before <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)$dependency_hashes
  expect_identical(names(before), c("qc", "preprocess", "cycle", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  downstream <- c("basis", "pcs", "batch", "neighbors", "clustering", "umap")
  changed <- p; changed$cycle$method <- "full"
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(cycle_schema_hash_changes(before, after), c("cycle", downstream))
  changed <- p; changed$cycle$reason <- "Revised explanation of the same reviewed choice."
  expect_identical(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes, before)
  changed <- p; changed$analysis$npcs <- 9L
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(cycle_schema_hash_changes(before, after), downstream)
  changed <- p; changed$analysis$scale_factor <- 5000
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(cycle_schema_hash_changes(before, after), c("preprocess", downstream))
  changed <- p; changed$qc$filters[[1L]]$min <- 2
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(cycle_schema_hash_changes(before, after), c("qc", "preprocess", downstream))
  expect_identical(after$cycle, before$cycle)
})

test_that("disabled cycle retains the legacy schema and dependency topology", {
  f <- cycle_schema_fixture(); config <- f$config; config$cycle_diagnostics <- NULL
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc)
  expect_false("cycle_diagnostics" %in% names(e$summary))
  expect_false("cycle_record" %in% names(e$private))
  expect_false("cycle" %in% names(e$summary$capabilities))
  expect_true(all(c("cycle_scoring", "cycle_regression") %in% e$summary$capabilities$unsupported))
  validated <- scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), e)
  expect_false("cycle" %in% names(validated$proposal))
  expect_false("cycle" %in% names(validated$applicability))
  expect_false("cycle" %in% names(validated))
  expect_identical(names(validated$dependency_hashes), c("qc", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(method = "none"), e), "supported named fields")
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc, f$record), "explicitly enabled")
})

test_that("verified cycle records cannot be detached from their local strategy evidence", {
  f <- cycle_schema_fixture()
  e <- f$evidence; e$private$cycle_record <- NULL; e <- cycle_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), e), "intact local cycle evidence")
  e <- f$evidence; e$summary$cycle_diagnostics <- NULL; e <- cycle_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), e), "intact local cycle evidence")
  e <- f$evidence; e$summary$cycle_diagnostics$status <- "insufficient"; e <- cycle_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), e), "summary differs")
  e <- f$evidence; e$private$cycle_record$scores[[f$record$summary$columns[["s_score"]]]][1L] <- 99
  e <- cycle_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(cycle_schema_proposal(), e), "missing or changed|inconsistent")
})
