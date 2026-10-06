# These are deterministic software controls. Planted low-quality cells and
# doublet predictions are not biological truth or a recommended QC policy.
# All provider and detector mocks are local; root acceptance separately runs
# the installed method and real browser on public PBMC data.

mad_integration_fixture <- function() {
  backgrounds <- paste0("MADBackground", seq_len(400L))
  features <- c("MT-CO1", backgrounds)
  controls <- c("lowboth-highmt", "lowcount-only", "lowfeature-only",
    "highmt-only", "highRNA-only", "empty")
  a <- c("001", "1", "NA", "cell space", paste0("A-base", sprintf("%03d", 5:122)),
    paste0("A-", controls))
  b <- c(paste0("B-base", sprintf("%03d", 1:122)), paste0("B-", controls))
  cells <- c(a, b)
  counts <- matrix(0, length(features), length(cells), dimnames = list(features, cells))
  for (group in seq_len(2L)) {
    for (i in seq_len(122L)) {
      n <- 250L + ((i - 1L) %% 11L) * 5L + if (group == 2L) 70L else 0L
      indices <- ((seq_len(n) + ((i - 1L) %% 4L) * 80L - 1L) %% 400L) + 1L
      column <- (group - 1L) * 128L + i
      counts[backgrounds[indices], column] <- if (group == 1L) 3L else 6L
      counts["MT-CO1", column] <- 1L + ((i - 1L) %% 5L)
    }
    prefix <- if (group == 1L) "A-" else "B-"
    # The first control has exactly 200 reads, three features and 99% mt.
    counts["MT-CO1", paste0(prefix, "lowboth-highmt")] <- 198L
    counts[backgrounds[1:2], paste0(prefix, "lowboth-highmt")] <- 1L
    counts["MT-CO1", paste0(prefix, "lowcount-only")] <- 1L
    counts[backgrounds, paste0(prefix, "lowcount-only")] <- 1L
    counts["MT-CO1", paste0(prefix, "lowfeature-only")] <- 1L
    counts[backgrounds[1:5], paste0(prefix, "lowfeature-only")] <- if (group == 1L) 150L else 420L
    counts["MT-CO1", paste0(prefix, "highmt-only")] <- 500L
    counts[backgrounds, paste0(prefix, "highmt-only")] <- if (group == 1L) 1L else 4L
    counts["MT-CO1", paste0(prefix, "highRNA-only")] <- 1L
    counts[backgrounds, paste0(prefix, "highRNA-only")] <- if (group == 1L) 20L else 40L
  }
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object$sample <- factor(rep(c("sample A", "sample B"), each = 128L),
    levels = c("sample B", "sample A", "empty declared group"))
  object$qc_group <- rep(c("quality stratum A", "quality stratum B"), each = 128L)
  object$capture <- rep(c("capture A", "capture B"), 128L)
  object$donor <- rep(c("donor one", "donor two", "donor three", "donor four"), 64L)
  object$condition <- rep(c("Ca", "Ctrl"), each = 64L, times = 2L)
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 128L),
    levels = c("prior A", "unused prior B"))
  object$old_QC_flag <- rep(c(TRUE, FALSE), 128L)
  object$scDblFinder.score <- seq_len(256L) / 1000
  object$scDblFinder.class <- factor(rep(c("old call", NA_character_), 128L),
    levels = c("old call", "unused old call"))
  object$private_note <- "Private per-cell control text must not enter aggregate model requests."
  object
}

mad_integration_context <- function() list(species = "human", tissue = "synthetic",
  columns = list(sample = "sample", capture = "capture", donor = "donor", condition = "condition"),
  design = list(type = "crossed quality groups, capture, donor and condition controls",
    notes = "A sample quality group is explicitly distinct from a capture/loading unit or donor."),
  research_goal = "Compare bounded local MAD candidates under one human decision.",
  notes = "Planted deterministic cells test mechanics, not scientific threshold optimality.")

mad_integration_options <- function(prefilter = TRUE, role = "sample") {
  list(grouping = list(method = "column", column = if (role == "sample") "sample" else "qc_group",
    declared_role = role, source = "Literal synthetic quality strata explicitly supplied by the fixture author."),
    k = 3, min_group_cells = 30L,
    prefilter = if (prefilter) list(method = "min_counts", min_counts = 1,
      source = "Explicitly preapproved removal of only zero-count synthetic controls.",
      preapproved = TRUE) else list(method = "none"))
}

mad_integration_doublet_options <- function() list(data_type = "scrna_droplet",
  input_source = "Synthetic software controls after a declared minimal count prefilter.",
  empty_droplets_removed = TRUE,
  capture = list(method = "column", column = "capture",
    source = "Fixture-author declaration of literal loading units, independent of quality groups."),
  rate = list(method = "manual", value = .05, sd = .02,
    source = "Software-control rate declared independently of the already prefiltered score cohort."),
  seed = 999L, column_prefix = "sc_doublet", nfeatures = 200L,
  dims = 10L, artificial_doublets = 1500L)

