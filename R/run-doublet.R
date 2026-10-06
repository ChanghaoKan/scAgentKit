# Doublet diagnostics are a fixed, local full-input reference. Diagnostic
# predictions never delete cells; the coordinator owns the reviewed choice.

.sc_run_doublet_fields <- function(value, required, permitted = required, label) {
  if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
      any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
      length(setdiff(required, names(value))) || length(setdiff(names(value), permitted)))
    .sc_project_fail(paste0(label, " requires exactly the supported named fields."))
  invisible(TRUE)
}

.sc_run_doublet_text <- function(value, label) {
  .sc_project_string(value, label)
  if (!nzchar(trimws(value))) .sc_project_fail(paste0(label, " must contain nonempty provenance text."))
  unname(value)
}

.sc_run_doublet_rate_values <- function(value) {
  if (is.list(value)) {
    if (is.null(names(value)) || anyNA(names(value)) || any(!nzchar(names(value))) ||
        anyDuplicated(names(value)) || !length(value) ||
        any(!vapply(value, function(x) is.numeric(x) && length(x) == 1L, logical(1))))
      .sc_project_fail("Manual doublet rate values must be a numeric scalar or an explicitly named per-capture numeric map.")
    value <- unlist(value, use.names = TRUE)
  }
  if (!is.numeric(value) || !length(value) || anyNA(value) || any(!is.finite(value)) ||
      any(value <= 0 | value >= .5) ||
      (length(value) != 1L && is.null(names(value))) ||
      (!is.null(names(value)) && (anyNA(names(value)) || any(!nzchar(names(value))) || anyDuplicated(names(value)))))
    .sc_project_fail("Manual doublet rates must be finite fractions strictly between zero and .5; this conservative bound is software policy, not an inferred biological rate.")
  result <- as.numeric(value)
  if (!is.null(names(value))) names(result) <- names(value)
  result
}

.sc_run_doublet_options <- function(context, value) {
  if (is.null(value) || identical(value, FALSE)) return(NULL)
  if (!is.list(context)) .sc_project_fail("Doublet diagnostics require explicit context$species and capture provenance.")
  species <- .sc_run_species(context$species, allow_missing = FALSE)
  fields <- c("data_type", "technology", "input_source", "empty_droplets_removed", "full_called_cohort", "capture", "rate",
              "column_prefix", "seed", "nfeatures", "dims", "artificial_doublets", "iter", "clusters")
  canonical <- is.list(value) && identical(value$schema, "scagentkit.doublet-options.v1")
  if (canonical) {
    if (!identical(value$species, species)) .sc_project_fail("Doublet options species does not match context$species.")
    value$schema <- NULL; value$species <- NULL
  }
  .sc_run_doublet_fields(value, c("data_type", "input_source", "empty_droplets_removed", "capture", "rate"), fields,
                        "doublet_diagnostics")
  if (!identical(value$data_type, "scrna_droplet"))
    .sc_project_fail("Unsupported doublet data type: this version supports declared droplet scRNA-seq called-cell raw counts only; plate, nuclei-only, Flex, ATAC, and multiome are outside this contract.")
  value$input_source <- .sc_run_doublet_text(value$input_source, "doublet input_source")
  if (!identical(value$empty_droplets_removed, TRUE))
    .sc_project_fail("Doublet diagnostics require empty_droplets_removed=TRUE with the called-cell matrix provenance recorded in input_source; no empty-droplet removal is performed.")
  if (is.null(value$full_called_cohort)) value$full_called_cohort <- FALSE
  if (!identical(value$full_called_cohort, TRUE) && !identical(value$full_called_cohort, FALSE))
    .sc_project_fail("Doublet full_called_cohort must be an explicit logical declaration; no pre-QC cohort completeness is inferred.")
  capture <- value$capture
  .sc_run_doublet_fields(capture, c("method", "source"), c("method", "source", "column", "id"), "doublet capture")
  capture$source <- .sc_run_doublet_text(capture$source, "doublet capture source")
  context_column <- if (is.list(context$columns)) context$columns$capture else NULL
  if (identical(capture$method, "column")) {
    .sc_run_doublet_fields(capture, c("method", "source", "column"), label = "doublet column capture")
    capture$column <- .sc_run_doublet_text(capture$column, "doublet capture column")
    if (!is.character(context_column) || length(context_column) != 1L ||
        is.na(context_column) || !identical(capture$column, context_column))
      .sc_project_fail("The explicitly declared doublet capture column must match context$columns$capture; sample, donor, condition, and batch are never inferred as loading units.")
    capture <- capture[c("method", "column", "source")]
  } else if (identical(capture$method, "single")) {
    .sc_run_doublet_fields(capture, c("method", "source", "id"), label = "doublet single capture")
    capture$id <- .sc_run_doublet_text(capture$id, "doublet single capture id")
    if (!is.null(context_column))
      .sc_project_fail("A declared context capture column cannot be replaced by a single-capture assumption; use its literal loading-unit values.")
    capture <- capture[c("method", "id", "source")]
  } else .sc_project_fail("Doublet capture method must be column or an explicit single declaration with provenance; no capture is guessed.")
  value$capture <- capture
  rate <- value$rate
  .sc_run_doublet_fields(rate, c("method", "source"), c("method", "source", "value", "sd"), "doublet rate")
  rate$source <- .sc_run_doublet_text(rate$source, "doublet rate source")
  if (is.null(rate$sd)) rate$sd <- .02
  rate$sd <- .sc_run_strategy_runtime_number(rate$sd, "doublet rate sd", 0, .5)
  if (identical(rate$method, "manual")) {
    if (is.null(rate$value)) .sc_project_fail("Manual doublet rate requires an explicit value and source; an unknown rate is unsupported.")
    rate$value <- .sc_run_doublet_rate_values(rate$value)
    rate <- rate[c("method", "value", "source", "sd")]
  } else if (identical(rate$method, "10x_standard")) {
    if (!is.null(rate$value)) .sc_project_fail("The standard-10x rate cannot also supply a manual value.")
    if (!identical(value$technology, "10x_chromium_standard"))
      .sc_project_fail("Standard-10x rate estimation requires explicit technology='10x_chromium_standard'; no Flex, HT, other chemistry, or non-10x rate is inferred.")
    if (!identical(value$full_called_cohort, TRUE))
      .sc_project_fail("Standard-10x rate estimation requires full_called_cohort=TRUE declaring the complete called-cell loading unit before quality filtering. Prior heavily filtered or unknown-completeness inputs require a manually sourced external expected rate.")
    rate <- rate[c("method", "source", "sd")]
  } else .sc_project_fail("Doublet rate must explicitly use manual or documented 10x_standard estimation; automatic unknown-rate estimation is unsupported.")
  value$rate <- rate
  if (is.null(value$technology)) value$technology <- "declared_droplet_other"
  value$technology <- .sc_run_doublet_text(value$technology, "doublet technology")
  if (!value$technology %in% c("10x_chromium_standard", "declared_droplet_other"))
    .sc_project_fail("Unsupported doublet technology: declare standard Chromium or another supported droplet protocol with a manually sourced rate. HT and Flex are outside this increment.")
  defaults <- list(column_prefix = "sc_doublet", seed = 999L, nfeatures = 1000L, dims = 20L,
                   artificial_doublets = 1500L, iter = 3L, clusters = FALSE)
  for (field in names(defaults)) if (is.null(value[[field]])) value[[field]] <- defaults[[field]]
  value$column_prefix <- .sc_run_doublet_text(value$column_prefix, "doublet column_prefix")
  if (!grepl("^[A-Za-z][A-Za-z0-9_.]*$", value$column_prefix))
    .sc_project_fail("Doublet column_prefix must start with a letter and contain only letters, digits, underscores, and periods.")
  bounds <- list(seed = c(0, .Machine$integer.max), nfeatures = c(200, 10000),
                 dims = c(2, 100), artificial_doublets = c(500, 50000))
  for (field in names(bounds)) value[[field]] <- .sc_run_strategy_runtime_number(value[[field]],
      paste0("doublet ", field), bounds[[field]][1L], bounds[[field]][2L], integer = TRUE)
  if (value$dims >= value$nfeatures)
    .sc_project_fail("Doublet dims must be strictly below nfeatures; no parameter clipping is performed.")
  if (!is.numeric(value$iter) || length(value$iter) != 1L || is.na(value$iter) || value$iter != 3)
    .sc_project_fail("Doublet diagnostics currently support exactly iter=3; arbitrary iteration settings are unsupported.")
  value$iter <- 3L
  if (!identical(value$clusters, FALSE))
    .sc_project_fail("Doublet diagnostics require clusters=FALSE random artificial pairs; biological clusters are never imported automatically.")
  c(list(schema = "scagentkit.doublet-options.v1", species = species), value[fields])
}

