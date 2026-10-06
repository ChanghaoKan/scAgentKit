# These captures and predictions are software fixtures, not biological truth.
# Real algorithm acceptance remains in the release-specific doublet tests.
prefilter_fixture <- function(n = 220L) {
  cells <- c("01", "1", "NA", "cell space", paste0("literal-", seq.int(5L, n)))
  features <- c("MT-CO1", paste0("Gene", seq_len(259L)))
  counts <- outer(seq_along(features), seq_len(n), function(row, column) 2 + (row + column) %% 4)
  dimnames(counts) <- list(features, cells)
  counts[, 1:4] <- 0
  counts[1, 1:4] <- c(0, 1, 199, 200)
  object <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  object$capture <- factor(rep(c("cap B", "cap A"), length.out = n), levels = c("cap A", "cap B", "unused capture"))
  object$sample <- factor(rep(c("sample first", "sample second"), each = n / 2),
                          levels = c("sample second", "sample first", "unused sample"))
  object$qc_group <- rep(c("quality A", "quality B", "quality C"), length.out = n)
  object$donor <- rep(c("donor X", "donor Y"), length.out = n)
  object$prior_annotation <- factor(rep(c("old label", NA_character_), length.out = n), levels = c("old label", "unused"))
  context <- list(species = "human", columns = list(sample = "sample", capture = "capture", qc_group = "qc_group", donor = "donor"))
  doublet <- list(data_type = "scrna_droplet", input_source = "Synthetic complete called-cell fixture.",
    empty_droplets_removed = TRUE, full_called_cohort = TRUE, technology = "10x_chromium_standard",
    capture = list(method = "column", column = "capture", source = "Fixture explicitly assigns physical capture independently of sample."),
    rate = list(method = "10x_standard", source = "Declared standard-10x fixture assumption; no biological truth."),
    nfeatures = 200L, dims = 6L, artificial_doublets = 1500L)
  config <- list(context = context, assay = "RNA", counts_layer = "counts", doublet_diagnostics = doublet,
    prefilter = list(method = "min_counts", min_counts = 200L, source = "Explicit preapproved software prerequisite fixture.", preapproved = TRUE))
  list(object = object, config = config)
}