mad_integration_begin <- function(root, object = mad_integration_fixture(),
                                  options = mad_integration_options(), doublet = TRUE,
                                  proposal = NULL, provider = NULL, chat_fn = NULL,
                                  context = mad_integration_context(), review = list()) {
  suppressWarnings(sc_run(input = object, project_dir = root, context = context,
    strategy = TRUE, strategy_proposal = proposal, qc_mad = options,
    doublet_diagnostics = if (doublet) mad_integration_doublet_options() else NULL,
    provider = provider, chat_fn = chat_fn, budget = 0, review = review,
    annotation_column = "reviewed_type"))
}

mad_integration_record <- function(root, name) {
  scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), name)
}

mad_integration_plan <- function(root, preset = "keep_all", doublet = "keep") {
  record <- mad_integration_record(root, "qc_mad")
  proposal <- list(schema = "scagentkit.strategy.v1",
    rationale = "Review a fixed aggregate panel and explicit local preset as a single decision.",
    risks = list("Neither planted labels nor higher retention establishes an optimal biological QC policy."),
    inferences = list("The synthetic quality strata are supplied facts; their relation to donors is not inferred."),
    qc = list(schema = "scagentkit.qc.mad.v1", preset_id = preset,
      panel_hash = record$panel_hash,
      rationale = "Explicitly select this exact immutable local candidate panel.",
      risks = list("MAD thresholds need interpretation; high RNA, ribosomal and hemoglobin signals are diagnostics.")),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 80L, npcs = 10L, seed = 999L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No integration or automatic sample exclusion is requested."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
    umap = list(run = FALSE, n_neighbors = 10L))
  if (!is.null(scAgentKit:::.sc_run_load(root)$config$doublet_diagnostics))
    proposal$doublet <- list(method = doublet,
      reason = "Keep or remove only the existing literal capture predictions after independently approved QC.")
  proposal
}

mad_integration_revise <- function(root, proposal, snapshot = sc_run_inspect(root)) {
  sc_run_strategy_revise(root, proposal, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, "offline MAD QA", "Revise the exact bounded whole-panel strategy.")
}

mad_integration_continue <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, retry = retry))
}

mad_integration_decide <- function(root, snapshot = sc_run_inspect(root), action = "approve") {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline MAD QA", reason = "Review this whole panel, exact candidate and joint cell impact.")
}

mad_integration_unknown <- function(root) {
  evidence <- sc_run_inspect(root)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(evidence$clusters, function(row) list(clusterId = row$clusterId,
      label = "Unknown", confidence = "low",
      rationale = "Synthetic software controls do not establish biological cell identities.", markers = list())))
  sc_run_propose(root, proposal, "offline MAD QA", "Use independently approved Unknown controls.")
}

mad_integration_files <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!dir.exists(paths)]
  stats::setNames(vapply(paths, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(paths, nchar(root) + 2L))
}

mad_integration_copy <- function(root) {
  target <- tempfile("mad-copy-"); dir.create(target)
  if (!all(file.copy(list.files(root, full.names = TRUE, all.files = TRUE, no.. = TRUE),
    target, recursive = TRUE, copy.mode = TRUE))) stop("Could not copy the stopped MAD project.")
  target
}

mad_integration_executions <- function(state, stage) {
  length(Filter(function(event) identical(event$action, "executed") &&
    identical(event$details$stage, stage), state$history))
}

mad_integration_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) { calls$factory <- calls$factory + 1L; stop("Offline MAD QA forbids provider factories.") }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Offline MAD QA forbids network requests.")
  }, .package = "httr2", .env = env)
  calls
}

mad_integration_detector <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$detector <- 0L; calls$captures <- list()
  # These literal predictions overlap two distinct QC controls, to prove that
  # post-QC selection is an exact intersection rather than positional joining.
  predicted <- c("001", "A-lowboth-highmt", "B-highRNA-only")
  detector <- function(counts, options, rate, seed) {
    calls$detector <- calls$detector + 1L
    if (isTRUE(getOption("mad_fixture_forbid_detector"))) stop("Saved MAD fixture predictions must not be recomputed.")
    calls$captures[[length(calls$captures) + 1L]] <- list(cells = colnames(counts),
      features = rownames(counts), rate = rate, seed = seed, sparse = inherits(counts, "sparseMatrix"))
    ids <- colnames(counts); positive <- ids %in% predicted
    values <- data.frame(cell_id = ids, score = ifelse(positive, .8, .05),
      class = ifelse(positive, "doublet", "singlet"), row.names = ids, stringsAsFactors = FALSE)
    list(scores = values, threshold = .5, warnings = character(), messages = character(),
      classifier_audit = list(train_attempts = 3L, train_successes = 3L,
        predict_attempts = 3L, predict_successes = 3L, training_errors = character(),
        prediction_errors = character(), test_only_mock = TRUE),
      adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
  }
  environment(detector) <- list2env(list(calls = calls, predicted = predicted), parent = baseenv())
  dependencies <- function() invisible(TRUE)
  versions <- function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
    fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution.",
    SingleCellExperiment = "software-mock-unexecuted")
  environment(dependencies) <- baseenv(); environment(versions) <- baseenv()
  testthat::local_mocked_bindings(.sc_run_doublet_detect_one = detector,
    .sc_run_doublet_dependencies = dependencies, .sc_run_doublet_versions = versions,
    .package = "scAgentKit", .env = env)
  calls
}