.sc_run_doublet_columns <- function(prefix) {
  stats::setNames(paste0(prefix, c("_score", "_class", "_capture")), c("score", "class", "capture"))
}

.sc_run_doublet_dependencies <- function() {
  .sc_run_strategy_runtime_dependencies(c("SeuratObject", "Matrix", "digest", "scDblFinder",
    "SingleCellExperiment", "SummarizedExperiment", "S4Vectors", "BiocParallel", "xgboost"))
  invisible(TRUE)
}

.sc_run_doublet_versions <- function() {
  packages <- c("Seurat", "SeuratObject", "Matrix", "scDblFinder", "SingleCellExperiment",
                "SummarizedExperiment", "S4Vectors", "BiocParallel", "scater", "scran", "scuttle",
                "BiocNeighbors", "BiocSingular", "xgboost")
  stats::setNames(lapply(packages, function(package)
    tryCatch(as.character(utils::packageVersion(package)), error = function(e) NA_character_)), packages)
}

.sc_run_doublet_hash <- function(record) {
  record$evidence_hash <- NULL
  .sc_run_hash(record)
}

.sc_run_doublet_seed <- function(seed, capture) {
  hash <- .sc_run_hash(enc2utf8(unname(capture)))
  as.integer((as.double(seed) + strtoi(substr(hash, 1L, 7L), base = 16L)) %% .Machine$integer.max)
}

.sc_run_doublet_rng <- function(seed, operation) {
  .sc_run_cycle_seed(seed, function() {
    original_kind <- RNGkind()
    on.exit(do.call(RNGkind, as.list(original_kind)), add = TRUE)
    RNGkind("Mersenne-Twister", "Inversion", "Rejection")
    set.seed(seed)
    operation()
  })
}

.sc_run_doublet_captures <- function(seu, options, cells) {
  if (identical(options$capture$method, "single")) {
    values <- rep(options$capture$id, length(cells))
  } else {
    column <- options$capture$column
    metadata <- seu[[]]
    if (!column %in% names(metadata)) .sc_project_fail("Declared doublet capture column is absent from source metadata.")
    values <- metadata[cells, column]
    if (!is.character(values) && !is.factor(values))
      .sc_project_fail("Capture labels must be literal character or factor values; numeric donor or sample IDs are not converted into loading units.")
    values <- as.character(values)
    if (anyNA(values) || any(!nzchar(trimws(values))))
      .sc_project_fail("Every source cell needs a nonempty, nonmissing capture/loading-unit label; no capture is guessed.")
  }
  stats::setNames(unname(values), cells)
}

.sc_run_doublet_resolve_rates <- function(options, capture_map) {
  captures <- unique(unname(capture_map))
  sizes <- vapply(captures, function(capture) sum(capture_map == capture), integer(1))
  if (identical(options$rate$method, "manual")) {
    value <- options$rate$value
    if (is.null(names(value))) rates <- rep(value, length(captures)) else {
      if (!setequal(names(value), captures))
        .sc_project_fail("The explicit per-capture manual rate map must cover every literal capture exactly, with no missing or extra loading units.")
      rates <- unname(value[captures])
    }
  } else {
    # Rate policy is verified against the installed official release by the
    # coordinator's dependency acceptance. Explicitly resolve dbr per capture
    # before invoking scDblFinder so post-QC sizes never change the reference.
    rates <- .008 * as.numeric(sizes) / 1000
    if (any(rates <= 0 | rates >= .5))
      .sc_project_fail("Standard-10x rate estimation lies outside the declared software range (0,.5); provide a justified manual rate instead of clipping.")
  }
  stats::setNames(as.numeric(rates), captures)
}

.sc_run_doublet_classifier_train <- function(training, ...) training(...)
.sc_run_doublet_classifier_predict <- function(object, ...) stats::predict(object, ...)

.sc_run_doublet_classifier_function_hash <- function(value) {
  # Pin every formal and body expression using canonical source text. Raw
  # language-object serialization changes after the release constructs nested
  # closures, despite identical expressions; it is not a stable code identity.
  .sc_run_hash(list(formals = paste(deparse(formals(value), width.cutoff = 500L), collapse = "\n"),
                    body = paste(deparse(body(value), width.cutoff = 500L), collapse = "\n")))
}

.sc_run_doublet_classifier_source_hashes <- function(version = "1.26.7") {
  # Canonical formal/body expression-text hashes, verified against official
  # release sources. The default remains data-only for existing saved records
  # and authored test fixtures; it never inspects an optional installed package.
  releases <- list(
    `1.26.7` = list(public_algorithm = "0beee189415aadb8eb7b1c2bd2d9a87bf7f19b6986cc7b410dd70b3976758fb7",
       private_scoring = "c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f",
       private_training = "9587a78018158c55d5bb3660b87660d9440efadf7d8cbb0476f53bea0aad3307"),
    `1.22.0` = list(public_algorithm = "9a4ad55e93b80d59f4ced150eacd6e5f2429bbe53567c24a5c3dc18194d441b2",
       private_scoring = "c17836de1f003e867401677a95ddb148311577997c9fd08f9cecda5ba83b4c9f",
       private_training = "d9be56120cc9b3e32a117366fbade307f13d06ad08e3e3150f38436fd3d3611a"))
  if (!is.character(version) || length(version) != 1L || is.na(version) ||
      !version %in% names(releases))
    .sc_project_fail("Doublet classifier auditing supports verified scDblFinder 1.26.7 or 1.22.0 only; another version requires explicit adapter acceptance before retrying.")
  releases[[version]]
}

.sc_run_doublet_classifier_versions_verify <- function(versions) {
  .sc_run_doublet_fields(versions, c("scDblFinder", "xgboost"), label = "doublet adapter versions")
  for (name in names(versions)) .sc_project_string(versions[[name]], paste0("doublet adapter ", name, " version"))
  hashes <- .sc_run_doublet_classifier_source_hashes(versions$scDblFinder)
  # The audited legacy training function uses the pre-3.x matrix/label API.
  # Accept only the independently inspected legacy pair, never a broad minimum
  # version. Modern 1.26.7 retains its existing package dependency contract.
  if (identical(versions$scDblFinder, "1.22.0") && !identical(versions$xgboost, "1.7.11.1"))
    .sc_project_fail("Verified scDblFinder 1.22.0 requires the audited xgboost 1.7.11.1 pair; another xgboost version is unsupported and no fallback is accepted.")
  if (identical(versions$scDblFinder, "1.26.7")) {
    backend <- tryCatch(package_version(versions$xgboost), error = function(e) NULL)
    if (is.null(backend) || backend < package_version("3.1"))
      .sc_project_fail("Verified scDblFinder 1.26.7 requires a saved xgboost version satisfying its >=3.1 dependency contract; a missing, unknown, or older backend is unsupported.")
  }
  hashes
}

