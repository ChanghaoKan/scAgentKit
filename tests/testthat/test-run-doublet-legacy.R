# Source-identity and audit fixtures below do no scientific fitting. The final
# test is explicitly gated on the exact installed legacy pair and runs its
# genuine algorithm; modern hosts skip that test with a stated reason.
doublet_legacy_versions <- function() list(scDblFinder = "1.22.0", xgboost = "1.7.11.1")

doublet_legacy_good_audit <- function() list(train_attempts = 3L, train_successes = 3L,
  predict_attempts = 3L, predict_successes = 3L, training_errors = character(),
  prediction_errors = character())

doublet_legacy_fixture <- function() {
  counts <- scAgentKit:::.sc_run_cycle_seed(118L, function()
    matrix(stats::rpois(260L * 220L, 2), 260L, 220L,
      dimnames = list(paste0("LiteralGene", 1:260), c("01", "1", "NA", "cell space", paste0("cell", 5:220)))))
  counts[1:65, 1:110] <- counts[1:65, 1:110] + 10L
  counts[66:130, 111:220] <- counts[66:130, 111:220] + 12L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0L, min.features = 0L)
  object$prior_annotation <- factor(rep(c("prior A", NA_character_), 110L), levels = c("prior A", "unused"))
  context <- list(species = "human", columns = list())
  options <- list(data_type = "scrna_droplet", input_source = "Synthetic called-cell software fixture.",
    empty_droplets_removed = TRUE,
    capture = list(method = "single", id = "literal capture", source = "Declared synthetic physical loading unit."),
    rate = list(method = "manual", value = .08, source = "Software-control assumption, not measured doublet truth.", sd = .02),
    nfeatures = 200L, dims = 6L, artificial_doublets = 1500L)
  list(object = object, config = list(context = context,
    doublet_diagnostics = scAgentKit:::.sc_run_doublet_options(context, options), assay = "RNA", counts_layer = "counts"))
}

test_that("accepted doublet source identities are exact, data-only release mappings", {
  hashes <- scAgentKit:::.sc_run_doublet_classifier_source_hashes
  expect_identical(hashes(), list(
    public_algorithm = "0beee189415aadb8eb7b1c2bd2d9a87bf7f19b6986cc7b410dd70b3976758fb7",
    private_scoring = "c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f",
    private_training = "9587a78018158c55d5bb3660b87660d9440efadf7d8cbb0476f53bea0aad3307"))
  expect_identical(hashes("1.22.0"), list(
    public_algorithm = "9a4ad55e93b80d59f4ced150eacd6e5f2429bbe53567c24a5c3dc18194d441b2",
    private_scoring = "c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f",
    private_training = "d9be56120cc9b3e32a117366fbade307f13d06ad08e3e3150f38436fd3d3611a"))
  for (unsupported in list("1.22.1", "1.26.6", "1.30.0", NA_character_, character(), c("1.22.0", "1.26.7")))
    expect_error(hashes(unsupported), "supports verified.*only")
  # Source hashes bind formals/body expressions and ignore closure environment.
  first <- function(value = 1L) value + 1L
  second <- first; environment(second) <- new.env(parent = baseenv())
  expect_identical(scAgentKit:::.sc_run_doublet_classifier_function_hash(first),
                   scAgentKit:::.sc_run_doublet_classifier_function_hash(second))
  body(second) <- quote(value + 2L)
  expect_false(identical(scAgentKit:::.sc_run_doublet_classifier_function_hash(first),
                        scAgentKit:::.sc_run_doublet_classifier_function_hash(second)))
  second <- first; formals(second)$value <- 2L
  expect_false(identical(scAgentKit:::.sc_run_doublet_classifier_function_hash(first),
                        scAgentKit:::.sc_run_doublet_classifier_function_hash(second)))
})

