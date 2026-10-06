# The deterministic prediction records below are software fixtures, not
# biological doublet calls. The one explicitly labelled release test uses the
# actual algorithm; workflow tests otherwise mock only its fixed leaf adapter.
doublet_engine_fixture <- function(n = 220L, features = 260L) {
  cells <- c("01", "1", "NA", "cell space", paste0("literal", 5:n))
  genes <- paste0("LiteralGene", seq_len(features))
  counts <- scAgentKit:::.sc_run_cycle_seed(113L, function()
    matrix(stats::rpois(features * n, 2), nrow = features, ncol = n, dimnames = list(genes, cells)))
  block <- max(1L, floor(features / 4L))
  counts[seq_len(block), seq_len(floor(n / 2L))] <- counts[seq_len(block), seq_len(floor(n / 2L))] + 10L
  counts[block + seq_len(block), seq.int(floor(n / 2L) + 1L, n)] <- counts[block + seq_len(block), seq.int(floor(n / 2L) + 1L, n)] + 12L
  object <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(counts, sparse = TRUE),
                                      min.cells = 0L, min.features = 0L)
  object$capture <- factor(rep(c("01", "1"), length.out = n), levels = c("1", "01", "unused"))
  object$donor <- rep(c("donor A", "donor B"), each = ceiling(n / 2L), length.out = n)
  object$sample <- object$donor
  object$doublet_score <- seq_len(n) / n
  object$doublet_class <- factor(rep(c("old singlet", NA_character_), length.out = n),
                                  levels = c("old singlet", "unused doublet"))
  object$annotation <- factor(rep(c("prior A", NA_character_), length.out = n), levels = c("prior A", "unused B"))
  context <- list(species = "Homo sapiens", columns = list(capture = "capture", sample = "sample"))
  options <- list(data_type = "scrna_droplet", input_source = "Synthetic called-cell software fixture; no empty droplets.",
    empty_droplets_removed = TRUE, capture = list(method = "column", column = "capture",
      source = "Alternating physical loading-unit labels explicitly assigned by this software fixture."),
    rate = list(method = "manual", value = .08, source = "Declared software fixture assumption, not measured truth.", sd = .02),
    nfeatures = 200L, dims = 6L, artificial_doublets = 1500L)
  config <- list(context = context, doublet_diagnostics = scAgentKit:::.sc_run_doublet_options(context, options),
                  assay = "RNA", counts_layer = "counts")
  list(object = object, context = context, options = options, config = config)
}

doublet_engine_mock_detection <- function(counts, options, rate, seed) {
  ids <- colnames(counts); predicted <- seq_along(ids) %% 11L == 1L
  list(scores = data.frame(cell_id = ids, score = ifelse(predicted, .8, .05),
      class = ifelse(predicted, "doublet", "singlet"), stringsAsFactors = FALSE, row.names = ids),
    threshold = .5, warnings = character(), messages = "Test-only deterministic algorithm-prediction fixture; no classifier was executed.",
    classifier_audit = list(train_attempts = 3L, train_successes = 3L, predict_attempts = 3L,
      predict_successes = 3L, training_errors = character(), prediction_errors = character(), test_only_mock = TRUE),
    adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
}

doublet_engine_mock_reference <- function(fixture) {
  calls <- list()
  testthat::local_mocked_bindings(
    .sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      calls[[length(calls) + 1L]] <<- list(cells = colnames(counts), rate = rate, seed = seed)
      doublet_engine_mock_detection(counts, options, rate, seed)
    }, .package = "scAgentKit")
  record <- scAgentKit:::.sc_run_doublet_evidence(fixture$object, fixture$config)
  list(record = record, calls = calls)
}