.sc_run_doublet_classifier_installed_versions <- function() {
  list(scDblFinder = as.character(utils::packageVersion("scDblFinder")),
       xgboost = as.character(utils::packageVersion("xgboost")))
}

.sc_run_doublet_classifier_provenance_verify <- function(versions, recorded_versions) {
  .sc_run_doublet_classifier_versions_verify(versions)
  if (!is.list(recorded_versions) ||
      !identical(versions$scDblFinder, recorded_versions$scDblFinder) ||
      !identical(versions$xgboost, recorded_versions$xgboost))
    .sc_project_fail("Doublet adapter provenance differs from the recorded dependency versions; no cross-version classifier evidence is accepted.")
  invisible(TRUE)
}

.sc_run_doublet_classifier_functions <- function() {
  namespace <- asNamespace("scDblFinder")
  list(namespace = namespace, algorithm = getExportedValue("scDblFinder", "scDblFinder"),
       scoring = get(".scDblscore", envir = namespace, inherits = FALSE),
       training = get(".xgbtrain", envir = namespace, inherits = FALSE))
}

.sc_run_doublet_classifier_audit_verify <- function(audit, hashes, iter, versions = NULL) {
  expected <- if (is.null(versions)) .sc_run_doublet_classifier_source_hashes() else
    .sc_run_doublet_classifier_versions_verify(versions)
  if (!is.list(audit) || !identical(hashes, expected) ||
      length(audit$training_errors) || length(audit$prediction_errors) ||
      !identical(audit$train_attempts, iter) || !identical(audit$train_successes, iter) ||
      !identical(audit$predict_attempts, iter) || !identical(audit$predict_successes, iter))
    .sc_project_fail(paste0("Doublet xgb classifier audit failed: every declared training and prediction iteration must succeed against the verified release; silently caught fallback scores are rejected. ",
      paste(c(audit$training_errors, audit$prediction_errors), collapse = " | ")))
  invisible(TRUE)
}

.sc_run_doublet_classifier_call <- function(adapter, sce, options, rate, seed) {
  adapter$algorithm(sce, clusters = FALSE, dbr = rate,
    dbr.sd = options$rate$sd, nfeatures = options$nfeatures, dims = options$dims,
    artificialDoublets = options$artificial_doublets, iter = options$iter,
    score = "xgb", threshold = TRUE,
    BPPARAM = BiocParallel::SerialParam(RNGseed = seed), verbose = FALSE)
}

.sc_run_doublet_classifier_adapter <- function() {
  # Both audited releases catch training/prediction errors and retain the
  # preceding heuristic score. Audit unchanged release function bodies in a
  # private lexical scope so that such a fallback cannot pass as xgb success.
  # No package binding, namespace, global option, or installed file is changed.
  versions <- .sc_run_doublet_classifier_installed_versions()
  expected <- .sc_run_doublet_classifier_versions_verify(versions)
  functions <- .sc_run_doublet_classifier_functions()
  namespace <- functions$namespace
  algorithm <- functions$algorithm; scoring <- functions$scoring; training <- functions$training
  if (!is.function(algorithm) || !is.function(scoring) || !is.function(training) ||
      !all(c("iter", "scoreType", "BPPARAM") %in% names(formals(scoring))) ||
      !all(c("d2", "ctype", "nthreads") %in% names(formals(training))))
    .sc_project_fail("Installed scDblFinder classifier structure differs from the accepted release; no unaudited fallback is supported.")
  source_hashes <- list(public_algorithm = .sc_run_doublet_classifier_function_hash(algorithm),
    private_scoring = .sc_run_doublet_classifier_function_hash(scoring),
    private_training = .sc_run_doublet_classifier_function_hash(training))
  if (!identical(source_hashes, expected))
    .sc_project_fail("Installed scDblFinder function-body/formal hashes differ from the verified official release; no unaudited classifier fallback is accepted.")
  audit <- new.env(parent = emptyenv())
  audit$train_attempts <- 0L; audit$train_successes <- 0L
  audit$predict_attempts <- 0L; audit$predict_successes <- 0L
  audit$training_errors <- character(); audit$prediction_errors <- character()
  wrapped_training <- function(...) {
    audit$train_attempts <- audit$train_attempts + 1L
    fit <- tryCatch(.sc_run_doublet_classifier_train(training, ...), error = function(e) {
      audit$training_errors <- c(audit$training_errors, conditionMessage(e)); stop(e)
    })
    audit$train_successes <- audit$train_successes + 1L
    fit
  }
  wrapped_predict <- function(object, ...) {
    audit$predict_attempts <- audit$predict_attempts + 1L
    prediction <- tryCatch(.sc_run_doublet_classifier_predict(object, ...), error = function(e) {
      audit$prediction_errors <- c(audit$prediction_errors, conditionMessage(e)); stop(e)
    })
    audit$predict_successes <- audit$predict_successes + 1L
    prediction
  }
  scope <- new.env(parent = namespace)
  assign(".xgbtrain", wrapped_training, envir = scope)
  assign("predict", wrapped_predict, envir = scope)
  environment(scoring) <- scope
  assign(".scDblscore", scoring, envir = scope)
  environment(algorithm) <- scope
  list(algorithm = algorithm, audit = audit, source_hashes = source_hashes, versions = versions)
}

.sc_run_doublet_detect_one <- function(counts, options, rate, seed) {
  # This fixed adapter is privately mockable by unit tests. No caller-supplied
  # function, code string, or arbitrary scDblFinder argument is accepted.
  warnings <- character(); messages <- character()
  adapter <- .sc_run_doublet_classifier_adapter()
  detected <- .sc_run_doublet_rng(seed, function() tryCatch(withCallingHandlers({
    sce <- SingleCellExperiment::SingleCellExperiment(assays = list(counts = counts))
    .sc_run_doublet_classifier_call(adapter, sce, options, rate, seed)
  }, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  }, message = function(m) {
    messages <<- c(messages, conditionMessage(m)); invokeRestart("muffleMessage")
  }), error = function(e) {
    .sc_project_fail(paste0("Doublet algorithm failed; saved input remains unchanged. Resolve the dependency or numerical error and explicitly retry: ", conditionMessage(e)))
  }))
  if (length(warnings) || any(grepl("error|failed|failure|fallback|unable|could not", messages, ignore.case = TRUE)))
    .sc_project_fail(paste0("Doublet algorithm emitted a warning or classifier-failure diagnostic; no scores were accepted and no fallback is permitted: ",
                           paste(unique(c(warnings, messages)), collapse = " | ")))
  audit <- as.list(adapter$audit)
  .sc_run_doublet_classifier_audit_verify(audit, adapter$source_hashes, options$iter, adapter$versions)
  metadata <- S4Vectors::metadata(detected)
  threshold <- metadata$scDblFinder.threshold
  if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold))
    .sc_project_fail("Doublet algorithm returned an unsupported threshold record; no fallback is permitted.")
  scores <- data.frame(cell_id = colnames(detected), score = detected$scDblFinder.score,
                       class = as.character(detected$scDblFinder.class), stringsAsFactors = FALSE,
                       row.names = colnames(detected))
  list(scores = scores, threshold = unname(threshold), warnings = warnings, messages = messages,
       classifier_audit = audit, adapter_source_hashes = adapter$source_hashes,
       adapter_versions = adapter$versions)
}

