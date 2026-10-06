# Harmony is mocked only at its public upstream generic in these coordinator
# tests. Real sparse QC/PCA/neighbors/markers and durable reviews still execute
# when root runs this file. Planted expression and shifted embeddings establish
# software invariants, not effective batch correction or biological truth.

harmony_integration_fixture <- function() {
  set.seed(9417L)
  cells <- c("001", "1", "NA", "cell space", paste0("harmonyCell", 5:120))
  features <- c("MT-CO1", paste0("HarmonyGene", 2:240))
  counts <- matrix(stats::rpois(length(features) * length(cells), 2),
    nrow = length(features), dimnames = list(features, cells))
  for (program in seq_len(4L)) {
    genes <- seq.int((program - 1L) * 20L + 2L, program * 20L + 1L)
    chosen <- seq.int((program - 1L) * 30L + 1L, program * 30L)
    counts[genes, chosen] <- counts[genes, chosen] + 8L
  }
  counts[, 120L] <- 0L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  indices <- 0:119
  object$group <- ifelse(indices %% 2L == 0L, "Ca", "Ctrl")
  object$condition <- ifelse((indices %/% 2L) %% 2L == 0L, "condition A", "condition B")
  object$treatment <- ifelse((indices %/% 4L) %% 2L == 0L, "vehicle", "drug")
  object$batch <- ifelse((indices %/% 8L) %% 2L == 0L, "technical A", "technical B")
  object$sample <- factor(ifelse((indices %/% 16L) %% 2L == 0L, "sample A", "sample B"),
    levels = c("sample B", "sample A", "unused sample"))
  object$donor <- paste0("donor ", (indices %/% 32L) %% 4L + 1L)
  object$capture <- paste0("capture ", indices %% 3L + 1L)
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 60L),
    levels = c("prior A", "unused prior B"))
  object$source_cluster <- factor(rep(c("01", "NA"), each = 60L), levels = c("NA", "01"))
  object$private_note <- "Private per-cell control field is never an aggregate model payload."
  object
}

harmony_integration_context <- function() list(species = "human", tissue = "synthetic",
  columns = list(sample = "sample", donor = "donor", capture = "capture", batch = "batch",
    group = "group", condition = "condition", treatment = "treatment"),
  design = list(type = "independent technical and biological metadata factors",
    technical_batch = TRUE,
    notes = "Fixture factors are explicit software declarations; no role or necessity of correction is inferred."),
  research_goal = "Review an explicit embedding-only correction and preserve the original scientific inputs.",
  notes = "Treatment is observed biology; excluding it from correction is not evidence its signal is preserved.")

harmony_integration_batch <- function(method = "harmony", vars = "batch") {
  if (method != "harmony") return(list(method = method,
    reason = "Explicit synthetic analyst choice; no batch correction is inferred."))
  list(method = "harmony", group_by_vars = vars, theta = 2, lambda = 1,
    sigma = .1, max_iter = 20L, nclust = 10L,
    reason = "Explicit supported software-control settings, not an automatically recommended biological analysis.")
}

harmony_integration_plan <- function(method = "harmony", vars = "batch",
                                     pcs = list(method = "fixed", ndim = 5L)) {
  list(schema = "scagentkit.strategy.v1",
    rationale = "Review the declared technical factors, actual QC impact and explicit analysis together.",
    risks = list("Design estimability and a finite embedding do not prove successful biological integration."),
    inferences = list("Planted expression programs are not known cell identities or evidence of batch effects."),
    qc = list(schema = "scagentkit.qc.v1", rationale = "Remove only the literal zero-count synthetic control.",
      risks = list("This software rule is not a recommended biological threshold."),
      filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 80L, npcs = 15L, seed = 999L),
    pcs = pcs, batch = harmony_integration_batch(method, vars),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
    umap = list(run = FALSE, n_neighbors = 10L))
}

harmony_integration_begin <- function(root, object = harmony_integration_fixture(),
                                      proposal = harmony_integration_plan(),
                                      context = harmony_integration_context()) {
  suppressWarnings(sc_run(object, root, context = context, strategy = TRUE,
    strategy_proposal = proposal, budget = 0, annotation_column = "reviewed_type"))
}