test_that("doublet options require explicit species, capture, called-cell input, and rate provenance", {
  f <- doublet_engine_fixture()
  options <- scAgentKit:::.sc_run_doublet_options
  expect_null(options(list(), NULL)); expect_null(options(list(), FALSE))
  expect_error(options(list(), f$options), "species")
  expect_error(options(list(species = "rat"), f$options), "species|human|mouse")
  expect_error(options(f$context, TRUE), "supported named fields")
  expect_identical(options(f$context, f$config$doublet_diagnostics), f$config$doublet_diagnostics)
  expect_identical(f$config$doublet_diagnostics$seed, 999L)
  expect_identical(f$config$doublet_diagnostics$iter, 3L)
  expect_false(f$config$doublet_diagnostics$clusters)
  bad <- f$options; bad$empty_droplets_removed <- FALSE
  expect_error(options(f$context, bad), "empty_droplets_removed")
  bad <- f$options; bad$data_type <- "snrna_droplet"
  expect_error(options(f$context, bad), "Unsupported.*data type")
  bad <- f$options; bad$input_source <- " "
  expect_error(options(f$context, bad), "nonempty provenance")
  bad <- f$options; bad$capture$column <- "donor"
  expect_error(options(f$context, bad), "must match.*capture|never inferred")
  bad <- f$options; bad$capture <- list(method = "single", id = "library", source = "Explicit fixture.")
  expect_error(options(f$context, bad), "cannot be replaced")
  context <- list(species = "mouse", columns = list(sample = "sample"))
  single <- options(context, bad)
  expect_identical(single$capture$id, "library")
  expect_identical(single$species, "mouse")
  bad$capture$source <- NULL
  expect_error(options(context, bad), "supported named fields")
  bad <- f$options; bad$rate <- list(method = "manual", source = "Unknown rate.")
  expect_error(options(f$context, bad), "explicit value|unknown rate")
  for (invalid in list(0, .5, NA_real_, Inf, c(.1, .2), list(A = "code"))) {
    bad <- f$options; bad$rate$value <- invalid
    expect_error(options(f$context, bad), "rate|fraction|numeric")
  }
  bad <- f$options; bad$rate$method <- "auto"
  expect_error(options(f$context, bad), "manual|10x_standard")
  bad <- f$options; bad$rate <- list(method = "10x_standard", source = "Explicit standard platform.")
  expect_error(options(f$context, bad), "technology")
  bad$technology <- "10x_chromium_standard"
  expect_error(options(f$context, bad), "full_called_cohort")
  bad$full_called_cohort <- TRUE
  auto <- options(f$context, bad)
  expect_equal(auto$rate$sd, .02)
  bad$technology <- "10x_flex"
  expect_error(options(f$context, bad), "technology|Flex")
  bad <- f$options; bad$nfeatures <- 199L
  expect_error(options(f$context, bad), "invalid.*nfeatures")
  bad <- f$options; bad$dims <- 200L
  expect_error(options(f$context, bad), "invalid.*dims|below nfeatures")
  bad <- f$options; bad$iter <- 2L
  expect_error(options(f$context, bad), "iter=3")
  bad <- f$options; bad$clusters <- TRUE
  expect_error(options(f$context, bad), "clusters=FALSE")
  bad <- f$options; bad$processing <- function(x) x
  expect_error(options(f$context, bad), "supported named fields")
})

test_that("manual and standard-10x expected rates use each exact complete loading unit", {
  f <- doublet_engine_fixture()
  map <- scAgentKit:::.sc_run_doublet_captures(f$object, f$config$doublet_diagnostics, colnames(f$object))
  expect_identical(names(map), colnames(f$object))
  expect_identical(unname(map), as.character(f$object$capture))
  value <- f$options; value$rate$value <- list(`1` = .09, `01` = .07)
  settings <- scAgentKit:::.sc_run_doublet_options(f$context, value)
  rates <- scAgentKit:::.sc_run_doublet_resolve_rates(settings, map)
  expect_identical(rates, c(`01` = .07, `1` = .09))
  value$rate$value <- c(`01` = .08, donor = .09)
  settings <- scAgentKit:::.sc_run_doublet_options(f$context, value)
  expect_error(scAgentKit:::.sc_run_doublet_resolve_rates(settings, map), "cover every literal capture")
  value <- f$options; value$technology <- "10x_chromium_standard"
  value$full_called_cohort <- TRUE
  value$rate <- list(method = "10x_standard", source = "Explicit standard 10x loading-unit assumption.")
  settings <- scAgentKit:::.sc_run_doublet_options(f$context, value)
  expect_equal(scAgentKit:::.sc_run_doublet_resolve_rates(settings, map), c(`01` = .00088, `1` = .00088))
  map <- stats::setNames(rep("pbmc3k", 2700L), paste0("cell", 1:2700))
  expect_equal(unname(scAgentKit:::.sc_run_doublet_resolve_rates(settings, map)), .0216)
  value <- f$options; value$rate$value <- c(`01` = .01)
  expect_error(scAgentKit:::.sc_run_doublet_resolve_rates(scAgentKit:::.sc_run_doublet_options(f$context, value),
               scAgentKit:::.sc_run_doublet_captures(f$object, f$config$doublet_diagnostics, colnames(f$object))), "cover every")
})