.sc_run_doublet_evidence <- function(seu, config, prefilter_record = NULL) {
  seu <- .sc_project_unwrap(seu)
  options <- .sc_run_doublet_options(config$context, config$doublet_diagnostics)
  if (is.null(options)) .sc_project_fail("Doublet evidence requires explicitly enabled doublet_diagnostics.")
  assay <- config$assay; counts_layer <- config$counts_layer
  .sc_project_string(assay, "doublet assay"); .sc_project_string(counts_layer, "doublet counts_layer")
  if (grepl("^(data|scale\\.data|normalized)(\\.|$)", counts_layer, ignore.case = TRUE))
    .sc_project_fail("Doublet diagnostics require genuine raw counts, not normalized or scaled data.")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  # .sc_project_layer returns canonical literal feature/cell order. Bind that
  # canonical matrix before arranging columns for original-source ID joins,
  # matching the QC/cycle/input evidence convention exactly.
  counts_hash <- .sc_project_sparse_hash(counts)
  cells <- colnames(seu); .sc_project_ids(cells, "Doublet source cell IDs")
  if (!setequal(colnames(counts), cells) || !identical(rownames(seu[[]]), cells))
    .sc_project_fail("Doublet counts and metadata must cover every literal source cell exactly.")
  counts <- counts[, cells, drop = FALSE]
  features <- rownames(counts); .sc_project_ids(features, "Doublet source feature IDs")
  columns <- .sc_run_doublet_columns(options$column_prefix)
  if (any(columns %in% names(seu[[]])))
    .sc_project_fail("Doublet output column already exists; choose a fresh column_prefix to preserve source metadata.")
  capture_map <- .sc_run_doublet_captures(seu, options, cells)
  score_cells <- cells
  if (!is.null(prefilter_record)) {
    .sc_run_prefilter_verify(prefilter_record)
    if (!identical(prefilter_record$context, config$context) ||
        !identical(prefilter_record$context_hash, .sc_run_hash(config$context)) ||
        !identical(prefilter_record$cell_ids, cells) || !identical(prefilter_record$feature_ids, features) ||
        !identical(prefilter_record$counts_hash, counts_hash) ||
        !identical(prefilter_record$count_cell_hashes, .sc_run_cycle_cell_counts(counts, cells)) ||
        !identical(prefilter_record$summary$assay, assay) ||
        !identical(prefilter_record$summary$counts_layer, counts_layer) ||
        (!is.null(prefilter_record$metrics$capture) &&
         !identical(prefilter_record$metrics$capture, unname(capture_map))))
      .sc_project_fail("Prefilter and doublet evidence must bind the same complete original raw counts, literal IDs, and declared capture assignments.")
    score_cells <- prefilter_record$keep_cells
  }
  captures <- unique(unname(capture_map)); rates <- .sc_run_doublet_resolve_rates(options, capture_map)
  capture_stats <- stats::setNames(lapply(captures, function(capture) {
    original <- which(capture_map == capture)
    selected <- original[cells[original] %in% score_cells]
    expressed <- sum(Matrix::rowSums(counts[, selected, drop = FALSE]) > 0)
    low_reads <- sum(Matrix::colSums(counts[, selected, drop = FALSE]) < 200)
    reasons <- character()
    if (length(selected) < 100L) reasons <- c(reasons, if (is.null(prefilter_record))
      "Fewer than 100 called cells in this capture; unsupported by the declared software prerequisite." else
      "Fewer than 100 pre-score cells remain in this capture after the explicit prefilter; the complete scoring reference is unsupported and no partial predictions are accepted.")
    if (low_reads) reasons <- c(reasons, paste0(low_reads, " cells have fewer than 200 raw counts; no low-coverage cells are silently removed."))
    if (expressed < options$nfeatures) reasons <- c(reasons, "Expressed capture features are fewer than declared nfeatures; no parameter clipping is performed.")
    if (options$dims >= min(length(selected), expressed)) reasons <- c(reasons, "Declared dimensions cannot be supported by this capture's cells and expressed features.")
    stat <- list(input_cells = length(original), expressed_features = expressed, low_read_cells = low_reads,
         expected_rate = unname(rates[capture]), expected_doublets = length(original) * unname(rates[capture]),
         predicted_doublets = 0L, predicted_fraction = NA_real_, unknown_cells = length(original),
         score_distribution = .sc_run_qc_distribution(rep(NA_real_, length(selected))), threshold = NA_real_,
         status = if (length(reasons)) "unsupported" else "applicable", reasons = unname(reasons))
    if (!is.null(prefilter_record)) {
      stat$pre_score_cells <- length(selected)
      stat$prefilter_excluded_cells <- length(original) - length(selected)
      stat$predicted_fraction_scored <- NA_real_
      stat$rate_provenance <- list(method = options$rate$method, source = options$rate$source,
        reference = if (identical(options$rate$method, "10x_standard")) "original_full_called_capture" else "explicit_manual_rate",
        original_called_cells = length(original), pre_score_cells = length(selected),
        original_cell_hash = .sc_run_hash(cells[original]), pre_score_cell_hash = .sc_run_hash(cells[selected]),
        expected_doublets_original = length(original) * unname(rates[capture]),
        expected_doublets_scoring_cohort = length(selected) * unname(rates[capture]),
        rate_reestimated_after_prefilter = FALSE)
    }
    stat
  }), captures)
  reasons <- unlist(lapply(captures, function(capture)
    if (length(capture_stats[[capture]]$reasons)) paste0("Capture '", capture, "': ", capture_stats[[capture]]$reasons) else character()), use.names = FALSE)
  status <- if (length(reasons)) "unsupported" else "available"
  scores <- data.frame(cell_id = cells, row.names = cells, stringsAsFactors = FALSE, check.names = FALSE)
  scores[[columns[["score"]]]] <- rep(NA_real_, length(cells))
  scores[[columns[["class"]]]] <- rep("Unknown", length(cells))
  scores[[columns[["capture"]]]] <- unname(capture_map)
  execution <- stats::setNames(vector("list", length(captures)), captures)
  adapter_versions <- NULL
  if (identical(status, "available")) .sc_run_doublet_dependencies()
  if (identical(status, "available")) for (index in seq_along(captures)) {
    capture <- captures[index]; selected <- cells[capture_map == capture & cells %in% score_cells]
    canonical_cells <- selected[order(enc2utf8(selected), method = "radix")]
    canonical_features <- features[order(enc2utf8(features), method = "radix")]
    seed <- .sc_run_doublet_seed(options$seed, capture)
    detected <- .sc_run_doublet_detect_one(counts[canonical_features, canonical_cells, drop = FALSE], options,
                                           unname(rates[capture]), seed)
    .sc_run_doublet_classifier_audit_verify(detected$classifier_audit, detected$adapter_source_hashes,
                                           options$iter, detected$adapter_versions)
    if (index == 1L) adapter_versions <- detected$adapter_versions else
      if (!identical(adapter_versions, detected$adapter_versions))
        .sc_project_fail("Doublet captures must use the same verified adapter dependency versions; no mixed-release evidence is accepted.")
    values <- detected$scores
    if (!is.data.frame(values) || !identical(names(values), c("cell_id", "score", "class")) ||
        !identical(values$cell_id, canonical_cells) || !identical(rownames(values), canonical_cells) ||
        !is.numeric(values$score) || any(!is.finite(values$score)) ||
        any(values$score < 0 | values$score > 1) || anyNA(values$class) ||
        any(!values$class %in% c("singlet", "doublet")) || length(detected$warnings))
      .sc_project_fail("Doublet algorithm did not return finite scores and valid predicted classes for the exact capture cell IDs, or emitted warnings; no partial/fallback evidence is accepted.")
    if (!is.numeric(detected$threshold) || length(detected$threshold) != 1L || !is.finite(detected$threshold) ||
        !identical(as.character(values$class), ifelse(values$score >= detected$threshold, "doublet", "singlet")))
      .sc_project_fail("Doublet predicted classes do not match the exact saved algorithm threshold; no manual cutoff or missing threshold is substituted.")
    values <- values[match(selected, values$cell_id), , drop = FALSE]
    scores[selected, columns[["score"]]] <- values$score
    scores[selected, columns[["class"]]] <- as.character(values$class)
    stats <- capture_stats[[capture]]
    stats$predicted_doublets <- sum(values$class == "doublet")
    stats$predicted_fraction <- stats$predicted_doublets / stats$input_cells
    stats$unknown_cells <- stats$input_cells - length(selected)
    stats$score_distribution <- .sc_run_qc_distribution(values$score)
    if (!is.null(prefilter_record)) stats$predicted_fraction_scored <- stats$predicted_doublets / length(selected)
    stats$threshold <- detected$threshold; stats$status <- "available"
    capture_stats[[capture]] <- stats
    execution[[capture]] <- list(seed = seed, dbr = unname(rates[capture]), dbr_sd = options$rate$sd,
      nfeatures = options$nfeatures, dims = options$dims, artificial_doublets = options$artificial_doublets,
      iter = options$iter, clusters = FALSE, score = "xgb", threshold_enabled = TRUE,
      xgb_nthreads = 1L, parallel = "BiocParallel::SerialParam", rng_seed = seed,
      processing = "default", multi_sample_mode = "split", nrounds = .25, max_depth = 4L,
      metric = "logloss", remove_unidentifiable = TRUE, unident_threshold = .2,
      include_pcs_argument = 19L, included_pcs = seq_len(min(19L, options$dims - 1L)),
      ordering = "literal UTF-8 feature and cell IDs sorted with radix within each capture; predictions rejoined to original source order",
      canonical_cell_hash = .sc_run_hash(canonical_cells), canonical_feature_hash = .sc_run_hash(canonical_features),
      capture_seed_hash = .sc_run_hash(enc2utf8(unname(capture))),
      seed_derivation = "(base seed + integer(first 7 hex digits of SHA-256 serialized literal UTF-8 capture ID)) modulo .Machine$integer.max",
      classifier_audit = detected$classifier_audit, adapter_source_hashes = detected$adapter_source_hashes,
      warnings = detected$warnings, messages = detected$messages)
    execution[[capture]]$adapter_versions <- detected$adapter_versions
  }
  versions <- .sc_run_doublet_versions()
  adapter_unavailable_reason <- NULL
  if (identical(status, "unsupported")) {
    # Local prerequisite diagnostics require no optional classifier. Bind an
    # accepted pair only when the saved version snapshot supports it; missing
    # or unknown backends stay explicitly unexecuted without fabricated hashes.
    candidate <- versions[c("scDblFinder", "xgboost")]
    adapter_unavailable_reason <- tryCatch({
      .sc_run_doublet_classifier_versions_verify(candidate); NULL
    }, error = function(e) conditionMessage(e))
    if (is.null(adapter_unavailable_reason)) adapter_versions <- candidate
  }
  if (!is.null(adapter_versions)) .sc_run_doublet_classifier_provenance_verify(adapter_versions, versions)
  predicted_cells <- cells[scores[[columns[["class"]]]] == "doublet"]
  summary <- list(schema = "scagentkit.doublet.evidence.v1", status = status, reasons = reasons,
    species = options$species, assay = assay, counts_layer = counts_layer, columns = columns,
    cells = length(cells), features = length(features), captures = length(captures),
    data_type = options$data_type, technology = options$technology, input_source = options$input_source,
    empty_droplets_removed = TRUE, full_called_cohort = options$full_called_cohort,
    capture = options$capture, rate = options$rate,
    parameters = options[c("seed", "nfeatures", "dims", "artificial_doublets", "iter", "clusters")],
    capture_stats = capture_stats, reference = "fixed_full_input", refit_after_qc = FALSE,
    cohort = list(input_cells = length(cells), scored_cells = if (status == "available") length(score_cells) else 0L,
                  predicted_doublets = length(predicted_cells), unknown_cells = if (status == "unsupported") length(cells) else length(cells) - length(score_cells),
                  removed_cells = 0L),
    scoring = list(function_name = "scDblFinder::scDblFinder", score = "xgb", clusters = FALSE,
                   threshold = TRUE, xgb_nthreads = 1L, capture_mode = "independent literal loading units",
                   parallel = "BiocParallel::SerialParam", versions = versions,
                   r_version = as.character(getRversion()), platform = R.version$platform,
                   rng_kind = c("Mersenne-Twister", "Inversion", "Rejection"),
                   caller_rng_kind = RNGkind(), bioc_parallel_rng_kind = "L'Ecuyer-CMRG",
                   ordering = "literal UTF-8 radix order within capture; exact ID join to original input order",
                   seed_derivation = "base seed plus first 7 hex capture-ID SHA-256 digits modulo .Machine$integer.max; independent of capture enumeration",
                   classifier_audits = lapply(execution, function(item) item$classifier_audit),
                   adapter_source_hashes = if (!is.null(adapter_versions))
                     .sc_run_doublet_classifier_source_hashes(adapter_versions$scDblFinder) else
                     if (identical(status, "available")) .sc_run_doublet_classifier_source_hashes() else NULL,
                   audit_scope = "Unchanged public and scoring function bodies in a private lexical scope; original xgb training and prediction audited; no namespace mutation."),
    interpretation = c("Scores and classes are algorithm predictions, not measured doublet truth or calibrated probabilities.",
      "The method chiefly detects heterotypic doublets; homotypic pairs can remain undetected.",
      "Capture denotes a physical loading unit; multiplexed donors may share a capture.",
      "Expected rate is a sourced model assumption, not a fixed deletion quota.",
      "The complete called-cell input is scored once; later QC and reviewed deletion reuse exact cell-ID predictions without refitting.",
      "Minimum cells, counts, and feature bounds are declared software prerequisites, not validated biological thresholds.",
      "Diagnostic predictions never delete cells; only an explicit approved remove_predicted strategy derives a subset."))
  summary$scoring$adapter_versions <- adapter_versions
  if (identical(status, "unsupported")) {
    summary$scoring$adapter_status <- "not_executed"
    summary$scoring$adapter_unavailable_reason <- adapter_unavailable_reason
    summary$scoring$audit_scope <- "No classifier executed because local scoring prerequisites were unsupported; any saved adapter hashes identify the accepted release, not an executed algorithm."
  }
  record <- list(summary = summary, scores = scores, options = options, cell_ids = cells, feature_ids = features,
    capture_map = capture_map, predicted_cells = predicted_cells, execution = execution,
    counts_hash = counts_hash, count_cell_hashes = .sc_run_cycle_cell_counts(counts, cells),
    cell_hash = .sc_run_hash(cells), features_hash = .sc_run_hash(features),
    capture_hash = .sc_run_hash(capture_map), options_hash = .sc_run_hash(options), scores_hash = .sc_run_hash(scores))
  if (!is.null(prefilter_record)) {
    record$prefilter_record <- prefilter_record
    record$prefilter_hash <- prefilter_record$evidence_hash
    record$scored_cell_ids <- if (identical(status, "available")) score_cells else character()
    record$summary$prefilter <- list(evidence_hash = prefilter_record$evidence_hash,
      options = prefilter_record$options, original_cells = length(cells), pre_score_cells = length(score_cells),
      excluded_cells = length(cells) - length(score_cells), scopes = prefilter_record$summary$scopes)
    record$summary$cohort$pre_score_cells <- length(score_cells)
    record$summary$cohort$prefilter_excluded_cells <- length(cells) - length(score_cells)
    record$summary$cohort$pre_score_cell_hash <- .sc_run_hash(score_cells)
    record$summary$interpretation[5L] <- "The explicit pre-score cohort is scored once; prefilter exclusions remain Unknown, while full original-input identity and original capture rate provenance are retained. Later quality filtering reuses the saved predictions without refitting."
  }
  record$evidence_hash <- .sc_run_doublet_hash(record)
  record
}

