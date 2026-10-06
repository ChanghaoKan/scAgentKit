# These are synthetic coordinator controls. Planted cell-cycle expression,
# metadata, QC cutoffs, and Unknown annotations make no biological claims.

cycle_integration_fixture <- function(cycle_genes = TRUE, coverage = "complete") {
  set.seed(17L)
  genes <- if (cycle_genes) sc_cycle_gene_set("human") else NULL
  phase_genes <- if (is.null(genes)) character() else
    unique(c(genes$s_genes, genes$g2m_genes))
  features <- c("MT-CO1", phase_genes, paste0("BackgroundGene", seq_len(220L)))
  cells <- c("001", "1", "NA", "cell space", paste0("literalCycleCell", 5:120))
  counts <- matrix(stats::rpois(length(features) * length(cells), 3),
    nrow = length(features), dimnames = list(features, cells))
  if (length(phase_genes)) {
    counts[genes$s_genes, 1:40] <- counts[genes$s_genes, 1:40] + 18L
    counts[genes$g2m_genes, 41:80] <- counts[genes$g2m_genes, 41:80] + 18L
  }
  for (program in seq_len(3L)) {
    chosen <- paste0("BackgroundGene", seq.int((program - 1L) * 15L + 1L, program * 15L))
    selected <- seq.int((program - 1L) * 40L + 1L, program * 40L)
    counts[chosen, selected] <- counts[chosen, selected] + 12L
  }
  # Count-positive QC initially keeps 119 cells. A later min=2 revision really
  # removes the separate one-count control, instead of changing only a hash.
  counts[, 119:120] <- 0L
  counts["MT-CO1", 119L] <- 1L
  if (cycle_genes && coverage != "complete") {
    retained_symbols <- if (coverage == "partial")
      c(genes$s_genes[1:2], genes$g2m_genes[1:2]) else character()
    replace <- which(rownames(counts) %in% setdiff(phase_genes, retained_symbols))
    rownames(counts)[replace] <- paste0("LiteralUnmappedGene", seq_along(replace))
  }
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <-
    log1p(Matrix::Matrix(counts * 7L, sparse = TRUE))
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object$source_cluster <- factor(rep(c("01", "NA"), each = 60L),
    levels = c("NA", "01", "unused cluster"))
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 60L),
    levels = c("prior A", "unused prior B"))
  object$sample <- rep(c("sample A", "sample B"), each = 60L)
  object$capture <- rep(rep(c("capture A", "capture B"), each = 30L), 2L)
  object$batch <- rep(c("technical A", "technical B"), each = 60L)
  object$group <- rep(c("Ca", "Ctrl"), 60L)
  object$private_note <- "Private per-cell field excluded from aggregate requests."
  object$S.Score <- seq_len(ncol(object)) / 100
  object$G2M.Score <- -seq_len(ncol(object)) / 100
  object$CC.Difference <- rep(999, ncol(object))
  object$Phase <- factor(rep(c("prior phase", NA_character_), 60L),
    levels = c("prior phase", "unused phase"))
  object
}

cycle_integration_context <- function() list(species = "human", tissue = "synthetic",
  columns = list(sample = "sample", capture = "capture", batch = "batch", group = "group"),
  design = list(type = "synthetic crossed software fixture", technical_batch = TRUE,
    notes = "Planted programs do not establish biological cell types or technical effects."),
  research_goal = "Review whether cell-cycle regression helps this synthetic workflow.",
  notes = "Software acceptance fixture; no scientific thresholds are recommended.")

cycle_integration_options <- function() list(gene_set = sc_cycle_gene_set("human"),
  column_prefix = "sc_cycle", seed = 17L, scale_factor = 10000,
  ctrl = 5L, nbin = 12L, min_genes = 5L, min_fraction = .2)

cycle_integration_plan <- function(method = NULL) {
  proposal <- list(schema = "scagentkit.strategy.v1",
    rationale = "Use a count-positive software QC control and explicit local analysis choices.",
    risks = list("Planted expression and metadata do not validate biology or QC thresholds."),
    inferences = list("Synthetic expression programs are test controls, not user biological facts."),
    qc = list(schema = "scagentkit.qc.v1", rationale = "Remove only the zero-count software control.",
      risks = list("A test cutoff, not a recommended biological threshold."),
      filters = list(list(op = "range", metric = "nCount", min = 1L))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 80L, npcs = 10L, seed = 17L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No automatic integration is requested for synthetic metadata."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
    umap = list(run = FALSE, n_neighbors = 10L))
  if (!is.null(method)) proposal$cycle <- list(method = method,
    reason = paste("Explicitly review", method, "for the planted cycle software control."))
  proposal
}

cycle_integration_begin <- function(root, object = cycle_integration_fixture(),
                                    proposal = cycle_integration_plan(),
                                    options = cycle_integration_options(),
                                    context = cycle_integration_context(),
                                    provider = NULL, chat_fn = NULL) {
  suppressWarnings(sc_run(object, root, context = context, strategy = TRUE,
    strategy_proposal = proposal, cycle_diagnostics = options,
    provider = provider, chat_fn = chat_fn, budget = 0,
    annotation_column = "reviewed_type"))
}

cycle_integration_continue <- function(root, snapshot = sc_run_inspect(root)) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash,
    snapshot$revision))
}

