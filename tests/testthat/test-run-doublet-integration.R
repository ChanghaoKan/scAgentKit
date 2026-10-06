# Synthetic coordinator controls only: the detector below returns planted
# predictions, not scDblFinder results or scientific doublet ground truth.
# Root acceptance separately executes the installed algorithm on public data.

doublet_integration_fixture <- function() {
  set.seed(999L)
  genes <- sc_cycle_gene_set("human")
  cycle <- unique(c(genes$s_genes, genes$g2m_genes))
  features <- c("MT-CO1", cycle, paste0("DoubletBackground", seq_len(320L)))
  cells <- c("001", "1", "NA", "cell space", paste0("literalDoubletCell", 5:202))
  counts <- matrix(stats::rpois(length(features) * length(cells), 2),
    nrow = length(features), dimnames = list(features, cells))
  for (program in seq_len(4L)) {
    chosen <- paste0("DoubletBackground", seq.int((program - 1L) * 16L + 1L, program * 16L))
    selected <- seq.int((program - 1L) * 50L + 1L, program * 50L)
    counts[chosen, selected] <- counts[chosen, selected] + 12L
  }
  counts[genes$s_genes, 1:67] <- counts[genes$s_genes, 1:67] + 9L
  counts[genes$g2m_genes, 68:134] <- counts[genes$g2m_genes, 68:134] + 9L
  # Both captures have 101 cells and every cell has at least 200 reads before
  # diagnosis. The exact 200-read cell is a separate, positive-count QC control.
  counts[, 202L] <- 0L
  counts["MT-CO1", 202L] <- 200L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <-
    log1p(Matrix::Matrix(counts * 7L, sparse = TRUE))
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object$capture <- rep(c("capture A", "capture B"), each = 101L)
  object$donor <- rep(c("donor A", "donor B"), 101L)
  object$sample <- rep(c("sample A", "sample B"), 101L)
  object$group <- rep(c("Ca", "Ctrl"), 101L)
  object$source_cluster <- factor(rep(c("01", "NA"), each = 101L),
    levels = c("NA", "01", "unused cluster"))
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 101L),
    levels = c("prior A", "unused prior B"))
  object$scDblFinder.score <- seq_len(ncol(object)) / 1000
  object$scDblFinder.class <- factor(rep(c("old call", NA_character_), 101L),
    levels = c("old call", "unused old call"))
  object$private_note <- "Per-cell private metadata stays local in this software fixture."
  object
}

doublet_integration_context <- function(species = "human") list(species = species,
  tissue = "synthetic", columns = list(sample = "sample", capture = "capture",
    donor = "donor", group = "group"),
  design = list(type = "synthetic crossed donor and capture controls",
    notes = "A capture is explicitly a loading unit, not inferred from donor or condition."),
  research_goal = "Review software doublet predictions before any optional cell deletion.",
  notes = "Synthetic workflow acceptance only; neither score nor class is ground truth.")

doublet_integration_options <- function(single = FALSE) list(data_type = "scrna_droplet",
  input_source = "Planted count-positive sparse software fixture, not biological validation.",
  empty_droplets_removed = TRUE,
  capture = if (single) list(method = "single", id = "declared loading unit",
    source = "Explicit single-capture declaration for this synthetic software control.") else
    list(method = "column", column = "capture",
      source = "The fixture creator explicitly supplied each cell's literal loading unit."),
  rate = list(method = "manual", value = .05,
    source = "A declared software-control rate; not a recommended biological doublet rate.", sd = .02),
  seed = 999L, column_prefix = "sc_doublet", nfeatures = 200L,
  dims = 10L, artificial_doublets = 1500L)

doublet_integration_plan <- function(method = NULL, cycle = NULL) {
  proposal <- list(schema = "scagentkit.strategy.v1",
    rationale = "Review exact count-positive QC and planted doublet predictions together.",
    risks = list("Predicted doublets and Unknown annotations are software controls, not biological truth."),
    inferences = list("No synthetic donor, condition, or score implies a biological cell identity."),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "Remove only the planted exact 200-count QC control.",
      risks = list("This software cutoff is not a recommended QC threshold."),
      filters = list(list(op = "range", metric = "nCount", min = 201L))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 80L, npcs = 10L, seed = 999L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No integration is requested for crossed synthetic controls."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
    umap = list(run = FALSE, n_neighbors = 10L))
  if (!is.null(method)) proposal$doublet <- list(method = method,
    reason = paste("Explicitly review", method, "for saved synthetic predictions."))
  if (!is.null(cycle)) proposal$cycle <- list(method = cycle,
    reason = "Review the distinct cycle regression policy without deleting cycling cells.")
  proposal
}

doublet_integration_begin <- function(root, object = doublet_integration_fixture(),
                                        proposal = doublet_integration_plan(),
                                        options = doublet_integration_options(),
                                        context = doublet_integration_context(),
                                        cycle = NULL, provider = NULL, chat_fn = NULL,
                                        start_stage = "qc") {
  extra <- if (start_stage == "processed") list(cluster_column = "source_cluster",
    processed_reason = "Explicit supplied sparse normalized data and literal clusters are reused.") else list()
  suppressWarnings(do.call(sc_run, c(list(input = object, project_dir = root,
    context = context, strategy = TRUE, strategy_proposal = proposal,
    doublet_diagnostics = options, cycle_diagnostics = cycle,
    provider = provider, chat_fn = chat_fn, budget = 0,
    annotation_column = "reviewed_type", start_stage = start_stage), extra)))
}

doublet_integration_continue <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, retry = retry))
}

doublet_integration_decide <- function(root, snapshot = sc_run_inspect(root), action = "approve") {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline doublet QA", reason = "Review exactly this synthetic whole-strategy scope.")
}

doublet_integration_revise <- function(root, proposal, snapshot = sc_run_inspect(root)) {
  sc_run_strategy_revise(root, proposal, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, "offline doublet QA", "Revise an explicit typed software-control policy.")
}

doublet_integration_unknown <- function(root) {
  evidence <- sc_run_inspect(root)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(evidence$clusters, function(row) list(clusterId = row$clusterId,
      label = "Unknown", confidence = "low",
      rationale = "Synthetic predictions do not establish biological cell identities.",
      markers = list())))
  sc_run_propose(root, proposal, "offline doublet QA", "Review explicit Unknown controls independently.")
}

doublet_integration_files <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  paths <- paths[!dir.exists(paths)]
  stats::setNames(vapply(paths, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(paths, nchar(root) + 2L))
}