.sc_run_doublet_verify <- function(record) {
  if (!is.list(record) || !is.list(record$summary) ||
      !identical(record$summary$schema, "scagentkit.doublet.evidence.v1") ||
      !(identical(record$summary$status, "available") || identical(record$summary$status, "unsupported")) ||
      !identical(record$evidence_hash, .sc_run_doublet_hash(record)))
    .sc_project_fail("Doublet evidence is missing or changed; regenerate it and obtain fresh strategy review.")
  # Historical evidence binds its saved release, not whichever optional
  # package happens to be installed in the reviewing process. Records from the
  # original modern adapter remain valid without the new explicit pair field.
  adapter_versions <- record$summary$scoring$adapter_versions
  not_executed <- identical(record$summary$status, "unsupported") &&
    identical(record$summary$scoring$adapter_status, "not_executed")
  if (not_executed && (!is.list(record$execution) || any(lengths(record$execution)) ||
      any(lengths(record$summary$scoring$classifier_audits))))
    .sc_project_fail("Unexecuted unsupported doublet diagnostics cannot contain classifier execution or audits.")
  if (not_executed && is.null(adapter_versions)) {
    if (!is.null(record$summary$scoring$adapter_source_hashes))
      .sc_project_fail("Unsupported diagnostics with an unavailable adapter cannot claim executed classifier source identities.")
    .sc_run_doublet_text(record$summary$scoring$adapter_unavailable_reason, "unexecuted doublet adapter unavailable reason")
    adapter_hashes <- NULL
  } else if (is.null(adapter_versions)) {
    versions <- record$summary$scoring$versions
    if (!is.list(versions) || !identical(versions$scDblFinder, "1.26.7"))
      .sc_project_fail("Doublet evidence without explicit adapter provenance requires saved verified scDblFinder 1.26.7 and its supported xgboost backend; legacy, missing, and unknown releases must be regenerated before review.")
    adapter_hashes <- .sc_run_doublet_classifier_versions_verify(versions[c("scDblFinder", "xgboost")])
  } else {
    .sc_run_doublet_classifier_provenance_verify(adapter_versions, record$summary$scoring$versions)
    adapter_hashes <- .sc_run_doublet_classifier_source_hashes(adapter_versions$scDblFinder)
  }
  context <- list(species = record$options$species, columns = if (identical(record$options$capture$method, "column"))
                    list(capture = record$options$capture$column) else list())
  canonical <- .sc_run_doublet_options(context, record$options)
  cells <- record$cell_ids; .sc_project_ids(cells, "Doublet reference cell IDs")
  .sc_project_ids(record$feature_ids, "Doublet reference feature IDs")
  prefilter <- record$prefilter_record
  score_cells <- cells
  if (!is.null(prefilter)) {
    .sc_run_prefilter_verify(prefilter)
    score_cells <- prefilter$keep_cells
    expected_prefilter <- list(evidence_hash = prefilter$evidence_hash,
      options = prefilter$options, original_cells = length(cells), pre_score_cells = length(score_cells),
      excluded_cells = length(cells) - length(score_cells), scopes = prefilter$summary$scopes)
    if (!identical(record$prefilter_hash, prefilter$evidence_hash) ||
        !identical(prefilter$cell_ids, cells) || !identical(prefilter$feature_ids, record$feature_ids) ||
        !identical(prefilter$counts_hash, record$counts_hash) ||
        !identical(prefilter$count_cell_hashes, record$count_cell_hashes) ||
        !identical(prefilter$summary$assay, record$summary$assay) ||
        !identical(prefilter$summary$counts_layer, record$summary$counts_layer) ||
        (!is.null(prefilter$metrics$capture) &&
         !identical(prefilter$metrics$capture, unname(record$capture_map))) ||
        !identical(record$summary$prefilter, expected_prefilter) ||
        !identical(record$summary$cohort$pre_score_cells, length(score_cells)) ||
        !identical(record$summary$cohort$prefilter_excluded_cells, length(cells) - length(score_cells)) ||
        !identical(record$summary$cohort$pre_score_cell_hash, .sc_run_hash(score_cells)) ||
        !identical(record$scored_cell_ids, if (identical(record$summary$status, "available")) score_cells else character()))
      .sc_project_fail("Doublet prefilter parent binding, complete original input, or exact pre-score scope is inconsistent.")
  } else if (!is.null(record$prefilter_hash) || !is.null(record$scored_cell_ids) ||
             !is.null(record$summary$prefilter) || !is.null(record$summary$cohort$pre_score_cells) ||
             !is.null(record$summary$cohort$prefilter_excluded_cells) || !is.null(record$summary$cohort$pre_score_cell_hash))
    .sc_project_fail("Doublet prefilter metadata requires its complete verified parent record; legacy evidence cannot imply a prefilter.")
  columns <- .sc_run_doublet_columns(record$options$column_prefix)
  if (!identical(record$options, canonical) || !identical(record$summary$columns, columns) ||
      !identical(record$cell_hash, .sc_run_hash(cells)) ||
      !identical(record$features_hash, .sc_run_hash(record$feature_ids)) ||
      !identical(record$options_hash, .sc_run_hash(record$options)) ||
      !identical(record$capture_hash, .sc_run_hash(record$capture_map)) ||
      !identical(record$scores_hash, .sc_run_hash(record$scores)) ||
      !is.data.frame(record$scores) || !identical(names(record$scores), c("cell_id", unname(columns))) ||
      !identical(record$scores$cell_id, cells) || !identical(rownames(record$scores), cells) ||
      !identical(names(record$capture_map), cells) || anyNA(record$capture_map) ||
      any(!nzchar(record$capture_map)) || !identical(record$scores[[columns[["capture"]]]], unname(record$capture_map)) ||
      !identical(names(record$count_cell_hashes), cells) || anyNA(record$count_cell_hashes) ||
      !identical(record$summary$reference, "fixed_full_input") || !identical(record$summary$refit_after_qc, FALSE))
    .sc_project_fail("Doublet reference identity, score, capture, or option hashes are inconsistent.")
  predicted <- record$scores[[columns[["class"]]]]
  numeric <- record$scores[[columns[["score"]]]]
  if (!is.numeric(numeric) || anyNA(predicted) || !is.character(predicted) ||
      !identical(record$predicted_cells, cells[predicted == "doublet"]))
    .sc_project_fail("Doublet reference requires numeric scores and exact ordered predicted cell IDs.")
  if (identical(record$summary$status, "unsupported")) {
    if (any(!is.na(numeric)) || any(predicted != "Unknown"))
      .sc_project_fail("Unsupported doublet evidence must contain Unknown classes and missing scores; no partial prediction is accepted.")
  } else {
    scored <- cells %in% score_cells
    if (any(!is.finite(numeric[scored])) || any(numeric[scored] < 0 | numeric[scored] > 1) ||
        any(!predicted[scored] %in% c("singlet", "doublet")) ||
        any(!is.na(numeric[!scored])) || any(predicted[!scored] != "Unknown"))
      .sc_project_fail("Available doublet evidence requires finite algorithm scores for the exact pre-score cells and Unknown/missing scores for explicit prefilter exclusions.")
  }
  captures <- unique(unname(record$capture_map))
  if (!identical(names(record$summary$capture_stats), captures) || !identical(names(record$execution), captures) ||
      !identical(record$summary$cells, length(cells)) || !identical(record$summary$features, length(record$feature_ids)) ||
      !identical(record$summary$captures, length(captures)) ||
      !identical(record$summary$cohort$input_cells, length(cells)) ||
      !identical(record$summary$cohort$scored_cells, if (identical(record$summary$status, "available")) length(score_cells) else 0L) ||
      !identical(record$summary$cohort$unknown_cells, if (identical(record$summary$status, "available")) length(cells) - length(score_cells) else length(cells)) ||
      !identical(record$summary$cohort$predicted_doublets, length(record$predicted_cells)) ||
      !identical(record$summary$cohort$removed_cells, 0L) ||
      !identical(record$summary$full_called_cohort, record$options$full_called_cohort) ||
      !identical(record$summary$capture, record$options$capture) || !identical(record$summary$rate, record$options$rate) ||
      !identical(record$summary$scoring$classifier_audits, lapply(record$execution, function(item) item$classifier_audit)) ||
      !identical(record$summary$scoring$adapter_source_hashes, adapter_hashes))
    .sc_project_fail("Doublet capture summaries and execution records must cover the literal capture units exactly.")
  if (identical(record$summary$status, "unsupported") && !length(record$summary$reasons))
    .sc_project_fail("Unsupported doublet evidence requires explicit prerequisite reasons; it is never a silent skip.")
  rates <- .sc_run_doublet_resolve_rates(record$options, record$capture_map)
  for (capture in captures) {
    selected <- record$capture_map == capture; stat <- record$summary$capture_stats[[capture]]
    scored <- selected & cells %in% score_cells
    if (!identical(stat$input_cells, sum(selected)) ||
        !identical(stat$predicted_doublets, sum(predicted[selected] == "doublet")) ||
        !identical(stat$unknown_cells, sum(predicted[selected] == "Unknown")) ||
        !identical(stat$expected_rate, unname(rates[capture])) ||
        !identical(stat$expected_doublets, sum(selected) * unname(rates[capture])))
      .sc_project_fail("Doublet capture summary does not match its exact private predictions.")
    if (!is.null(prefilter)) {
      expected_rate_provenance <- list(method = record$options$rate$method, source = record$options$rate$source,
        reference = if (identical(record$options$rate$method, "10x_standard")) "original_full_called_capture" else "explicit_manual_rate",
        original_called_cells = sum(selected), pre_score_cells = sum(scored),
        original_cell_hash = .sc_run_hash(cells[selected]), pre_score_cell_hash = .sc_run_hash(cells[scored]),
        expected_doublets_original = sum(selected) * unname(rates[capture]),
        expected_doublets_scoring_cohort = sum(scored) * unname(rates[capture]),
        rate_reestimated_after_prefilter = FALSE)
      if (!identical(stat$pre_score_cells, sum(scored)) ||
          !identical(stat$prefilter_excluded_cells, sum(selected) - sum(scored)) ||
          !identical(stat$rate_provenance, expected_rate_provenance) ||
          !identical(stat$predicted_fraction_scored, if (identical(record$summary$status, "available"))
            sum(predicted[scored] == "doublet") / sum(scored) else NA_real_))
        .sc_project_fail("Doublet rate provenance must retain original full-called capture size and the separately hashed pre-score cohort.")
    }
    if (identical(record$summary$status, "available") && length(record$execution[[capture]]$warnings))
      .sc_project_fail("Doublet classifier warnings cannot be accepted as successful evidence.")
    if (identical(record$summary$status, "available")) {
      if (!identical(record$execution[[capture]]$adapter_versions, adapter_versions))
        .sc_project_fail("Doublet capture adapter provenance differs from its saved release summary.")
      .sc_run_doublet_classifier_audit_verify(record$execution[[capture]]$classifier_audit,
                                             record$execution[[capture]]$adapter_source_hashes, record$options$iter,
                                             adapter_versions)
      if (!is.numeric(stat$threshold) || length(stat$threshold) != 1L || !is.finite(stat$threshold) ||
          !identical(predicted[scored], ifelse(numeric[scored] >= stat$threshold, "doublet", "singlet")))
        .sc_project_fail("Available doublet prediction classes must match their exact saved algorithm threshold.")
      ordered_cells <- cells[scored][order(enc2utf8(cells[scored]), method = "radix")]
      ordered_features <- record$feature_ids[order(enc2utf8(record$feature_ids), method = "radix")]
      execution <- record$execution[[capture]]
      if (!identical(execution$seed, .sc_run_doublet_seed(record$options$seed, capture)) ||
          !identical(execution$canonical_cell_hash, .sc_run_hash(ordered_cells)) ||
          !identical(execution$canonical_feature_hash, .sc_run_hash(ordered_features)) ||
          !identical(execution$capture_seed_hash, .sc_run_hash(enc2utf8(unname(capture)))) ||
          !identical(execution$parallel, "BiocParallel::SerialParam") || !identical(execution$xgb_nthreads, 1L))
        .sc_project_fail("Doublet execution seed, literal canonical ordering, or fixed serial-worker record is inconsistent.")
    }
  }
  invisible(TRUE)
}