test_that("fixed full-input prediction fixtures preserve sparse counts, old metadata, cell order, and capture seeds", {
  f <- doublet_engine_fixture()
  snapshot <- serialize(f$object, NULL, version = 2L)
  set.seed(137); before_seed <- .Random.seed
  built <- doublet_engine_mock_reference(f); record <- built$record
  expect_identical(.Random.seed, before_seed)
  expect_identical(serialize(f$object, NULL, version = 2L), snapshot)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
  expect_identical(record$summary$status, "available")
  expect_identical(record$summary$reference, "fixed_full_input")
  expect_false(record$summary$refit_after_qc)
  expect_identical(record$cell_ids, colnames(f$object))
  expect_identical(rownames(record$scores), colnames(f$object))
  expect_identical(length(built$calls), 2L)
  expect_identical(built$calls[[1]]$seed, scAgentKit:::.sc_run_doublet_seed(999L, "01"))
  expect_identical(built$calls[[2]]$seed, scAgentKit:::.sc_run_doublet_seed(999L, "1"))
  expect_identical(built$calls[[1]]$cells, sort(colnames(f$object)[as.character(f$object$capture) == "01"], method = "radix"))
  expect_equal(record$summary$capture_stats[["01"]]$predicted_doublets, 10L)
  expect_equal(record$summary$cohort$removed_cells, 0L)
  expect_false(any(c("scores", "cell_ids", "cell_id", "predicted_cells", "count_cell_hashes") %in% names(record$summary)))
  attached <- scAgentKit:::.sc_run_doublet_attach(f$object, record)
  expect_identical(attached[[]][, names(f$object[[]]), drop = FALSE], f$object[[]])
  expect_identical(SeuratObject::LayerData(attached, assay = "RNA", layer = "counts"),
                   SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts"))
  expect_true(inherits(SeuratObject::LayerData(attached, assay = "RNA", layer = "counts"), "sparseMatrix"))
  expect_identical(as.character(attached$sc_doublet_capture), as.character(f$object$capture))
  expect_error(scAgentKit:::.sc_run_doublet_attach(attached, record), "already exists|fresh")
})

test_that("literal-ID attachment rejects stale counts, capture assignments, scores, and features", {
  f <- doublet_engine_fixture(); record <- doublet_engine_mock_reference(f)$record
  ids <- colnames(f$object)[c(4, 2, 45:130)]
  retained <- f$object[, ids]
  attached <- scAgentKit:::.sc_run_doublet_attach(retained, record)
  expected <- record$scores[match(colnames(retained), record$cell_ids), unname(record$summary$columns), drop = FALSE]
  rownames(expected) <- colnames(retained)
  expect_identical(attached[[]][, unname(record$summary$columns), drop = FALSE], expected)
  expect_identical(attached[[]][, names(retained[[]]), drop = FALSE], retained[[]])
  changed <- retained
  values <- SeuratObject::LayerData(changed, assay = "RNA", layer = "counts", fast = FALSE)
  values[1, 1] <- values[1, 1] + 1L
  SeuratObject::LayerData(changed, assay = "RNA", layer = "counts") <- values
  expect_error(scAgentKit:::.sc_run_doublet_attach(changed, record), "raw counts.*changed")
  changed <- retained; changed$capture <- rep("other declared capture", ncol(changed))
  expect_error(scAgentKit:::.sc_run_doublet_attach(changed, record), "capture assignments changed")
  changed <- record; changed$scores[1, "sc_doublet_score"] <- .999
  expect_error(scAgentKit:::.sc_run_doublet_verify(changed), "evidence.*changed")
  changed <- record; changed$options$rate$source <- "new assumption"
  expect_error(scAgentKit:::.sc_run_doublet_verify(changed), "evidence.*changed")
  changed <- record; changed$predicted_cells <- rev(changed$predicted_cells)
  expect_error(scAgentKit:::.sc_run_doublet_verify(changed), "evidence.*changed")
  renamed <- Seurat::RenameCells(retained, new.names = paste0("unknown", seq_len(ncol(retained))))
  expect_error(scAgentKit:::.sc_run_doublet_attach(renamed, record), "absent.*reference")
})

test_that("capture and within-capture enumeration changes preserve literal prediction joins and seeds", {
  f <- doublet_engine_fixture(); first <- doublet_engine_mock_reference(f)
  reordered <- f
  cells <- rev(colnames(f$object))
  counts <- SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts", fast = FALSE)
  reordered$object <- Seurat::CreateSeuratObject(
    counts = counts[rev(rownames(counts)), cells, drop = FALSE],
    meta.data = f$object[[]][cells, , drop = FALSE], min.cells = 0L, min.features = 0L)
  second <- doublet_engine_mock_reference(reordered)
  columns <- unname(first$record$summary$columns)
  remapped <- second$record$scores[match(first$record$cell_ids, second$record$cell_ids), c("cell_id", columns), drop = FALSE]
  expect_identical(remapped, first$record$scores)
  for (capture in c("01", "1")) {
    expect_identical(first$record$execution[[capture]]$seed, second$record$execution[[capture]]$seed)
    expect_identical(first$record$execution[[capture]]$canonical_cell_hash, second$record$execution[[capture]]$canonical_cell_hash)
    expect_identical(first$record$execution[[capture]]$canonical_feature_hash, second$record$execution[[capture]]$canonical_feature_hash)
  }
  expect_identical(second$record$cell_ids, rev(first$record$cell_ids))
  expect_false(identical(first$record$cell_hash, second$record$cell_hash))
  expect_false(identical(first$record$evidence_hash, second$record$evidence_hash))
  expect_silent(scAgentKit:::.sc_run_doublet_verify(second$record))
})

test_that("unsupported captures return explicit full-input Unknown without fitting or silent filtering", {
  f <- doublet_engine_fixture()
  cases <- list(tiny = doublet_engine_fixture(n = 180L), too_few_features = doublet_engine_fixture(features = 199L))
  low <- f; values <- SeuratObject::LayerData(low$object, assay = "RNA", layer = "counts", fast = FALSE)
  values[, 1L] <- 0L; values[1L, 1L] <- 199L
  SeuratObject::LayerData(low$object, assay = "RNA", layer = "counts") <- values
  cases$low_reads <- low
  for (item in cases) {
    built <- doublet_engine_mock_reference(item); record <- built$record
    expect_identical(record$summary$status, "unsupported")
    expect_length(built$calls, 0L)
    expect_gt(length(record$summary$reasons), 0L)
    expect_true(all(is.na(record$scores$sc_doublet_score)))
    expect_true(all(record$scores$sc_doublet_class == "Unknown"))
    expect_length(record$predicted_cells, 0L)
    expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
    keep <- scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Declared unsupported reference."),
                                                        record, record$cell_ids)
    expect_identical(keep$keep_cells, record$cell_ids)
    expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "remove_predicted", reason = "Fixture."),
                   record, record$cell_ids), "unsupported|unavailable")
  }
  missing <- f; missing$object$capture[1L] <- NA
  expect_error(doublet_engine_mock_reference(missing), "nonmissing.*capture|nonmissing capture|Every source cell")
  numeric <- f; numeric$object$capture <- seq_len(ncol(numeric$object))
  expect_error(doublet_engine_mock_reference(numeric), "literal character or factor")
})