cycle_integration_decide <- function(root, snapshot = sc_run_inspect(root), action = "approve") {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline cycle QA", reason = "Review this exact synthetic software-control scope.")
}

cycle_integration_revise <- function(root, proposal, snapshot = sc_run_inspect(root)) {
  sc_run_strategy_revise(root, proposal, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, "offline cycle QA", "Explicit supported revision of the inspected software-control strategy.")
}

cycle_integration_unknown <- function(root) {
  evidence <- sc_run_inspect(root)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(evidence$clusters, function(row) list(clusterId = row$clusterId,
      label = "Unknown", confidence = "low", rationale = "Synthetic controls leave biological identity unresolved.",
      markers = list())))
  sc_run_propose(root, proposal, "offline cycle QA", "Keep explicit Unknown labels under a separate exact annotation review.")
}

cycle_integration_files <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  paths <- paths[!dir.exists(paths)]
  stats::setNames(vapply(paths, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(paths, nchar(root) + 2L))
}

cycle_integration_copy <- function(root) {
  target <- tempfile("cycle-copy-"); dir.create(target)
  if (!all(file.copy(list.files(root, full.names = TRUE, all.files = TRUE, no.. = TRUE),
                     target, recursive = TRUE, copy.mode = TRUE)))
    stop("Could not copy the stopped synthetic project.")
  target
}

cycle_integration_executions <- function(state, stage) {
  length(Filter(function(event) identical(event$action, "executed") &&
    identical(event$details$stage, stage), state$history))
}