.sc_run_doublet_attach <- function(seu, record) {
  .sc_run_doublet_verify(record); seu <- .sc_project_unwrap(seu)
  cells <- colnames(seu); .sc_project_ids(cells, "Retained doublet cell IDs")
  if (any(!cells %in% record$cell_ids)) .sc_project_fail("Retained cells are absent from the fixed full-input doublet reference.")
  columns <- record$summary$columns; metadata <- seu[[]]
  if (any(columns %in% names(metadata))) .sc_project_fail("Doublet output column already exists; choose a fresh column_prefix to preserve source metadata.")
  if (!identical(rownames(metadata), cells)) .sc_project_fail("Doublet attachment requires exact retained metadata cell order.")
  counts <- .sc_project_layer(seu, record$summary$assay, record$summary$counts_layer, raw_counts = TRUE)
  if (!identical(rownames(counts), record$feature_ids) || !setequal(colnames(counts), cells) ||
      !identical(.sc_run_cycle_cell_counts(counts, cells), record$count_cell_hashes[cells]))
    .sc_project_fail("Retained raw counts or literal features changed from the fixed full-input doublet reference.")
  if (identical(record$options$capture$method, "column") &&
      !identical(.sc_run_doublet_captures(seu, record$options, cells), record$capture_map[cells]))
    .sc_project_fail("Retained capture assignments changed from the fixed full-input doublet reference.")
  values <- record$scores[match(cells, record$cell_ids), unname(columns), drop = FALSE]
  rownames(values) <- cells
  seu <- SeuratObject::AddMetaData(seu, metadata = values)
  if (!identical(colnames(seu), cells) || !identical(seu[[]][, names(metadata), drop = FALSE], metadata))
    .sc_project_fail("Doublet attachment changed original metadata or literal cell order.")
  seu
}

