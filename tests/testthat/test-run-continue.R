# Synthetic data only. Provider factories and HTTP are monitored independently
# of the coordinator implementation fingerprint, including in a fresh R process.
continue_fixture <- function() {
  set.seed(917)
  counts <- matrix(stats::rpois(64 * 72, 2), nrow = 64,
    dimnames = list(c("MT-CO1", paste0("Gene", 2:64)),
      c("001", "1", "NA", "cell space", paste0("cell", 5:72))))
  counts[2:12, 1:36] <- counts[2:12, 1:36] + 18L
  counts[13:24, 37:71] <- counts[13:24, 37:71] + 18L
  counts[, 72] <- 0L
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  object$sample <- rep(c("sample A", "sample B"), each = 36)
  object$capture <- rep(c("cap 1", "cap 2"), 36)
  object$condition <- rep(c("Ca", "Ctrl"), 36)
  object$old_annotation <- factor(rep(c("old label", NA_character_), 36), levels = c("old label", "unused"))
  object
}
continue_rule <- function() list(schema = "scagentkit.qc.v1",
  rationale = "Remove only the explicitly synthetic zero-count cell.",
  risks = list("Mechanism test, not a biological threshold recommendation."),
  filters = list(list(op = "range", metric = "nCount", min = 1L)))
continue_begin <- function(root, object = continue_fixture(), provider = NULL, qc = continue_rule(), umap = FALSE) {
  sc_run(object, root, context = list(species = "human", tissue = "synthetic", columns = list(
    sample = "sample", capture = "capture", condition = "condition")),
    provider = provider, budget = .2, review = list(allow_external = TRUE), qc_proposal = qc,
    analysis = list(nfeatures = 40, npcs = 5, dims = 1:5, resolution = .4,
      run_umap = umap, umap_neighbors = 12, seed = 917), annotation_column = "reviewed_type")
}
continue_call <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  sc_run_continue(root, snapshot$project_id, snapshot$input_hash, snapshot$revision, retry)
}
continue_approve <- function(root) {
  snapshot <- sc_run_inspect(root)
  sc_run_approve(root, snapshot$pending$hash, "synthetic local Continue QA",
    "Approve exact synthetic scope only.", expected_revision = snapshot$revision)
}
continue_files <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  stats::setNames(vapply(files, .sc_project_sha_file, character(1)), substring(files, nchar(root) + 2L))
}
continue_sentinels <- function(env = parent.frame()) {
  calls <- new.env(parent = emptyenv()); calls$factory <- 0L; calls$http <- 0L
  factory <- function(...) { calls$factory <- calls$factory + 1L; stop("Synthetic factory sentinel; no provider is allowed.") }
  testthat::local_mocked_bindings(chat_deepseek = factory, chat_grok = factory,
    .package = "agentomicsCore", .env = env)
  testthat::local_mocked_bindings(req_perform = function(...) {
    calls$http <- calls$http + 1L; stop("Synthetic HTTP sentinel; no network is allowed.")
  }, .package = "httr2", .env = env)
  calls
}
continue_child <- function(root, snapshot = sc_run_inspect(root), retry = FALSE) {
  work <- tempfile("continue-child-"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  arguments <- file.path(work, "arguments.rds"); result <- file.path(work, "result.rds")
  script <- file.path(work, "child.R"); log <- file.path(work, "stdout.log")
  saveRDS(list(root = root, project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    revision = snapshot$revision, retry = retry, result = result, libraries = .libPaths(),
    package = getNamespaceInfo(asNamespace("scAgentKit"), "path")), arguments)
  writeLines(c("local({", "args <- readRDS(commandArgs(TRUE)[[1]])", ".libPaths(args$libraries)",
    "Sys.unsetenv(c('DEEPSEEK_API_KEY','XAI_API_KEY','OPENAI_API_KEY'))",
    "if (file.exists(file.path(args$package,'R','run.R'))) pkgload::load_all(args$package,quiet=TRUE,helpers=FALSE) else library(scAgentKit,lib.loc=dirname(args$package))",
    "factory_calls <- 0L; http_calls <- 0L",
    "factory <- function(...) { factory_calls <<- factory_calls+1L; stop('Synthetic factory sentinel') }",
    "testthat::local_mocked_bindings(chat_deepseek=factory,chat_grok=factory,.package='agentomicsCore',.env=environment())",
    "testthat::local_mocked_bindings(req_perform=function(...) { http_calls <<- http_calls+1L; stop('Synthetic HTTP sentinel') },.package='httr2',.env=environment())",
    "out <- suppressWarnings(sc_run_continue(args$root,args$project_id,args$input_hash,args$revision,args$retry))",
    "stopifnot(factory_calls==0L,http_calls==0L)",
    "saveRDS(list(status=out,factory_calls=factory_calls,http_calls=http_calls),args$result)", "})"), script)
  code <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script), shQuote(arguments)), stdout = log, stderr = log)
  if (code != 0L || !file.exists(result)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  readRDS(result)
}

