# These deterministic predicted labels test schema/selection boundaries only.
# They are authored software fixtures, not scDblFinder performance evidence,
# calibrated probabilities, or ground-truth doublet labels. Real algorithm and
# restart/Continue checks are owned by the engine and workflow test suites.
doublet_schema_authored_record <- function(seu, config, predicted, unsupported) {
  predictions <- colnames(seu)[predicted]
  testthat::local_mocked_bindings(
    .sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      ids <- colnames(counts); called <- ids %in% predictions
      list(scores = data.frame(cell_id = ids, score = ifelse(called, .8, .2),
        class = ifelse(called, "doublet", "singlet"), row.names = ids,
        stringsAsFactors = FALSE), threshold = .5, warnings = character(),
        messages = "Authored predicted labels for schema software tests only; no classifier was executed.",
        classifier_audit = list(train_attempts = 3L, train_successes = 3L,
          predict_attempts = 3L, predict_successes = 3L,
          training_errors = character(), prediction_errors = character(),
          test_only_mock = TRUE),
        adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
    }, .package = "scAgentKit", .env = environment())
  record <- scAgentKit:::.sc_run_doublet_evidence(seu, config)
  scAgentKit:::.sc_run_doublet_verify(record)
  record
}

doublet_schema_fixture <- function(processed = FALSE, predicted = c(1:8, 102:109),
                                   cycle = FALSE, unsupported = FALSE,
                                   selected_expression = FALSE) {
  cells <- sprintf("DOUBLET-CELL-SECRET-%03d", seq_len(202L))
  genes <- paste0("DoubletPrivateGene", seq_len(240L))
  values <- outer(seq_along(genes), seq_along(cells),
    function(g, c) 1 + (g * g + 3 * g * c + c * c) %% 19)
  if (cycle) {
    values[1:12, ] <- values[1:12, ] + rep((seq_along(cells) %% 7L)^2, each = 12L)
    values[13:24, ] <- values[13:24, ] +
      rep(((seq_along(cells) %/% 7L) %% 6L)^2, each = 12L)
  }
  if (selected_expression) {
    values[3:240, ] <- 0
    values[3:240, predicted] <- 4
    # Keep this schema boundary within the detector's declared minimum count
    # prerequisite. Only two genes remain expressed after the authored removal.
    values[1:2, ] <- values[1:2, ] + 200
  }
  values[length(genes), c(1:4, 102:105)] <- values[length(genes), c(1:4, 102:105)] + 5000
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(genes, cells)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$capture_loading_unit <- rep(c("CAPTURE-A", "CAPTURE-B"), each = 101L)
  seu$donor_id <- rep(c("DONOR-1", "DONOR-2"), length.out = length(cells))
  seu$private_note <- "PRIVATE-DOUBLET-METADATA"
  if (processed) {
    SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
    seu$existing_clusters <- rep(c("01", "NA", "cluster space"), length.out = length(cells))
  }
  context <- scAgentKit:::.sc_run_context(list(species = "human", tissue = "synthetic tissue",
    columns = list(capture = "capture_loading_unit", donor = "donor_id"),
    design = list(type = "Synthetic droplet software fixture", technical_batch = FALSE),
    research_goal = "Check exact-ID selection and strategy dependency boundaries."), seu)
  options <- scAgentKit:::.sc_run_doublet_options(context,
    list(data_type = "scrna_droplet", input_source = "Authored called-cell synthetic count fixture",
      empty_droplets_removed = TRUE,
      capture = list(method = "column", column = "capture_loading_unit",
        source = "Explicit synthetic physical loading units, crossed with donors"),
      rate = list(method = "manual", value = .1, source = "Authored software fixture rate"),
      nfeatures = if (unsupported) 500L else 200L, seed = 17L))
  config <- list(context = context, assay = "RNA", counts_layer = "counts",
    normalized_layer = "data", start_stage = if (processed) "processed" else "qc",
    cluster_column = if (processed) "existing_clusters" else "sc_strategy_clusters",
    processed_reason = if (processed) "Reuse supplied synthetic data and literal clusters." else NULL,
    doublet_diagnostics = options)
  qc <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  record <- doublet_schema_authored_record(seu, config, predicted, unsupported)
  cycle_record <- NULL
  if (cycle) {
    geneset <- scAgentKit::sc_cycle_gene_set("human", s_genes = genes[1:12],
      g2m_genes = genes[13:24], source = "Synthetic schema software fixture", version = "1")
    config$cycle_diagnostics <- scAgentKit:::.sc_run_cycle_options(context,
      list(gene_set = geneset, column_prefix = "sc_test_cycle", seed = 17L, nbin = 4L, ctrl = 2L))
    cycle_record <- scAgentKit:::.sc_run_cycle_evidence(seu, config)
  }
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc,
    cycle_record = cycle_record, doublet_record = record)
  list(seu = seu, counts = counts, context = context, config = config,
    qc = qc, record = record, cycle_record = cycle_record, evidence = evidence)
}