mad_integration_child <- function(root, snapshot = sc_run_inspect(root)) {
  work <- tempfile("mad-child-"); dir.create(work); on.exit(unlink(work, recursive = TRUE), add = TRUE)
  args_path <- file.path(work, "arguments.rds"); result <- file.path(work, "result.rds")
  script <- file.path(work, "child.R"); log <- file.path(work, "stdout.log")
  keys <- c(".sc_run_doublet_detect_one", ".sc_run_doublet_dependencies", ".sc_run_doublet_versions")
  bindings <- stats::setNames(lapply(keys, get, envir = asNamespace("scAgentKit")), keys)
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path"), bindings = bindings), args_path)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','GROK_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','AZURE_OPENAI_API_KEY','COHERE_API_KEY','MISTRAL_API_KEY','OPENROUTER_API_KEY','HF_TOKEN','HUGGINGFACEHUB_API_TOKEN'))",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else library(scAgentKit,lib.loc=dirname(args$package))",
    "factory_calls <- 0L; http_calls <- 0L",
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('No remote MAD factory permitted') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('No MAD HTTP permitted') },.package='httr2',.env=environment())",
    "do.call(testthat::local_mocked_bindings,c(args$bindings,list(.package='scAgentKit',.env=environment())))",
    "options(mad_fixture_forbid_detector=TRUE)",
    "detector <- args$bindings[['.sc_run_doublet_detect_one']]",
    "detector_before <- environment(detector)$calls$detector",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision))",
    "detector_calls <- environment(detector)$calls$detector-detector_before",
    "stopifnot(factory_calls==0L,http_calls==0L,detector_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls,detector_calls=detector_calls),args$result)", "})"), script)
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(args_path)), stdout = log, stderr = log)
  if (status != 0L || !file.exists(result)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

mad_integration_preserved <- function(object, source, cells) {
  expect_identical(colnames(object), cells); expect_identical(rownames(object), rownames(source))
  for (column in names(source[[]])) expect_identical(object[[]][[column]], source[[]][cells, column])
  for (layer in c("counts", "extra")) {
    actual <- SeuratObject::LayerData(object, assay = "RNA", layer = layer)
    expect_identical(actual, SeuratObject::LayerData(source, assay = "RNA", layer = layer)[, cells, drop = FALSE])
    expect_true(inherits(actual, "sparseMatrix"))
  }
}

mad_integration_prefilter_ids <- function(object) colnames(object)[!colnames(object) %in% c("A-empty", "B-empty")]
mad_integration_conservative_ids <- function(object) colnames(object)[!colnames(object) %in%
  c("A-empty", "B-empty", "A-lowboth-highmt", "B-lowboth-highmt")]

test_that("minimal prefilter and capture scoring precede one explicit sample-aware MAD decision", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  begun <- mad_integration_begin(root, object)
  expect_identical(begun$status, "awaiting_configuration"); expect_identical(begun$stage, "strategy_propose")
  snapshot <- sc_run_inspect(root); state <- scAgentKit:::.sc_run_load(root)
  expect_null(snapshot$review_node); expect_null(state$files$qc_object); expect_null(state$files$analysis)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(serialize(mad_integration_record(root, "input"), NULL, version = 2L), original)
  qc <- mad_integration_record(root, "qc_evidence"); record <- mad_integration_record(root, "qc_mad")
  prefilter <- mad_integration_record(root, "prefilter")
  expect_equal(prefilter$summary$original_cells, 256L)
  expect_equal(prefilter$summary$pre_score_cells, 254L)
  expect_equal(prefilter$summary$excluded_cells, 2L)
  expect_identical(prefilter$excluded_cells, c("A-empty", "B-empty"))
  expect_identical(prefilter$keep_cells, mad_integration_prefilter_ids(object))
  for (capture in c("capture A", "capture B")) {
    expect_equal(prefilter$summary$per_capture[[capture]]$original_cells, 128L)
    expect_equal(prefilter$summary$per_capture[[capture]]$pre_score_cells,
      if (capture == "capture A") 128L else 126L)
  }
  expect_identical(record, qc$mad_record); expect_identical(record$summary, qc$summary$mad)
  expect_identical(record$options$grouping$column, "sample")
  expect_identical(record$options$grouping$declared_role, "sample")
  expect_identical(record$cell_ids, colnames(object))
  expect_equal(length(unique(as.character(object$sample))), 2L)
  expect_equal(length(unique(object$capture)), 2L)
  expect_false(identical(as.character(object$sample), object$capture))
  expect_equal(detector$detector, 2L)
  expected_ids <- mad_integration_prefilter_ids(object)
  for (capture in c("capture A", "capture B")) {
    index <- match(capture, c("capture A", "capture B"))
    expect_identical(detector$captures[[index]]$cells,
      sort(enc2utf8(expected_ids[object[[]][expected_ids, "capture"] == capture]), method = "radix"))
    # Both even-indexed zero controls happen to belong to capture B. Capture
    # counts must follow those literal declarations, not balanced sample sizes.
    expect_equal(length(detector$captures[[index]]$cells), if (capture == "capture A") 128L else 126L)
    expect_equal(detector$captures[[index]]$rate, .05)
    expect_true(detector$captures[[index]]$sparse)
  }
  doublet <- mad_integration_record(root, "doublet_diagnostics")
  expect_identical(doublet$cell_ids, colnames(object))
  expect_identical(doublet$scored_cell_ids, expected_ids)
  expect_equal(doublet$summary$cohort$pre_score_cells, 254L)
  expect_equal(doublet$summary$cohort$prefilter_excluded_cells, 2L)
  excluded <- match(c("A-empty", "B-empty"), doublet$scores$cell_id)
  expect_true(all(is.na(doublet$scores$sc_doublet_score[excluded])))
  expect_identical(doublet$scores$sc_doublet_class[excluded], c("Unknown", "Unknown"))
  # High RNA remains in the first scoring cohort and the conservative policy.
  expect_true(all(c("A-highRNA-only", "B-highRNA-only") %in% unlist(lapply(detector$captures, `[[`, "cells"))))
  # The first local Continue records its provider-free boundary; repeating that
  # exact stopped boundary must leave every project byte unchanged.
  expect_identical(mad_integration_continue(root)$status, "awaiting_configuration")
  bytes <- mad_integration_files(root)
  expect_identical(mad_integration_continue(root)$status, "awaiting_configuration")
  expect_identical(mad_integration_files(root), bytes)
  proposal <- mad_integration_plan(root, "conservative_and3")
  revised <- mad_integration_revise(root, proposal)
  expect_identical(revised$status, "awaiting_review")
  snapshot <- sc_run_inspect(root)
  expect_identical(snapshot$review_node$kind, "strategy")
  expect_identical(snapshot$strategy_review$details$qc_mad$panel_hash, record$panel_hash)
  expect_identical(snapshot$strategy_review$details$qc_mad$choice$preset_id, "conservative_and3")
  validated <- mad_integration_record(root, "qc_validated")
  expect_identical(validated$keep_cells, mad_integration_conservative_ids(object))
  expect_equal(validated$retention$retained, 252L)
  expect_identical(mad_integration_record(root, "strategy_validated")$selected_cells, validated$keep_cells)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("headless approval restart output and annotation undo preserve exact source identities and columns", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  mad_integration_begin(root, object)
  mad_integration_revise(root, mad_integration_plan(root, "conservative_and3", "remove_predicted"))
  node <- sc_run_inspect(root)
  expected <- colnames(object)[!colnames(object) %in%
    c("A-empty", "B-empty", "A-lowboth-highmt", "B-lowboth-highmt", "001", "B-highRNA-only")]
  expect_identical(mad_integration_record(root, "strategy_validated")$selected_cells, expected)
  immutable_keys <- c("input", "prefilter", "qc_evidence", "qc_mad", "doublet_diagnostics", "strategy_evidence")
  immutable <- scAgentKit:::.sc_run_load(root)$files[immutable_keys]
  mad_integration_decide(root, node)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  restarted <- mad_integration_child(root)
  expect_identical(restarted$status$status, "awaiting_configuration")
  expect_identical(restarted$status$stage, "annotation_propose")
  expect_identical(restarted$detector_calls, 0L)
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[immutable_keys], immutable)
  mad_integration_preserved(mad_integration_record(root, "analysis"), object, expected)
  stages <- vapply(Filter(function(e) identical(e$action, "executed"), state$history),
    function(e) e$details$stage, character(1))
  graph <- c("prefilter", "strategy_evidence", "strategy_apply", "qc_apply", "strategy_selection",
    "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence")
  expect_true(all(graph %in% stages)); expect_true(all(diff(match(graph, stages)) > 0))
  mad_integration_unknown(root); annotation <- sc_run_inspect(root)
  expect_identical(annotation$review_node$kind, "annotation")
  mad_integration_decide(root, annotation)
  finished <- mad_integration_child(root)
  expect_identical(finished$status$status, "complete")
  output <- readRDS(finished$status$output$seurat)
  mad_integration_preserved(output, object, expected)
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_true(is.factor(output$old_annotation)); expect_true(anyNA(output$old_annotation))
  expect_true(all(c("1", "NA", "cell space") %in% colnames(output)))
  completed <- scAgentKit:::.sc_run_load(root)
  for (stage in c(graph, "annotation_apply", "finalize"))
    expect_identical(mad_integration_executions(completed, stage), 1L)
  decisions <- Filter(function(e) identical(e$action, "approved"), completed$history)
  expect_identical(vapply(decisions, function(e) e$details$kind, character(1)), c("strategy", "annotation"))
  bytes <- mad_integration_files(root)
  expect_identical(mad_integration_continue(root)$status, "complete")
  expect_identical(mad_integration_files(root), bytes)
  retained <- completed$files[c(immutable_keys, "qc_object", "strategy_selected", "strategy_preprocess", "strategy_basis", "analysis")]
  annotation_id <- completed$approvals[[completed$approved$hash]]$decision_id
  undone <- sc_run_undo(root, annotation_id, "offline MAD QA", "Undo only the synthetic Unknown annotation.")
  expect_identical(undone$status, "awaiting_configuration"); expect_identical(undone$stage, "annotation_propose")
  expect_identical(scAgentKit:::.sc_run_load(root)$files[names(retained)], retained)
  expect_error(sc_run_undo(root, annotation_id, "offline MAD QA", "Repeated undo control."), "already undone|No executed")
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_equal(detector$detector, 2L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("whole-panel candidate changes rebuild necessary QC work while reason-only and JSON edits reuse calculations", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  mad_integration_begin(root, object)
  mad_integration_revise(root, mad_integration_plan(root, "keep_all"))
  mad_integration_decide(root); mad_integration_continue(root)
  first <- scAgentKit:::.sc_run_load(root)
  immutable_keys <- c("input", "prefilter", "qc_evidence", "qc_mad", "doublet_diagnostics", "strategy_evidence")
  immutable <- first$files[immutable_keys]
  expect_identical(colnames(mad_integration_record(root, "analysis")), mad_integration_prefilter_ids(object))
  scientific_keys <- c("qc_object", "strategy_selected", "strategy_preprocess", "strategy_basis", "strategy_neighbors", "analysis", "markers", "annotation_evidence")
  scientific <- first$files[scientific_keys]
  plan <- mad_integration_plan(root, "keep_all")
  plan$qc$rationale <- "Only explanatory text changes; exact fixed rules remain identical."
  # Browser whole-object JSON changes numeric storage modes, not policy.
  browser <- jsonlite::fromJSON(jsonlite::toJSON(plan, auto_unbox = TRUE, null = "null"), simplifyVector = FALSE)
  mad_integration_revise(root, browser)
  second <- scAgentKit:::.sc_run_load(root)
  expect_identical(second$files[immutable_keys], immutable)
  expect_identical(second$files[scientific_keys], scientific)
  expect_identical(mad_integration_record(root, "strategy_validated")$dependency_hashes,
    readRDS(file.path(root, first$files$strategy_validated$path))$dependency_hashes)
  mad_integration_decide(root); mad_integration_continue(root)
  expect_identical(scAgentKit:::.sc_run_load(root)$files[scientific_keys], scientific)
  expect_identical(mad_integration_executions(scAgentKit:::.sc_run_load(root), "qc_apply"), 1L)
  for (step in seq_along(c("conservative_and3", "keep_all"))) {
    preset <- c("conservative_and3", "keep_all")[[step]]
    old_annotation <- sc_run_inspect(root)
    mad_integration_revise(root, mad_integration_plan(root, preset))
    revised <- scAgentKit:::.sc_run_load(root)
    expect_identical(revised$files[immutable_keys], immutable)
    for (key in scientific_keys) expect_null(revised$files[[key]])
    expect_error(mad_integration_continue(root, old_annotation), "[Ss]tale|revision")
    mad_integration_decide(root); mad_integration_child(root)
    state <- scAgentKit:::.sc_run_load(root)
    expected <- if (preset == "keep_all") mad_integration_prefilter_ids(object) else mad_integration_conservative_ids(object)
    mad_integration_preserved(mad_integration_record(root, "analysis"), object, expected)
    expect_identical(state$files[immutable_keys], immutable)
    for (stage in c("qc_apply", "strategy_selection", "strategy_preprocess", "strategy_basis",
      "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
      expect_identical(mad_integration_executions(state, stage), step + 1L)
  }
  expect_equal(detector$detector, 2L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("bounded MAD proposals reject invented operations and stale concurrent approvals without changing files", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  mad_integration_begin(root)
  mad_integration_revise(root, mad_integration_plan(root, "conservative_and3"))
  snapshot <- sc_run_inspect(root); bytes <- mad_integration_files(root)
  invalid <- list(
    list(preset_id = "best_for_my_labels"), list(panel_hash = strrep("0", 64L)),
    list(code = "system('false')"), list(k = 2), list(cell_ids = "001"),
    list(grouping = "donor"), list(filters = list(list(op = "range", metric = "nCount", min = 1))))
  for (fields in invalid) {
    proposal <- mad_integration_plan(root, "conservative_and3")
    for (key in names(fields)) proposal$qc[[key]] <- fields[[key]]
    expect_error(mad_integration_revise(root, proposal, snapshot))
    expect_identical(mad_integration_files(root), bytes)
  }
  legacy <- mad_integration_plan(root)
  legacy$qc <- list(schema = "scagentkit.qc.v1", rationale = "Legacy cannot silently replace MAD semantics.",
    risks = list("Explicitly select a legacy project instead."), filters = list(list(op = "range", metric = "nCount", min = 1)))
  expect_error(mad_integration_revise(root, legacy, snapshot), "MAD|schema|legacy|Unsupported")
  expect_identical(mad_integration_files(root), bytes)
  wrong <- snapshot; wrong$revision <- wrong$revision + 1L
  expect_error(mad_integration_revise(root, mad_integration_plan(root), wrong), "[Ss]tale|revision")
  wrong <- snapshot; wrong$review_node$review_hash <- strrep("0", 64L)
  expect_error(mad_integration_decide(root, wrong), "[Ss]tale|fingerprint|hash")
  wrong <- snapshot; wrong$input_hash <- strrep("0", 64L)
  expect_error(mad_integration_continue(root, wrong), "Foreign|changed input|[Ss]tale")
  expect_identical(mad_integration_files(root), bytes)
  lock <- scAgentKit:::.sc_run_lock(root); locked <- mad_integration_files(root)
  expect_error(mad_integration_decide(root, snapshot), "locked")
  expect_error(mad_integration_continue(root, snapshot), "locked")
  expect_error(mad_integration_revise(root, mad_integration_plan(root), snapshot), "locked")
  expect_identical(mad_integration_files(root), locked)
  scAgentKit:::.sc_run_release(root, lock)
  mad_integration_decide(root, snapshot); approved <- mad_integration_files(root)
  expect_identical(mad_integration_decide(root, snapshot)$stage, "strategy_apply")
  expect_identical(mad_integration_files(root), approved)
  expect_error(mad_integration_continue(root, snapshot), "[Ss]tale|revision")
  expect_identical(mad_integration_files(root), approved)
  expect_equal(detector$detector, 2L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("input panel prefilter and context changes cannot consume a whole-panel approval", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  base <- tempfile(); roots <- c(roots, base)
  mad_integration_begin(base)
  mad_integration_revise(base, mad_integration_plan(base, "conservative_and3"))
  mad_integration_decide(base); approved <- sc_run_inspect(base)
  for (key in c("input", "prefilter", "qc_mad", "qc_evidence", "strategy_evidence", "strategy_validated", "strategy_review")) {
    root <- mad_integration_copy(base); roots <- c(roots, root)
    state <- scAgentKit:::.sc_run_load(root)
    saveRDS(list(altered = paste("Tampered synthetic", key, "artifact")), file.path(root, state$files[[key]]$path))
    bytes <- mad_integration_files(root)
    expect_error(mad_integration_continue(root, approved), "[Ss]tale|changed")
    expect_error(sc_run_resume(root), "[Ss]tale|changed")
    expect_identical(mad_integration_files(root), bytes)
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  for (change in c("grouping", "k", "min_group_cells", "context", "prefilter")) {
    root <- mad_integration_copy(base); roots <- c(roots, root)
    state <- scAgentKit:::.sc_run_load(root)
    if (change == "grouping") state$config$qc_mad$grouping$column <- "capture" else
    if (change == "k") state$config$qc_mad$k <- 2 else
    if (change == "min_group_cells") state$config$qc_mad$min_group_cells <- 40L else
    if (change == "context") state$config$context$notes <- "Changed reviewed user context." else
      state$config$prefilter$min_counts <- 2
    state$config_hash <- scAgentKit:::.sc_run_hash(state$config)
    scAgentKit:::.sc_run_save(root, state); bytes <- mad_integration_files(root)
    expect_error(mad_integration_continue(root, approved), "[Ss]tale|changed|fingerprint|approval|scope|differ")
    expect_identical(mad_integration_files(root), bytes)
  }
  expect_equal(detector$detector, 2L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("an interrupted approved MAD selection needs explicit retry and never repeats prefilter panel or capture scoring", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture()
  mad_integration_begin(root, object)
  mad_integration_revise(root, mad_integration_plan(root, "conservative_and3", "remove_predicted"))
  mad_integration_decide(root)
  withr::local_options(list(scAgentKit.continue_crash = "strategy_selection:before"))
  capture.output(failed <- mad_integration_continue(root))
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "strategy_selection")
  expect_match(failed$failure$message, "Injected local continuation failure")
  state <- scAgentKit:::.sc_run_load(root)
  retained_keys <- c("input", "prefilter", "qc_evidence", "qc_mad", "doublet_diagnostics", "strategy_evidence", "qc_object")
  retained <- state$files[retained_keys]
  expect_null(state$files$strategy_selected)
  expect_identical(colnames(mad_integration_record(root, "qc_object")), mad_integration_conservative_ids(object))
  bytes <- mad_integration_files(root)
  expect_identical(mad_integration_continue(root)$status, "failed")
  expect_identical(sc_run_resume(root)$status, "failed")
  expect_identical(mad_integration_files(root), bytes)
  options(scAgentKit.continue_crash = NULL)
  resumed <- mad_integration_continue(root, retry = TRUE)
  expect_identical(resumed$status, "awaiting_configuration"); expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[retained_keys], retained)
  for (stage in c("prefilter", "strategy_evidence", "qc_apply", "strategy_selection", "strategy_preprocess",
    "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
    expect_identical(mad_integration_executions(state, stage), 1L)
  expect_true(any(vapply(state$history, function(e) identical(e$action, "local_continue_retry_requested"), logical(1))))
  expect_equal(detector$detector, 2L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("a mock provider chooses only the saved aggregate preset panel and cache avoids another request", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  calls <- 0L; seen <- NULL
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    seen <<- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    plan <- mad_integration_plan(root, "conservative_and3")
    list(content = as.character(jsonlite::toJSON(plan, auto_unbox = TRUE, null = "null")),
      cost_usd = 0, usage = list(input_tokens = 0L, output_tokens = 0L))
  }
  provider <- list(name = "mock", external = FALSE, model = "bounded-local-MAD-proposal-only")
  begun <- mad_integration_begin(root, object, provider = provider, chat_fn = callback)
  expect_identical(begun$status, "awaiting_review"); expect_identical(calls, 1L)
  expect_identical(seen$evidence$quality$mad$panel_hash, mad_integration_record(root, "qc_mad")$panel_hash)
  state <- scAgentKit:::.sc_run_load(root); request <- mad_integration_record(root, "strategy_request")
  for (private in c("A-lowboth-highmt", "B-highRNA-only", "Private per-cell control", '"cell_id"', '"scores"', '"private"'))
    expect_false(grepl(private, request$user_prompt, fixed = TRUE))
  expect_null(state$files$qc_object); expect_null(state$files$analysis)
  bytes <- mad_integration_files(root)
  expect_identical(sc_run_resume(root, chat_fn = callback)$status, "awaiting_review")
  expect_identical(mad_integration_continue(root)$status, "awaiting_review")
  expect_identical(mad_integration_files(root), bytes); expect_identical(calls, 1L)
  evidence <- mad_integration_record(root, "strategy_evidence")
  request$validator <- function(value) scAgentKit:::.sc_run_strategy_validate(value, evidence)$proposal
  ledger <- file.path(root, "provider", "ledger.json"); ledger_hash <- scAgentKit:::.sc_project_sha_file(ledger)
  cached <- scAgentKit:::.sc_run_call(root, request, provider = provider, chat_fn = callback, budget = 0)
  expect_identical(cached$status, "ok"); expect_true(cached$cached)
  expect_equal(cached$charged_or_held_usd, 0); expect_identical(calls, 1L)
  expect_identical(scAgentKit:::.sc_project_sha_file(ledger), ledger_hash)
  mad_integration_decide(root); mad_integration_continue(root)
  expect_identical(calls, 1L); expect_equal(detector$detector, 2L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("small quality strata block partial filtering while an all-prefilter-excluded group remains known zero", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture()
  object$qc_group[1:10] <- "tiny declared stratum"
  object$qc_group[match("A-empty", colnames(object))] <- "all-prefilter-excluded stratum"
  context <- mad_integration_context(); context$columns$qc_group <- "qc_group"
  begun <- mad_integration_begin(root, object, options = mad_integration_options(role = "qc_group"),
    doublet = FALSE, context = context)
  expect_identical(begun$status, "awaiting_configuration")
  record <- mad_integration_record(root, "qc_mad")
  find_group <- function(value) Filter(function(group) identical(group$value, value), record$summary$groups)[[1L]]
  small <- find_group("tiny declared stratum")
  expect_equal(small$before, 10L); expect_equal(small$pre_score, 10L)
  expect_false(small$metrics$nCount$available)
  expect_match(paste(small$metrics$nCount$unavailable_reasons, collapse = " "), "Fewer than 30")
  empty <- find_group("all-prefilter-excluded stratum")
  expect_equal(empty$before, 1L); expect_equal(empty$pre_score, 0L)
  expect_equal(empty$flags$low_count, 0L)
  presets <- stats::setNames(record$summary$presets,
    vapply(record$summary$presets, `[[`, character(1), "preset_id"))
  expect_true(presets$keep_all$available)
  expect_equal(presets$keep_all$retained, 254L)
  expect_false(presets$conservative_and3$available)
  impact_empty <- Filter(function(group) identical(group$value, "all-prefilter-excluded stratum"),
    presets$conservative_and3$groups)[[1L]]
  impact_small <- Filter(function(group) identical(group$value, "tiny declared stratum"),
    presets$conservative_and3$groups)[[1L]]
  expect_identical(impact_empty$retained, 0L)
  expect_true(impact_empty$empty_after_quality)
  expect_null(impact_small$retained); expect_null(impact_small$fraction_retained)
  bytes <- mad_integration_files(root)
  expect_error(mad_integration_revise(root, mad_integration_plan(root, "conservative_and3")), "unavailable")
  expect_identical(mad_integration_files(root), bytes)
  expect_identical(mad_integration_revise(root, mad_integration_plan(root, "keep_all"))$status, "awaiting_review")
  expect_identical(mad_integration_record(root, "qc_validated")$keep_cells, mad_integration_prefilter_ids(object))
  expect_identical(sc_run_inspect(root)$review_node$kind, "strategy")
  expect_identical(detector$detector, 0L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("zero MAD or absent mt diagnostics allow explicit keep without inventing executable deletion rules", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  zero <- mad_integration_fixture()
  counts <- SeuratObject::LayerData(zero, layer = "counts")
  for (cell in colnames(zero)[1:40]) counts[, cell] <- counts[, "A-base005", drop = FALSE]
  SeuratObject::LayerData(zero, layer = "counts") <- counts
  zero$qc_group[1:40] <- "zero MAD declared stratum"
  missing_mt <- mad_integration_fixture()[setdiff(rownames(mad_integration_fixture()), "MT-CO1"), ]
  for (kind in c("zero", "missing_mt")) {
    root <- tempfile(); roots <- c(roots, root)
    object <- if (kind == "zero") zero else missing_mt
    context <- mad_integration_context()
    options <- mad_integration_options()
    if (kind == "zero") { context$columns$qc_group <- "qc_group"; options <- mad_integration_options(role = "qc_group") }
    begun <- mad_integration_begin(root, object, options = options, doublet = FALSE, context = context)
    expect_identical(begun$status, "awaiting_configuration")
    record <- mad_integration_record(root, "qc_mad")
    if (kind == "zero") {
      group <- Filter(function(group) identical(group$value, "zero MAD declared stratum"), record$summary$groups)[[1L]]
      expect_equal(group$metrics$nCount$exact$scaled_mad, 0)
      expect_match(paste(group$metrics$nCount$unavailable_reasons, collapse = " "), "zero or near zero")
      expect_false(group$metrics$nCount$available)
    } else {
      expect_false(mad_integration_record(root, "qc_evidence")$summary$mitochondrial$available)
      expect_true(all(is.na(record$metrics$percent_mt)))
      expect_true(all(is.na(record$flags$high_mt)))
    }
    bytes <- mad_integration_files(root)
    expect_error(mad_integration_revise(root, mad_integration_plan(root, "conservative_and3")), "unavailable")
    expect_identical(mad_integration_files(root), bytes)
    expect_identical(mad_integration_revise(root, mad_integration_plan(root, "keep_all"))$status, "awaiting_review")
    expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  }
  expect_identical(detector$detector, 0L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("MAD and minimal prefilter declarations fail closed before guessing groups or accepting duplicate IDs", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture()
  failures <- list()
  absent <- mad_integration_options(); absent$grouping <- NULL
  failures[["no implicit grouping"]] <- absent
  donor <- mad_integration_options(); donor$grouping$declared_role <- "donor"; donor$grouping$column <- "donor"
  failures[["no donor substitution"]] <- donor
  capture <- mad_integration_options(); capture$grouping$column <- "capture"
  failures[["capture is not sample"]] <- capture
  undeclared <- mad_integration_options(); undeclared$grouping$declared_role <- "qc_group"; undeclared$grouping$column <- "qc_group"
  failures[["quality role must be in context"]] <- undeclared
  constant <- mad_integration_options(); constant$mad_constant <- 1
  failures[["no unreviewed MAD constant"]] <- constant
  missing_approval <- mad_integration_options(); missing_approval$prefilter$preapproved <- FALSE
  failures[["prefilter needs explicit preapproval"]] <- missing_approval
  aggressive <- mad_integration_options(); aggressive$prefilter$min_counts <- 201
  failures[["only bounded minimal prefilter"]] <- aggressive
  source <- mad_integration_options(); source$prefilter$source <- ""
  failures[["prefilter needs sourced provenance"]] <- source
  for (options in failures) {
    root <- tempfile(); roots <- c(roots, root)
    expect_error(mad_integration_begin(root, object, options = options))
    expect_false(file.exists(file.path(root, "state.rds")))
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  duplicate <- SeuratObject::LayerData(object, layer = "counts")
  colnames(duplicate)[2L] <- "001"
  root <- tempfile(); roots <- c(roots, root)
  expect_error(mad_integration_begin(root, duplicate, doublet = FALSE), "unique")
  expect_false(file.exists(file.path(root, "state.rds")))
  expect_identical(detector$detector, 0L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("MAD-only final output rejects an unauthorized subset or reordered approved cells before publishing artifacts", {
  network <- mad_integration_sentinels(); detector <- mad_integration_detector()
  root <- tempfile(); probes <- character()
  on.exit(unlink(c(root, probes), recursive = TRUE), add = TRUE)
  object <- mad_integration_fixture()
  mad_integration_begin(root, object, doublet = FALSE)
  mad_integration_revise(root, mad_integration_plan(root, "conservative_and3"))
  mad_integration_decide(root)
  expect_identical(mad_integration_continue(root)$stage, "annotation_propose")
  mad_integration_unknown(root); mad_integration_decide(root)
  finished <- mad_integration_continue(root)
  expect_identical(finished$status, "complete")
  state <- scAgentKit:::.sc_run_load(root)
  validated <- mad_integration_record(root, "strategy_validated")
  expect_null(validated$selected_cells) # MAD-only has no doublet selection field.
  expected <- mad_integration_conservative_ids(object)
  expect_identical(validated$qc_validated$keep_cells, expected)
  output <- readRDS(finished$output$seurat)
  expect_identical(colnames(output), expected)
  summary <- jsonlite::fromJSON(file.path(root, "output", "qc_mad_summary.json"), simplifyVector = FALSE)
  expect_identical(unlist(summary$actual_retained_cell_ids, use.names = FALSE), expected)
  review <- mad_integration_record(root, "strategy_review")
  for (kind in c("subset", "reordered")) {
    probe <- mad_integration_copy(root); probes <- c(probes, probe)
    # Retain exact scientific checkpoints but start with an empty output sink:
    # a rejected object cannot leave a success summary, CSV, or plot behind.
    unlink(file.path(probe, "output"), recursive = TRUE)
    dir.create(file.path(probe, "output"))
    requested <- if (kind == "subset") expected[-1L] else rev(expected)
    # Seurat subsetting preserves its source cell order. Construct this probe
    # from the public sparse layer to establish a genuinely reordered object.
    bad <- if (kind == "subset") output[, requested] else
      Seurat::CreateSeuratObject(SeuratObject::LayerData(output, assay = "RNA", layer = "counts")
        [, requested, drop = FALSE], min.cells = 0, min.features = 0)
    expect_identical(colnames(bad), requested)
    expect_equal(ncol(bad), length(requested))
    before <- mad_integration_files(probe)
    expect_error(scAgentKit:::.sc_run_mad_outputs(probe, state, bad, review),
      "Final cell IDs/order differ from the exact approved MAD selection")
    expect_identical(mad_integration_files(probe), before)
    expect_length(list.files(file.path(probe, "output"), all.files = TRUE, no.. = TRUE), 0L)
    expect_false(file.exists(file.path(probe, "output", "qc_mad_summary.json")))
  }
  expect_identical(detector$detector, 0L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