prefilter_mock_leaf <- function(counts, options, rate, seed) {
  ids <- colnames(counts); predicted <- seq_along(ids) %% 11L == 1L
  list(scores = data.frame(cell_id = ids, score = ifelse(predicted, .8, .05),
      class = ifelse(predicted, "doublet", "singlet"), stringsAsFactors = FALSE, row.names = ids),
    threshold = .5, warnings = character(), messages = "Deterministic software fixture; no classifier executed.",
    classifier_audit = list(train_attempts = 3L, train_successes = 3L, predict_attempts = 3L,
      predict_successes = 3L, training_errors = character(), prediction_errors = character(), test_only_mock = TRUE),
    adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
}

test_that("minimal prefiltering is explicit, bounded, inclusive, and requires deletion preapproval", {
  parse <- scAgentKit:::.sc_run_prefilter_options
  none <- parse(NULL)
  expect_identical(none, parse(FALSE))
  expect_identical(none$method, "none"); expect_false(none$preapproved)
  expect_identical(parse(none), none)
  expect_error(parse(TRUE), "supported named fields")
  expect_error(parse(list(method = "qc")), "none or min_counts")
  expect_error(parse(list(method = "none", min_counts = 1)), "cannot supply")
  expect_error(parse(list(method = "none", preapproved = TRUE)), "no deletion")
  minimum <- list(method = "min_counts", min_counts = 200, source = "Explicit fixture.", preapproved = TRUE)
  expect_identical(parse(minimum)$min_counts, 200L)
  expect_identical(parse(parse(minimum)), parse(minimum))
  for (invalid in list(0, 201, 1.5, NA_real_, Inf, "200", c(1, 2))) {
    bad <- minimum; bad$min_counts <- invalid
    expect_error(parse(bad), "min_counts")
  }
  for (invalid in list(FALSE, NULL, 1, "TRUE")) {
    bad <- minimum; bad$preapproved <- invalid
    expect_error(parse(bad), "preapproved|supported named fields")
  }
  bad <- minimum; bad$source <- " "
  expect_error(parse(bad), "nonempty provenance")
  bad <- minimum; bad$code <- "system('arbitrary')"
  expect_error(parse(bad), "supported named fields")
})

test_that("prefilter evidence keeps complete sparse source identity and independent known group scopes", {
  f <- prefilter_fixture(); before <- serialize(f$object, NULL, version = 2L)
  record <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  expect_silent(scAgentKit:::.sc_run_prefilter_verify(record))
  expect_identical(serialize(f$object, NULL, version = 2L), before)
  expect_identical(record$cell_ids, colnames(f$object))
  expect_identical(record$metrics$cell_id, colnames(f$object))
  expect_identical(record$excluded_cells, colnames(f$object)[1:3])
  expect_true(colnames(f$object)[4] %in% record$keep_cells)
  expect_identical(record$summary$original_cells, 220L)
  expect_identical(record$summary$pre_score_cells, 217L)
  expect_identical(record$summary$excluded_cells, 3L)
  expect_identical(record$context_hash, scAgentKit:::.sc_run_hash(f$config$context))
  expect_identical(names(record$summary$scopes), c("sample", "capture", "qc_group"))
  expect_identical(names(record$summary$per_capture), c("cap B", "cap A"))
  expect_identical(record$summary$per_capture[["cap B"]]$original_cells, 110L)
  expect_identical(record$summary$per_capture[["cap B"]]$pre_score_cells, 108L)
  expect_identical(record$summary$per_capture[["cap A"]]$pre_score_cells, 109L)
  expect_identical(record$summary$per_sample[["sample first"]]$excluded_cells, 3L)
  expect_identical(record$summary$per_sample[["sample second"]]$excluded_cells, 0L)
  expect_false("donor" %in% names(record$metrics))
  counts <- scAgentKit:::.sc_project_layer(f$object, "RNA", "counts", raw_counts = TRUE)
  expect_true(inherits(counts, "sparseMatrix"))
  expect_identical(record$counts_hash, scAgentKit:::.sc_project_sparse_hash(counts))
  expect_identical(record$count_cell_hashes, scAgentKit:::.sc_run_cycle_cell_counts(counts, colnames(f$object)))
  f$config$prefilter <- NULL
  none <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  expect_identical(none$keep_cells, colnames(f$object))
  expect_identical(none$excluded_cells, character())
  expect_identical(none$counts_hash, record$counts_hash)
  bad <- record; bad$keep_cells <- rev(bad$keep_cells)
  expect_error(scAgentKit:::.sc_run_prefilter_verify(bad), "changed")
  bad$evidence_hash <- scAgentKit:::.sc_run_prefilter_hash(bad)
  expect_error(scAgentKit:::.sc_run_prefilter_verify(bad), "exact inclusive rule")
  bad <- record; bad$metrics$nCount[4] <- NA_real_
  bad$metrics_hash <- scAgentKit:::.sc_run_hash(bad$metrics); bad$evidence_hash <- scAgentKit:::.sc_run_prefilter_hash(bad)
  expect_error(scAgentKit:::.sc_run_prefilter_verify(bad), "identity, metrics")
  bad <- record; bad$cell_ids[2] <- bad$cell_ids[1]
  bad$evidence_hash <- scAgentKit:::.sc_run_prefilter_hash(bad)
  expect_error(scAgentKit:::.sc_run_prefilter_verify(bad), "unique, literal")
  bad <- record; bad$context$notes <- "Changed context after evidence generation."
  bad$evidence_hash <- scAgentKit:::.sc_run_prefilter_hash(bad)
  expect_error(scAgentKit:::.sc_run_prefilter_verify(bad), "identity, metrics")
})

test_that("empty pre-score groups are known zero and single capture is only explicitly declared", {
  f <- prefilter_fixture()
  counts <- scAgentKit:::.sc_project_layer(f$object, "RNA", "counts", raw_counts = TRUE)
  cells <- colnames(f$object)
  counts[, cells[f$object$sample == "sample first"]] <- 0
  changed <- Seurat::CreateSeuratObject(counts = counts[, cells, drop = FALSE], min.cells = 0, min.features = 0,
    meta.data = f$object[[]][, c("sample", "capture", "qc_group", "donor"), drop = FALSE])
  record <- scAgentKit:::.sc_run_prefilter_evidence(changed, f$config)
  expect_identical(record$summary$per_sample[["sample first"]]$pre_score_cells, 0L)
  expect_true(record$summary$per_sample[["sample first"]]$measured)
  expect_identical(record$summary$per_sample[["sample first"]]$retained_fraction, 0)
  expect_identical(record$summary$per_sample[["sample second"]]$pre_score_cells, 110L)
  f$config$context$columns$capture <- NULL
  f$config$doublet_diagnostics$capture <- list(method = "single", id = "one physical loading unit", source = "Explicit single-capture fixture.")
  single <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  expect_identical(names(single$summary$per_capture), "one physical loading unit")
  expect_identical(single$summary$per_capture[[1]]$original_cells, 220L)
  f$config$doublet_diagnostics <- NULL
  no_capture <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  expect_null(no_capture$summary$per_capture)
  expect_false("capture" %in% names(no_capture$metrics))
})

test_that("doublet scoring uses exact pre-score captures while standard rates retain original full-called size", {
  f <- prefilter_fixture(); original <- serialize(f$object, NULL, version = 2L)
  prefilter <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  calls <- list()
  local_mocked_bindings(
    .sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      calls[[length(calls) + 1L]] <<- list(cells = colnames(counts), features = rownames(counts), rate = rate, seed = seed)
      prefilter_mock_leaf(counts, options, rate, seed)
    }, .package = "scAgentKit")
  record <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config, prefilter)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
  expect_identical(serialize(f$object, NULL, version = 2L), original)
  expect_identical(record$cell_ids, colnames(f$object))
  expect_identical(record$counts_hash, prefilter$counts_hash)
  expect_identical(record$prefilter_hash, prefilter$evidence_hash)
  expect_identical(record$scored_cell_ids, prefilter$keep_cells)
  expect_identical(length(calls), 2L)
  for (index in seq_along(calls)) {
    capture <- names(record$execution)[index]
    expected <- prefilter$keep_cells[prefilter$keep_cells %in% names(record$capture_map)[record$capture_map == capture]]
    expect_identical(calls[[index]]$cells, expected[order(enc2utf8(expected), method = "radix")])
    expect_identical(calls[[index]]$seed, scAgentKit:::.sc_run_doublet_seed(999L, capture))
    expect_equal(calls[[index]]$rate, .008 * 110 / 1000)
    stat <- record$summary$capture_stats[[capture]]
    expect_identical(stat$rate_provenance$original_called_cells, 110L)
    expect_identical(stat$rate_provenance$pre_score_cells, length(expected))
    expect_identical(stat$rate_provenance$reference, "original_full_called_capture")
    expect_false(stat$rate_provenance$rate_reestimated_after_prefilter)
    expect_identical(stat$unknown_cells, 110L - length(expected))
  }
  columns <- record$summary$columns
  expect_true(all(is.na(record$scores[prefilter$excluded_cells, columns[["score"]]])))
  expect_true(all(record$scores[prefilter$excluded_cells, columns[["class"]]] == "Unknown"))
  expect_false(any(prefilter$excluded_cells %in% record$predicted_cells))
  expect_identical(record$summary$cohort$scored_cells, 217L)
  expect_identical(record$summary$cohort$unknown_cells, 3L)
  keep <- scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Explicit fixture keep."), record, prefilter$keep_cells)
  expect_identical(keep$keep_cells, prefilter$keep_cells)
  expect_identical(keep$impact$prefilter_excluded_cells, 3L)
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Bad restoration fixture."), record, record$cell_ids), "cannot restore")
  bad <- record; bad$summary$capture_stats[[1]]$rate_provenance$original_called_cells <- 108L
  bad$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(bad)
  expect_error(scAgentKit:::.sc_run_doublet_verify(bad), "rate provenance")
  bad <- record; bad$scores[prefilter$excluded_cells[1], columns[["class"]]] <- "singlet"
  bad$scores_hash <- scAgentKit:::.sc_run_hash(bad$scores); bad$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(bad)
  expect_error(scAgentKit:::.sc_run_doublet_verify(bad), "Unknown/missing")
  counts <- scAgentKit:::.sc_project_layer(f$object, "RNA", "counts", raw_counts = TRUE)
  reordered_ids <- rev(colnames(f$object))
  reordered <- Seurat::CreateSeuratObject(counts = counts[rev(rownames(counts)), reordered_ids, drop = FALSE],
    min.cells = 0, min.features = 0, meta.data = f$object[[]][reordered_ids, , drop = FALSE])
  reordered_prefilter <- scAgentKit:::.sc_run_prefilter_evidence(reordered, f$config)
  reversed <- scAgentKit:::.sc_run_doublet_evidence(reordered, f$config, reordered_prefilter)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(reversed))
  expect_identical(reversed$counts_hash, record$counts_hash)
  expect_identical(reversed$scores[record$cell_ids, , drop = FALSE], record$scores)
  for (capture in names(record$execution)) {
    expect_identical(reversed$execution[[capture]]$seed, record$execution[[capture]]$seed)
    expect_identical(reversed$execution[[capture]]$canonical_cell_hash, record$execution[[capture]]$canonical_cell_hash)
    expect_identical(reversed$execution[[capture]]$canonical_feature_hash, record$execution[[capture]]$canonical_feature_hash)
    expect_identical(reversed$execution[[capture]]$dbr, record$execution[[capture]]$dbr)
  }
  f$config$doublet_diagnostics$rate <- list(method = "manual", value = .08,
    source = "Manually sourced software-fixture assumption, unchanged by prefilter.", sd = .02)
  manual <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config, prefilter)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(manual))
  for (capture in names(manual$execution)) {
    expect_identical(manual$execution[[capture]]$dbr, .08)
    expect_identical(manual$summary$capture_stats[[capture]]$rate_provenance$reference, "explicit_manual_rate")
    expect_identical(manual$summary$capture_stats[[capture]]$rate_provenance$source,
                     f$config$doublet_diagnostics$rate$source)
  }
})