test_that("legacy classifier acceptance rejects unreviewed xgboost pairs and altered identities", {
  verify <- scAgentKit:::.sc_run_doublet_classifier_versions_verify
  expect_identical(verify(doublet_legacy_versions()), scAgentKit:::.sc_run_doublet_classifier_source_hashes("1.22.0"))
  for (version in c("1.7.10.1", "1.7.11", "1.7.11.2", "2.0.0", "3.2.1.1"))
    expect_error(verify(list(scDblFinder = "1.22.0", xgboost = version)), "requires.*1.7.11.1")
  expect_error(verify(list(scDblFinder = "1.22.0")), "supported named fields")
  expect_error(verify(list(scDblFinder = "1.22.0", xgboost = NA_character_)), "version")
  expect_error(verify(list(scDblFinder = "1.22.0", xgboost = "1.7.11.1", extra = "unchecked")), "supported named fields")
  # Modern release retains the existing scDblFinder dependency contract.
  expect_identical(verify(list(scDblFinder = "1.26.7", xgboost = "3.2.1.1")),
                   scAgentKit:::.sc_run_doublet_classifier_source_hashes())
  expect_identical(verify(list(scDblFinder = "1.26.7", xgboost = "3.1")),
                   scAgentKit:::.sc_run_doublet_classifier_source_hashes())
  for (version in c("unknown", "", "1.7.11.1", "2.0.0", "3.0.9"))
    expect_error(verify(list(scDblFinder = "1.26.7", xgboost = version)), "version|>=3.1")
  audit <- doublet_legacy_good_audit(); hashes <- verify(doublet_legacy_versions())
  expect_silent(scAgentKit:::.sc_run_doublet_classifier_audit_verify(audit, hashes, 3L, doublet_legacy_versions()))
  expect_error(scAgentKit:::.sc_run_doublet_classifier_audit_verify(audit, hashes, 3L), "audit failed")
  for (field in names(hashes)) {
    changed <- hashes; changed[[field]] <- paste0("modified-", changed[[field]])
    expect_error(scAgentKit:::.sc_run_doublet_classifier_audit_verify(audit, changed, 3L, doublet_legacy_versions()), "audit failed")
  }
})

doublet_legacy_source_mock <- function(version) {
  # These short functions exercise adapter routing/auditing only. Their source
  # identities are explicitly mocked, never represented as official algorithms.
  namespace <- new.env(parent = baseenv())
  algorithm <- function(sce, ...) .scDblscore(sce, iter = 3L)
  scoring <- function(d, iter = 3L, scoreType = "xgb", BPPARAM = NULL) {
    result <- rep(.1, length(d))
    for (i in seq_len(iter)) tryCatch({
      fit <- .xgbtrain(d2 = list(data = d), ctype = "real", nthreads = 1L)
      result <- predict(fit, d)
    }, error = function(e) NULL)
    result
  }
  training <- function(d2, ctype, nthreads) list(data = d2$data)
  functions <- list(algorithm = algorithm, scoring = scoring, training = training)
  roles <- c(algorithm = "public_algorithm", scoring = "private_scoring", training = "private_training")
  for (name in names(functions)) {
    environment(functions[[name]]) <- namespace
    attr(functions[[name]], "test_only_identity") <- unname(roles[[name]])
  }
  assign("scDblFinder", functions$algorithm, namespace)
  assign(".scDblscore", functions$scoring, namespace)
  assign(".xgbtrain", functions$training, namespace)
  lockEnvironment(namespace, bindings = TRUE)
  list(functions = c(list(namespace = namespace), functions),
    hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes(version), namespace = namespace)
}