doublet_integration_copy <- function(root) {
  target <- tempfile("doublet-copy-"); dir.create(target)
  if (!all(file.copy(list.files(root, full.names = TRUE, all.files = TRUE, no.. = TRUE),
                     target, recursive = TRUE, copy.mode = TRUE)))
    stop("Could not copy the stopped synthetic doublet project.")
  target
}

doublet_integration_executions <- function(state, stage) {
  length(Filter(function(event) identical(event$action, "executed") &&
    identical(event$details$stage, stage), state$history))
}

doublet_integration_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) {
    calls$factory <- calls$factory + 1L
    stop("Offline doublet acceptance prohibits remote provider factories.")
  }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L
    stop("Offline doublet acceptance prohibits network dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

doublet_integration_detector <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$detector <- 0L; calls$captures <- list(); calls$mode <- "ok"
  # Predictions bind literal source IDs, not algorithm call positions. The
  # adapter is free to sort each capture without changing the QC overlap.
  predicted_cells <- c("001", paste0("literalDoubletCell",
    c(seq.int(11L, 101L, by = 10L), seq.int(102L, 202L, by = 10L))))
  detector <- function(counts, options, rate, seed) {
    calls$detector <- calls$detector + 1L
    if (isTRUE(getOption("fixture_forbid_doublet_detector")))
      stop("Saved fixture doublet predictions must not be recomputed in this R process.")
    calls$captures[[length(calls$captures) + 1L]] <- list(cells = colnames(counts),
      features = rownames(counts), rate = rate, seed = seed,
      sparse = inherits(counts, "sparseMatrix"))
    if (identical(calls$mode, "error")) stop("Injected synthetic doublet detector error.")
    cells <- colnames(counts)
    predicted <- cells %in% predicted_cells
    values <- data.frame(cell_id = cells, score = ifelse(predicted, .8, .05),
      class = ifelse(predicted, "doublet", "singlet"),
      stringsAsFactors = FALSE, row.names = cells)
    if (identical(calls$mode, "malformed")) values$cell_id <- rev(values$cell_id)
    audit <- list(train_attempts = 3L, train_successes = 3L,
      predict_attempts = 3L, predict_successes = 3L,
      training_errors = character(), prediction_errors = character(), test_only_mock = TRUE)
    if (identical(calls$mode, "fallback")) {
      audit$train_successes <- 0L
      audit$training_errors <- "Injected classifier fallback with superficially finite scores."
    }
    list(scores = values, threshold = .5,
      warnings = if (identical(calls$mode, "warning")) "Injected fixture classifier warning." else character(),
      messages = character(), classifier_audit = audit,
      adapter_source_hashes = scAgentKit:::.sc_run_doublet_classifier_source_hashes())
  }
  environment(detector) <- list2env(list(calls = calls,
    predicted_cells = predicted_cells), parent = baseenv())
  dependencies <- function() {
    if (isTRUE(getOption("fixture_missing_doublet_dependency")))
      stop("Required dependency 'scDblFinder' is unavailable in this synthetic dependency control.")
    invisible(TRUE)
  }
  versions <- function() list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
    fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution.",
    SingleCellExperiment = "software-mock-unexecuted")
  environment(dependencies) <- baseenv(); environment(versions) <- baseenv()
  testthat::local_mocked_bindings(.sc_run_doublet_detect_one = detector,
    .sc_run_doublet_dependencies = dependencies, .sc_run_doublet_versions = versions,
    .package = "scAgentKit", .env = env)
  calls
}

# A child process resumes only saved diagnostics and locally approved work.
# It cannot repeat a detector computation, instantiate a provider, or dispatch HTTP.
doublet_integration_child <- function(root, snapshot = sc_run_inspect(root)) {
  work <- tempfile("doublet-child-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  arguments <- file.path(work, "arguments.rds"); result <- file.path(work, "result.rds")
  script <- file.path(work, "child.R"); log <- file.path(work, "stdout.log")
  bindings <- lapply(c(".sc_run_doublet_detect_one", ".sc_run_doublet_dependencies",
    ".sc_run_doublet_versions"), get, envir = asNamespace("scAgentKit"))
  names(bindings) <- c(".sc_run_doublet_detect_one", ".sc_run_doublet_dependencies",
    ".sc_run_doublet_versions")
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path"),
    bindings = bindings), arguments)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','GROK_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','AZURE_OPENAI_API_KEY','COHERE_API_KEY','MISTRAL_API_KEY','OPENROUTER_API_KEY','HF_TOKEN','HUGGINGFACEHUB_API_TOKEN'))",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else library(scAgentKit,lib.loc=dirname(args$package))",
    "factory_calls <- 0L; http_calls <- 0L",
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('No remote doublet factory permitted') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('No doublet HTTP permitted') },.package='httr2',.env=environment())",
    "do.call(testthat::local_mocked_bindings,c(args$bindings,list(.package='scAgentKit',.env=environment())))",
    "options(fixture_forbid_doublet_detector=TRUE)",
    "detector <- args$bindings[['.sc_run_doublet_detect_one']]",
    "detector_before <- environment(detector)$calls$detector",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision))",
    "detector_calls <- environment(detector)$calls$detector-detector_before",
    "stopifnot(factory_calls==0L,http_calls==0L,detector_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls,detector_calls=detector_calls),args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(arguments)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result))
    stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

doublet_integration_preserved <- function(object, source, cells, processed = FALSE) {
  expect_identical(colnames(object), cells)
  expect_identical(rownames(object), rownames(source))
  for (column in names(source[[]]))
    expect_identical(object[[]][[column]], source[[]][cells, column])
  for (layer in c("counts", "extra", if (processed) "data")) {
    actual <- SeuratObject::LayerData(object, assay = "RNA", layer = layer)
    expect_identical(actual,
      SeuratObject::LayerData(source, assay = "RNA", layer = layer)[, cells, drop = FALSE])
    expect_true(inherits(actual, "sparseMatrix"))
  }
  expect_true(inherits(SeuratObject::LayerData(object, assay = "RNA", layer = "data"), "sparseMatrix"))
}

doublet_integration_scores <- function(object, record) {
  cells <- colnames(object)
  expected <- record$scores[match(cells, record$scores$cell_id),
    unname(record$summary$columns), drop = FALSE]
  for (column in names(expected)) expect_identical(object[[]][[column]], expected[[column]])
}

