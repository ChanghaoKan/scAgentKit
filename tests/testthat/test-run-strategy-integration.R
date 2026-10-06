# Coordinator acceptance fixtures are synthetic software controls. Planted
# expression programs and crossed metadata do not establish biological types,
# scientific QC thresholds, or an effect of batch integration.
strategy_integration_fixture <- function() {
  set.seed(7413)
  cells <- c("001", "1", "NA", "cell space", paste0("literalCell", 5:96))
  counts <- matrix(stats::rpois(120L * 96L, 1), nrow = 120L,
    dimnames = list(c("MT-CO1", paste0("Gene", 2:120)), cells))
  for (program in seq_len(4L)) {
    genes <- ((program - 1L) * 12L + 2L):((program - 1L) * 12L + 13L)
    selected <- ((program - 1L) * 24L + 1L):(program * 24L)
    counts[genes, selected] <- counts[genes, selected] + 14L
  }
  counts[, 96L] <- 0L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE),
    min.cells = 0, min.features = 0)
  SeuratObject::LayerData(object, assay = "RNA", layer = "extra") <-
    Matrix::Matrix(counts * 2L, sparse = TRUE)
  object$source_cluster <- factor(rep(c("01", "NA"), each = 48L), levels = c("NA", "01"))
  object$old_annotation <- factor(rep(c("prior A", NA_character_), each = 48L),
    levels = c("prior A", "unused prior B"))
  object$sample <- rep(c("sample A", "sample B"), each = 48L)
  object$capture <- rep(c("capture A", "capture B"), each = 48L)
  object$batch <- rep(c("technical A", "technical B"), each = 48L)
  object$group <- rep(c("Ca", "Ctrl"), 48L)
  object$private_note <- "Per-cell field excluded from aggregate prompts."
  object
}

strategy_integration_context <- function() list(species = "human", tissue = "synthetic",
  columns = list(sample = "sample", capture = "capture", batch = "batch", group = "group"),
  design = list(type = "synthetic crossed software fixture", technical_batch = TRUE,
    notes = "No actual integration effect or biological sample replication is claimed."),
  research_goal = "Exercise one reviewed strategy and preserve the supplied object.",
  notes = "Publicly shareable synthetic mechanism fixture only.")

strategy_integration_plan <- function(umap = FALSE) list(schema = "scagentkit.strategy.v1",
  rationale = "A synthetic count-positive QC control and explicitly chosen local parameters.",
  risks = list("No biological QC, annotation, or integration conclusion is validated."),
  inferences = list("Expression programs are planted; this inference is not a user fact."),
  qc = list(schema = "scagentkit.qc.v1", rationale = "Remove only the planted zero-count cell.",
    risks = list("A software control, not a recommended threshold."),
    filters = list(list(op = "range", metric = "nCount", min = 1L))),
  analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
    nfeatures = 50L, npcs = 10L, seed = 7413L),
  pcs = list(method = "fixed", ndim = 5L),
  batch = list(method = "none", reason = "No automatic integration is requested for synthetic metadata."),
  clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .6)),
  umap = list(run = umap, n_neighbors = 10L))

strategy_integration_begin <- function(root, object = strategy_integration_fixture(),
                                       plan = strategy_integration_plan(), provider = NULL,
                                       chat_fn = NULL, context = strategy_integration_context()) {
  suppressWarnings(sc_run(object, root, context = context, strategy = TRUE,
    strategy_proposal = plan, provider = provider, chat_fn = chat_fn, budget = 0,
    annotation_column = "reviewed_type"))
}

strategy_integration_continue <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  suppressWarnings(sc_run_continue(root, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, retry = retry))
}

strategy_integration_decide <- function(root, action = "approve", snapshot = sc_run_inspect(root),
                                        reason = "Approve the exact synthetic software-control scope.") {
  node <- snapshot$review_node
  sc_run_review(root, action, node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "offline strategy QA", reason = reason)
}

strategy_integration_revise <- function(root, proposal, snapshot = sc_run_inspect(root),
                                        reason = "Revise supported parameters with an explicit rationale.") {
  sc_run_strategy_revise(root, proposal, snapshot$project_id, snapshot$input_hash,
    snapshot$revision, "offline strategy QA", reason)
}