test_that("both exact release adapters privately audit every success and swallowed failure", {
  for (version in c("1.22.0", "1.26.7")) {
    mock <- doublet_legacy_source_mock(version)
    versions <- list(scDblFinder = version, xgboost = if (version == "1.22.0") "1.7.11.1" else "3.2.1.1")
    originals <- as.list(mock$namespace, all.names = TRUE)
    testthat::local_mocked_bindings(
      .sc_run_doublet_classifier_installed_versions = function() versions,
      .sc_run_doublet_classifier_functions = function() mock$functions,
      .sc_run_doublet_classifier_function_hash = function(value) mock$hashes[[attr(value, "test_only_identity")]],
      .sc_run_doublet_classifier_predict = function(object, ...) object$data / 10,
      .package = "scAgentKit")
    adapter <- scAgentKit:::.sc_run_doublet_classifier_adapter()
    expect_identical(adapter$algorithm(1:4), (1:4) / 10)
    expect_identical(adapter$versions, versions)
    expect_silent(scAgentKit:::.sc_run_doublet_classifier_audit_verify(as.list(adapter$audit), adapter$source_hashes, 3L, versions))
    expect_identical(as.list(mock$namespace, all.names = TRUE), originals)
    expect_false(identical(environment(adapter$algorithm), mock$namespace))
    for (name in names(originals)) expect_identical(environment(originals[[name]]), mock$namespace)
    testthat::local_mocked_bindings(.sc_run_doublet_classifier_train = function(training, ...) stop("Injected swallowed training failure."),
      .package = "scAgentKit")
    failed <- scAgentKit:::.sc_run_doublet_classifier_adapter()
    expect_identical(failed$algorithm(1:4), rep(.1, 4L))
    expect_identical(failed$audit$train_attempts, 3L)
    expect_identical(failed$audit$train_successes, 0L)
    expect_error(scAgentKit:::.sc_run_doublet_classifier_audit_verify(as.list(failed$audit), failed$source_hashes, 3L, versions),
                 "audit failed.*swallowed training failure")
    testthat::local_mocked_bindings(.sc_run_doublet_classifier_train = function(training, ...) training(...),
      .sc_run_doublet_classifier_predict = function(object, ...) stop("Injected swallowed prediction failure."), .package = "scAgentKit")
    failed <- scAgentKit:::.sc_run_doublet_classifier_adapter()
    expect_identical(failed$algorithm(1:4), rep(.1, 4L))
    expect_identical(failed$audit$train_successes, 3L)
    expect_identical(failed$audit$predict_attempts, 3L)
    expect_identical(failed$audit$predict_successes, 0L)
    expect_error(scAgentKit:::.sc_run_doublet_classifier_audit_verify(as.list(failed$audit), failed$source_hashes, 3L, versions),
                 "audit failed.*swallowed prediction failure")
    expect_identical(as.list(mock$namespace, all.names = TRUE), originals)
  }
})

test_that("adapter rejects unsupported versions and modified source before algorithm execution", {
  function_reads <- 0L; fits <- 0L
  testthat::local_mocked_bindings(
    .sc_run_doublet_classifier_installed_versions = function() list(scDblFinder = "1.22.1", xgboost = "1.7.11.1"),
    .sc_run_doublet_classifier_functions = function() { function_reads <<- function_reads + 1L; stop("Must not read unaudited functions.") },
    .sc_run_doublet_classifier_train = function(...) { fits <<- fits + 1L; stop("Must not fit an unaudited classifier.") }, .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_classifier_adapter(), "supports verified.*only")
  expect_identical(function_reads, 0L); expect_identical(fits, 0L)
  testthat::local_mocked_bindings(.sc_run_doublet_classifier_installed_versions = function()
    list(scDblFinder = "1.22.0", xgboost = "3.2.1.1"), .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_classifier_adapter(), "requires.*1.7.11.1")
  expect_identical(function_reads, 0L)
  mock <- doublet_legacy_source_mock("1.22.0")
  testthat::local_mocked_bindings(.sc_run_doublet_classifier_installed_versions = doublet_legacy_versions,
    .sc_run_doublet_classifier_functions = function() mock$functions,
    .sc_run_doublet_classifier_function_hash = function(value) {
      name <- attr(value, "test_only_identity")
      if (name == "private_training") "changed-source" else mock$hashes[[name]]
    }, .package = "scAgentKit")
  expect_error(scAgentKit:::.sc_run_doublet_classifier_adapter(), "function-body/formal hashes differ")
  expect_identical(fits, 0L)
})