doublet_schema_proposal <- function(processed = FALSE, method = NULL) {
  proposal <- list(schema = "scagentkit.strategy.v1",
    rationale = "Review authored doublet predictions on actual synthetic count evidence.",
    risks = character(), inferences = character(),
    qc = if (processed) NULL else list(schema = "scagentkit.qc.v1",
      rationale = "Retain measured positive-count cells.", risks = character(),
      filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = if (processed) NULL else list(normalization_method = "LogNormalize",
      scale_factor = 10000, nfeatures = 32L, npcs = 8L, seed = 11L),
    pcs = if (processed) NULL else list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No integration requested in a software fixture."),
    clustering = if (processed) NULL else list(resolution = .4),
    umap = if (processed) NULL else list(run = FALSE, n_neighbors = 10L))
  if (!is.null(method)) proposal$doublet <- list(method = method,
    reason = "Explicit software-test choice; predictions are not truth.")
  proposal
}

doublet_schema_rehash <- function(evidence) {
  evidence$evidence_hash <- scAgentKit:::.sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])
  evidence
}

doublet_schema_hash_changes <- function(before, after) {
  names(before)[!vapply(names(before), function(name) identical(before[[name]], after[[name]]), logical(1))]
}

test_that("enabled doublet evidence binds actual counts and local IDs without sharing per-cell data", {
  f <- doublet_schema_fixture(); before <- f$seu
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc,
    doublet_record = f$record)
  expect_identical(f$seu, before)
  expect_identical(e$summary$doublet_diagnostics, f$record$summary)
  expect_identical(e$private$doublet_record, f$record)
  expect_identical(f$record$cell_ids, colnames(f$seu))
  expect_identical(f$record$scores$cell_id, colnames(f$seu))
  expect_identical(e$summary$capabilities$doublet, c("doublet_scoring", "keep", "remove_predicted"))
  expect_false(any(c("doublet_scoring", "doublet_removal") %in% e$summary$capabilities$unsupported))
  expect_true(all(c("cycling_cell_deletion", "subclustering") %in%
    e$summary$capabilities$unsupported))
  expect_false("harmony_execution" %in% e$summary$capabilities$unsupported)
  expect_true("harmony" %in% e$summary$capabilities$batch)
  request <- scAgentKit:::.sc_run_request("strategy", e$summary, f$config)
  expect_match(request$user_prompt, "doublet_diagnostics")
  expect_false(grepl("DOUBLET-CELL-SECRET|DoubletPrivateGene|PRIVATE-DOUBLET-METADATA|cell_ids|predicted_cells|capture_map|count_cell_hashes", request$user_prompt))
  expect_identical(e$evidence_hash, scAgentKit:::.sc_run_hash(e[setdiff(names(e), "evidence_hash")]))
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc), "missing|changed|absent")
  bad <- f$record; bad$scores[[bad$summary$columns[["score"]]]][1L] <- 999
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc,
    doublet_record = bad), "changed|inconsistent")
  config <- f$config; config$doublet_diagnostics$seed <- 18L
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc,
    doublet_record = f$record), "options differ")
  altered <- f$seu
  counts <- SeuratObject::LayerData(altered, assay = "RNA", layer = "counts")
  counts[1L, 1L] <- counts[1L, 1L] + 1
  SeuratObject::LayerData(altered, assay = "RNA", layer = "counts") <- counts
  qc <- scAgentKit:::.sc_run_qc_evidence(altered, f$context)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(altered, f$config, qc,
    doublet_record = f$record), "Doublet evidence source")
  renamed <- SeuratObject::RenameCells(f$seu, new.names = rev(colnames(f$seu)))
  qc <- scAgentKit:::.sc_run_qc_evidence(renamed, f$context)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(renamed, f$config, qc,
    doublet_record = f$record), "Doublet evidence source")
  captures <- f$seu
  captures$capture_loading_unit <- unname(rev(captures$capture_loading_unit))
  expect_false(identical(unname(captures$capture_loading_unit),
    unname(f$seu$capture_loading_unit)))
  qc <- scAgentKit:::.sc_run_qc_evidence(captures, f$context)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(captures, f$config, qc,
    doublet_record = f$record), "capture/loading-unit assignments")
})