test_that("reviewed deletion uses exactly predicted QC intersections and aggregate per-capture impact", {
  f <- doublet_engine_fixture(); record <- doublet_engine_mock_reference(f)$record
  qc <- record$cell_ids[-c(1L, 2L, 3L, 4L)]
  keep <- scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Predictions remain diagnostic."), record, qc)
  remove <- scAgentKit:::.sc_run_doublet_validate_choice(list(method = "remove_predicted", reason = "Explicit reviewed subset."), record, qc)
  expect_identical(keep$keep_cells, qc)
  expect_length(keep$removed_cells, 0L)
  expect_identical(remove$removed_cells, qc[qc %in% record$predicted_cells])
  expect_identical(remove$keep_cells, qc[!qc %in% record$predicted_cells])
  expect_equal(remove$impact$predicted_qc_excluded, 2L)
  expect_equal(remove$impact$removed_cells, length(remove$removed_cells))
  expect_equal(remove$impact$per_capture[["01"]]$qc_retained, 108L)
  expect_equal(remove$impact$per_capture[["01"]]$removed_fraction_after_qc, 9 / 108)
  expect_equal(remove$impact$per_capture[["01"]]$retained_fraction_after_qc, 99 / 108)
  expect_false(remove$impact$predictions_are_truth)
  expect_false(remove$impact$scores_are_calibrated_probabilities)
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "automatic", reason = "Fixture."), record, qc), "explicitly")
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Fixture.", threshold = .5), record, qc), "supported named fields")
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = " "), record, qc), "nonempty provenance")
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Fixture."), record, c(qc, "newcell")), "absent.*reference")
})