test_that("prefilter can make the full diagnostic unsupported without partial scoring or rate recomputation", {
  f <- prefilter_fixture()
  counts <- scAgentKit:::.sc_project_layer(f$object, "RNA", "counts", raw_counts = TRUE)
  cells <- colnames(f$object); cap <- cells[f$object$capture == "cap B"]
  counts[, cap[1:12]] <- 0
  changed <- Seurat::CreateSeuratObject(counts = counts[, cells, drop = FALSE], min.cells = 0, min.features = 0,
    meta.data = f$object[[]][, c("sample", "capture", "qc_group", "donor"), drop = FALSE])
  prefilter <- scAgentKit:::.sc_run_prefilter_evidence(changed, f$config)
  calls <- 0L
  local_mocked_bindings(.sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(...) { calls <<- calls + 1L; stop("Must not score a partial capture set") }, .package = "scAgentKit")
  record <- scAgentKit:::.sc_run_doublet_evidence(changed, f$config, prefilter)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
  expect_identical(calls, 0L); expect_identical(record$summary$status, "unsupported")
  expect_match(paste(record$summary$reasons, collapse = " "), "Fewer than 100 pre-score")
  expect_identical(record$scored_cell_ids, character())
  expect_identical(record$summary$cohort$scored_cells, 0L)
  expect_identical(record$summary$cohort$unknown_cells, 220L)
  expect_true(all(record$scores[[record$summary$columns[["class"]]]] == "Unknown"))
  expect_equal(record$summary$capture_stats[["cap B"]]$expected_rate, .008 * 110 / 1000)
  expect_silent(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Keep unsupported fixture."), record, prefilter$keep_cells))
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "remove_predicted", reason = "Unsupported removal."), record, prefilter$keep_cells), "unsupported")
})