test_that("doublet choice omission keeps all cells and removal is one exact QC intersection", {
  f <- doublet_schema_fixture(); p <- doublet_schema_proposal()
  keep <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(keep$proposal$doublet,
    list(method = "keep", reason = "Diagnostics only; no removal requested."))
  expect_identical(keep$selected_cells, colnames(f$seu))
  expect_identical(keep$doublet$removed_cells, character())
  expect_identical(keep$applicability$doublet$removed_cell_ids, character())
  p$doublet <- list(method = "remove_predicted", reason = "Review the authored exact set.")
  p$qc$filters[[1L]]$max <- 2800
  removed <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  qc_keep <- removed$qc_validated$keep_cells
  expected_removed <- qc_keep[qc_keep %in% f$record$predicted_cells]
  expected_selected <- qc_keep[!qc_keep %in% f$record$predicted_cells]
  expect_gt(length(expected_removed), 0)
  expect_gt(sum(!f$record$predicted_cells %in% qc_keep), 0)
  expect_identical(removed$doublet$removed_cells, expected_removed)
  expect_identical(removed$selected_cells, expected_selected)
  expect_identical(removed$applicability$doublet$qc_keep_cell_ids, qc_keep)
  expect_identical(removed$applicability$doublet$selected_cell_ids, expected_selected)
  expect_identical(removed$applicability$doublet$removed_cell_ids, expected_removed)
  expect_equal(removed$applicability$retained_cells, length(expected_selected))
  expect_identical(removed$applicability$doublet$evidence_hash, f$record$evidence_hash)
  expect_identical(removed$applicability$doublet$selection_hash, removed$dependency_hashes$selection)
  expect_identical(removed$qc_validated,
    scAgentKit:::.sc_run_qc_validate(p$qc, f$qc))
  expect_true(removed$executable)
})

test_that("all analysis bounds use actual cells and genes after doublet selection", {
  f <- doublet_schema_fixture(predicted = 1:182)
  p <- doublet_schema_proposal(method = "remove_predicted")
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, f$evidence), "at least 21.*retained")
  f <- doublet_schema_fixture(predicted = 1:180)
  p$analysis$npcs <- 22L
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, f$evidence), "npcs must be smaller")
  p <- doublet_schema_proposal(method = "remove_predicted"); p$umap$n_neighbors <- 22L
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, f$evidence), "umap\\$n_neighbors")
  f <- doublet_schema_fixture(selected_expression = TRUE)
  expect_error(scAgentKit:::.sc_run_strategy_validate(
    doublet_schema_proposal(method = "remove_predicted"), f$evidence), "Fewer than three genes")
})

