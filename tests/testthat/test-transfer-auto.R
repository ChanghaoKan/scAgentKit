test_that("offline simulation retains distinct scope and never authorizes a remote simulated request", {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  confirmation <- list(mode = "project", confirmed = TRUE, reviewer = "offline-test",
    reason = "Explicit simulation of public aggregate project scope.",
    categories = c("study_context", "aggregate_qc", "aggregate_markers", "aggregate_design", "aggregate_expression"))
  sc_analyze(env$pbmc_small, root, context = list(species = "human"), provider = "mock", budget = .1,
    review = list(allow_external = TRUE, transfer_consent = confirmation),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, diagnostic_resolutions = NULL, umap = FALSE))
  ordinary <- sc_run_suggest(root)
  simulated <- sc_run_suggest(root, simulate = TRUE)
  expect_true(simulated$can_auto_request)
  expect_false(identical(ordinary$preview$request_hash, simulated$preview$request_hash))
  state <- .sc_run_load(root)
  context <- .sc_run_suggestion_context(root, state, TRUE)
  expect_identical(context$request$transfer_scope$kind, "simulated_strategy")
  expect_true(.sc_run_transfer_authorized(context$request, state$config))
  changed <- state$config; changed$provider$name <- "remote"
  changed$review$transfer_consent$provider_hash <- .sc_run_provider_hash(changed$provider)
  consent <- changed$review$transfer_consent; consent$hash <- NULL
  changed$review$transfer_consent$hash <- .sc_run_provider_hash(consent)
  expect_false(.sc_run_transfer_authorized(context$request, changed))
  result <- sc_run_suggest(root, "request", project_id = simulated$project_id, input_hash = simulated$input_hash,
    expected_revision = simulated$revision, suggestion_hash = simulated$suggestion_hash, simulate = TRUE)
  expect_identical(result$status, "candidate"); expect_false(result$can_auto_request)
  expect_length(.sc_run_load(root)$approvals, 0L)
  expect_true(result$preview$simulated); expect_equal(result$preview$known_cost_usd, 0)
})


test_that("a saved local-only annotation boundary can stage one scoped automatic draft", {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  confirmation <- list(mode="project",confirmed=TRUE,reviewer="offline-test",reason="Public fixture aggregate scope.",
    categories=c("study_context","aggregate_qc","aggregate_markers","aggregate_design","aggregate_expression"))
  env$pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(env$pbmc_small))
  suppressWarnings(sc_run(env$pbmc_small, root, context=list(species="human",tissue="blood"),
    start_stage="processed", processed_reason="Public software-control annotation boundary.",
    provider="mock",budget=.1,review=list(allow_external=TRUE,transfer_consent=confirmation)))
  state <- .sc_run_load(root)
  expect_identical(state$stage,"annotation_propose");expect_identical(state$status,"awaiting_configuration")
  view <- sc_run_suggest(root,simulate=TRUE)
  expect_true(view$can_auto_request);expect_identical(view$kind,"annotation")
  result <- sc_run_suggest(root,"request",project_id=view$project_id,input_hash=view$input_hash,
    expected_revision=view$revision,suggestion_hash=view$suggestion_hash,simulate=TRUE)
  expect_identical(result$status,"candidate");expect_false(result$can_auto_request)
  expect_length(.sc_run_load(root)$approvals,0L)
})