.sc_run_doublet_validate_choice <- function(choice, record, qc_keep, cycle_record = NULL) {
  .sc_run_doublet_verify(record)
  .sc_run_doublet_fields(choice, c("method", "reason"), label = "doublet choice")
  choice$reason <- .sc_run_doublet_text(choice$reason, "doublet choice reason")
  if (!is.character(choice$method) || length(choice$method) != 1L || is.na(choice$method) ||
      !choice$method %in% c("keep", "remove_predicted"))
    .sc_project_fail("Doublet choice must explicitly select keep or remove_predicted; custom scores, thresholds, cell lists, and arbitrary code are unsupported.")
  .sc_project_ids(qc_keep, "Proposed QC retained doublet IDs")
  if (any(!qc_keep %in% record$cell_ids)) .sc_project_fail("Proposed QC cells are absent from the fixed doublet reference.")
  if (!is.null(record$prefilter_record) && any(!qc_keep %in% record$prefilter_record$keep_cells))
    .sc_project_fail("Post-score QC cannot restore cells excluded by the explicit preapproved prefilter; select from the recorded pre-score cohort.")
  if (identical(choice$method, "remove_predicted") && !identical(record$summary$status, "available"))
    .sc_project_fail("Predicted-doublet removal is unsupported because the diagnostic reference is unavailable; keep cells or resolve the stated prerequisites and obtain fresh review.")
  predicted <- record$predicted_cells
  qc_predictions <- qc_keep[qc_keep %in% predicted]
  removed <- if (identical(choice$method, "remove_predicted")) qc_predictions else character()
  keep <- qc_keep[!qc_keep %in% removed]
  if (!length(keep)) .sc_project_fail("Approved doublet removal would retain no cells; obtain a different explicit strategy.")
  per_capture <- stats::setNames(lapply(unique(unname(record$capture_map)), function(capture) {
    input <- record$cell_ids[record$capture_map == capture]
    post_qc <- qc_keep[qc_keep %in% input]; remove <- removed[removed %in% input]
    stat <- list(input_cells = length(input), predicted_input = sum(input %in% predicted),
         qc_retained = length(post_qc), predicted_after_qc = sum(post_qc %in% predicted),
         predicted_qc_excluded = sum(input %in% predicted & !input %in% qc_keep),
         removed = length(remove), retained = length(post_qc) - length(remove),
         removed_fraction_after_qc = if (length(post_qc)) length(remove) / length(post_qc) else NA_real_,
         removed_fraction_input = length(remove) / length(input),
         retained_fraction_after_qc = if (length(post_qc)) (length(post_qc) - length(remove)) / length(post_qc) else NA_real_,
         retained_fraction_input = (length(post_qc) - length(remove)) / length(input))
    if (!is.null(record$prefilter_record)) {
      stat$pre_score_cells <- sum(input %in% record$prefilter_record$keep_cells)
      stat$prefilter_excluded_cells <- length(input) - stat$pre_score_cells
      stat$quality_excluded_after_pre_score <- stat$pre_score_cells - length(post_qc)
      stat$rate_provenance <- record$summary$capture_stats[[capture]]$rate_provenance
    }
    stat
  }), unique(unname(record$capture_map)))
  cycle <- NULL
  if (!is.null(cycle_record)) {
    .sc_run_cycle_verify(cycle_record)
    if (!identical(cycle_record$cell_ids, record$cell_ids) ||
        !identical(cycle_record$counts_hash, record$counts_hash) ||
        !identical(cycle_record$feature_ids, record$feature_ids))
      .sc_project_fail("Cycle and doublet evidence must use the same exact full-input counts and literal IDs before impact review.")
    phase_column <- cycle_record$summary$columns[["phase"]]
    levels <- c("G1", "S", "G2M", "Undecided", "Unknown")
    groups <- list(full_input = record$cell_ids, post_qc = qc_keep, predicted_after_qc = qc_predictions,
                   proposed_removed = removed, retained = keep)
    cycle <- list(evidence_hash = cycle_record$evidence_hash, status = cycle_record$summary$status,
      phase_by_scope = lapply(groups, function(ids) {
        values <- cycle_record$scores[match(ids, cycle_record$cell_ids), phase_column]
        table <- table(factor(values, levels = levels))
        stats::setNames(as.list(as.integer(table)), levels)
      }), score_by_scope = lapply(groups, function(ids) stats::setNames(lapply(
        cycle_record$summary$columns[c("s_score", "g2m_score", "difference")], function(column)
          .sc_run_qc_distribution(cycle_record$scores[match(ids, cycle_record$cell_ids), column])),
        c("s_score", "g2m_score", "difference"))))
  }
  validated <- list(choice = list(method = unname(choice$method), reason = unname(choice$reason)),
       method = unname(choice$method), evidence_hash = record$evidence_hash,
       keep_cells = keep, removed_cells = removed,
       impact = list(reference = "fixed_full_input", input_cells = length(record$cell_ids),
         predicted_input = length(predicted), qc_retained = length(qc_keep),
         predicted_after_qc = length(qc_predictions), predicted_qc_excluded = sum(!predicted %in% qc_keep),
         removed_cells = length(removed), retained_cells = length(keep), per_capture = per_capture,
         cycle = cycle, scores_are_calibrated_probabilities = FALSE, predictions_are_truth = FALSE))
  if (!is.null(record$prefilter_record)) {
    validated$impact$prefilter_hash <- record$prefilter_hash
    validated$impact$pre_score_cells <- length(record$prefilter_record$keep_cells)
    validated$impact$prefilter_excluded_cells <- length(record$prefilter_record$excluded_cells)
    validated$impact$quality_excluded_after_pre_score <- length(record$prefilter_record$keep_cells) - length(qc_keep)
  }
  validated
}