test_that("saved legacy provenance verifies without installed dependencies and rejects cross-version evidence", {
  fixture <- doublet_legacy_fixture(); original <- serialize(fixture$object, NULL, version = 2L)
  versions <- doublet_legacy_versions()
  testthat::local_mocked_bindings(.sc_run_doublet_dependencies = function() invisible(TRUE),
    .sc_run_doublet_versions = function() versions,
    .sc_run_doublet_classifier_installed_versions = function() stop("Saved-record verification must not inspect installed packages."),
    .sc_run_doublet_detect_one = function(counts, options, rate, seed) {
      ids <- colnames(counts)
      list(scores = data.frame(cell_id = ids, score = rep(.1, length(ids)), class = rep("singlet", length(ids)), row.names = ids),
        threshold = .5, warnings = character(), messages = "Test-only predicted scores; no algorithm executed.",
        classifier_audit = doublet_legacy_good_audit(),
        adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes("1.22.0"), adapter_versions = versions)
    }, .package = "scAgentKit")
  record <- scAgentKit:::.sc_run_doublet_evidence(fixture$object, fixture$config)
  expect_identical(record$summary$scoring$adapter_versions, versions)
  expect_identical(record$execution[[1L]]$adapter_versions, versions)
  expect_identical(serialize(fixture$object, NULL, version = 2L), original)
  saved <- tempfile(fileext = ".rds"); on.exit(unlink(saved), add = TRUE)
  saveRDS(record, saved)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(readRDS(saved)))
  historical <- record
  historical$summary$scoring$adapter_versions <- NULL
  historical$summary$scoring$versions <- list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
    fixture_scope = "Authored historical modern record metadata; no classifier execution.")
  historical$summary$scoring$adapter_source_hashes <- scAgentKit:::.sc_run_doublet_classifier_source_hashes()
  for (capture in names(historical$execution)) {
    historical$execution[[capture]]$adapter_versions <- NULL
    historical$execution[[capture]]$adapter_source_hashes <- scAgentKit:::.sc_run_doublet_classifier_source_hashes()
  }
  historical$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(historical)
  saveRDS(historical, saved)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(readRDS(saved)))
  for (change in c("unknown_release", "legacy_release", "missing_release", "missing_versions", "unknown_backend", "missing_backend", "older_backend")) {
    invalid <- historical
    if (change == "unknown_release") invalid$summary$scoring$versions$scDblFinder <- "fictional"
    if (change == "legacy_release") invalid$summary$scoring$versions$scDblFinder <- "1.22.0"
    if (change == "missing_release") invalid$summary$scoring$versions$scDblFinder <- NULL
    if (change == "missing_versions") invalid$summary$scoring$versions <- NULL
    if (change == "unknown_backend") invalid$summary$scoring$versions$xgboost <- "unknown"
    if (change == "missing_backend") invalid$summary$scoring$versions$xgboost <- NULL
    if (change == "older_backend") invalid$summary$scoring$versions$xgboost <- "1.7.11.1"
    invalid$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(invalid)
    expect_error(scAgentKit:::.sc_run_doublet_verify(invalid), "provenance|backend|supported named fields")
  }
  for (change in c("pair", "hash", "missing", "summary", "capture")) {
    invalid <- record
    if (change == "pair") invalid$summary$scoring$adapter_versions$xgboost <- "3.2.1.1"
    if (change == "hash") invalid$summary$scoring$adapter_source_hashes$public_algorithm <- "modified"
    if (change == "missing") invalid$summary$scoring$adapter_versions <- NULL
    if (change == "summary") invalid$summary$scoring$versions$scDblFinder <- "1.26.7"
    if (change == "capture") invalid$execution[[1L]]$adapter_versions$scDblFinder <- "1.26.7"
    invalid$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(invalid)
    expect_error(scAgentKit:::.sc_run_doublet_verify(invalid), "requires|provenance|summaries")
  }
})