test_that("classifier audit rejects swallowed training and prediction errors without namespace mutation", {
  skip_if_not_installed("scDblFinder", minimum_version = "1.26.7")
  skip_if_not_installed("SingleCellExperiment")
  f <- doublet_engine_fixture(); counts <- SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts", fast = FALSE)
  namespace <- asNamespace("scDblFinder")
  originals <- lapply(c("scDblFinder", ".scDblscore", ".xgbtrain"), function(name) get(name, envir = namespace, inherits = FALSE))
  names(originals) <- c("scDblFinder", ".scDblscore", ".xgbtrain")
  # This bridge reproduces the release's tryCatch fallback while exercising
  # the real lexical audit wrappers. It does no scientific model fitting.
  fallback_call <- function(adapter, sce, options, rate, seed) {
    scope <- environment(adapter$algorithm)
    train <- get(".xgbtrain", envir = scope, inherits = FALSE)
    predict <- get("predict", envir = scope, inherits = FALSE)
    for (i in seq_len(options$iter)) tryCatch({
      fit <- train(); predict(fit, matrix(0, nrow = ncol(sce), ncol = 2L))
    }, error = function(e) NULL)
    sce$scDblFinder.score <- rep(.1, ncol(sce))
    sce$scDblFinder.class <- rep("singlet", ncol(sce))
    S4Vectors::metadata(sce)$scDblFinder.threshold <- .5
    sce
  }
  testthat::local_mocked_bindings(.sc_run_doublet_classifier_call = fallback_call,
    .sc_run_doublet_classifier_train = function(training, ...) stop("Injected swallowed fit failure."),
    .sc_run_doublet_classifier_predict = function(object, ...) rep(.1, nrow(list(...)[[1L]])), .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_detect_one(counts, f$config$doublet_diagnostics, .08, 999L),
               "audit failed.*swallowed|swallowed fit failure")
  testthat::local_mocked_bindings(.sc_run_doublet_classifier_train = function(training, ...) structure(list(), class = "mock fit"),
    .sc_run_doublet_classifier_predict = function(object, ...) stop("Injected swallowed prediction failure."), .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_detect_one(counts, f$config$doublet_diagnostics, .08, 999L),
               "audit failed.*swallowed|swallowed prediction failure")
  for (name in names(originals)) expect_identical(get(name, envir = namespace, inherits = FALSE), originals[[name]])
})

test_that("model warnings, repaired identities, and missing classifier audits are recoverable failures", {
  f <- doublet_engine_fixture()
  testthat::local_mocked_bindings(.sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      value <- doublet_engine_mock_detection(counts, options, rate, seed)
      value$warnings <- "Injected dependency warning."
      value
    }, .package = "scAgentKit")
  before <- serialize(f$object, NULL, version = 2L)
  expect_error(scAgentKit:::.sc_run_doublet_evidence(f$object, f$config), "warnings|partial/fallback")
  expect_identical(serialize(f$object, NULL, version = 2L), before)
  testthat::local_mocked_bindings(.sc_run_doublet_detect_one = function(counts, options, rate, seed) {
    value <- doublet_engine_mock_detection(counts, options, rate, seed)
    value$scores$cell_id[1L] <- "repaired_cell"
    value
  }, .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_evidence(f$object, f$config), "exact capture cell IDs")
  testthat::local_mocked_bindings(.sc_run_doublet_detect_one = function(counts, options, rate, seed) {
    value <- doublet_engine_mock_detection(counts, options, rate, seed)
    value$classifier_audit$train_successes <- 2L
    value
  }, .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_evidence(f$object, f$config), "audit failed")
  testthat::local_mocked_bindings(.sc_run_doublet_dependencies = function()
    stop("Injected unavailable classifier dependency; explicitly install before retrying."), .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_evidence(f$object, f$config), "unavailable.*dependency")
  expect_identical(serialize(f$object, NULL, version = 2L), before)
})