harmony_integration_record <- function(root, name) {
  scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), name)
}
harmony_integration_continue <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, retry = retry))
}
harmony_integration_decide <- function(root, snapshot = sc_run_inspect(root), action = "approve") {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline Harmony QA", reason = "Approve exactly the declared whole strategy and current evidence.")
}
harmony_integration_revise <- function(root, proposal, snapshot = sc_run_inspect(root)) {
  sc_run_strategy_revise(root, proposal, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, "offline Harmony QA", "Revise only the explicitly supported whole strategy.")
}
harmony_integration_unknown <- function(root) {
  evidence <- sc_run_inspect(root)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(evidence$clusters, function(row) list(clusterId = row$clusterId,
      label = "Unknown", confidence = "low",
      rationale = "Synthetic shifted embeddings cannot establish biological identities.", markers = list())))
  sc_run_propose(root, proposal, "offline Harmony QA", "Review explicit Unknown labels independently.")
}
harmony_integration_files <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(files, nchar(root) + 2L))
}
harmony_integration_copy <- function(root) {
  target <- tempfile("harmony-copy-"); dir.create(target)
  if (!all(file.copy(list.files(root, full.names = TRUE, all.files = TRUE, no.. = TRUE),
    target, recursive = TRUE, copy.mode = TRUE))) stop("Could not copy the stopped Harmony project.")
  target
}
harmony_integration_executions <- function(state, stage) {
  length(Filter(function(event) identical(event$action, "executed") &&
    identical(event$details$stage, stage), state$history))
}
harmony_integration_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) { calls$factory <- calls$factory + 1L; stop("Offline Harmony QA forbids provider factories.") }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Offline Harmony QA forbids network dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

harmony_integration_upstream <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$count <- 0L; calls$inputs <- list(); calls$mode <- "ok"
  upstream <- function(...) {
    args <- list(...); object <- args$object
    calls$count <- calls$count + 1L
    if (isTRUE(getOption("harmony_fixture_forbid_call"))) stop("Cached Harmony fixture must not execute again.")
    calls$inputs[[length(calls$inputs) + 1L]] <- list(parameters = args[names(args) != "object"],
      pca = SeuratObject::Embeddings(object[["pca"]]), metadata = object[[]],
      layers = stats::setNames(lapply(SeuratObject::Layers(object[["RNA"]]), function(layer)
        SeuratObject::LayerData(object, assay = "RNA", layer = layer)), SeuratObject::Layers(object[["RNA"]])))
    if (identical(calls$mode, "error")) stop("Injected explicit upstream Harmony failure.")
    selected <- SeuratObject::Embeddings(object[["pca"]])[, args$dims.use, drop = FALSE]
    # Consume RNG deliberately: only the adapter's recorded seed scope may
    # affect this upstream call, and it must restore the caller's RNG state.
    stats::runif(1L)
    first <- as.character(object[[]][[args$group.by.vars[[1L]]]])
    selected[, 1L] <- selected[, 1L] + ifelse(first == sort(unique(first), method = "radix")[[1L]], -.1, .1)
    colnames(selected) <- paste0("HARMONY_", seq_len(ncol(selected)))
    object[["harmony"]] <- SeuratObject::CreateDimReducObject(embeddings = selected,
      key = "HARMONY_", assay = "RNA")
    object
  }
  # The installed public generic has exactly (...). Keep that signature and
  # leave the actual Seurat/default method bodies and their namespace intact.
  environment(upstream) <- list2env(list(calls = calls), parent = baseenv())
  testthat::local_mocked_bindings(RunHarmony = upstream, .package = "harmony", .env = env)
  calls
}