test_that("doublet removal rechecks fixed cycle scores on the final selected set", {
  f <- doublet_schema_fixture(cycle = TRUE)
  p <- doublet_schema_proposal(method = "remove_predicted")
  p$cycle <- list(method = "full", reason = "Explicit synthetic regression choice.")
  validated <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_equal(validated$applicability$cycle$retained_cells, length(validated$selected_cells))
  expect_identical(validated$cycle$evidence_hash, f$cycle_record$evidence_hash)
  expect_false(validated$applicability$cycle$refit_after_qc)
  expect_identical(validated$cycle,
    scAgentKit:::.sc_run_cycle_validate_choice(p$cycle, f$cycle_record, validated$selected_cells))
  expect_identical(names(validated$dependency_hashes),
    c("qc", "selection", "doublet", "preprocess", "cycle", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  # Author a constant retained-score boundary while leaving predicted rows
  # variable. The score values are labelled software evidence, not biology.
  cycle <- f$cycle_record; columns <- cycle$summary$columns
  selected <- !cycle$cell_ids %in% f$record$predicted_cells
  cycle$scores[[columns[["s_score"]]]][selected] <- 1
  cycle$scores[[columns[["g2m_score"]]]][selected] <- 2
  cycle$scores[[columns[["s_score"]]]][!selected] <- seq_len(sum(!selected))
  cycle$scores[[columns[["g2m_score"]]]][!selected] <- seq_len(sum(!selected))^2
  cycle$scores[[columns[["difference"]]]] <-
    cycle$scores[[columns[["s_score"]]]] - cycle$scores[[columns[["g2m_score"]]]]
  cycle$summary$score_distributions <- stats::setNames(lapply(
    columns[c("s_score", "g2m_score", "difference")], function(column)
      scAgentKit:::.sc_run_qc_distribution(cycle$scores[[column]])),
    c("s_score", "g2m_score", "difference"))
  cycle$scores_hash <- scAgentKit:::.sc_run_hash(cycle$scores)
  cycle$evidence_hash <- scAgentKit:::.sc_run_cycle_hash(cycle)
  e <- f$evidence; e$private$cycle_record <- cycle; e$summary$cycle_diagnostics <- cycle$summary
  e <- doublet_schema_rehash(e)
  p$doublet$method <- "keep"
  expect_true(scAgentKit:::.sc_run_strategy_validate(p, e)$executable)
  p$doublet$method <- "remove_predicted"
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "zero or unavailable variance|rank deficient")
})

test_that("doublet choice rejects unsupported code fields arbitrary IDs scores and methods", {
  e <- doublet_schema_fixture()$evidence
  invalid <- list(NULL, list(), "remove_predicted", list(method = "keep"),
    list(method = "keep", reason = ""), list(method = "keep", reason = " "),
    list(method = 1, reason = "typed"), list(method = c("keep", "remove_predicted"), reason = "typed"),
    list(method = "keep", reason = list("text")), list(method = "keep", reason = NA_character_),
    list(method = "remove_all", reason = "unsupported"),
    list(method = "score_cutoff", reason = "unsupported"),
    list(method = "keep", reason = "typed", threshold = .5),
    list(method = "keep", reason = "typed", cells = "DOUBLET-CELL-SECRET-001"),
    list(method = "keep", reason = "typed", code = "arbitrary()"))
  for (choice in invalid) {
    p <- doublet_schema_proposal(); p["doublet"] <- list(choice)
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "[Dd]oublet choice|doublet\\$|unsupported|nonempty")
  }
  p <- doublet_schema_proposal(); p$doublet <- list(method = "keep", method = "remove_predicted", reason = "duplicate")
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "exactly|supported")
  for (field in c("code", "doublet_cells", "subcluster")) {
    p <- doublet_schema_proposal(); p[[field]] <- list(method = "keep", reason = "unsupported")
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "supported named fields")
  }
})

test_that("processed doublet diagnostics support keep with the existing analysis foundation", {
  f <- doublet_schema_fixture(processed = TRUE)
  expect_true("harmony_execution" %in% f$evidence$summary$capabilities$unsupported)
  expect_false("harmony" %in% f$evidence$summary$capabilities$batch)
  v <- scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(TRUE), f$evidence)
  expect_true(v$applicability$processed_reuse)
  expect_true(v$applicability$doublet$processed_reuse)
  expect_null(v$qc_validated)
  expect_identical(v$selected_cells, colnames(f$seu))
  expect_identical(v$proposal$doublet$method, "keep")
  expect_identical(f$evidence$summary$capabilities$doublet, c("doublet_scoring", "keep"))
  expect_true("doublet_removal" %in% f$evidence$summary$capabilities$unsupported)
  expect_error(scAgentKit:::.sc_run_strategy_validate(
    doublet_schema_proposal(TRUE, "remove_predicted"), f$evidence), "reuses its analysis foundation")
})