test_that("doublet impact binds fixed cycle scope and preserves phase and numeric-score aggregates", {
  f <- doublet_engine_fixture(); record <- doublet_engine_mock_reference(f)$record
  gene_set <- sc_cycle_gene_set("human", paste0("LiteralGene", 1:10), paste0("LiteralGene", 11:20),
                                source = "Literal synthetic cycle software fixture.", version = "fixture-v1")
  cycle_config <- f$config
  cycle_config$cycle_diagnostics <- scAgentKit:::.sc_run_cycle_options(f$context,
                                     list(gene_set = gene_set, nbin = 4L, ctrl = 2L))
  cycle <- scAgentKit:::.sc_run_cycle_evidence(f$object, cycle_config)
  qc <- record$cell_ids[-seq_len(12L)]
  choice <- scAgentKit:::.sc_run_doublet_validate_choice(list(method = "remove_predicted", reason = "Review exact intersection."),
                                                         record, qc, cycle_record = cycle)
  expect_identical(choice$impact$cycle$evidence_hash, cycle$evidence_hash)
  expect_equal(sum(unlist(choice$impact$cycle$phase_by_scope$post_qc)), length(qc))
  expect_equal(sum(unlist(choice$impact$cycle$phase_by_scope$proposed_removed)), length(choice$removed_cells))
  expect_equal(sum(unlist(choice$impact$cycle$phase_by_scope$retained)), length(choice$keep_cells))
  expect_equal(choice$impact$cycle$score_by_scope$post_qc$s_score$n, length(qc))
  mismatch <- cycle
  mismatch$counts_hash <- "changed raw counts"
  mismatch$evidence_hash <- scAgentKit:::.sc_run_cycle_hash(mismatch)
  expect_error(scAgentKit:::.sc_run_doublet_validate_choice(list(method = "keep", reason = "Fixture."), record, qc,
                    cycle_record = mismatch), "same exact full-input counts")
})

test_that("verified official release produces bounded real algorithm evidence on a small two-origin fixture", {
  skip_if_not_installed("scDblFinder", minimum_version = "1.26.7")
  skip_if_not_installed("SingleCellExperiment")
  f <- doublet_engine_fixture()
  # One declared physical capture containing two synthetic expression origins.
  f$context$columns$capture <- NULL
  f$options$capture <- list(method = "single", id = "actual release fixture",
                            source = "Explicit synthetic single physical loading unit.")
  f$config$context <- f$context
  f$config$doublet_diagnostics <- scAgentKit:::.sc_run_doublet_options(f$context, f$options)
  before <- serialize(f$object, NULL, version = 2L)
  namespace <- asNamespace("scDblFinder")
  functions <- c("scDblFinder", ".scDblscore", ".xgbtrain")
  original_environments <- stats::setNames(lapply(functions, function(name)
    environment(get(name, envir = namespace, inherits = FALSE))), functions)
  original_hashes <- stats::setNames(lapply(functions, function(name)
    scAgentKit:::.sc_run_doublet_classifier_function_hash(get(name, envir = namespace, inherits = FALSE))), functions)
  set.seed(1371); random <- .Random.seed
  record <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config)
  repeated <- scAgentKit:::.sc_run_doublet_evidence(f$object, f$config)
  expect_identical(record$summary$status, "available")
  expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
  expect_identical(serialize(f$object, NULL, version = 2L), before)
  expect_identical(.Random.seed, random)
  expect_identical(repeated$scores, record$scores)
  expect_identical(repeated$summary$capture_stats, record$summary$capture_stats)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(repeated))
  for (name in functions) {
    current <- get(name, envir = namespace, inherits = FALSE)
    expect_identical(environment(current), original_environments[[name]])
    expect_identical(scAgentKit:::.sc_run_doublet_classifier_function_hash(current), original_hashes[[name]])
  }
  audit <- record$execution[[1L]]$classifier_audit
  expect_identical(audit$train_successes, 3L)
  expect_identical(audit$predict_successes, 3L)
  expect_length(audit$training_errors, 0L)
  expect_length(audit$prediction_errors, 0L)
  expect_identical(repeated$execution[[1L]]$classifier_audit$train_successes, 3L)
  expect_identical(repeated$execution[[1L]]$classifier_audit$predict_successes, 3L)
  expect_true(all(is.finite(record$scores$sc_doublet_score)))
  expect_true(all(record$scores$sc_doublet_class %in% c("singlet", "doublet")))
  expect_true(is.finite(record$summary$capture_stats[[1L]]$threshold))
  expect_equal(record$summary$cohort$removed_cells, 0L)
})