harmony_integration_child <- function(root, snapshot = sc_run_inspect(root)) {
  work <- tempfile("harmony-child-"); dir.create(work); on.exit(unlink(work, recursive = TRUE), add = TRUE)
  args_path <- file.path(work, "arguments.rds"); result <- file.path(work, "result.rds")
  script <- file.path(work, "child.R"); log <- file.path(work, "stdout.log")
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path"),
    upstream = get("RunHarmony", envir = asNamespace("harmony"))), args_path)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','GROK_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','AZURE_OPENAI_API_KEY','COHERE_API_KEY','MISTRAL_API_KEY','OPENROUTER_API_KEY','HF_TOKEN','HUGGINGFACEHUB_API_TOKEN'))",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else library(scAgentKit,lib.loc=dirname(args$package))",
    "factory_calls <- 0L; http_calls <- 0L",
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('No remote Harmony factory permitted') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('No Harmony HTTP permitted') },.package='httr2',.env=environment())",
    "testthat::local_mocked_bindings(RunHarmony=args$upstream,.package='harmony',.env=environment())",
    "options(harmony_fixture_forbid_call=TRUE)",
    "before <- environment(args$upstream)$calls$count",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision))",
    "upstream_calls <- environment(args$upstream)$calls$count-before",
    "stopifnot(factory_calls==0L,http_calls==0L,upstream_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls,upstream_calls=upstream_calls),args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(args_path)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

harmony_integration_preserved <- function(object, source, cells) {
  expect_identical(colnames(object), cells); expect_identical(rownames(object), rownames(source))
  for (column in names(source[[]])) expect_identical(object[[]][[column]], source[[]][cells, column])
  for (layer in c("counts", "extra")) {
    actual <- SeuratObject::LayerData(object, assay = "RNA", layer = layer)
    expect_identical(actual, SeuratObject::LayerData(source, assay = "RNA", layer = layer)[, cells, drop = FALSE])
    expect_true(inherits(actual, "sparseMatrix"))
  }
}