test_that("approved raw QC continues real local analysis and completes reviewed output in fresh R", {
  calls <- continue_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  input <- continue_fixture(); before <- .sc_run_hash(input)
  initial <- continue_begin(root, input, umap = TRUE)
  expect_identical(initial$status, "awaiting_review")
  original_files <- continue_files(root)
  expect_identical(continue_call(root)$status, "awaiting_review")
  expect_identical(continue_files(root), original_files)
  continue_approve(root)
  paused <- suppressWarnings(continue_call(root))
  expect_identical(paused$status, "awaiting_configuration")
  expect_identical(paused$stage, "annotation_propose")
  expect_identical(paused$diagnostics$local_continue_boundary$dispatch, "not_sent")
  expect_true(all(c("qc_apply", "analysis", "markers", "annotation_evidence") %in% paused$completed))
  state <- .sc_run_load(root); analysis <- .sc_run_get(root, state, "analysis")
  expect_true(all(c("counts", "data", "scale.data") %in% SeuratObject::Layers(analysis[["RNA"]])))
  expect_true(all(c("pca", "umap") %in% names(analysis@reductions)))
  expect_true(all(c("RNA_nn", "RNA_snn") %in% names(analysis@graphs)))
  expect_gt(nrow(.sc_run_get(root, state, "markers")$markers), 0)
  expect_identical(colnames(analysis), colnames(input)[1:71])
  expect_identical(analysis$old_annotation, input$old_annotation[1:71])
  expect_identical(.sc_run_hash(input), before)
  saved_files <- continue_files(root)
  expect_identical(continue_child(root)$status$status, "awaiting_configuration")
  expect_identical(continue_files(root), saved_files)
  evidence <- sc_run_inspect(root)$evidence
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(evidence$clusters,
    function(row) list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Synthetic mechanism only; no biological annotation is claimed.", markers = list())))
  reviewed <- sc_run_propose(root, proposal, "offline QA", "Explicit synthetic Unknown proposal.")
  expect_identical(reviewed$pending$kind, "annotation")
  expect_null(reviewed$diagnostics$local_continue_boundary)
  review_files <- continue_files(root)
  expect_identical(continue_call(root)$status, "awaiting_review")
  expect_identical(continue_files(root), review_files)
  continue_approve(root)
  child <- continue_child(root)
  expect_identical(child$status$status, "complete")
  expect_identical(child$factory_calls, 0L); expect_identical(child$http_calls, 0L)
  final <- readRDS(child$status$output$seurat)
  expect_identical(colnames(final), colnames(input)[1:71])
  expect_identical(final$old_annotation, input$old_annotation[1:71])
  expect_identical(final$condition, input$condition[1:71])
  expect_true(anyNA(final$old_annotation)); expect_true(is.factor(final$old_annotation))
  expect_identical(unname(final$reviewed_type), rep("Unknown", 71))
  expect_true(all(c("reviewed_type", "reviewed_type_confidence", "reviewed_type_rationale") %in% names(final[[]])))
  expect_equal(SeuratObject::LayerData(final, layer = "counts"),
    SeuratObject::LayerData(input, layer = "counts")[, 1:71, drop = FALSE])
  expect_identical(.sc_run_hash(input), before)
  complete_files <- continue_files(root)
  expect_identical(continue_call(root)$status, "complete")
  expect_identical(continue_files(root), complete_files)
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(calls$factory, 0L); expect_identical(calls$http, 0L)
})

test_that("approved external payload remains an R provider boundary for built-in and custom configurations", {
  calls <- continue_sentinels()
  withr::local_envvar(c(DEEPSEEK_API_KEY = "offline-factory-sentinel", XAI_API_KEY = "offline-factory-sentinel"))
  for (provider in list("deepseek", "grok", list(name = "custom", external = TRUE, model = "synthetic"))) {
    root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
    started <- continue_begin(root, provider = provider, qc = NULL)
    expect_identical(started$pending$kind, "external_transfer")
    continue_approve(root)
    state_before <- .sc_run_load(root)
    paused <- continue_call(root)
    expect_identical(paused$status, "awaiting_configuration")
    expect_identical(paused$stage, "qc_propose")
    expect_identical(paused$diagnostics$local_continue_boundary$dispatch, "not_sent")
    state_after <- .sc_run_load(root)
    expect_identical(state_after$transfer_hashes, state_before$transfer_hashes)
    expect_identical(state_after$approvals, state_before$approvals)
    expect_identical(state_after$files, state_before$files)
    expect_false(file.exists(file.path(root, "provider", "ledger.json")))
    files <- continue_files(root)
    expect_identical(continue_call(root)$status, "awaiting_configuration")
    expect_identical(continue_files(root), files)
  }
  expect_identical(calls$factory, 0L); expect_identical(calls$http, 0L)
})

test_that("typed identities revisions lock review and rejection stop before any run mutation", {
  calls <- continue_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  current <- continue_begin(root); files <- continue_files(root)
  args <- list(project_dir = root, project_id = current$project_id, input_hash = current$input_hash,
    expected_revision = current$revision, retry = FALSE)
  bad <- list(list(project_id = "foreign"), list(input_hash = strrep("0", 64)),
    list(input_hash = "not-a-fingerprint"), list(expected_revision = current$revision + 1),
    list(expected_revision = NULL), list(expected_revision = "1"), list(expected_revision = -.1),
    list(retry = "TRUE"), list(retry = NA))
  for (overrides in bad) {
    supplied <- args
    for (name in names(overrides)) supplied[name] <- overrides[name]
    expect_error(do.call(sc_run_continue, supplied))
    expect_identical(continue_files(root), files)
  }
  lock <- .sc_run_lock(root)
  locked_files <- continue_files(root)
  expect_error(continue_call(root, current), "locked")
  expect_identical(continue_files(root), locked_files)
  .sc_run_release(root, lock)
  expect_identical(continue_files(root), files)
  rejected <- sc_run_reject(root, current$pending$hash, "offline QA", "Keep all input untouched for review.")
  rejected_files <- continue_files(root)
  expect_identical(continue_call(root, rejected)$status, "rejected")
  expect_identical(continue_files(root), rejected_files)
  expect_identical(calls$factory, 0L); expect_identical(calls$http, 0L)
})

test_that("saved inputs approval configuration and implementation changes reject before events", {
  calls <- continue_sentinels()
  for (change in c("input", "approved", "configuration", "implementation", "missing_approval")) {
    root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
    old <- continue_begin(root); continue_approve(root)
    state <- .sc_run_load(root); snapshot <- .sc_run_public(state)
    expect_error(continue_call(root, old), "[Ss]tale.*revision")
    if (change == "input") saveRDS("Synthetic altered checkpoint", file.path(root, state$files$input$path))
    else {
      if (change == "approved") state$approved$next_stage <- "finalize"
      if (change == "configuration") state$config$analysis$npcs <- 4
      if (change == "implementation") state$implementation_hash <- strrep("0", 64)
      if (change == "missing_approval") state$approved <- NULL
      .sc_run_save(root, state)
    }
    files <- continue_files(root)
    expect_error(continue_call(root, snapshot), "changed|stale|approval is absent", ignore.case = TRUE)
    expect_identical(continue_files(root), files)
    expect_false(dir.exists(file.path(root, ".run-lock")))
  }
  expect_identical(calls$factory, 0L); expect_identical(calls$http, 0L)
})

test_that("local failures require explicit retry without rerunning completed QC or leaking failure stdout", {
  calls <- continue_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  continue_begin(root); continue_approve(root)
  withr::local_options(list(scAgentKit.continue_crash = "analysis:before"))
  stdout <- capture.output(failed <- continue_call(root))
  expect_identical(failed$status, "failed"); expect_identical(failed$stage, "analysis")
  expect_match(failed$failure$message, "Injected local continuation failure")
  expect_false(any(grepl("Injected local continuation failure", stdout, fixed = TRUE)))
  state <- .sc_run_load(root); qc_checkpoint <- state$files$qc_object
  expect_true("qc_apply" %in% state$completed)
  files <- continue_files(root)
  expect_identical(continue_call(root)$status, "failed")
  expect_identical(continue_files(root), files)
  options(scAgentKit.continue_crash = NULL)
  paused <- suppressWarnings(continue_call(root, retry = TRUE))
  expect_identical(paused$status, "awaiting_configuration")
  expect_identical(paused$stage, "annotation_propose")
  state <- .sc_run_load(root)
  expect_identical(state$files$qc_object, qc_checkpoint)
  qc_runs <- Filter(function(event) event$action == "executed" && identical(event$details$stage, "qc_apply"), state$history)
  expect_length(qc_runs, 1L)
  expect_true(any(vapply(state$history, function(event) identical(event$action, "local_continue_retry_requested"), logical(1))))
  expect_false(dir.exists(file.path(root, "provider")))
  expect_identical(calls$factory, 0L); expect_identical(calls$http, 0L)
})

test_that("proposal failures stay explicit and ordinary R resume can still invoke an offline callback", {
  network <- continue_sentinels()
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L
  bad <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    list(content = '{"unsupported":"synthetic invalid proposal"}', cost_usd = 0,
      usage = list(input_tokens = 0, output_tokens = 0))
  }
  first <- sc_run(continue_fixture(), root, provider = list(name = "mock", external = FALSE), chat_fn = bad)
  expect_identical(first$status, "failed"); expect_identical(first$stage, "qc_propose")
  expect_identical(calls, 1L)
  files <- continue_files(root)
  expect_identical(continue_call(root)$status, "failed")
  expect_error(continue_call(root, retry = TRUE), "only local computation")
  expect_identical(continue_files(root), files); expect_identical(calls, 1L)
  good <- function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    list(content = as.character(jsonlite::toJSON(continue_rule(), auto_unbox = TRUE)),
      cost_usd = 0, usage = list(input_tokens = 0, output_tokens = 0))
  }
  recovered <- sc_run_resume(root, chat_fn = good, retry = TRUE)
  expect_identical(recovered$status, "awaiting_review"); expect_identical(recovered$pending$kind, "qc")
  expect_identical(calls, 2L)
  expect_identical(network$factory, 0L); expect_identical(network$http, 0L)
})