.sc_run_doublet_plot <- function(record, path) {
  .sc_run_doublet_verify(record); .sc_project_string(path, "doublet plot path")
  grDevices::png(path, width = 1000L, height = 740L, res = 120L)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (identical(record$summary$status, "unsupported")) {
    graphics::plot.new(); graphics::title("Doublet diagnostics: unsupported")
    graphics::text(.5, .5, paste(strwrap(paste(record$summary$reasons, collapse = " "), 85L), collapse = "\n"))
  } else {
    columns <- record$summary$columns
    labels <- unname(record$capture_map); captures <- unique(labels)
    values <- split(record$scores[[columns[["score"]]]], factor(labels, levels = captures))
    graphics::boxplot(values, outline = FALSE, las = 2L, col = "#a9c6df",
                      ylab = "Algorithm score (not a calibrated probability)",
                      main = "Fixed full-input doublet predictions by capture")
    for (index in seq_along(captures)) {
      select <- which(labels == captures[index])
      doublet <- record$scores[[columns[["class"]]]][select] == "doublet"
      graphics::points(rep(index, length(select)), record$scores[[columns[["score"]]]][select],
        pch = 16L, cex = .4, col = grDevices::adjustcolor(ifelse(doublet, "#b23c32", "#366da8"), alpha.f = .45))
    }
    graphics::legend("topright", c("predicted singlet", "predicted doublet"),
                     col = c("#366da8", "#b23c32"), pch = 16L, bty = "n")
  }
  invisible(path)
}