test_that("explicit Harmony uses only approved PCs and technical factors under one strategy then separate annotation review", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- harmony_integration_fixture(); original <- serialize(object, NULL, version = 2L)
  begun <- harmony_integration_begin(root, object)
  expect_identical(begun$status, "awaiting_review")
  snapshot <- sc_run_inspect(root)
  expect_identical(snapshot$review_node$kind, "strategy")
  expect_true(harmony_integration_record(root, "strategy_validated")$executable)
  expect_identical(snapshot$strategy_review$details$canonical_proposal$batch$group_by_vars, "batch")
  expect_null(scAgentKit:::.sc_run_load(root)$files$strategy_batch)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  expect_identical(upstream$count, 0L)
  harmony_integration_decide(root)
  paused <- harmony_integration_continue(root)
  expect_identical(paused$status, "awaiting_configuration"); expect_identical(paused$stage, "annotation_propose")
  expect_identical(upstream$count, 1L)
  expected <- colnames(object)[1:119]
  basis <- harmony_integration_record(root, "strategy_basis")
  corrected <- harmony_integration_record(root, "strategy_batch")
  analysis <- harmony_integration_record(root, "analysis")
  harmony_integration_preserved(corrected, object, expected)
  harmony_integration_preserved(analysis, object, expected)
  expect_false("harmony" %in% names(basis@reductions))
  expect_true("harmony" %in% names(corrected@reductions))
  expect_identical(corrected[["pca"]], basis[["pca"]])
  expect_identical(corrected[[]], basis[[]])
  for (layer in SeuratObject::Layers(basis[["RNA"]]))
    expect_identical(SeuratObject::LayerData(corrected, assay = "RNA", layer = layer),
      SeuratObject::LayerData(basis, assay = "RNA", layer = layer))
  input <- upstream$inputs[[1L]]
  expect_identical(input$pca, SeuratObject::Embeddings(basis[["pca"]]))
  expect_identical(input$parameters$group.by.vars, "batch")
  expect_identical(input$parameters$dims.use, 1:5)
  expect_identical(input$parameters$reduction.use, "pca")
  expect_identical(input$parameters$reduction.save, "harmony")
  expect_false(input$parameters$project.dim); expect_equal(input$parameters$ncores, 1L)
  expect_equal(input$parameters$theta, 2); expect_equal(input$parameters$lambda, 1)
  expect_equal(input$parameters$sigma, .1); expect_equal(input$parameters$max_iter, 20L)
  expect_equal(input$parameters$nclust, 10L)
  expect_false(any(c("group", "condition", "treatment", "capture") %in% input$parameters$group.by.vars))
  expect_identical(analysis@misc$strategy_execution$neighbors$reduction, "harmony")
  state <- scAgentKit:::.sc_run_load(root)
  for (stage in c("strategy_evidence", "qc_apply", "strategy_basis", "strategy_batch",
    "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
    expect_identical(harmony_integration_executions(state, stage), 1L)
  bytes <- harmony_integration_files(root)
  expect_identical(harmony_integration_child(root)$status$status, "awaiting_configuration")
  expect_identical(harmony_integration_files(root), bytes)
  harmony_integration_unknown(root); annotation <- sc_run_inspect(root)
  expect_identical(annotation$review_node$kind, "annotation")
  harmony_integration_decide(root, annotation)
  finished <- harmony_integration_child(root)
  expect_identical(finished$status$status, "complete")
  bundled <- jsonlite::fromJSON(file.path(root, "bundle", "project.json"), simplifyVector = FALSE)$parameters
  expect_identical(bundled$batchIntegration, "harmony")
  expect_equal(bundled$analysis$nfeatures, 80L)
  expect_true(bundled$analysisExecution$foundationExecuted)
  expect_identical(bundled$analysisExecution$activeReduction, "harmony")
  expect_identical(bundled$analysisExecution$strategySummary$sha256,
    scAgentKit:::.sc_project_sha_file(file.path(root, "output", "strategy_summary.json")))
  expect_identical(bundled$analysisExecution$batchDiagnostics$sha256,
    scAgentKit:::.sc_project_sha_file(file.path(root, "output", "batch_diagnostics.json")))
  output <- readRDS(finished$status$output$seurat)
  harmony_integration_preserved(output, object, expected)
  expect_identical(output[["pca"]], basis[["pca"]])
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_true(all(c("001", "1", "NA", "cell space") %in% colnames(output)))
  approvals <- Filter(function(event) identical(event$action, "approved"), scAgentKit:::.sc_run_load(root)$history)
  expect_identical(vapply(approvals, function(event) event$details$kind, character(1)), c("strategy", "annotation"))
  expect_identical(upstream$count, 1L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("batch or reviewed PC revisions reuse original QC and PCA while rebuilding only corrected embeddings and downstream work", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); roots <- root; on.exit(unlink(roots, recursive = TRUE), add = TRUE)
  object <- harmony_integration_fixture()
  object@misc$strategy_execution <- list(schema = "scagentkit.strategy-execution.v1",
    batch = list(choice = list(method = "harmony", reason = "Inherited historical software claim, not current execution."),
      corrected = TRUE, reduction = "harmony", fake_historical_control = TRUE))
  original <- serialize(object, NULL, version = 2L)
  harmony_integration_begin(root, object, harmony_integration_plan("none"))
  harmony_integration_decide(root); harmony_integration_continue(root)
  first <- scAgentKit:::.sc_run_load(root)
  immutable_keys <- c("input", "qc_evidence", "strategy_evidence", "qc_object", "strategy_basis")
  immutable <- first$files[immutable_keys]
  expect_null(first$files$strategy_batch); expect_identical(upstream$count, 0L)
  expect_null(harmony_integration_record(root, "strategy_basis")@misc$strategy_execution$batch)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(serialize(harmony_integration_record(root, "input"), NULL, version = 2L), original)
  # Complete an isolated copy of this already-computed none foundation. No
  # additional QC/PCA/Harmony run is needed to verify honest final reporting.
  none_copy <- harmony_integration_copy(root); roots <- c(roots, none_copy)
  harmony_integration_unknown(none_copy); harmony_integration_decide(none_copy)
  none_finished <- harmony_integration_child(none_copy)
  expect_identical(none_finished$status$status, "complete")
  none_output <- readRDS(none_finished$status$output$seurat)
  expect_null(none_output@misc$strategy_execution$batch)
  none_summary <- jsonlite::fromJSON(file.path(none_copy, "output", "batch_diagnostics.json"), simplifyVector = FALSE)
  expect_identical(none_summary$approved_choice$method, "none")
  expect_false(none_summary$executed); expect_null(none_summary$execution)
  expect_identical(none_summary$active_reduction, "pca")
  none_bundle <- jsonlite::fromJSON(file.path(none_copy, "bundle", "project.json"), simplifyVector = FALSE)$parameters
  expect_identical(none_bundle$batchIntegration, "none")
  expect_identical(none_bundle$analysisExecution$activeReduction, "pca")
  expect_true(none_bundle$analysisExecution$foundationExecuted)
  expect_identical(upstream$count, 0L)
  last <- first
  for (step in seq_len(3L)) {
    proposal <- harmony_integration_plan()
    if (step == 2L) proposal$batch$theta <- 3
    if (step == 3L) {
      proposal$batch$theta <- 3
      proposal$pcs <- list(method = "computed_top50", threshold = .80)
    }
    old <- sc_run_inspect(root)
    # Browser serialization cannot broaden the selected factors or silently
    # change integer-vs-double QC bounds into a new QC calculation.
    proposal <- jsonlite::fromJSON(jsonlite::toJSON(proposal, auto_unbox = TRUE, null = "null"), simplifyVector = FALSE)
    harmony_integration_revise(root, proposal)
    revised <- scAgentKit:::.sc_run_load(root)
    expect_identical(revised$files[immutable_keys], immutable)
    for (key in c("strategy_batch", "strategy_neighbors", "analysis", "markers", "annotation_evidence"))
      expect_null(revised$files[[key]])
    expect_error(harmony_integration_continue(root, old), "[Ss]tale|revision")
    harmony_integration_decide(root); harmony_integration_continue(root)
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[immutable_keys], immutable)
    expect_identical(upstream$count, step)
    expect_identical(harmony_integration_executions(state, "qc_apply"), 1L)
    expect_identical(harmony_integration_executions(state, "strategy_basis"), 1L)
    expect_identical(harmony_integration_executions(state, "strategy_batch"), step)
    expect_identical(harmony_integration_executions(state, "strategy_neighbors"), step + 1L)
    expect_identical(SeuratObject::Embeddings(harmony_integration_record(root, "strategy_basis")[["pca"]]),
      SeuratObject::Embeddings(readRDS(file.path(root, first$files$strategy_basis$path))[["pca"]]))
    if (step == 3L) {
      pca <- harmony_integration_record(root, "strategy_batch")@misc$strategy_execution$batch$pca
      expect_identical(pca$method, "computed_top50")
      expect_identical(pca$top50_candidates$reference_pcs, 15L)
      expect_identical(pca$top50_candidates$shortfall_count, 35L)
      expect_identical(pca$ndim, pca$top50_candidates$candidates$p80$ndim)
      expect_identical(upstream$inputs[[step]]$parameters$dims.use, seq_len(pca$ndim))
    }
    last <- state
  }
  retained <- last$files[c(immutable_keys, "strategy_batch", "strategy_neighbors", "analysis", "markers", "annotation_evidence")]
  plan <- harmony_integration_record(root, "strategy_validated")$proposal
  hashes <- harmony_integration_record(root, "strategy_validated")$dependency_hashes
  plan$batch$reason <- "Explanation changes only; the same explicit covariates and numbers remain approved."
  harmony_integration_revise(root, plan)
  expect_identical(scAgentKit:::.sc_run_load(root)$files[names(retained)], retained)
  expect_identical(harmony_integration_record(root, "strategy_validated")$dependency_hashes, hashes)
  harmony_integration_decide(root); harmony_integration_child(root)
  expect_identical(scAgentKit:::.sc_run_load(root)$files[names(retained)], retained)
  expect_identical(upstream$count, 3L)
  plan$clustering$resolution <- .6
  harmony_integration_revise(root, plan)
  expect_identical(scAgentKit:::.sc_run_load(root)$files$strategy_batch, retained$strategy_batch)
  expect_identical(scAgentKit:::.sc_run_load(root)$files$strategy_neighbors, retained$strategy_neighbors)
  expect_null(scAgentKit:::.sc_run_load(root)$files$analysis)
  harmony_integration_decide(root); harmony_integration_child(root)
  expect_identical(upstream$count, 3L)
  expect_identical(serialize(object, NULL, version = 2L), original)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("an approved Harmony failure needs explicit retry and reuses the saved QC and PCA", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  harmony_integration_begin(root); harmony_integration_decide(root)
  upstream$mode <- "error"
  failed <- harmony_integration_continue(root)
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "strategy_batch")
  expect_match(failed$failure$message, "Injected explicit upstream Harmony failure")
  state <- scAgentKit:::.sc_run_load(root)
  retained_keys <- c("input", "qc_evidence", "strategy_evidence", "qc_object", "strategy_basis")
  retained <- state$files[retained_keys]
  expect_null(state$files$strategy_batch); expect_null(state$files$analysis)
  expect_identical(upstream$count, 1L)
  bytes <- harmony_integration_files(root)
  expect_identical(harmony_integration_continue(root)$status, "failed")
  expect_identical(sc_run_resume(root)$status, "failed")
  expect_identical(harmony_integration_files(root), bytes)
  upstream$mode <- "ok"
  resumed <- harmony_integration_continue(root, retry = TRUE)
  expect_identical(resumed$status, "awaiting_configuration"); expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[retained_keys], retained)
  expect_identical(upstream$count, 2L)
  for (stage in c("qc_apply", "strategy_basis", "strategy_batch", "strategy_neighbors", "strategy_cluster", "markers"))
    expect_identical(harmony_integration_executions(state, stage), 1L)
  expect_true(any(vapply(state$history, function(event) identical(event$action, "local_continue_retry_requested"), logical(1))))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("unsupported Harmony parameters and biological covariates cannot replace a current reviewed strategy", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  harmony_integration_begin(root)
  snapshot <- sc_run_inspect(root); bytes <- harmony_integration_files(root)
  invalid <- list(list(theta = NaN), list(lambda = 0), list(sigma = Inf), list(sigma = 0),
    list(max_iter = 0L), list(max_iter = 51L), list(nclust = 1L), list(nclust = 120L),
    list(theta = c(batch = 2)), list(lambda = c(1, 2)), list(group_by_vars = c("batch", "batch")),
    list(group_by_vars = "treatment"), list(group_by_vars = "group"), list(group_by_vars = "condition"),
    list(group_by_vars = "capture"), list(group_by_vars = "hallucinated_column"),
    list(code = "system('false')"), list(cell_ids = "001"), list(assume_preserved_treatment = TRUE))
  for (fields in invalid) {
    proposal <- harmony_integration_plan()
    for (key in names(fields)) proposal$batch[[key]] <- fields[[key]]
    expect_error(harmony_integration_revise(root, proposal, snapshot))
    expect_identical(harmony_integration_files(root), bytes)
  }
  for (threshold in c(.799, .801, .9, NaN)) {
    proposal <- harmony_integration_plan(pcs = list(method = "computed_top50", threshold = threshold))
    expect_error(harmony_integration_revise(root, proposal, snapshot))
    expect_identical(harmony_integration_files(root), bytes)
  }
  for (method in c("none", "manual")) {
    proposal <- harmony_integration_plan(method)
    proposal$batch$theta <- 2
    expect_error(harmony_integration_revise(root, proposal, snapshot))
    expect_identical(harmony_integration_files(root), bytes)
  }
  expect_identical(upstream$count, 0L)
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("single missing confounded or aliased design facts block execution without automatic factor substitution", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  for (kind in c("single_factor", "missing_biology", "single_biology", "confounded", "factor_alias", "technical_undeclared")) {
    object <- harmony_integration_fixture(); context <- harmony_integration_context()
    proposal <- harmony_integration_plan()
    if (kind == "single_factor") object$batch <- "one technical level" else
    if (kind == "missing_biology") context$columns[c("group", "condition", "treatment")] <- NULL else
    if (kind == "single_biology") {
      object$group <- "one group"; object$condition <- "one condition"; object$treatment <- "one treatment"
    } else
    if (kind == "confounded") object$batch <- object$treatment else
    if (kind == "factor_alias") { object$sample <- object$batch; proposal$batch$group_by_vars <- c("batch", "sample") } else
      context$design$technical_batch <- FALSE
    root <- tempfile(); roots <- c(roots, root)
    begun <- harmony_integration_begin(root, object, proposal, context)
    expect_identical(begun$status, "awaiting_review")
    validated <- harmony_integration_record(root, "strategy_validated")
    expect_false(validated$executable); expect_gt(length(validated$blockers), 0L)
    expect_identical(validated$proposal$batch$group_by_vars, proposal$batch$group_by_vars)
    harmony_integration_decide(root)
    stopped <- harmony_integration_continue(root)
    expect_identical(stopped$status, "awaiting_configuration")
    state <- scAgentKit:::.sc_run_load(root)
    expect_null(state$files$qc_object); expect_null(state$files$strategy_basis); expect_null(state$files$strategy_batch)
    expect_identical(harmony_integration_executions(state, "strategy_batch"), 0L)
    expect_identical(upstream$count, 0L)
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("Harmony approvals reject stale snapshots tampered batch scope and concurrent or duplicate operations", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); roots <- root; on.exit(unlink(roots, recursive = TRUE), add = TRUE)
  harmony_integration_begin(root)
  snapshot <- sc_run_inspect(root); bytes <- harmony_integration_files(root)
  wrong <- snapshot; wrong$revision <- wrong$revision + 1L
  expect_error(harmony_integration_revise(root, harmony_integration_plan(), wrong), "[Ss]tale|revision")
  wrong <- snapshot; wrong$review_node$review_hash <- strrep("0", 64L)
  expect_error(harmony_integration_decide(root, wrong), "[Ss]tale|fingerprint|hash")
  wrong <- snapshot; wrong$input_hash <- strrep("0", 64L)
  expect_error(harmony_integration_continue(root, wrong), "Foreign|changed input|[Ss]tale")
  expect_identical(harmony_integration_files(root), bytes)
  lock <- scAgentKit:::.sc_run_lock(root); locked <- harmony_integration_files(root)
  expect_error(harmony_integration_decide(root, snapshot), "locked")
  expect_error(harmony_integration_continue(root, snapshot), "locked")
  expect_error(harmony_integration_revise(root, harmony_integration_plan(), snapshot), "locked")
  expect_identical(harmony_integration_files(root), locked)
  scAgentKit:::.sc_run_release(root, lock)
  harmony_integration_decide(root, snapshot); approved <- sc_run_inspect(root)
  saved <- harmony_integration_files(root)
  expect_identical(harmony_integration_decide(root, snapshot)$stage, "strategy_apply")
  expect_identical(harmony_integration_files(root), saved)
  expect_error(harmony_integration_continue(root, snapshot), "[Ss]tale|revision")
  for (key in c("input", "strategy_evidence", "strategy_validated", "strategy_review")) {
    copy <- harmony_integration_copy(root); roots <- c(roots, copy)
    state <- scAgentKit:::.sc_run_load(copy)
    value <- readRDS(file.path(copy, state$files[[key]]$path))
    if (key == "strategy_validated") value$proposal$batch$group_by_vars <- "donor" else
      value <- list(altered = paste("Changed synthetic", key, "artifact"))
    saveRDS(value, file.path(copy, state$files[[key]]$path))
    before <- harmony_integration_files(copy)
    expect_error(harmony_integration_continue(copy, approved), "[Ss]tale|changed")
    expect_identical(harmony_integration_files(copy), before)
  }
  expect_identical(upstream$count, 0L); expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("an explicitly revised public Harmony source rebuilds only its derived cache under a fresh approval", {
  network <- harmony_integration_sentinels(); upstream <- harmony_integration_upstream()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  harmony_integration_begin(root); harmony_integration_decide(root)
  expect_identical(harmony_integration_continue(root)$stage, "annotation_propose")
  expect_identical(upstream$count, 1L)
  snapshot <- sc_run_inspect(root)
  state <- scAgentKit:::.sc_run_load(root)
  proposal <- harmony_integration_record(root, "strategy_validated")$proposal
  hashes <- harmony_integration_record(root, "strategy_validated")$dependency_hashes
  immutable_keys <- c("input", "qc_evidence", "strategy_evidence", "qc_object", "strategy_basis")
  immutable <- state$files[immutable_keys]
  old_batch <- state$files$strategy_batch
  old_source <- scAgentKit:::.sc_run_harmony_source()
  implementation <- scAgentKit:::.sc_run_implementation()
  # Change only a test-scoped public generic body. Its original (...) signature,
  # return behavior, namespace method bodies, package version and closure stay
  # identical; the ignored literal still changes the audited public source hash.
  changed <- get("RunHarmony", envir = asNamespace("harmony"))
  statements <- as.list(body(changed))
  stopifnot(identical(statements[[1L]], as.name("{")))
  body(changed) <- as.call(c(list(as.name("{"),
    quote(harmony_source_drift_fixture_literal <- TRUE)), statements[-1L]))
  testthat::local_mocked_bindings(RunHarmony = changed, .package = "harmony", .env = environment())
  expect_identical(names(formals(changed)), "...")
  new_source <- scAgentKit:::.sc_run_harmony_source()
  expect_identical(new_source$versions, old_source$versions)
  expect_identical(new_source$source_hashes$seurat, old_source$source_hashes$seurat)
  expect_identical(new_source$source_hashes$default, old_source$source_hashes$default)
  expect_false(identical(new_source$source_hashes$generic, old_source$source_hashes$generic))
  expect_identical(scAgentKit:::.sc_run_implementation(), implementation)
  before <- harmony_integration_files(root)
  expect_error(harmony_integration_continue(root, snapshot), "[Ss]tale|source|runtime|changed")
  expect_error(sc_run_inspect(root), "[Ss]tale|source|runtime|changed")
  expect_identical(harmony_integration_files(root), before)
  expect_identical(upstream$count, 1L)
  # The old snapshot remains the exact durable revision: rejection wrote
  # nothing. An explicit whole-strategy revision must acknowledge the new
  # runtime source, retaining the same scientific choice and PCA checkpoint.
  revised <- harmony_integration_revise(root, proposal, snapshot)
  expect_identical(revised$status, "awaiting_review")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[immutable_keys], immutable)
  expect_identical(harmony_integration_record(root, "strategy_validated")$dependency_hashes, hashes)
  for (key in c("strategy_batch", "strategy_neighbors", "analysis", "markers", "annotation_evidence"))
    expect_null(state$files[[key]])
  events <- Filter(function(event) identical(event$action, "cached_harmony_runtime_invalidated"), state$history)
  expect_length(events, 1L)
  expect_identical(events[[1L]]$details$old_source_hash, scAgentKit:::.sc_run_hash(old_source))
  expect_identical(events[[1L]]$details$new_source_hash, scAgentKit:::.sc_run_hash(new_source))
  expect_true(events[[1L]]$details$cached_runtime_changed)
  expect_true(file.exists(file.path(root, old_batch$path)))
  review <- sc_run_inspect(root)
  expect_identical(review$strategy_review$details$batch_runtime_source, new_source)
  expect_identical(review$review_node$kind, "strategy")
  expect_identical(upstream$count, 1L)
  harmony_integration_decide(root, review)
  expect_identical(harmony_integration_continue(root)$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[immutable_keys], immutable)
  expect_identical(upstream$count, 2L)
  expect_false(identical(state$files$strategy_batch, old_batch))
  expect_identical(harmony_integration_record(root, "strategy_batch")@misc$strategy_execution$batch$source, new_source)
  expect_identical(harmony_integration_executions(state, "qc_apply"), 1L)
  expect_identical(harmony_integration_executions(state, "strategy_basis"), 1L)
  for (stage in c("strategy_batch", "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence"))
    expect_identical(harmony_integration_executions(state, stage), 2L)
  cached <- harmony_integration_files(root)
  expect_identical(harmony_integration_child(root)$status$status, "awaiting_configuration")
  expect_identical(harmony_integration_files(root), cached)
  expect_identical(upstream$count, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