cycle_integration_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) {
    calls$factory <- calls$factory + 1L
    stop("Offline cycle acceptance prohibits remote provider factories.")
  }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L
    stop("Offline cycle acceptance prohibits network dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

# Same installed-namespace/source-checkout routing as the established strategy
# integration fixture. The child has no profiles, provider callback, or keys.
cycle_integration_child <- function(root, snapshot = sc_run_inspect(root)) {
  work <- tempfile("cycle-child-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  arguments <- file.path(work, "arguments.rds"); result <- file.path(work, "result.rds")
  script <- file.path(work, "child.R"); log <- file.path(work, "stdout.log")
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path")), arguments)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','GROK_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','AZURE_OPENAI_API_KEY','COHERE_API_KEY','MISTRAL_API_KEY','OPENROUTER_API_KEY','HF_TOKEN','HUGGINGFACEHUB_API_TOKEN'))",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else library(scAgentKit,lib.loc=dirname(args$package))",
    "factory_calls <- 0L; http_calls <- 0L",
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('No remote cycle factory permitted') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('No cycle HTTP permitted') },.package='httr2',.env=environment())",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision))",
    "stopifnot(factory_calls==0L,http_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls),args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(arguments)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result))
    stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

cycle_integration_preserved <- function(object, source, cells) {
  expect_identical(colnames(object), cells)
  expect_identical(rownames(object), rownames(source))
  for (column in names(source[[]]))
    expect_identical(object[[]][[column]], source[[]][cells, column])
  for (layer in c("counts", "extra")) {
    actual <- SeuratObject::LayerData(object, assay = "RNA", layer = layer)
    expect_identical(actual, SeuratObject::LayerData(source, assay = "RNA", layer = layer)[, cells, drop = FALSE])
    expect_true(inherits(actual, "sparseMatrix"))
  }
  expect_true(inherits(SeuratObject::LayerData(object, assay = "RNA", layer = "data"), "sparseMatrix"))
}

cycle_integration_scores <- function(object, record) {
  cells <- colnames(object)
  expected <- record$scores[match(cells, record$scores$cell_id),
    unname(record$summary$columns), drop = FALSE]
  for (column in names(expected)) expect_identical(object[[]][[column]], expected[[column]])
}

test_that("full-input diagnostics precede one whole strategy review and none attaches fresh scores without filtering", {
  network <- cycle_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- cycle_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  expect_gt(nrow(object), 200L)
  expect_true(all(c("MCM5", "PCNA", "TOP2A", "MKI67") %in% rownames(object)))
  context <- cycle_integration_context(); context$species <- "Homo sapiens"
  begun <- cycle_integration_begin(root, object, context = context)
  expect_identical(begun$status, "awaiting_review")
  snapshot <- sc_run_inspect(root)
  expect_identical(snapshot$review_node$kind, "strategy")
  expect_identical(snapshot$strategy_review$details$canonical_proposal$cycle$method, "none")
  expect_equal(snapshot$strategy_review$details$applicability$details$retained_cells, 119L)
  state <- scAgentKit:::.sc_run_load(root)
  record <- scAgentKit:::.sc_run_get(root, state, "cycle_diagnostics")
  expect_identical(record$summary$status, "available")
  expect_identical(record$cell_ids, colnames(object))
  expect_identical(record$summary$reference, "fixed_full_input")
  expect_false(record$summary$refit_after_qc)
  expect_equal(record$summary$cohort$input_cells, 120L)
  expect_equal(record$summary$cohort$removed_cells, 0L)
  expect_identical(record$summary$normalization$method, "LogNormalize")
  expect_equal(record$summary$normalization$scale_factor, 10000)
  expect_identical(record$summary$scoring$function_name, "Seurat::CellCycleScoring")
  expect_identical(record$summary$gene_set$source, "Seurat::cc.genes.updated.2019")
  expect_identical(record$summary$gene_set$version, "2019")
  expect_equal(record$summary$options$ctrl, 5L)
  expect_equal(record$summary$options$nbin, 12L)
  expect_true(all(is.finite(record$scores$sc_cycle_S.Score)))
  expect_true(all(is.finite(record$scores$sc_cycle_G2M.Score)))
  expect_gt(mean(record$scores$sc_cycle_S.Score[1:40]),
    mean(record$scores$sc_cycle_S.Score[81:118]))
  expect_gt(mean(record$scores$sc_cycle_G2M.Score[41:80]),
    mean(record$scores$sc_cycle_G2M.Score[81:118]))
  expect_equal(record$scores$sc_cycle_CC.Difference,
    record$scores$sc_cycle_S.Score - record$scores$sc_cycle_G2M.Score)
  expect_null(state$files$qc_object)
  expect_null(state$files$strategy_preprocess)
  expect_null(state$files$strategy_basis)
  expect_identical(snapshot$strategy_review$details$cycle_diagnostics, record$summary)
  expect_null(snapshot$strategy_review$details$cycle_diagnostics$scores)
  expect_null(snapshot$strategy_review$details$cycle_diagnostics$cell_ids)
  expect_identical(serialize(scAgentKit:::.sc_run_get(root, state, "input"), NULL, version = 2L), original)
  bytes <- cycle_integration_files(root)
  expect_identical(cycle_integration_continue(root)$status, "awaiting_review")
  expect_identical(cycle_integration_files(root), bytes)
  cycle_integration_decide(root)
  approved <- scAgentKit:::.sc_run_load(root)
  expect_null(approved$files$qc_object)
  expect_identical(approved$strategy_authorizations$cycle$dependency_hash,
    snapshot$strategy_review$details$dependency_hashes$cycle)
  stopped <- cycle_integration_continue(root)
  expect_identical(stopped$status, "awaiting_configuration")
  expect_identical(stopped$stage, "annotation_propose")
  expect_null(sc_run_inspect(root)$review_node)
  expect_identical(sc_run_inspect(root)$strategy_review$details$canonical_proposal$cycle$method, "none")
  expect_identical(stopped$diagnostics$local_continue_boundary$dispatch, "not_sent")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files$cycle_diagnostics, approved$files$cycle_diagnostics)
  stages <- vapply(Filter(function(event) identical(event$action, "executed"), state$history),
    function(event) event$details$stage, character(1))
  expected_order <- c("strategy_evidence", "strategy_apply", "qc_apply",
    "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence")
  expect_true(all(expected_order %in% stages))
  expect_true(all(diff(match(expected_order, stages)) > 0))
  analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
  expect_gt(nrow(scAgentKit:::.sc_run_get(root, state, "markers")$markers), 0L)
  cycle_integration_preserved(analysis, object, colnames(object)[1:119])
  cycle_integration_scores(analysis, record)
  expect_identical(analysis@misc$strategy_execution$basis$regressors, character())
  expect_identical(state$files$input, approved$files$input)
  cycle_integration_unknown(root)
  annotation <- sc_run_inspect(root)
  expect_identical(annotation$review_node$kind, "annotation")
  expect_null(scAgentKit:::.sc_run_load(root)$files$annotated)
  cycle_integration_decide(root, annotation)
  final <- cycle_integration_child(root)
  expect_identical(final$status$status, "complete")
  expect_identical(final$factory_calls, 0L); expect_identical(final$http_calls, 0L)
  output <- readRDS(final$status$output$seurat)
  cycle_integration_preserved(output, object, colnames(object)[1:119])
  cycle_integration_scores(output, record)
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_true(is.factor(output$old_annotation)); expect_true(anyNA(output$old_annotation))
  expect_true(is.factor(output$Phase)); expect_true(anyNA(output$Phase))
  decisions <- Filter(function(event) identical(event$action, "approved"),
    scAgentKit:::.sc_run_load(root)$history)
  expect_identical(vapply(decisions, function(event) event$details$kind, character(1)),
    c("strategy", "annotation"))
  complete_bytes <- cycle_integration_files(root)
  expect_identical(cycle_integration_continue(root)$status, "complete")
  expect_identical(cycle_integration_files(root), complete_bytes)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("none full and difference revisions reuse fixed scores QC and preprocessing while actually rebuilding downstream stages", {
  network <- cycle_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- cycle_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  cycle_integration_begin(root, object, cycle_integration_plan("none"))
  cycle_integration_decide(root); cycle_integration_continue(root)
  first <- scAgentKit:::.sc_run_load(root)
  record <- scAgentKit:::.sc_run_get(root, first, "cycle_diagnostics")
  retained <- c("input", "cycle_diagnostics", "qc_evidence", "strategy_evidence", "qc_object", "strategy_preprocess")
  refs <- first$files[retained]
  expect_identical(scAgentKit:::.sc_run_get(root, first, "analysis")@misc$strategy_execution$basis$regressors,
    character())
  previous <- first
  for (method in c("full", "difference")) {
    # An independently approved annotation from the old basis is deliberately
    # present; changing the cycle method must remove its active authority.
    cycle_integration_unknown(root); cycle_integration_decide(root)
    old_annotation <- sc_run_inspect(root)
    before <- scAgentKit:::.sc_run_load(root)
    immutable <- cycle_integration_files(root)
    revised <- cycle_integration_revise(root, cycle_integration_plan(method))
    expect_identical(revised$status, "awaiting_review")
    expect_identical(revised$pending$kind, "strategy")
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[retained], refs)
    invalidated <- c("strategy_basis", "strategy_neighbors", "analysis", "markers", "annotation_evidence",
      "manual_annotation", "annotation_validated", "annotation_review", "annotated")
    expect_false(any(invalidated %in% names(state$files)))
    expect_null(state$approved)
    expect_identical(state$history[seq_along(before$history)], before$history)
    expect_identical(state$approvals[[before$approved$hash]], before$approvals[[before$approved$hash]])
    current_bytes <- cycle_integration_files(root)
    immutable <- immutable[startsWith(names(immutable), "checkpoints/")]
    expect_identical(current_bytes[names(immutable)], immutable)
    expect_error(cycle_integration_decide(root, old_annotation), "[Ss]tale|different review kind")
    pending_bytes <- cycle_integration_files(root)
    expect_identical(cycle_integration_continue(root)$status, "awaiting_review")
    expect_identical(cycle_integration_files(root), pending_bytes)
    review <- sc_run_inspect(root)
    expect_identical(review$strategy_review$details$canonical_proposal$cycle$method, method)
    cycle_integration_decide(root, review)
    result <- cycle_integration_child(root)
    expect_identical(result$status$status, "awaiting_configuration")
    expect_identical(result$status$stage, "annotation_propose")
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[retained], refs)
    expect_false(identical(state$files$strategy_basis, previous$files$strategy_basis))
    expect_false(identical(state$files$strategy_neighbors, previous$files$strategy_neighbors))
    expect_false(identical(state$files$annotation_evidence, previous$files$annotation_evidence))
    analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
    expected_regressors <- if (method == "full") c("sc_cycle_S.Score", "sc_cycle_G2M.Score") else "sc_cycle_CC.Difference"
    expect_identical(analysis@misc$strategy_execution$basis$regressors, expected_regressors)
    # Check an effect of real linear residualization, beyond the recorded
    # parameter names: scaled HVGs should have negligible correlation with
    # the reviewed fresh covariates. Only the already dense HVG scale layer
    # enters this calculation; source counts and data stay sparse.
    scaled <- SeuratObject::LayerData(analysis, assay = "RNA", layer = "scale.data")
    covariates <- analysis[[]][, expected_regressors, drop = FALSE]
    correlations <- stats::cor(t(scaled), covariates)
    expect_true(all(is.finite(correlations)))
    expect_lt(max(abs(correlations)), .02)
    expect_false(identical(SeuratObject::Embeddings(analysis[["pca"]]),
      SeuratObject::Embeddings(scAgentKit:::.sc_run_get(root, previous, "analysis")[["pca"]])))
    cycle_integration_preserved(analysis, object, colnames(object)[1:119])
    cycle_integration_scores(analysis, record)
    for (stage in c("strategy_evidence", "qc_apply", "strategy_preprocess"))
      expect_identical(cycle_integration_executions(state, stage), 1L)
    expected_runs <- if (method == "full") 2L else 3L
    for (stage in c("strategy_basis", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
      expect_identical(cycle_integration_executions(state, stage), expected_runs)
    expect_null(state$files$annotated)
    expect_identical(serialize(object, NULL, version = 2L), original)
    previous <- state
  }
  cycle_integration_unknown(root)
  expect_identical(sc_run_inspect(root)$review_node$kind, "annotation")
  cycle_integration_decide(root)
  complete <- cycle_integration_child(root)
  expect_identical(complete$status$status, "complete")
  output <- readRDS(complete$status$output$seurat)
  cycle_integration_preserved(output, object, colnames(object)[1:119])
  cycle_integration_scores(output, record)
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("cycle choices exact review identities locks and calculation scope cannot consume stale approval", {
  network <- cycle_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  root <- tempfile(); roots <- c(roots, root)
  cycle_integration_begin(root)
  snapshot <- sc_run_inspect(root); bytes <- cycle_integration_files(root)
  invalid <- list(
    list(method = "delete_cycling", reason = "Unsupported deletion control."),
    list(method = "auto", reason = "A model goal cannot choose a hidden method."),
    list(method = "full", reason = "Unsupported arbitrary covariate control.", vars_to_regress = "S.Score"),
    list(method = "none", reason = "Unsupported mutable scoring control.", seed = 18L),
    list(method = "none", reason = "Unsupported mutable gene list control.", s_genes = "PCNA"),
    list(method = "none", reason = "Unsupported mutable tag control.", column_prefix = "other_cycle"))
  for (choice in invalid) {
    proposal <- cycle_integration_plan(); proposal$cycle <- choice
    expect_error(cycle_integration_revise(root, proposal, snapshot))
    expect_identical(cycle_integration_files(root), bytes)
  }
  proposal <- cycle_integration_plan(); proposal["cycle"] <- list(NULL)
  expect_error(cycle_integration_revise(root, proposal, snapshot))
  expect_identical(cycle_integration_files(root), bytes)
  stale <- snapshot; stale$revision <- stale$revision + 1L
  expect_error(cycle_integration_revise(root, cycle_integration_plan("full"), stale), "[Ss]tale|revision")
  foreign <- snapshot; foreign$project_id <- "another-project"
  expect_error(cycle_integration_continue(root, foreign), "Foreign project")
  expect_identical(cycle_integration_files(root), bytes)
  wrong_review <- snapshot; wrong_review$review_node$review_hash <- paste(rep("0", 64L), collapse = "")
  expect_error(cycle_integration_decide(root, wrong_review), "[Ss]tale|review.*hash|fingerprint")
  expect_identical(cycle_integration_files(root), bytes)
  lock <- scAgentKit:::.sc_run_lock(root)
  locked <- cycle_integration_files(root)
  expect_error(cycle_integration_decide(root, snapshot), "locked")
  expect_error(cycle_integration_continue(root, snapshot), "locked")
  expect_error(cycle_integration_revise(root, cycle_integration_plan("full"), snapshot), "locked")
  expect_identical(cycle_integration_files(root), locked)
  scAgentKit:::.sc_run_release(root, lock)
  expect_identical(cycle_integration_files(root), bytes)
  cycle_integration_decide(root, snapshot)
  approved <- cycle_integration_files(root)
  expect_identical(cycle_integration_decide(root, snapshot)$stage, "strategy_apply")
  expect_identical(cycle_integration_files(root), approved)
  expect_error(cycle_integration_continue(root, snapshot), "[Ss]tale|revision")
  expect_identical(cycle_integration_files(root), approved)
  state <- scAgentKit:::.sc_run_load(root)
  changed <- state$config; changed$cycle_diagnostics$seed <- 18L
  expect_false(identical(scAgentKit:::.sc_run_strategy_scope_config_hash(changed),
    snapshot$strategy_review$calculation_scope_hash))
  changed <- state$config; changed$cycle_diagnostics$column_prefix <- "other_cycle"
  expect_false(identical(scAgentKit:::.sc_run_strategy_scope_config_hash(changed),
    snapshot$strategy_review$calculation_scope_hash))
  changed <- state$config
  changed$cycle_diagnostics$gene_set <- sc_cycle_gene_set("human",
    s_genes = state$config$cycle_diagnostics$gene_set$s_genes,
    g2m_genes = state$config$cycle_diagnostics$gene_set$g2m_genes,
    source = "Synthetic provenance scope control", version = "new-version")
  expect_false(identical(scAgentKit:::.sc_run_strategy_scope_config_hash(changed),
    snapshot$strategy_review$calculation_scope_hash))
  # Recomputed state/config envelope hashes cannot renew the original authority.
  copied <- cycle_integration_copy(root); roots <- c(roots, copied)
  altered <- scAgentKit:::.sc_run_load(copied)
  altered$config$cycle_diagnostics$seed <- 18L
  altered$config_hash <- scAgentKit:::.sc_run_hash(altered$config)
  scAgentKit:::.sc_run_save(copied, altered)
  tampered <- cycle_integration_files(copied)
  saved_snapshot <- sc_run_inspect(root)
  expect_error(cycle_integration_continue(copied, saved_snapshot), "[Ss]tale|changed|fingerprint|options|approval")
  expect_identical(cycle_integration_files(copied), tampered)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("changed input fixed score or cycle review checkpoints reject approved Continue without writes", {
  network <- cycle_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  base <- tempfile(); roots <- c(roots, base)
  cycle_integration_begin(base, proposal = cycle_integration_plan("full"))
  cycle_integration_decide(base)
  approved <- sc_run_inspect(base)
  for (key in c("input", "cycle_diagnostics", "strategy_evidence", "strategy_validated", "strategy_review")) {
    root <- cycle_integration_copy(base); roots <- c(roots, root)
    state <- scAgentKit:::.sc_run_load(root)
    path <- file.path(root, state$files[[key]]$path)
    value <- readRDS(path)
    if (key == "cycle_diagnostics") value$scores$sc_cycle_S.Score[[1L]] <- 999 else
      value <- list(altered = paste("Synthetic tampered", key, "checkpoint"))
    saveRDS(value, path)
    bytes <- cycle_integration_files(root)
    expect_error(cycle_integration_continue(root, approved), "[Ss]tale|changed")
    expect_error(sc_run_resume(root), "[Ss]tale|changed")
    expect_identical(cycle_integration_files(root), bytes)
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("fresh cycle columns cannot overwrite a source field and unsupported species never obtain review", {
  network <- cycle_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  root <- tempfile(); roots <- c(roots, root)
  object <- cycle_integration_fixture()
  object$sc_cycle_S.Score <- rep(-999, ncol(object))
  original <- serialize(object, NULL, version = 2L)
  calls <- 0L
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    jsonlite::toJSON(cycle_integration_plan(), auto_unbox = TRUE, null = "null")
  }
  stopped <- cycle_integration_begin(root, object, proposal = NULL,
    provider = list(name = "mock", external = FALSE, model = "unreached-cycle-control"),
    chat_fn = callback)
  expect_identical(stopped$status, "failed")
  expect_identical(stopped$stage, "strategy_evidence")
  expect_match(stopped$failure$message, "output column already exists|fresh.*prefix|fresh.*column")
  expect_identical(calls, 0L)
  state <- scAgentKit:::.sc_run_load(root)
  expect_null(state$files$cycle_diagnostics)
  expect_null(state$files$qc_object)
  expect_null(state$files$strategy_request)
  expect_null(state$files$strategy_review)
  expect_null(state$approved)
  saved <- scAgentKit:::.sc_run_get(root, state, "input")
  expect_identical(saved$sc_cycle_S.Score, object$sc_cycle_S.Score)
  expect_identical(serialize(saved, NULL, version = 2L), original)
  bytes <- cycle_integration_files(root)
  expect_identical(cycle_integration_continue(root)$status, "failed")
  expect_identical(sc_run_resume(root, chat_fn = callback)$status, "failed")
  expect_identical(cycle_integration_files(root), bytes)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(calls, 0L)
  for (enabled in c(FALSE, TRUE)) {
    unsupported <- tempfile(); roots <- c(roots, unsupported)
    context <- cycle_integration_context(); context$species <- "zebrafish"
    expect_error(suppressWarnings(sc_run(cycle_integration_fixture(), unsupported,
      context = context, strategy = TRUE, strategy_proposal = cycle_integration_plan(),
      cycle_diagnostics = if (enabled) cycle_integration_options() else NULL)), "human or mouse|[Uu]nsupported species")
    expect_false(file.exists(file.path(unsupported, "state.rds")))
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("noncycle PC and actual QC revisions each approve Continue and complete Unknown with correct reuse", {
  network <- cycle_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  base <- tempfile(); roots <- c(roots, base)
  object <- cycle_integration_fixture(cycle_genes = FALSE)
  original <- serialize(object, NULL, version = 2L)
  initial <- suppressWarnings(sc_run(object, base, context = cycle_integration_context(),
    strategy = TRUE, strategy_proposal = cycle_integration_plan(), budget = 0,
    annotation_column = "reviewed_type"))
  expect_identical(initial$status, "awaiting_review")
  expect_null(scAgentKit:::.sc_run_load(base)$files$cycle_diagnostics)
  expect_null(sc_run_inspect(base)$strategy_review$details$canonical_proposal$cycle)
  cycle_integration_decide(base)
  expect_identical(cycle_integration_continue(base)$stage, "annotation_propose")
  cycle_integration_unknown(base); cycle_integration_decide(base)
  before <- scAgentKit:::.sc_run_load(base)
  prior_annotation <- sc_run_inspect(base)
  expect_identical(before$approved$kind, "annotation")
  for (kind in c("pcs", "qc")) {
    root <- cycle_integration_copy(base); roots <- c(roots, root)
    proposal <- cycle_integration_plan()
    if (kind == "pcs") proposal$pcs$ndim <- 4L else {
      proposal$qc$filters[[1L]]$min <- 2L
      proposal$qc$rationale <- "Also remove the planted one-count control in this actual QC revision."
    }
    revised <- cycle_integration_revise(root, proposal)
    expect_identical(revised$status, "awaiting_review")
    state <- scAgentKit:::.sc_run_load(root)
    expect_null(state$approved)
    expect_false(any(c("manual_annotation", "annotation_validated", "annotation_review") %in% names(state$files)))
    expect_error(cycle_integration_decide(root, prior_annotation), "[Ss]tale|different review kind")
    expect_identical(state$history[seq_along(before$history)], before$history)
    if (kind == "pcs") {
      expect_identical(state$files[c("qc_object", "strategy_basis")], before$files[c("qc_object", "strategy_basis")])
    } else {
      expect_null(state$files$qc_object); expect_null(state$files$strategy_basis)
    }
    cycle_integration_decide(root)
    boundary <- cycle_integration_child(root)
    expect_identical(boundary$status$status, "awaiting_configuration")
    expect_identical(boundary$status$stage, "annotation_propose")
    state <- scAgentKit:::.sc_run_load(root)
    expected_cells <- colnames(object)[seq_len(if (kind == "pcs") 119L else 118L)]
    analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
    cycle_integration_preserved(analysis, object, expected_cells)
    expect_false(any(startsWith(names(analysis[[]]), "sc_cycle_")))
    if (kind == "pcs") {
      expect_identical(state$files[c("qc_object", "strategy_basis")], before$files[c("qc_object", "strategy_basis")])
      expect_equal(analysis@misc$strategy_execution$neighbors$pcs$ndim, 4L)
      expect_identical(cycle_integration_executions(state, "qc_apply"), 1L)
      expect_identical(cycle_integration_executions(state, "strategy_basis"), 1L)
    } else {
      expect_false(identical(state$files$qc_object, before$files$qc_object))
      expect_false(identical(state$files$strategy_basis, before$files$strategy_basis))
      expect_identical(cycle_integration_executions(state, "qc_apply"), 2L)
      expect_identical(cycle_integration_executions(state, "strategy_basis"), 2L)
      expect_false(colnames(object)[[119L]] %in% colnames(analysis))
    }
    for (stage in c("strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
      expect_identical(cycle_integration_executions(state, stage), 2L)
    expect_identical(cycle_integration_executions(state, "strategy_evidence"), 1L)
    expect_null(state$files$annotated)
    cycle_integration_unknown(root)
    exact_annotation <- sc_run_inspect(root)
    expect_identical(exact_annotation$review_node$kind, "annotation")
    cycle_integration_decide(root, exact_annotation)
    completed <- cycle_integration_child(root)
    expect_identical(completed$status$status, "complete")
    output <- readRDS(completed$status$output$seurat)
    cycle_integration_preserved(output, object, expected_cells)
    expect_true(all(output$reviewed_type == "Unknown"))
    expect_null(scAgentKit:::.sc_run_load(root)$files$cycle_diagnostics)
    expect_false(dir.exists(file.path(root, "provider")))
    expect_identical(serialize(object, NULL, version = 2L), original)
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("one aggregate mock response is cached and an omitted cycle choice never authorizes goal-driven regression", {
  network <- cycle_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L; seen <- NULL
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    seen <<- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    list(content = as.character(jsonlite::toJSON(cycle_integration_plan(),
      auto_unbox = TRUE, null = "null")), cost_usd = 0,
      usage = list(input_tokens = 0L, output_tokens = 0L))
  }
  provider <- list(name = "mock", external = FALSE, model = "synthetic-cycle-only")
  context <- cycle_integration_context()
  context$research_goal <- "Remove cell-cycle effects if a model thinks regression is needed."
  initial <- cycle_integration_begin(root, proposal = NULL, context = context,
    provider = provider, chat_fn = callback)
  expect_identical(initial$status, "awaiting_review")
  expect_identical(calls, 1L)
  expect_identical(seen$evidence$background_facts$research_goal, context$research_goal)
  expect_identical(seen$evidence$cycle_diagnostics$status, "available")
  expect_equal(seen$evidence$cycle_diagnostics$cohort$input_cells, 120L)
  expect_null(seen$evidence$private)
  expect_null(seen$evidence$cycle_diagnostics$scores)
  expect_null(seen$evidence$cycle_diagnostics$cell_ids)
  state <- scAgentKit:::.sc_run_load(root)
  request <- scAgentKit:::.sc_run_get(root, state, "strategy_request")
  expect_false(grepl("literalCycleCell", request$user_prompt, fixed = TRUE))
  expect_false(grepl("Private per-cell field", request$user_prompt, fixed = TRUE))
  expect_false(grepl('"cell_id"', request$user_prompt, fixed = TRUE))
  expect_identical(sc_run_inspect(root)$strategy_review$details$canonical_proposal$cycle$method, "none")
  bytes <- cycle_integration_files(root)
  expect_identical(sc_run_resume(root, chat_fn = callback)$status, "awaiting_review")
  expect_identical(cycle_integration_files(root), bytes)
  expect_identical(calls, 1L)
  evidence <- scAgentKit:::.sc_run_get(root, state, "strategy_evidence")
  request$validator <- function(value) scAgentKit:::.sc_run_strategy_validate(value, evidence)$proposal
  ledger <- file.path(root, "provider", "ledger.json")
  ledger_hash <- scAgentKit:::.sc_project_sha_file(ledger)
  cached <- scAgentKit:::.sc_run_call(root, request, provider = provider, chat_fn = callback, budget = 0)
  expect_identical(cached$status, "ok"); expect_true(cached$cached)
  expect_equal(cached$charged_or_held_usd, 0)
  expect_identical(calls, 1L)
  expect_identical(scAgentKit:::.sc_project_sha_file(ledger), ledger_hash)
  cycle_integration_decide(root)
  boundary <- cycle_integration_continue(root)
  expect_identical(boundary$status, "awaiting_configuration")
  expect_identical(boundary$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
  expect_identical(analysis@misc$strategy_execution$basis$regressors, character())
  cycle_integration_scores(analysis, scAgentKit:::.sc_run_get(root, state, "cycle_diagnostics"))
  boundary_bytes <- cycle_integration_files(root)
  expect_identical(cycle_integration_child(root)$status$status, "awaiting_configuration")
  expect_identical(cycle_integration_files(root), boundary_bytes)
  cycle_integration_unknown(root); cycle_integration_decide(root)
  completed <- cycle_integration_child(root)
  expect_identical(completed$status$status, "complete")
  expect_true(all(readRDS(completed$status$output$seurat)$reviewed_type == "Unknown"))
  expect_identical(calls, 1L)
  expect_identical(scAgentKit:::.sc_project_sha_file(ledger), ledger_hash)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("missing or insufficient literal cycle genes complete with none and Unknown while regression revisions reject atomically", {
  network <- cycle_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  for (coverage in c("missing", "partial")) {
    root <- tempfile(); roots <- c(roots, root)
    object <- cycle_integration_fixture(coverage = coverage)
    original <- serialize(object, NULL, version = 2L)
    initial <- cycle_integration_begin(root, object)
    expect_identical(initial$status, "awaiting_review")
    state <- scAgentKit:::.sc_run_load(root)
    record <- scAgentKit:::.sc_run_get(root, state, "cycle_diagnostics")
    expect_identical(record$summary$status, "insufficient")
    expect_equal(record$summary$cohort$removed_cells, 0L)
    expect_equal(record$summary$cohort$unknown_cells, 120L)
    expect_true(all(record$scores$sc_cycle_Phase == "Unknown"))
    expect_true(all(is.na(record$scores$sc_cycle_S.Score)))
    expect_true(all(is.na(record$scores$sc_cycle_G2M.Score)))
    expect_true(all(is.na(record$scores$sc_cycle_CC.Difference)))
    if (coverage == "missing") {
      expect_equal(record$summary$coverage$S$present, 0L)
      expect_equal(record$summary$coverage$G2M$present, 0L)
    } else {
      expect_lt(record$summary$coverage$S$expressed, 5L)
      expect_lt(record$summary$coverage$G2M$expressed, 5L)
    }
    snapshot <- sc_run_inspect(root); bytes <- cycle_integration_files(root)
    for (method in c("full", "difference")) {
      expect_error(cycle_integration_revise(root, cycle_integration_plan(method), snapshot),
        "[Ii]napplicable|insufficient")
      expect_identical(cycle_integration_files(root), bytes)
    }
    cycle_integration_decide(root, snapshot)
    stopped <- cycle_integration_continue(root)
    expect_identical(stopped$status, "awaiting_configuration")
    state <- scAgentKit:::.sc_run_load(root)
    analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
    expect_identical(analysis@misc$strategy_execution$basis$regressors, character())
    cycle_integration_preserved(analysis, object, colnames(object)[1:119])
    cycle_integration_scores(analysis, record)
    cycle_integration_unknown(root); cycle_integration_decide(root)
    completed <- cycle_integration_child(root)
    expect_identical(completed$status$status, "complete")
    output <- readRDS(completed$status$output$seurat)
    cycle_integration_preserved(output, object, colnames(object)[1:119])
    cycle_integration_scores(output, record)
    expect_true(all(output$reviewed_type == "Unknown"))
    expect_identical(serialize(object, NULL, version = 2L), original)
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("processed cycle diagnostics preserve supplied foundation and never report historical regression as current execution", {
  network <- cycle_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- cycle_integration_fixture()
  object@misc$strategy_execution <- list(basis = list(cycle_method = "full",
    regressors = c("historical_S", "historical_G2M")))
  original <- serialize(object, NULL, version = 2L)
  proposal <- cycle_integration_plan("none")
  proposal[c("qc", "analysis", "pcs", "clustering", "umap")] <- rep(list(NULL), 5L)
  begun <- suppressWarnings(sc_run(object, root, context = cycle_integration_context(),
    strategy = TRUE, strategy_proposal = proposal, cycle_diagnostics = cycle_integration_options(),
    start_stage = "processed", processed_reason = "Explicit synthetic supplied foundation; reuse all existing cells/data/clusters.",
    cluster_column = "source_cluster", annotation_column = "reviewed_type"))
  expect_identical(begun$status, "awaiting_review")
  for (method in c("full", "difference")) {
    changed <- proposal; changed$cycle$method <- method
    expect_error(cycle_integration_revise(root, changed), "Processed|processed")
  }
  supplied_analysis <- scAgentKit:::.sc_run_load(root)$files$analysis
  manual <- proposal; manual$batch <- list(method = "manual", reason = "Explicit analyst boundary; retain supplied foundation.")
  cycle_integration_revise(root, manual); cycle_integration_decide(root)
  boundary <- cycle_integration_child(root)$status
  expect_identical(boundary$status, "awaiting_configuration")
  expect_identical(boundary$stage, "strategy_apply")
  expect_identical(scAgentKit:::.sc_run_load(root)$files$analysis, supplied_analysis)
  cycle_integration_revise(root, proposal)
  expect_identical(scAgentKit:::.sc_run_load(root)$files$analysis, supplied_analysis)
  cycle_integration_decide(root)
  stopped <- cycle_integration_child(root)$status
  expect_identical(stopped$stage, "annotation_propose")
  cycle_integration_unknown(root); cycle_integration_decide(root)
  finished <- cycle_integration_child(root)$status
  expect_identical(finished$status, "complete")
  output <- readRDS(finished$output$seurat)
  expect_identical(serialize(object, NULL, version = 2L), original)
  cycle_integration_preserved(output, object, colnames(object))
  expect_identical(SeuratObject::LayerData(output, assay = "RNA", layer = "data"),
    SeuratObject::LayerData(object, assay = "RNA", layer = "data"))
  state <- scAgentKit:::.sc_run_load(root)
  for (stage in c("qc_apply", "strategy_preprocess", "strategy_basis", "strategy_neighbors", "strategy_cluster"))
    expect_equal(cycle_integration_executions(state, stage), 0L)
  summary <- jsonlite::read_json(file.path(root, "output/cycle_summary.json"), simplifyVector = TRUE)
  expect_identical(summary$execution$cycle_method, "none")
  expect_false(summary$execution$scaling_executed)
  expect_length(summary$execution$regressors, 0L)
  expect_equal(network$factory + network$http, 0L)
})

test_that("no-provider cycle projects remain inspectable configuration boundaries without invented review hashes", {
  network <- cycle_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  begun <- sc_run(cycle_integration_fixture(), root, context = cycle_integration_context(),
    strategy = TRUE, cycle_diagnostics = cycle_integration_options(), budget = 0)
  expect_identical(begun$status, "awaiting_configuration")
  view <- sc_run_inspect(root)
  expect_identical(view$stage, "strategy_propose")
  expect_null(view$review_node)
  expect_null(view$strategy_review)
  before <- cycle_integration_files(root)
  expect_identical(sc_run_inspect(root)$revision, view$revision)
  expect_identical(cycle_integration_files(root), before)
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(scAgentKit:::.sc_run_get(root, state, "cycle_diagnostics")$summary$status, "available")
  expect_equal(network$factory + network$http, 0L)
})