test_that("unsupported diagnostics are explicit and allow only preservation of cells", {
  f <- doublet_schema_fixture(unsupported = TRUE)
  v <- scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), f$evidence)
  expect_identical(f$evidence$summary$capabilities$doublet, "keep")
  expect_true(all(c("doublet_scoring", "doublet_removal") %in% f$evidence$summary$capabilities$unsupported))
  expect_identical(v$applicability$doublet$scoring_status, "unsupported")
  expect_identical(v$selected_cells, colnames(f$seu))
  expect_error(scAgentKit:::.sc_run_strategy_validate(
    doublet_schema_proposal(method = "remove_predicted"), f$evidence), "unsupported|unavailable")
})

test_that("doublet selection changes required downstream hashes without invalidating pure QC", {
  f <- doublet_schema_fixture(); p <- doublet_schema_proposal()
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence); before <- v$dependency_hashes
  expect_identical(names(before),
    c("qc", "selection", "doublet", "preprocess", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$doublet <- list(method = "remove_predicted", reason = "Explicit removal.")
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  downstream <- c("selection", "doublet", "preprocess", "basis", "pcs", "batch", "neighbors", "clustering", "umap")
  expect_identical(doublet_schema_hash_changes(before, after), downstream)
  changed <- v$proposal; changed$doublet$reason <- "Revised explanation; same executable choice."
  expect_identical(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes, before)
  changed <- p; changed$analysis$npcs <- 9L
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(doublet_schema_hash_changes(before, after), c("basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$analysis$scale_factor <- 5000
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(doublet_schema_hash_changes(before, after), c("preprocess", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$qc$filters[[1L]]$min <- 2
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(doublet_schema_hash_changes(before, after), c("qc", "selection", "preprocess", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  expect_identical(after$doublet, before$doublet)
})

test_that("disabled doublet keeps prior schemas capabilities and hash topology unchanged", {
  f <- doublet_schema_fixture(); config <- f$config; config$doublet_diagnostics <- NULL
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc)
  expect_false("doublet_diagnostics" %in% names(e$summary))
  expect_false("doublet_record" %in% names(e$private))
  expect_false("doublet" %in% names(e$summary$capabilities))
  expect_true(all(c("doublet_scoring", "doublet_removal") %in% e$summary$capabilities$unsupported))
  v <- scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e)
  expect_false(any(c("doublet", "selected_cells") %in% names(v)))
  expect_false("doublet" %in% names(v$proposal))
  expect_false("doublet" %in% names(v$applicability))
  expect_identical(names(v$dependency_hashes), c("qc", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
  enabled <- scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), f$evidence)
  expect_identical(enabled$dependency_hashes$qc, v$dependency_hashes$qc)
  expect_error(scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(method = "keep"), e), "supported named fields")
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc,
    doublet_record = f$record), "explicitly enabled")
  cycle <- doublet_schema_fixture(cycle = TRUE)
  config <- cycle$config; config$doublet_diagnostics <- NULL
  e <- scAgentKit:::.sc_run_strategy_evidence(cycle$seu, config, cycle$qc, cycle$cycle_record)
  v <- scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e)
  expect_identical(names(v$dependency_hashes), c("qc", "preprocess", "cycle", "basis", "pcs", "batch", "neighbors", "clustering", "umap"))
})

test_that("verified doublet records cannot be detached altered or substituted under a fresh wrapper hash", {
  f <- doublet_schema_fixture()
  e <- f$evidence; e$private$doublet_record <- NULL; e <- doublet_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e), "intact local doublet evidence")
  e <- f$evidence; e$summary$doublet_diagnostics <- NULL; e <- doublet_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e), "intact local doublet evidence")
  e <- f$evidence; e$summary$doublet_diagnostics$status <- "unsupported"; e <- doublet_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e), "summary differs")
  e <- f$evidence; e$private$doublet_record$scores[[f$record$summary$columns[["score"]]]][1L] <- 99
  e <- doublet_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(doublet_schema_proposal(), e), "changed|inconsistent")
})