test_that("unsupported local diagnostics persist unavailable backends without classifier execution", {
  fixture <- doublet_legacy_fixture(); fixture$object <- fixture$object[, seq_len(99L)]
  dependencies <- 0L; detections <- 0L
  testthat::local_mocked_bindings(.sc_run_doublet_dependencies = function() {
    dependencies <<- dependencies + 1L; stop("Optional classifier dependencies are unavailable.")
  }, .sc_run_doublet_versions = function() list(scDblFinder = NA_character_, xgboost = NA_character_,
    fixture_scope = "Authored unavailable-package snapshot; no package or classifier execution."),
  .sc_run_doublet_detect_one = function(...) {
    detections <<- detections + 1L; stop("No classifier may execute for unsupported local diagnostics.")
  }, .sc_run_doublet_classifier_installed_versions = function() stop("Offline review must not inspect installed packages."),
  .package = "scAgentKit")
  record <- scAgentKit:::.sc_run_doublet_evidence(fixture$object, fixture$config)
  expect_identical(dependencies, 0L); expect_identical(detections, 0L)
  expect_identical(record$summary$status, "unsupported")
  expect_identical(record$summary$scoring$adapter_status, "not_executed")
  expect_null(record$summary$scoring$adapter_versions)
  expect_null(record$summary$scoring$adapter_source_hashes)
  expect_match(record$summary$scoring$adapter_unavailable_reason, "version|supports verified")
  expect_true(all(record$scores$sc_doublet_class == "Unknown"))
  expect_true(all(is.na(record$scores$sc_doublet_score)))
  expect_true(all(lengths(record$execution) == 0L))
  saved <- tempfile(fileext = ".rds"); on.exit(unlink(saved), add = TRUE)
  saveRDS(record, saved)
  expect_silent(scAgentKit:::.sc_run_doublet_verify(readRDS(saved)))
  for (change in c("available", "scores", "execution", "source", "missing_reason")) {
    invalid <- record
    if (change == "available") invalid$summary$status <- "available"
    if (change == "scores") invalid$scores$sc_doublet_score <- rep(.1, nrow(invalid$scores))
    if (change == "execution") invalid$execution[[1L]] <- list(classifier_audit = doublet_legacy_good_audit())
    if (change == "source") invalid$summary$scoring$adapter_source_hashes <- scAgentKit:::.sc_run_doublet_classifier_source_hashes()
    if (change == "missing_reason") invalid$summary$scoring$adapter_unavailable_reason <- NULL
    if (change == "scores") invalid$scores_hash <- scAgentKit:::.sc_run_hash(invalid$scores)
    invalid$evidence_hash <- scAgentKit:::.sc_run_doublet_hash(invalid)
    expect_error(scAgentKit:::.sc_run_doublet_verify(invalid), "provenance|Unknown|execution|source identities|unavailable reason")
  }
})

test_that("exact legacy pair produces genuine bounded algorithm evidence without namespace mutation", {
  skip_if_not_installed("scDblFinder")
  skip_if_not_installed("xgboost")
  skip_if(!identical(as.character(utils::packageVersion("scDblFinder")), "1.22.0") ||
          !identical(as.character(utils::packageVersion("xgboost")), "1.7.11.1"),
          "Genuine legacy algorithm acceptance requires installed scDblFinder 1.22.0 and xgboost 1.7.11.1.")
  fixture <- doublet_legacy_fixture(); original <- serialize(fixture$object, NULL, version = 2L)
  namespace <- asNamespace("scDblFinder"); functions <- c("scDblFinder", ".scDblscore", ".xgbtrain")
  identities <- stats::setNames(lapply(functions, function(name) {
    fn <- get(name, namespace, inherits = FALSE)
    list(environment = environment(fn), hash = scAgentKit:::.sc_run_doublet_classifier_function_hash(fn))
  }), functions)
  set.seed(725L); random <- .Random.seed
  record <- scAgentKit:::.sc_run_doublet_evidence(fixture$object, fixture$config)
  expect_identical(record$summary$status, "available")
  expect_silent(scAgentKit:::.sc_run_doublet_verify(record))
  expect_identical(record$summary$scoring$adapter_versions, doublet_legacy_versions())
  expect_identical(record$summary$scoring$adapter_source_hashes, scAgentKit:::.sc_run_doublet_classifier_source_hashes("1.22.0"))
  audit <- record$execution[[1L]]$classifier_audit; expected <- doublet_legacy_good_audit()
  expect_setequal(names(audit), names(expected))
  expect_identical(audit[names(expected)], expected)
  expect_identical(record$summary$cohort$removed_cells, 0L)
  expect_true(all(is.finite(record$scores$sc_doublet_score)))
  expect_true(all(record$scores$sc_doublet_class %in% c("singlet", "doublet")))
  expect_identical(record$cell_ids, colnames(fixture$object))
  expect_identical(serialize(fixture$object, NULL, version = 2L), original)
  expect_identical(.Random.seed, random)
  for (name in functions) {
    fn <- get(name, namespace, inherits = FALSE)
    expect_identical(environment(fn), identities[[name]]$environment)
    expect_identical(scAgentKit:::.sc_run_doublet_classifier_function_hash(fn), identities[[name]]$hash)
  }
})