strategy_integration_unknown <- function(root) {
  evidence <- sc_run_inspect(root)$evidence
  list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters, function(row)
    list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Synthetic software control; biological identity remains unresolved.", markers = list())))
}

strategy_integration_files <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, scAgentKit:::.sc_project_sha_file, character(1)),
    substring(files, nchar(root) + 2L))
}

strategy_integration_copy <- function(root) {
  target <- tempfile("strategy-copy-"); dir.create(target)
  paths <- list.files(root, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (!all(file.copy(paths, target, recursive = TRUE, copy.mode = TRUE)))
    stop("Could not copy the synthetic stopped project.")
  target
}

strategy_integration_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) {
    calls$factory <- calls$factory + 1L
    stop("Offline strategy QA prohibits remote provider factories.")
  }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Offline strategy QA prohibits network dispatch.")
  }, .package = "httr2", .env = env)
  calls
}

strategy_integration_child <- function(root, snapshot = sc_run_inspect(root)) {
  work <- tempfile("strategy-child-"); dir.create(work)
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
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('No remote strategy factory permitted') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('No strategy HTTP permitted') },.package='httr2',.env=environment())",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision))",
    "stopifnot(factory_calls==0L,http_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls),args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(arguments)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result))
    stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

test_that("one concentrated strategy review authorizes QC and analysis, with separate annotation review and fresh-process output", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- strategy_integration_fixture(); source <- serialize(object, NULL, version = 2L)
  initial <- strategy_integration_begin(root, object, strategy_integration_plan(umap = TRUE))
  expect_identical(initial$status, "awaiting_review")
  inspected <- sc_run_inspect(root)
  expect_identical(inspected$pending$kind, "strategy")
  expect_identical(inspected$review_node$kind, "strategy")
  expect_equal(inspected$strategy_review$details$applicability$details$retained_cells, 95L)
  expect_identical(inspected$strategy_review$details$background$facts$research_goal,
    strategy_integration_context()$research_goal)
  expect_identical(inspected$strategy_review$details$canonical_proposal$inferences,
    strategy_integration_plan()$inferences[[1]])
  expect_identical(inspected$strategy_review$details$applicability$details$batch_group_audit$status,
    "crossed_design")
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  before <- strategy_integration_files(root)
  expect_identical(strategy_integration_continue(root)$status, "awaiting_review")
  expect_identical(strategy_integration_files(root), before)
  approved <- strategy_integration_decide(root)
  expect_identical(approved$stage, "strategy_apply")
  expect_null(scAgentKit:::.sc_run_load(root)$files$qc_object)
  paused <- strategy_integration_continue(root)
  expect_identical(paused$status, "awaiting_configuration")
  expect_identical(paused$stage, "annotation_propose")
  expect_null(sc_run_inspect(root)$review_node)
  expect_identical(paused$diagnostics$local_continue_boundary$dispatch, "not_sent")
  state <- scAgentKit:::.sc_run_load(root)
  expect_true(all(c("strategy_evidence", "strategy_apply", "qc_apply", "strategy_basis",
    "strategy_neighbors", "strategy_cluster", "markers", "annotation_evidence") %in% state$completed))
  approvals <- Filter(function(event) event$action == "approved", state$history)
  expect_identical(vapply(approvals, function(event) event$details$kind, character(1)), "strategy")
  analysis <- scAgentKit:::.sc_run_get(root, state, "analysis")
  expect_true(all(c("pca", "umap") %in% names(analysis@reductions)))
  expect_true(all(c("sc_strategy_nn", "sc_strategy_snn") %in% names(analysis@graphs)))
  expect_gt(nrow(scAgentKit:::.sc_run_get(root, state, "markers")$markers), 0L)
  expect_identical(colnames(analysis), colnames(object)[1:95])
  expect_identical(analysis$source_cluster, object$source_cluster[1:95])
  expect_identical(analysis$old_annotation, object$old_annotation[1:95])
  expect_false("sc_strategy_clusters" %in% names(object[[]]))
  expect_identical(serialize(object, NULL, version = 2L), source)
  boundary_files <- strategy_integration_files(root)
  expect_identical(strategy_integration_child(root)$status$status, "awaiting_configuration")
  expect_identical(strategy_integration_files(root), boundary_files)
  proposed <- sc_run_propose(root, strategy_integration_unknown(root), "offline strategy QA",
    "Use explicit Unknown controls; scientific annotation still needs review.")
  expect_identical(proposed$pending$kind, "annotation")
  expect_null(scAgentKit:::.sc_run_load(root)$files$annotated)
  strategy_integration_decide(root)
  child <- strategy_integration_child(root)
  expect_identical(child$status$status, "complete")
  expect_identical(child$factory_calls, 0L); expect_identical(child$http_calls, 0L)
  output <- readRDS(child$status$output$seurat)
  expect_identical(colnames(output), colnames(object)[1:95])
  expect_identical(output$old_annotation, object$old_annotation[1:95])
  expect_true(is.factor(output$old_annotation)); expect_true(anyNA(output$old_annotation))
  expect_identical(output$source_cluster, object$source_cluster[1:95])
  expect_identical(output$group, object$group[1:95])
  for (layer in c("counts", "extra")) {
    expect_identical(SeuratObject::LayerData(output, assay = "RNA", layer = layer),
      SeuratObject::LayerData(object, assay = "RNA", layer = layer)[, 1:95, drop = FALSE])
  }
  expect_true(inherits(SeuratObject::LayerData(output, assay = "RNA", layer = "counts"), "sparseMatrix"))
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_true(all(c("reviewed_type", "reviewed_type_confidence", "reviewed_type_rationale") %in% names(output[[]])))
  final_state <- scAgentKit:::.sc_run_load(root)
  decisions <- Filter(function(event) event$action == "approved", final_state$history)
  expect_identical(vapply(decisions, function(event) event$details$kind, character(1)), c("strategy", "annotation"))
  complete_files <- strategy_integration_files(root)
  expect_identical(strategy_integration_continue(root)$status, "complete")
  expect_identical(strategy_integration_files(root), complete_files)
  expect_identical(serialize(object, NULL, version = 2L), source)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("mock strategy sees aggregate facts and a cached result costs nothing on repeated resume or Continue", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L; seen <- NULL
  plan <- strategy_integration_plan()
  callback <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    seen <<- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    list(content = as.character(jsonlite::toJSON(plan, auto_unbox = TRUE, null = "null")),
      cost_usd = 0, usage = list(input_tokens = 0L, output_tokens = 0L))
  }
  provider <- list(name = "mock", external = FALSE, model = "synthetic-strategy-only")
  initial <- strategy_integration_begin(root, plan = NULL, provider = provider, chat_fn = callback)
  expect_identical(initial$status, "awaiting_review"); expect_identical(calls, 1L)
  expect_identical(seen$evidence$background_facts$research_goal, strategy_integration_context()$research_goal)
  expect_equal(seen$evidence$input$cells, 96L)
  expect_length(seen$evidence$role_sizes$sample, 2L)
  prompt <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "strategy_request")$user_prompt
  expect_false(grepl("literalCell", prompt, fixed = TRUE))
  expect_false(grepl("Per-cell field excluded", prompt, fixed = TRUE))
  expect_false(grepl('"private"', prompt, fixed = TRUE))
  files <- strategy_integration_files(root)
  expect_identical(sc_run_resume(root, chat_fn = callback)$status, "awaiting_review")
  expect_identical(strategy_integration_files(root), files); expect_identical(calls, 1L)
  state <- scAgentKit:::.sc_run_load(root)
  request <- scAgentKit:::.sc_run_get(root, state, "strategy_request")
  evidence <- scAgentKit:::.sc_run_get(root, state, "strategy_evidence")
  request$validator <- function(value) scAgentKit:::.sc_run_strategy_validate(value, evidence)$proposal
  ledger_hash <- scAgentKit:::.sc_project_sha_file(file.path(root, "provider", "ledger.json"))
  cached <- scAgentKit:::.sc_run_call(root, request, provider = provider, chat_fn = callback, budget = 0)
  expect_identical(cached$status, "ok"); expect_true(cached$cached)
  expect_identical(calls, 1L); expect_equal(cached$charged_or_held_usd, 0)
  expect_identical(scAgentKit:::.sc_project_sha_file(file.path(root, "provider", "ledger.json")), ledger_hash)
  strategy_integration_decide(root)
  paused <- strategy_integration_continue(root)
  expect_identical(paused$status, "awaiting_configuration")
  expect_identical(paused$stage, "annotation_propose")
  expect_identical(calls, 1L)
  expect_identical(scAgentKit:::.sc_project_sha_file(file.path(root, "provider", "ledger.json")), ledger_hash)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("missing configuration and approved manual batch remain explicit provider-free boundaries", {
  network <- strategy_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  root <- tempfile(); roots <- c(roots, root)
  initial <- strategy_integration_begin(root, plan = NULL, context = list(species = "human"))
  expect_identical(initial$status, "awaiting_configuration")
  expect_identical(initial$stage, "strategy_propose")
  evidence <- scAgentKit:::.sc_run_get(root, scAgentKit:::.sc_run_load(root), "strategy_evidence")
  expect_true(all(c("tissue", "design", "research_goal", "columns.sample", "columns.batch", "columns.group") %in%
    evidence$summary$missing_facts))
  expect_identical(evidence$summary$batch_group_audit$status, "missing_information")
  expect_false(evidence$summary$batch_group_audit$batch_declared)
  expect_null(evidence$summary$background_facts$columns$batch)
  expect_false(dir.exists(file.path(root, "provider")))
  root <- tempfile(); roots <- c(roots, root)
  plan <- strategy_integration_plan(); plan$batch$method <- "manual"
  plan$batch$reason <- "Technical correction needs analyst preparation and is not implemented here."
  started <- strategy_integration_begin(root, plan = plan)
  expect_identical(started$status, "awaiting_review")
  review <- sc_run_inspect(root)$strategy_review$details
  expect_false(review$applicability$executable)
  expect_identical(review$applicability$blockers[[1]]$code, "manual_required")
  strategy_integration_decide(root)
  stopped <- strategy_integration_continue(root)
  expect_identical(stopped$status, "awaiting_configuration")
  expect_identical(stopped$stage, "strategy_apply")
  expect_identical(stopped$diagnostics$strategy_manual_boundary$dispatch, "not_sent")
  state <- scAgentKit:::.sc_run_load(root)
  expect_null(state$files$qc_object); expect_null(state$files$strategy_basis)
  bytes <- strategy_integration_files(root)
  expect_identical(strategy_integration_continue(root)$status, "awaiting_configuration")
  expect_identical(sc_run_resume(root)$status, "awaiting_configuration")
  expect_identical(strategy_integration_files(root), bytes)
  supported <- strategy_integration_plan()
  strategy_integration_revise(root, supported,
    reason = "Explicitly choose none for this software fixture instead of a pending manual preparation.")
  strategy_integration_decide(root)
  resumed <- strategy_integration_continue(root)
  expect_identical(resumed$stage, "annotation_propose")
  expect_identical(resumed$status, "awaiting_configuration")
  expect_null(resumed$diagnostics$strategy_manual_boundary)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("strategy revisions reject unsupported operations atomically and exact identities and locks bind review", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  initial <- strategy_integration_begin(root)
  snapshot <- sc_run_inspect(root); files <- strategy_integration_files(root)
  invalid <- list()
  invalid[[1]] <- strategy_integration_plan(); invalid[[1]]$cycle <- list(regress = TRUE)
  invalid[[2]] <- strategy_integration_plan(); invalid[[2]]$doublet <- list(delete = TRUE)
  invalid[[3]] <- strategy_integration_plan(); invalid[[3]]$batch$method <- "harmony"
  invalid[[4]] <- strategy_integration_plan(); invalid[[4]]$analysis$vars_to_regress <- "S.Score"
  invalid[[5]] <- strategy_integration_plan(); invalid[[5]]$analysis$r_code <- "stop('must never run')"
  invalid[[6]] <- strategy_integration_plan(); invalid[[6]]$pcs$ndim <- 100L
  invalid[[7]] <- strategy_integration_plan(); invalid[[7]]$clustering$diagnostic_resolutions <- c(.1, .2, .3, .4, .5, .6)
  invalid[[8]] <- strategy_integration_plan(); invalid[[8]]$qc$filters[[1]]$metric <- "doublet_score"
  invalid[[9]] <- strategy_integration_plan(); invalid[[9]]$umap$n_neighbors <- 95L
  invalid[[10]] <- strategy_integration_plan(); invalid[[10]]$analysis$nfeatures <- 121L
  for (proposal in invalid) {
    expect_error(strategy_integration_revise(root, proposal, snapshot))
    expect_identical(strategy_integration_files(root), files)
  }
  expect_error(strategy_integration_revise(root, strategy_integration_plan(),
    within(snapshot, revision <- revision + 1L)), "[Ss]tale|revision")
  foreign <- snapshot; foreign$project_id <- "different-project"
  expect_error(strategy_integration_revise(root, strategy_integration_plan(), foreign), "Foreign project")
  expect_identical(strategy_integration_files(root), files)
  lock <- scAgentKit:::.sc_run_lock(root)
  locked <- strategy_integration_files(root)
  expect_error(strategy_integration_decide(root, snapshot = snapshot), "locked")
  expect_error(strategy_integration_continue(root, snapshot), "locked")
  expect_error(strategy_integration_revise(root, strategy_integration_plan(), snapshot), "locked")
  expect_identical(strategy_integration_files(root), locked)
  scAgentKit:::.sc_run_release(root, lock)
  expect_identical(strategy_integration_files(root), files)
  strategy_integration_decide(root, snapshot = snapshot)
  approved <- strategy_integration_files(root)
  expect_identical(strategy_integration_decide(root, snapshot = snapshot)$stage, "strategy_apply")
  expect_identical(strategy_integration_files(root), approved)
  expect_error(strategy_integration_continue(root, snapshot), "[Ss]tale|revision")
  expect_identical(strategy_integration_files(root), approved)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("an interrupted local strategy requires explicit retry and preserves completed QC and basis", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  strategy_integration_begin(root); strategy_integration_decide(root)
  withr::local_options(list(scAgentKit.continue_crash = "strategy_neighbors:before"))
  output <- capture.output(failed <- strategy_integration_continue(root))
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "strategy_neighbors")
  expect_match(failed$failure$message, "Injected local continuation failure")
  expect_false(any(grepl("Injected local continuation failure", output, fixed = TRUE)))
  state <- scAgentKit:::.sc_run_load(root)
  retained <- state$files[c("qc_object", "strategy_basis")]
  expect_true(all(c("qc_apply", "strategy_basis") %in% state$completed))
  expect_null(state$files$strategy_neighbors)
  files <- strategy_integration_files(root)
  expect_identical(strategy_integration_continue(root)$status, "failed")
  expect_identical(strategy_integration_files(root), files)
  options(scAgentKit.continue_crash = NULL)
  resumed <- strategy_integration_continue(root, retry = TRUE)
  expect_identical(resumed$status, "awaiting_configuration")
  expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[c("qc_object", "strategy_basis")], retained)
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster")) {
    executions <- Filter(function(event) event$action == "executed" && identical(event$details$stage, stage), state$history)
    expect_length(executions, 1L)
  }
  expect_true(any(vapply(state$history, function(event)
    identical(event$action, "local_continue_retry_requested"), logical(1))))
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("resolution PC and QC revisions invalidate only affected active checkpoints and retain old immutable history", {
  network <- strategy_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  base <- tempfile(); roots <- c(roots, base)
  strategy_integration_begin(base); strategy_integration_decide(base)
  strategy_integration_continue(base)
  sc_run_propose(base, strategy_integration_unknown(base), "offline strategy QA", "A pending Unknown review before parameter revision.")
  strategy_integration_decide(base)
  original <- scAgentKit:::.sc_run_load(base)
  original_review <- sc_run_inspect(base)
  expect_identical(original$stage, "annotation_apply")
  expect_identical(original$approved$kind, "annotation")
  cases <- list(
    resolution = list(keep = c("qc_object", "strategy_basis", "strategy_neighbors"),
      drop = c("analysis", "markers", "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review")),
    pcs = list(keep = c("qc_object", "strategy_basis"),
      drop = c("strategy_neighbors", "analysis", "markers", "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review")),
    qc = list(keep = character(),
      drop = c("qc_object", "strategy_basis", "strategy_neighbors", "analysis", "markers", "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review")))
  for (kind in names(cases)) {
    root <- strategy_integration_copy(base); roots <- c(roots, root)
    old_files <- strategy_integration_files(root)
    proposal <- strategy_integration_plan()
    if (kind == "resolution") proposal$clustering$resolution <- .6
    if (kind == "pcs") proposal$pcs$ndim <- 4L
    if (kind == "qc") proposal$qc$filters[[1]]$min <- 2L
    revised <- strategy_integration_revise(root, proposal)
    expect_identical(revised$status, "awaiting_review")
    expect_identical(revised$pending$kind, "strategy")
    state <- scAgentKit:::.sc_run_load(root)
    expect_identical(state$files[cases[[kind]]$keep], original$files[cases[[kind]]$keep])
    expect_false(any(cases[[kind]]$drop %in% names(state$files)))
    expect_null(state$approved)
    expect_identical(state$approvals[[original$approved$hash]], original$approvals[[original$approved$hash]])
    expect_identical(state$history[seq_along(original$history)], original$history)
    expect_false(identical(state$pending$hash, original$approved$hash))
    unchanged <- old_files[startsWith(names(old_files), "checkpoints/")]
    current <- strategy_integration_files(root)
    expect_identical(current[names(unchanged)], unchanged)
    expect_error(strategy_integration_decide(root, snapshot = original_review), "[Ss]tale|different review kind")
    expect_null(state$files$annotated)
  }
  # Only the resolution case is resumed: actual basis, PCA-neighbor/UMAP bytes
  # must be reused, while clustering and markers execute again under approval.
  root <- roots[[2L]]; strategy_integration_decide(root)
  resumed <- strategy_integration_continue(root)
  expect_identical(resumed$status, "awaiting_configuration")
  expect_identical(resumed$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files[c("qc_object", "strategy_basis", "strategy_neighbors")],
    original$files[c("qc_object", "strategy_basis", "strategy_neighbors")])
  expect_false(identical(state$files$analysis, original$files$analysis))
  expect_identical(scAgentKit:::.sc_run_get(root, state, "analysis")@misc$strategy_execution$cluster$resolution, .6)
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors"))
    expect_length(Filter(function(event) event$action == "executed" && identical(event$details$stage, stage), state$history), 1L)
  expect_length(Filter(function(event) event$action == "executed" && identical(event$details$stage, "strategy_cluster"), state$history), 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("pure explanatory strategy revision restores exact downstream annotation authorization without recomputation", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  strategy_integration_begin(root); strategy_integration_decide(root)
  strategy_integration_continue(root)
  sc_run_propose(root, strategy_integration_unknown(root), "offline strategy QA", "Explicit Unknown review remains independent.")
  strategy_integration_decide(root)
  original <- scAgentKit:::.sc_run_load(root)
  proposal <- strategy_integration_plan()
  proposal$rationale <- "Clarify the rationale only; execution parameters and exact QC rules are unchanged."
  proposal$risks <- c(proposal$risks, "Additional explanatory limitation only.")
  proposal$inferences <- list("This text remains an inference rather than a user fact.")
  proposal$batch$reason <- "Clarified explicit none decision for the same synthetic scope."
  revised <- strategy_integration_revise(root, proposal)
  expect_identical(revised$pending$kind, "strategy")
  state <- scAgentKit:::.sc_run_load(root)
  keys <- c("qc_object", "strategy_basis", "strategy_neighbors", "analysis", "markers",
    "annotation_evidence", "manual_annotation", "annotation_validated", "annotation_review")
  expect_identical(state$files[keys], original$files[keys])
  expect_identical(state$strategy_return$approved, original$approved)
  expect_identical(state$strategy_return$pending, original$pending)
  expect_null(state$approved)
  strategy_integration_decide(root)
  # Stop immediately after the restore checkpoint so annotation is not applied
  # until an explicit later Continue. The injected point never changes code.
  withr::local_options(list(scAgentKit.continue_crash = "annotation_apply:before"))
  restored <- strategy_integration_continue(root)
  expect_identical(restored$status, "failed")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$approved, original$approved)
  expect_identical(state$files[keys], original$files[keys])
  expect_null(state$strategy_return)
  expect_true(any(vapply(state$history, function(event)
    identical(event$action, "strategy_text_revision_reused"), logical(1))))
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster", "markers"))
    expect_length(Filter(function(event) event$action == "executed" && identical(event$details$stage, stage), state$history), 1L)
  options(scAgentKit.continue_crash = NULL)
  completed <- strategy_integration_continue(root, retry = TRUE)
  expect_identical(completed$status, "complete")
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("processed strategy explicitly reuses cells layers and original clusters after a central decision", {
  network <- strategy_integration_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  object <- strategy_integration_fixture()[, 1:95]
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <-
    log1p(SeuratObject::LayerData(object, assay = "RNA", layer = "counts"))
  source <- serialize(object, NULL, version = 2L)
  plan <- strategy_integration_plan()
  plan[c("qc", "analysis", "pcs", "clustering", "umap")] <- rep(list(NULL), 5L)
  initial <- suppressWarnings(sc_run(object, root, strategy = TRUE, strategy_proposal = plan,
    context = strategy_integration_context(), start_stage = "processed", cluster_column = "source_cluster",
    processed_reason = "The caller explicitly supplies sparse normalized data and literal original clusters.",
    annotation_column = "reviewed_type"))
  expect_identical(initial$status, "awaiting_review")
  expect_identical(initial$pending$kind, "strategy")
  expect_true(sc_run_inspect(root)$strategy_review$details$applicability$details$processed_reuse)
  before <- scAgentKit:::.sc_run_load(root)
  analysis <- before$files$analysis
  strategy_integration_decide(root)
  stopped <- strategy_integration_continue(root)
  expect_identical(stopped$status, "awaiting_configuration")
  expect_identical(stopped$stage, "annotation_propose")
  state <- scAgentKit:::.sc_run_load(root)
  expect_identical(state$files$analysis, analysis)
  for (stage in c("qc_apply", "strategy_basis", "strategy_neighbors", "strategy_cluster"))
    expect_length(Filter(function(event) event$action == "executed" && identical(event$details$stage, stage), state$history), 0L)
  sc_run_propose(root, strategy_integration_unknown(root), "offline strategy QA", "Explicit processed-object Unknown control.")
  strategy_integration_decide(root)
  final <- strategy_integration_continue(root)
  expect_identical(final$status, "complete")
  bundle_parameters <- jsonlite::fromJSON(file.path(root, "bundle", "project.json"), simplifyVector = FALSE)$parameters
  expect_identical(bundle_parameters$batchIntegration, "processed/reused")
  expect_false(bundle_parameters$analysisExecution$foundationExecuted)
  expect_identical(bundle_parameters$analysisExecution$activeReduction, "reused/unspecified")
  expect_length(bundle_parameters$analysis, 0L)
  expect_identical(bundle_parameters$analysisExecution$strategySummary$sha256,
    scAgentKit:::.sc_project_sha_file(file.path(root, "output", "strategy_summary.json")))
  output <- readRDS(final$output$seurat)
  expect_identical(colnames(output), colnames(object))
  expect_identical(output$source_cluster, object$source_cluster)
  expect_identical(output$old_annotation, object$old_annotation)
  for (layer in c("counts", "data", "extra"))
    expect_identical(SeuratObject::LayerData(output, assay = "RNA", layer = layer),
      SeuratObject::LayerData(object, assay = "RNA", layer = layer))
  expect_identical(serialize(object, NULL, version = 2L), source)
  expect_false("sc_strategy_clusters" %in% names(output[[]]))
  expect_true(all(output$reviewed_type == "Unknown"))
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})

test_that("changed saved input or strategy evidence cannot consume a previously approved strategy", {
  network <- strategy_integration_sentinels()
  roots <- character(); on.exit(lapply(roots, unlink, recursive = TRUE), add = TRUE)
  for (key in c("input", "strategy_evidence")) {
    root <- tempfile(); roots <- c(roots, root)
    strategy_integration_begin(root); strategy_integration_decide(root)
    snapshot <- sc_run_inspect(root)
    state <- scAgentKit:::.sc_run_load(root)
    path <- file.path(root, state$files[[key]]$path)
    saveRDS(list(altered = "Synthetic changed checkpoint"), path)
    files <- strategy_integration_files(root)
    expect_error(strategy_integration_continue(root, snapshot), "changed|[Ss]tale")
    expect_error(sc_run_resume(root), "changed|[Ss]tale")
    expect_identical(strategy_integration_files(root), files)
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