test_that("omitted prefilter preserves legacy doublet records and prefilter mismatches fail before scoring", {
  f <- prefilter_fixture(); f$config$prefilter <- NULL
  # The legacy diagnostics software prerequisite remains unchanged: these
  # fixtures include low counts, so the legacy whole record is unsupported.
  local_mocked_bindings(.sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(...) stop("Unexpected scoring"), .package = "scAgentKit")
  implicit <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config)
  explicit <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config, NULL)
  expect_identical(implicit, explicit)
  expect_false(any(c("prefilter_record", "prefilter_hash", "scored_cell_ids") %in% names(implicit)))
  expect_null(implicit$summary$prefilter)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(implicit))
  f$config$prefilter <- list(method = "min_counts", min_counts = 200L, source = "Explicit fixture.", preapproved = TRUE)
  prefilter <- scAgentKit:::.sc_run_prefilter_evidence(f$object, f$config)
  bad <- prefilter; bad$counts_hash <- paste(rep("0", 64L), collapse = "")
  bad$evidence_hash <- scAgentKit:::.sc_run_prefilter_hash(bad)
  expect_error(scAgentKit:::.sc_run_doublet_evidence(f$object, f$config, bad), "same complete original raw counts")
  bad <- implicit; bad$prefilter_hash <- prefilter$evidence_hash
  bad$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(bad)
  expect_error(scAgentKit:::.sc_run_doublet_verify(bad), "requires its complete verified parent")
})