test_that("fixed capture predictions precede one strategy review and keep never deletes predicted doublets", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  expect_equal(table(object$capture), c("capture A" = 101L, "capture B" = 101L), ignore_attr = TRUE)
  expect_true(all(Matrix::colSums(SeuratObject::LayerData(object, layer = "counts")) >= 200))
  begun <- doublet_integration_begin(root, object)
  expect_identical(begun$status, "awaiting_review")
  snapshot <- sc_run_inspect(root); state <- scAgentKit:::.sc_run_load(root)
  record <- scAgentKit:::.sc_run_get(root, state, "doublet_diagnostics")
  expect_identical(snapshot$review_node$kind, "strategy")
  expect_identical(snapshot$strategy_review$details$canonical_proposal$doublet$method, "keep")
  expect_identical(record$summary$status, "available")
  expect_identical(record$summary$reference, "fixed_full_input")
  expect_false(record$summary$refit_after_qc)
  expect_identical(record$cell_ids, colnames(object))
  expect_equal(record$summary$cohort$input_cells, 202L)
  expect_equal(record$summary$cohort$removed_cells, 0L)
  expect_equal(record$summary$cohort$predicted_doublets, 22L)
  expect_identical(record$summary$scoring$function_name, "scDblFinder::scDblFinder")
  expect_identical(record$summary$scoring$versions[c("scDblFinder", "xgboost", "fixture_scope")],
    list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
      fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."))
  expect_equal(detector$detector, 2L)
  expect_identical(detector$captures[[1L]]$cells, sort(enc2utf8(colnames(object)[1:101]), method = "radix"))
  expect_identical(detector$captures[[2L]]$cells, sort(enc2utf8(colnames(object)[102:202]), method = "radix"))
  expect_identical(detector$captures[[1L]]$features, sort(enc2utf8(rownames(object)), method = "radix"))
  expect_identical(detector$captures[[2L]]$features, sort(enc2utf8(rownames(object)), method = "radix"))
  expect_equal(vapply(detector$captures, function(x) x$rate, numeric(1)), c(.05, .05))
  expect_equal(vapply(detector$captures, function(x) x$seed, integer(1)),
    vapply(c("capture A", "capture B"), function(capture)
      scAgentKit:::.sc_run_doublet_seed(999L, capture), integer(1)), ignore_attr = TRUE)
  expect_true(all(vapply(detector$captures, function(x) x$sparse, logical(1))))
  expect_identical(snapshot$strategy_review$details$doublet_diagnostics, record$summary)
  expect_null(snapshot$strategy_review$details$doublet_diagnostics$cell_ids)
  expect_null(snapshot$strategy_review$details$doublet_diagnostics$scores)
  impact <- snapshot$strategy_review$details$applicability$doublet
  expect_identical(impact$qc_keep_cell_ids, colnames(object)[1:201])
  expect_identical(impact$selected_cell_ids, colnames(object)[1:201])
  expect_identical(impact$removed_cell_ids, character())
  expect_equal(impact$predicted_after_qc, 21L)
  expect_equal(impact$predicted_qc_excluded, 1L)
  expect_false(impact$scores_are_calibrated_probabilities)
  expect_false(impact$predictions_are_truth)
  expect_null(state$files$qc_object); expect_null(state$files$strategy_selected)
  expect_identical(serialize(scAgentKit:::.sc_run_get(root, state, "input"), NULL, version = 2L), original)
  bytes <- doublet_integration_files(root)
  expect_identical(doublet_integration_continue(root)$status, "awaiting_review")
  expect_identical(doublet_integration_files(root), bytes)
  doublet_integration_decide(root)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  stopped <- doublet_integration_child(root)
  expect_identical(stopped$status$status, "awaiting_configuration")
  expect_identical(stopped$status$stage, "annotation_propose")
  expect_identical(stopped$detector_calls, 0L)
  expect_null(sc_run_inspect(root)$review_node)
  state <- scAgentKit:::.sc_run_load(root)
  qc <- scAgentKit:::.sc_run_get(root, state, "qc_object")
  selected <- scAgentKit:::.sc_run_get(root, state, "strategy_selected")
  analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
  expect_identical(colnames(qc), colnames(object)[1:201])
  expect_false(any(startsWith(names(qc[[]]), "sc_doublet_")))
  doublet_integration_preserved(selected, object, colnames(object)[1:201])
  doublet_integration_preserved(analysis, object, colnames(object)[1:201])
  doublet_integration_scores(analysis, record)
  expect_equal(sum(analysis$sc_doublet_class == "doublet"), 21L)
  stages <- vapply(Filter(function(e) identical(e$action, "executed"), state$history),
    function(e) e$details$stage, character(1))
  expected <- c("strategy_evidence", "strategy_apply", "qc_apply", "strategy_selection",
    "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence")
  expect_true(all(expected %in% stages)); expect_true(all(diff(match(expected, stages)) > 0))
  expect_gt(nrow(scAgentKit:::.sc_run_get(root, state, "markers")$markers), 0L)
  doublet_integration_unknown(root); annotation <- sc_run_inspect(root)
  expect_identical(annotation$review_node$kind, "annotation")
  doublet_integration_decide(root, annotation)
  final <- doublet_integration_child(root)
  expect_identical(final$status$status, "complete")
  expect_identical(final$factory_calls, 0L); expect_identical(final$http_calls, 0L)
  expect_identical(final$detector_calls, 0L)
  output <- readRDS(final$status$output$seurat)
  doublet_integration_preserved(output, object, colnames(object)[1:201])
  doublet_integration_scores(output, record)
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_true(is.factor(output$old_annotation)); expect_true(anyNA(output$old_annotation))
  expect_true(is.factor(output$scDblFinder.class)); expect_true(anyNA(output$scDblFinder.class))
  expect_true(file.exists(file.path(root, "output", "doublet_summary.json")))
  expect_true(file.exists(file.path(root, "output", "doublet_diagnostics.png")))
  completed <- scAgentKit:::.sc_run_load(root)
  decisions <- Filter(function(e) identical(e$action, "approved"), completed$history)
  expect_identical(vapply(decisions, function(e) e$details$kind, character(1)), c("strategy", "annotation"))
  bytes <- doublet_integration_files(root)
  expect_identical(doublet_integration_continue(root)$status, "complete")
  expect_identical(doublet_integration_files(root), bytes)
  # Annotation undo restores an independent review boundary and leaves the
  # already reviewed cell selection, original counts, and predictions intact.
  retained <- completed$files[c("input", "doublet_diagnostics", "qc_object", "strategy_selected",
    "strategy_preprocess", "strategy_basis", "strategy_neighbors", "analysis", "markers")]
  annotation_id <- completed$approvals[[completed$approved$hash]]$decision_id
  undone <- sc_run_undo(root, annotation_id, "offline doublet QA", "Undo only the applied Unknown software annotation.")
  expect_identical(undone$status, "awaiting_configuration")
  expect_identical(undone$stage, "annotation_propose")
  expect_identical(scAgentKit:::.sc_run_load(root)$files[names(retained)], retained)
  expect_error(sc_run_undo(root, annotation_id, "offline doublet QA", "Repeated undo control."), "already undone|No executed")
  doublet_integration_unknown(root); doublet_integration_decide(root)
  again <- doublet_integration_child(root)
  expect_identical(again$status$status, "complete")
  doublet_integration_scores(readRDS(again$status$output$seurat), record)
  for (stage in c("strategy_evidence", "qc_apply", "strategy_selection", "strategy_preprocess",
                  "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers"))
    expect_identical(doublet_integration_executions(scAgentKit:::.sc_run_load(root), stage), 1L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(detector$detector, 2L)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("keep remove and keep revisions rebuild only selection and downstream work from pure saved QC", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  cycle <- list(gene_set = sc_cycle_gene_set("human"), column_prefix = "sc_cycle",
    seed = 17L, nbin = 12L, ctrl = 5L, scale_factor = 10000,
    min_genes = 5L, min_fraction = .2)
  initial_plan <- doublet_integration_plan("keep", "none")
  initial_plan$qc$filters[[1L]]$min <- 201 # Authored R double, like a saved public QC proposal.
  doublet_integration_begin(root, object, proposal = initial_plan, cycle = cycle)
  doublet_integration_decide(root); doublet_integration_continue(root)
  first <- scAgentKit:::.sc_run_load(root)
  record <- scAgentKit:::.sc_run_get(root, first, "doublet_diagnostics")
  cycle_record <- scAgentKit:::.sc_run_get(root, first, "cycle_diagnostics")
  expect_identical(cycle_record$summary$status, "available")
  immutable_keys <- c("input", "qc_evidence", "cycle_diagnostics", "doublet_diagnostics",
    "strategy_evidence", "qc_validated", "qc_object")
  refs <- first$files[immutable_keys]
  original_qc_hash <- scAgentKit:::.sc_run_get(root, first, "strategy_validated")$dependency_hashes$qc
  qc_ids <- colnames(object)[1:201]
  predicted <- qc_ids[qc_ids %in% record$predicted_cells]
  previous <- first
  for (method in c("remove_predicted", "keep")) {
    doublet_integration_unknown(root); doublet_integration_decide(root)
    old_annotation <- sc_run_inspect(root); before <- scAgentKit:::.sc_run_load(root)
    old_bytes <- doublet_integration_files(root)
    # A browser sends the entire saved proposal through JSON even when only
    # the doublet choice changes. JSON represents the R double bound 201 as
    # an integer token; this representational change must not rerun pure QC.
    proposal <- old_annotation$strategy_review$details$canonical_proposal
    expect_identical(proposal$qc$filters[[1L]]$min, 201)
    proposal <- jsonlite::fromJSON(as.character(jsonlite::toJSON(proposal,
      auto_unbox = TRUE, null = "null", digits = NA)), simplifyVector = FALSE)
    expect_identical(proposal$qc$filters[[1L]]$min, 201L)
    proposal$doublet <- list(method = method,
      reason = paste("Explicit JSON-roundtripped", method, "software policy; QC is unchanged."))
    revised <- doublet_integration_revise(root, proposal)
    expect_identical(revised$status, "awaiting_review")
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[immutable_keys], refs)
    expect_null(state$approved)
    expect_false(any(c("strategy_selected", "strategy_preprocess", "strategy_basis", "strategy_neighbors", "analysis",
      "markers", "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review", "annotated") %in% names(state$files)))
    expect_identical(state$history[seq_along(before$history)], before$history)
    expect_identical(state$approvals[[before$approved$hash]], before$approvals[[before$approved$hash]])
    old_bytes <- old_bytes[startsWith(names(old_bytes), "checkpoints/")]
    expect_identical(doublet_integration_files(root)[names(old_bytes)], old_bytes)
    expect_error(doublet_integration_decide(root, old_annotation), "[Ss]tale|different review kind")
    review <- sc_run_inspect(root)
    expect_identical(review$strategy_review$details$canonical_proposal$qc$filters[[1L]]$min, 201)
    expect_identical(review$strategy_review$details$dependency_hashes$qc, original_qc_hash)
    impact <- review$strategy_review$details$applicability$doublet
    expected_ids <- if (method == "keep") qc_ids else qc_ids[!qc_ids %in% predicted]
    removed <- if (method == "keep") character() else predicted
    expect_identical(impact$method, method)
    expect_identical(impact$qc_keep_cell_ids, qc_ids)
    expect_identical(impact$selected_cell_ids, expected_ids)
    expect_identical(impact$removed_cell_ids, removed)
    expect_equal(impact$removed_cells, length(removed))
    expect_equal(impact$retained_cells, length(expected_ids))
    expect_equal(impact$predicted_after_qc, 21L)
    expect_equal(impact$predicted_qc_excluded, 1L)
    expect_identical(names(impact$per_capture), c("capture A", "capture B"))
    expect_equal(impact$per_capture[["capture A"]]$qc_retained, 101L)
    expect_equal(impact$per_capture[["capture B"]]$qc_retained, 100L)
    expect_equal(impact$per_capture[["capture A"]]$removed, if (method == "keep") 0L else 11L)
    expect_equal(impact$per_capture[["capture B"]]$removed, if (method == "keep") 0L else 10L)
    expect_equal(impact$per_capture[["capture A"]]$removed_fraction_after_qc,
      if (method == "keep") 0 else 11 / 101)
    expect_equal(impact$per_capture[["capture B"]]$removed_fraction_after_qc,
      if (method == "keep") 0 else 10 / 100)
    expect_identical(impact$cycle$evidence_hash, cycle_record$evidence_hash)
    expect_equal(sum(unlist(impact$cycle$phase_by_scope$post_qc)), length(qc_ids))
    expect_equal(sum(unlist(impact$cycle$phase_by_scope$proposed_removed)), length(removed))
    expect_equal(sum(unlist(impact$cycle$phase_by_scope$retained)), length(expected_ids))
    expect_identical(review$strategy_review$details$canonical_proposal$cycle$method, "none")
    bytes <- doublet_integration_files(root)
    expect_identical(doublet_integration_continue(root)$status, "awaiting_review")
    expect_identical(doublet_integration_files(root), bytes)
    doublet_integration_decide(root, review)
    boundary <- doublet_integration_child(root)
    expect_identical(boundary$status$status, "awaiting_configuration")
    expect_identical(boundary$status$stage, "annotation_propose")
    expect_identical(boundary$detector_calls, 0L)
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[immutable_keys], refs)
    expect_false(identical(state$files$strategy_selected, previous$files$strategy_selected))
    expect_false(identical(state$files$strategy_preprocess, previous$files$strategy_preprocess))
    analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
    doublet_integration_preserved(analysis, object, expected_ids)
    doublet_integration_scores(analysis, record)
    for (column in unname(cycle_record$summary$columns))
      expect_identical(analysis[[]][[column]],
        cycle_record$scores[[column]][match(expected_ids, cycle_record$cell_ids)])
    expect_identical(colnames(scAgentKit:::.sc_run_get(root, state, "qc_object")), qc_ids)
    expect_identical(analysis@misc$strategy_execution$basis$regressors, character())
    for (stage in c("strategy_evidence", "qc_apply"))
      expect_identical(doublet_integration_executions(state, stage), 1L)
    expected_runs <- if (method == "remove_predicted") 2L else 3L
    for (stage in c("strategy_selection", "strategy_preprocess", "strategy_basis",
      "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
      expect_identical(doublet_integration_executions(state, stage), expected_runs)
    expect_identical(detector$detector, 2L)
    previous <- state
  }
  # The final keep state restores the original pure-QC scope from its saved
  # source, rather than trying to add cells back to the smaller derived object.
  doublet_integration_unknown(root); doublet_integration_decide(root)
  final <- doublet_integration_child(root)
  expect_identical(final$status$status, "complete")
  output <- readRDS(final$status$output$seurat)
  doublet_integration_preserved(output, object, qc_ids)
  doublet_integration_scores(output, record)
  expect_equal(sum(output$sc_doublet_class == "doublet"), 21L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("doublet review rejects arbitrary deletion fields stale snapshots and concurrent or repeated approval", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  doublet_integration_begin(root)
  snapshot <- sc_run_inspect(root); bytes <- doublet_integration_files(root)
  invalid <- list(
    list(method = "delete_high_score", reason = "Unsupported score-threshold operation."),
    list(method = "auto", reason = "A model cannot silently select or execute deletion."),
    list(method = "remove_predicted", reason = "No caller-supplied cell list.", cell_ids = "001"),
    list(method = "remove_predicted", reason = "No caller-supplied threshold.", threshold = .25),
    list(method = "remove_predicted", reason = "No donor regrouping of saved predictions.", capture_column = "donor"),
    list(method = "keep", reason = "No mutable rate inside a strategy choice.", rate = .1))
  for (choice in invalid) {
    proposal <- doublet_integration_plan(); proposal$doublet <- choice
    expect_error(doublet_integration_revise(root, proposal, snapshot))
    expect_identical(doublet_integration_files(root), bytes)
  }
  null <- doublet_integration_plan(); null["doublet"] <- list(NULL)
  expect_error(doublet_integration_revise(root, null, snapshot))
  expect_identical(doublet_integration_files(root), bytes)
  wrong <- snapshot; wrong$revision <- wrong$revision + 1L
  expect_error(doublet_integration_revise(root, doublet_integration_plan("remove_predicted"), wrong), "[Ss]tale|revision")
  wrong <- snapshot; wrong$project_id <- "foreign-doublet-project"
  expect_error(doublet_integration_continue(root, wrong), "Foreign project")
  wrong <- snapshot; wrong$review_node$review_hash <- strrep("0", 64L)
  expect_error(doublet_integration_decide(root, wrong), "[Ss]tale|fingerprint|review.*hash")
  expect_identical(doublet_integration_files(root), bytes)
  lock <- scAgentKit:::.sc_run_lock(root)
  locked <- doublet_integration_files(root)
  expect_error(doublet_integration_decide(root, snapshot), "locked")
  expect_error(doublet_integration_continue(root, snapshot), "locked")
  expect_error(doublet_integration_revise(root, doublet_integration_plan("remove_predicted"), snapshot), "locked")
  expect_identical(doublet_integration_files(root), locked)
  scAgentKit:::.sc_run_release(root, lock)
  expect_identical(doublet_integration_files(root), bytes)
  doublet_integration_decide(root, snapshot)
  approved <- doublet_integration_files(root)
  expect_identical(doublet_integration_decide(root, snapshot)$stage, "strategy_apply")
  expect_identical(doublet_integration_files(root), approved)
  expect_error(doublet_integration_continue(root, snapshot), "[Ss]tale|revision")
  expect_identical(doublet_integration_files(root), approved)
  expect_equal(detector$detector, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("changed source predictions or declared scoring scope cannot consume an approved removal", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  base <- tempfile(); roots <- c(roots, base)
  doublet_integration_begin(base, proposal = doublet_integration_plan("remove_predicted"))
  doublet_integration_decide(base); approved <- sc_run_inspect(base)
  for (key in c("input", "doublet_diagnostics", "strategy_evidence", "strategy_validated", "strategy_review")) {
    root <- doublet_integration_copy(base); roots <- c(roots, root)
    state <- scAgentKit:::.sc_run_load(root)
    path <- file.path(root, state$files[[key]]$path)
    value <- readRDS(path)
    if (key == "doublet_diagnostics") value$scores$sc_doublet_class[[1L]] <- "singlet" else
      value <- list(altered = paste("Synthetic tampered", key, "checkpoint"))
    saveRDS(value, path)
    bytes <- doublet_integration_files(root)
    expect_error(doublet_integration_continue(root, approved), "[Ss]tale|changed")
    expect_error(sc_run_resume(root), "[Ss]tale|changed")
    expect_identical(doublet_integration_files(root), bytes)
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  # An attacker recomputing the outer config checksum still cannot broaden
  # the exact scoring/capture/rate scope bound to the original approval.
  for (change in c("rate", "seed", "capture", "provenance")) {
    root <- doublet_integration_copy(base); roots <- c(roots, root)
    state <- scAgentKit:::.sc_run_load(root)
    if (change == "rate") state$config$doublet_diagnostics$rate$value <- .1 else
    if (change == "seed") state$config$doublet_diagnostics$seed <- 998L else
    if (change == "capture") state$config$doublet_diagnostics$capture$column <- "donor" else
      state$config$doublet_diagnostics$input_source <- "Changed software source provenance."
    state$config_hash <- scAgentKit:::.sc_run_hash(state$config)
    scAgentKit:::.sc_run_save(root, state)
    bytes <- doublet_integration_files(root)
    expect_error(doublet_integration_continue(root, approved), "[Ss]tale|changed|fingerprint|approval|scope")
    expect_identical(doublet_integration_files(root), bytes)
  }
  expect_identical(detector$detector, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("an interrupted approved selection needs explicit retry and reuses QC and fixed predictions", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  doublet_integration_begin(root, object, doublet_integration_plan("remove_predicted"))
  doublet_integration_decide(root)
  withr::local_options(list(scAgentKit.continue_crash = "strategy_selection:before"))
  output <- capture.output(failed <- doublet_integration_continue(root))
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "strategy_selection")
  expect_match(failed$failure$message, "Injected local continuation failure")
  expect_false(any(grepl("Injected local continuation failure", output, fixed = TRUE)))
  state <- scAgentKit:::.sc_run_load(root)
  retained <- state$files[c("input", "qc_evidence", "doublet_diagnostics", "strategy_evidence", "qc_object")]
  expect_null(state$files$strategy_selected)
  expect_identical(colnames(scAgentKit:::.sc_run_get(root, state, "qc_object")), colnames(object)[1:201])
  bytes <- doublet_integration_files(root)
  expect_identical(doublet_integration_continue(root)$status, "failed")
  expect_identical(sc_run_resume(root)$status, "failed")
  expect_identical(doublet_integration_files(root), bytes)
  options(scAgentKit.continue_crash = NULL)
  resumed <- doublet_integration_continue(root, retry = TRUE)
  expect_identical(resumed$status, "awaiting_configuration")
  expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[names(retained)], retained)
  record <- scAgentKit:::.sc_run_get(root, state, "doublet_diagnostics")
  expected <- colnames(object)[1:201]; expected <- expected[!expected %in% record$predicted_cells]
  doublet_integration_preserved(scAgentKit:::.sc_run_get(root, state, "analysis"), object, expected)
  for (stage in c("strategy_evidence", "qc_apply", "strategy_selection", "strategy_preprocess",
    "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
    expect_identical(doublet_integration_executions(state, stage), 1L)
  expect_true(any(vapply(state$history, function(e)
    identical(e$action, "local_continue_retry_requested"), logical(1))))
  doublet_integration_unknown(root); doublet_integration_decide(root)
  final <- doublet_integration_child(root)
  expect_identical(final$status$status, "complete")
  doublet_integration_scores(readRDS(final$status$output$seurat), record)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(detector$detector, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("dependency warnings malformed identity and fallback failures stop before strategy review and permit explicit retry", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  withr::local_options(list(fixture_missing_doublet_dependency = FALSE))
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  for (mode in c("dependency", "error", "warning", "malformed", "fallback")) {
    root <- tempfile(); roots <- c(roots, root)
    detector$mode <- if (mode == "dependency") "ok" else mode
    options(fixture_missing_doublet_dependency = identical(mode, "dependency"))
    cycle <- if (mode == "dependency") list(gene_set = sc_cycle_gene_set("human"),
      column_prefix = "sc_cycle", seed = 17L, nbin = 12L, ctrl = 5L,
      scale_factor = 10000, min_genes = 5L, min_fraction = .2) else NULL
    before_calls <- detector$detector
    failed <- doublet_integration_begin(root, object, cycle = cycle)
    expect_identical(failed$status, "failed")
    expect_identical(failed$stage, "strategy_evidence")
    expect_match(failed$failure$message,
      "unavailable|detector error|valid predicted classes|classifier|audit|fallback")
    state <- scAgentKit:::.sc_run_load(root)
    expect_null(state$files$doublet_diagnostics)
    expect_null(state$files$strategy_evidence); expect_null(state$files$strategy_review)
    expect_null(state$files$strategy_request); expect_null(state$approved)
    expect_null(state$files$qc_object); expect_null(state$files$strategy_selected)
    expect_false(is.null(state$files$qc_evidence))
    retained_keys <- c("input", "qc_evidence", if (!is.null(cycle)) "cycle_diagnostics")
    retained <- state$files[retained_keys]
    if (mode == "dependency") {
      expect_identical(detector$detector, before_calls)
      expect_false(is.null(state$files$cycle_diagnostics))
    } else expect_identical(detector$detector, before_calls + 1L)
    expect_identical(serialize(scAgentKit:::.sc_run_get(root, state, "input"), NULL, version = 2L), original)
    bytes <- doublet_integration_files(root)
    expect_identical(doublet_integration_continue(root)$status, "failed")
    expect_identical(sc_run_resume(root)$status, "failed")
    expect_identical(doublet_integration_files(root), bytes)
    # The helper bodies and saved implementation fingerprint remain unchanged;
    # only the deliberately injected external failure condition is resolved.
    detector$mode <- "ok"; options(fixture_missing_doublet_dependency = FALSE)
    retry_calls <- detector$detector
    resumed <- suppressWarnings(sc_run_resume(root, retry = TRUE))
    expect_identical(resumed$status, "awaiting_review")
    expect_identical(resumed$stage, "strategy_propose")
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[retained_keys], retained)
    expect_identical(detector$detector, retry_calls + 2L)
    expect_identical(scAgentKit:::.sc_run_get(root, state, "doublet_diagnostics")$summary$status, "available")
    expect_null(state$files$qc_object)
    paused_bytes <- doublet_integration_files(root)
    expect_identical(sc_run_resume(root)$status, "awaiting_review")
    expect_identical(doublet_integration_files(root), paused_bytes)
    expect_identical(serialize(object, NULL, version = 2L), original)
  }
  expect_false(any(vapply(roots, function(root) dir.exists(file.path(root, "provider")), logical(1))))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("unsupported capture size or read coverage is visible and cannot authorize predicted removal", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  objects <- list(
    small_capture = doublet_integration_fixture()[, 1:200],
    low_reads = doublet_integration_fixture())
  low <- SeuratObject::LayerData(objects$low_reads, layer = "counts")
  low[, 1L] <- 0L; low[1L, 1L] <- 199L
  SeuratObject::LayerData(objects$low_reads, layer = "counts") <- low
  for (kind in names(objects)) {
    root <- tempfile(); roots <- c(roots, root)
    object <- objects[[kind]]; original <- serialize(object, NULL, version = 2L)
    before_calls <- detector$detector
    begun <- doublet_integration_begin(root, object)
    expect_identical(begun$status, "awaiting_review")
    snapshot <- sc_run_inspect(root); state <- scAgentKit:::.sc_run_load(root)
    record <- scAgentKit:::.sc_run_get(root, state, "doublet_diagnostics")
    expect_identical(record$summary$status, "unsupported")
    expect_true(any(grepl(if (kind == "small_capture") "Fewer than 100" else "fewer than 200", record$summary$reasons)))
    expect_true(all(is.na(record$scores$sc_doublet_score)))
    expect_true(all(record$scores$sc_doublet_class == "Unknown"))
    expect_equal(record$summary$cohort$scored_cells, 0L)
    expect_equal(record$summary$cohort$removed_cells, 0L)
    expect_identical(detector$detector, before_calls)
    expect_identical(snapshot$strategy_review$details$canonical_proposal$doublet$method, "keep")
    expect_identical(snapshot$strategy_review$details$applicability$doublet$scoring_status, "unsupported")
    expect_identical(snapshot$strategy_review$details$applicability$doublet$removed_cell_ids, character())
    bytes <- doublet_integration_files(root)
    expect_error(doublet_integration_revise(root, doublet_integration_plan("remove_predicted")), "unsupported|unavailable")
    expect_identical(doublet_integration_files(root), bytes)
    expect_null(state$files$qc_object)
    expect_identical(serialize(scAgentKit:::.sc_run_get(root, state, "input"), NULL, version = 2L), original)
    expect_identical(serialize(object, NULL, version = 2L), original)
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("capture provenance and expected-rate configuration are explicit before any persistent analysis", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  failures <- list()
  context <- doublet_integration_context(); context$columns$capture <- NULL
  failures[["donor is not inferred as capture"]] <- list(context = context, options = doublet_integration_options())
  unknown <- doublet_integration_options(); unknown$rate$method <- "auto"
  failures[["unknown rate is not inferred"]] <- list(context = doublet_integration_context(), options = unknown)
  absent <- doublet_integration_options(); absent$rate$value <- NULL
  failures[["manual rate cannot be absent"]] <- list(context = doublet_integration_context(), options = absent)
  platform <- doublet_integration_options(); platform$data_type <- "snrna"
  failures[["unsupported data type is explicit"]] <- list(context = doublet_integration_context(), options = platform)
  droplets <- doublet_integration_options(); droplets$empty_droplets_removed <- FALSE
  failures[["uncalled droplets cannot be silently removed"]] <- list(context = doublet_integration_context(), options = droplets)
  standard <- doublet_integration_options()
  standard$technology <- "10x_chromium_standard"
  standard$rate <- list(method = "10x_standard", source = "Explicit synthetic standard-loading software declaration.", sd = .02)
  failures[["called droplets alone do not establish the full cohort"]] <- list(
    context = doublet_integration_context(), options = standard)
  filtered <- standard; filtered$full_called_cohort <- FALSE
  failures[["a quality-filtered subset cannot estimate the loading rate"]] <- list(
    context = doublet_integration_context(), options = filtered)
  for (failure in failures) {
    root <- tempfile(); roots <- c(roots, root)
    expect_error(doublet_integration_begin(root, object, options = failure$options, context = failure$context),
      "capture|loading|rate|Unsupported|empty_droplets|called-cell|full_called_cohort|full called")
    expect_false(file.exists(file.path(root, "state.rds")))
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  expect_identical(detector$detector, 0L)
  # A donor column and even an undeclared metadata column named capture do
  # not prevent an explicit, sourced declaration of one loading unit.
  root <- tempfile(); roots <- c(roots, root)
  begun <- doublet_integration_begin(root, object, options = doublet_integration_options(single = TRUE), context = context)
  expect_identical(begun$status, "awaiting_review")
  record <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "doublet_diagnostics")
  expect_equal(record$summary$captures, 1L)
  expect_identical(unique(unname(record$capture_map)), "declared loading unit")
  expect_equal(detector$detector, 1L)
  expect_identical(detector$captures[[1L]]$cells, sort(enc2utf8(colnames(object)), method = "radix"))
  # Standard-loading estimation is permitted only with the additional
  # explicit full called-cell cohort declaration. Here the algorithm remains
  # mocked; neither this declared technology nor its rate is scientific proof.
  standard$full_called_cohort <- TRUE
  root <- tempfile(); roots <- c(roots, root)
  begun <- doublet_integration_begin(root, object, options = standard)
  expect_identical(begun$status, "awaiting_review")
  record <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "doublet_diagnostics")
  expect_true(record$options$full_called_cohort)
  expect_identical(record$options$technology, "10x_chromium_standard")
  expect_identical(record$options$rate$method, "10x_standard")
  expect_equal(record$summary$capture_stats[["capture A"]]$expected_rate, .008 * 101 / 1000)
  expect_equal(record$summary$capture_stats[["capture B"]]$expected_rate, .008 * 101 / 1000)
  expect_equal(detector$detector, 3L)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("processed keep attaches scores but reuses its foundation and rejects doublet deletion atomically", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  plan <- doublet_integration_plan()
  plan[c("qc", "analysis", "pcs", "clustering", "umap")] <- rep(list(NULL), 5L)
  begun <- doublet_integration_begin(root, object, proposal = plan, start_stage = "processed")
  expect_identical(begun$status, "awaiting_review")
  snapshot <- sc_run_inspect(root)
  expect_identical(snapshot$review_node$kind, "strategy")
  expect_identical(snapshot$strategy_review$details$canonical_proposal$doublet$method, "keep")
  impact <- snapshot$strategy_review$details$applicability$doublet
  expect_true(impact$processed_reuse)
  expect_identical(impact$qc_keep_cell_ids, colnames(object))
  expect_identical(impact$selected_cell_ids, colnames(object))
  expect_identical(impact$removed_cell_ids, character())
  before <- scAgentKit:::.sc_run_load(root)
  foundation <- before$files$analysis
  record <- scAgentKit:::.sc_run_get(root, before, "doublet_diagnostics")
  scored <- scAgentKit:::.sc_run_get(root, before, "analysis")
  doublet_integration_preserved(scored, object, colnames(object), processed = TRUE)
  doublet_integration_scores(scored, record)
  invalid <- plan; invalid$doublet <- list(method = "remove_predicted",
    reason = "This attempted processed deletion must require raw entry and rebuilt analysis.")
  bytes <- doublet_integration_files(root)
  expect_error(doublet_integration_revise(root, invalid), "Processed entry|foundation|raw entry")
  expect_identical(doublet_integration_files(root), bytes)
  doublet_integration_decide(root)
  boundary <- doublet_integration_child(root)
  expect_identical(boundary$status$status, "awaiting_configuration")
  expect_identical(boundary$status$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files$analysis, foundation)
  expect_null(state$files$qc_object); expect_null(state$files$strategy_selected)
  expect_null(state$files$strategy_preprocess); expect_null(state$files$strategy_basis)
  for (stage in c("qc_apply", "strategy_selection", "strategy_preprocess", "strategy_basis",
                  "strategy_neighbors", "strategy_cluster"))
    expect_identical(doublet_integration_executions(state, stage), 0L)
  doublet_integration_unknown(root); doublet_integration_decide(root)
  final <- doublet_integration_child(root)
  expect_identical(final$status$status, "complete")
  output <- readRDS(final$status$output$seurat)
  doublet_integration_preserved(output, object, colnames(object), processed = TRUE)
  doublet_integration_scores(output, record)
  expect_identical(output$source_cluster, object$source_cluster)
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_false("sc_strategy_clusters" %in% names(output[[]]))
  expect_equal(sum(output$sc_doublet_class == "doublet"), 22L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(detector$detector, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("a local mock proposal sees aggregates only and cannot delete or repeat a cached request", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  calls <- 0L; seen <- NULL
  proposal <- doublet_integration_plan("remove_predicted")
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    seen <<- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    list(content = as.character(jsonlite::toJSON(proposal, auto_unbox = TRUE, null = "null")),
      cost_usd = 0, usage = list(input_tokens = 0L, output_tokens = 0L))
  }
  provider <- list(name = "mock", external = FALSE, model = "synthetic-doublet-strategy-only")
  begun <- doublet_integration_begin(root, object, proposal = NULL,
    provider = provider, chat_fn = callback)
  expect_identical(begun$status, "awaiting_review"); expect_identical(calls, 1L)
  expect_equal(seen$evidence$input$cells, 202L)
  expect_equal(seen$evidence$doublet_diagnostics$captures, 2L)
  expect_identical(seen$evidence$doublet_diagnostics$reference, "fixed_full_input")
  expect_equal(seen$evidence$doublet_diagnostics$capture_stats[["capture A"]]$input_cells, 101L)
  expect_identical(seen$evidence$background_facts$research_goal, doublet_integration_context()$research_goal)
  state <- scAgentKit:::.sc_run_load(root)
  request <- scAgentKit:::.sc_run_get(root, state, "strategy_request")
  expect_false(grepl("literalDoubletCell", request$user_prompt, fixed = TRUE))
  expect_false(grepl("Per-cell private metadata", request$user_prompt, fixed = TRUE))
  expect_false(grepl('"cell_id"', request$user_prompt, fixed = TRUE))
  expect_false(grepl('"scores"', request$user_prompt, fixed = TRUE))
  expect_false(grepl('"predicted_cells"', request$user_prompt, fixed = TRUE))
  expect_false(grepl('"feature_detection"', request$user_prompt, fixed = TRUE))
  expect_false(grepl('"private"', request$user_prompt, fixed = TRUE))
  expect_null(state$files$qc_object); expect_null(state$files$strategy_selected)
  expect_identical(serialize(scAgentKit:::.sc_run_get(root, state, "input"), NULL, version = 2L), original)
  bytes <- doublet_integration_files(root)
  expect_identical(sc_run_resume(root, chat_fn = callback)$status, "awaiting_review")
  expect_identical(doublet_integration_continue(root)$status, "awaiting_review")
  expect_identical(doublet_integration_files(root), bytes)
  expect_identical(calls, 1L); expect_identical(detector$detector, 2L)
  evidence <- scAgentKit:::.sc_run_get(root, state, "strategy_evidence")
  request$validator <- function(value) scAgentKit:::.sc_run_strategy_validate(value, evidence)$proposal
  ledger <- file.path(root, "provider", "ledger.json")
  ledger_hash <- scAgentKit:::.sc_project_sha_file(ledger)
  cached <- scAgentKit:::.sc_run_call(root, request, provider = provider, chat_fn = callback, budget = 0)
  expect_identical(cached$status, "ok"); expect_true(cached$cached)
  expect_equal(cached$charged_or_held_usd, 0)
  expect_identical(calls, 1L); expect_identical(detector$detector, 2L)
  expect_identical(scAgentKit:::.sc_project_sha_file(ledger), ledger_hash)
  doublet_integration_decide(root)
  boundary <- doublet_integration_continue(root)
  expect_identical(boundary$status, "awaiting_configuration")
  expect_identical(boundary$stage, "annotation_propose")
  expect_identical(calls, 1L); expect_identical(detector$detector, 2L)
  expect_identical(scAgentKit:::.sc_project_sha_file(ledger), ledger_hash)
  derived <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "analysis")
  expect_equal(ncol(derived), 180L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("formal human and mouse declarations use literal fixture features without inferring species", {
  network <- doublet_integration_sentinels(); detector <- doublet_integration_detector()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  # The same literal expression matrix is intentional: this tests only the
  # accepted declaration mechanism. It is not real mouse method validation.
  object <- doublet_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  for (species in c("Homo sapiens", "Mus musculus")) {
    root <- tempfile(); roots <- c(roots, root)
    context <- doublet_integration_context(species)
    begun <- doublet_integration_begin(root, object, context = context)
    expect_identical(begun$status, "awaiting_review")
    record <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "doublet_diagnostics")
    expect_identical(record$summary$species, if (species == "Homo sapiens") "human" else "mouse")
    expect_identical(record$feature_ids, sort(enc2utf8(rownames(object)), method = "radix"))
    expect_identical(record$cell_ids, colnames(object))
    expect_identical(record$summary$scoring$versions[c("scDblFinder", "xgboost", "fixture_scope")],
      list(scDblFinder = "1.26.7", xgboost = "3.2.1.1",
        fixture_scope = "Authored accepted-version metadata only; no package inspection or classifier execution."))
  }
  root <- tempfile(); roots <- c(roots, root)
  expect_error(doublet_integration_begin(root, object,
    context = doublet_integration_context("zebrafish")), "[Uu]nsupported species|human or mouse")
  expect_false(file.exists(file.path(root, "state.rds")))
  expect_identical(detector$detector, 4L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
