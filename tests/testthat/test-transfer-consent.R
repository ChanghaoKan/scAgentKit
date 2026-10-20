transfer_confirmation <- function(categories = c("study_context", "aggregate_qc",
    "aggregate_markers", "aggregate_design", "aggregate_expression")) {
  list(mode = "project", confirmed = TRUE, reviewer = "offline-test",
    reason = "Explicitly reviewed public aggregate categories and the USD cap.", categories = categories)
}
transfer_policy <- function() {
  provider <- .sc_run_provider_spec(list(name = "offline_remote", external = TRUE,
    model = "offline-v1", reservation_usd = .01))$metadata
  list(provider = provider, budget = .1, review = list(allow_external = TRUE,
    transfer_consent = .sc_run_transfer_options(transfer_confirmation(), provider, .1)))
}

test_that("project transfer consent is explicit and cannot expand provider, cap, prompt or categories", {
  config <- transfer_policy()
  for (kind in c("strategy", "qc", "annotation")) {
    request <- .sc_run_request(kind, list(), config)
    expect_true(.sc_run_transfer_authorized(request, config))
    expect_true(nzchar(.sc_run_request_hash(request, config$provider)))
    request$transfer_scope$prompt_version <- "unknown.v2"
    expect_false(.sc_run_transfer_authorized(request, config))
    expect_error(.sc_run_request_hash(request, config$provider), "transfer scope")
  }
  request <- .sc_run_request("annotation", list(), config)
  for (field in c("provider", "allow_external", "categories")) {
    changed <- config
    if (field == "budget") changed$budget <- .2
    if (field == "provider") changed$provider$model <- "new-model"
    if (field == "allow_external") changed$review$allow_external <- FALSE
    if (field == "categories") changed$review$transfer_consent$categories <- c("study_context", "aggregate_markers")
    expect_false(.sc_run_transfer_authorized(request, changed))
  }
  limited <- config
  limited$review$transfer_consent <- .sc_run_transfer_options(
    transfer_confirmation(c("study_context", "aggregate_qc", "aggregate_design")), config$provider, config$budget)
  expect_false(.sc_run_transfer_authorized(request, limited))
  expect_true(.sc_run_transfer_authorized(.sc_run_request("qc", list(), limited), limited))
  value <- transfer_confirmation(); value$confirmed <- FALSE
  expect_error(.sc_run_transfer_options(value, config$provider, .1), "Confirm")
  value <- transfer_confirmation("cell_ids")
  expect_error(.sc_run_transfer_options(value, config$provider, .1), "cannot be authorized")
  expect_no_error(.sc_run_transfer_options(transfer_confirmation(), config$provider, 0))
  strict <- config; strict$review$transfer_consent <- NULL
  request <- .sc_run_request("annotation", list(), strict)
  expect_null(request$transfer_scope)
  expect_false(.sc_run_transfer_authorized(request, strict))
})

transfer_draft_fixture <- function(confirmation = transfer_confirmation(), budget = .1, scan = FALSE) {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  root <- tempfile("transfer-public-")
  sc_analyze(env$pbmc_small, root,
    context = list(species = "human", tissue = "Public PBMC software fixture",
      research_goal = "Offline transfer boundary validation", columns = list(sample = "orig.ident")),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4,
      diagnostic_resolutions = if (scan) c(.2, .4, .6, .8, 1) else NULL, umap = FALSE),
    provider = list(name = "offline_remote", model = "offline-v1", external = TRUE, reservation_usd = .01),
    budget = budget, review = list(allow_external = TRUE, transfer_consent = confirmation))
  root
}
transfer_action <- function(root, action, ...) {
  view <- sc_run_suggest(root)
  sc_run_suggest(root, action = action, project_id = view$project_id,
    input_hash = view$input_hash, expected_revision = view$revision,
    suggestion_hash = view$suggestion_hash, ...)
}

test_that("scope consent requests a mock draft without granting a scientific approval", {
  root <- transfer_draft_fixture(); on.exit(unlink(root, recursive = TRUE))
  state <- .sc_run_load(root); original <- state$pending
  proposal <- .sc_run_get(root, state, "manual_strategy")
  view <- sc_run_suggest(root)
  expect_true(view$can_request); expect_false(view$can_approve)
  expect_true(view$can_auto_request)
  expect_identical(view$preview$consent_mode, "project")
  expect_null(view$preview$remaining_usd)
  calls <- 0L
  answer <- transfer_action(root, "request", chat_fn = function(...) {
    calls <<- calls + 1L
    list(content = .sc_run_provider_json(proposal), cost_usd = .01)
  })
  expect_identical(answer$status, "candidate")
  expect_false(answer$can_auto_request)
  expect_null(answer$preview$remaining_usd)
  after <- .sc_run_load(root)
  expect_identical(after$pending, original); expect_length(after$approvals, 0L)
  expect_null(after$files$analysis); expect_identical(calls, 1L)
  expect_identical(after$history[[length(after$history)]]$action, "suggestion_request_finished")
  transfer_action(root, "adopt", reviewer = "human-test", reason = "Adopt the typed draft for review only.")
  adopted <- .sc_run_load(root)
  expect_length(adopted$approvals, 0L); expect_null(adopted$files$analysis)
  expect_identical(adopted$pending$kind, "strategy")
  expect_false(sc_run_suggest(root)$can_auto_request)
})

test_that("strict mode and failed requests preserve unapproved draft fields", {
  for (mode in c("strict", "invalid", "budget")) {
    root <- transfer_draft_fixture(if (mode == "strict") NULL else transfer_confirmation(),
      budget = if (mode == "budget") .005 else .1)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    before_state <- .sc_run_load(root)
    before <- before_state$pending
    before_draft <- .sc_run_get(root, before_state, "manual_strategy")
    view <- sc_run_suggest(root)
    calls <- 0L
    fn <- function(...) { calls <<- calls + 1L; list(content = "{invalid", cost_usd = .001) }
    if (mode == "strict") {
      expect_false(view$can_request); expect_true(view$can_approve)
      expect_error(transfer_action(root, "request", chat_fn = fn), "Approve the exact")
    } else {
      value <- transfer_action(root, "request", chat_fn = fn)
      expect_identical(value$status, "failed")
      expect_identical(value$response$status, "invalid_response")
    }
    state <- .sc_run_load(root)
    if (mode == "strict") {
      expect_identical(state$pending, before)
    } else {
      # A failed optional request now saves an identified local rule draft.
      # Its QC rationale/hash can change; scientific approval never follows.
      fallback <- sc_run_suggest(root)$fallback
      expect_true(fallback$saved)
      expect_identical(fallback$trigger_status, "invalid_response")
      expect_false(fallback$scientific_approval)
      expect_identical(state$pending$kind, "strategy")
      after_draft <- .sc_run_get(root, state, "manual_strategy")
      unchanged_fields <- setdiff(names(before_draft), "qc")
      # Typed validation normalizes integer/double and array storage in R.
      # Compare every retained field's exact JSON value rather than storage type.
      expect_identical(.sc_run_provider_json(after_draft[unchanged_fields]),
        .sc_run_provider_json(before_draft[unchanged_fields]))
    }
    expect_length(state$approvals, 0L)
    expect_null(state$files$analysis)
    expect_identical(calls, if (mode == "strict") 0L else 1L)
  }
})

transfer_review <- function(...) {
  invisible(capture.output(value <- sc_review(...)))
  value
}

test_that("public mock draft adoption still requires three separate human scientific approvals", {
  root <- transfer_draft_fixture(scan = TRUE); on.exit(unlink(root, recursive = TRUE))
  original_input_hash <- .sc_run_load(root)$files$input$sha256
  calls <- 0L
  strategy <- .sc_run_get(root, .sc_run_load(root), "manual_strategy")
  candidate <- transfer_action(root, "request", chat_fn = function(...) {
    calls <<- calls + 1L
    list(content = .sc_run_provider_json(strategy), cost_usd = .01)
  })
  expect_identical(candidate$status, "candidate")
  transfer_action(root, "adopt", reviewer = "human-test", reason = "Stage the public fixture draft.")
  expect_length(.sc_run_load(root)$approvals, 0L)
  initial <- transfer_review(sc_open(root))
  measured <- suppressWarnings(transfer_review(initial, "approve", reviewer = "human-test",
    reason = "Reviewed initial public fixture strategy.", continue = TRUE))
  expect_identical(measured$view$pending$kind, "strategy")
  expect_length(.sc_run_load(root)$approvals, 1L)
  expect_false(is.null(measured$view$strategy_review$details$cluster_diagnostics))
  measured <- transfer_review(measured)
  annotation <- suppressWarnings(transfer_review(measured, "approve", reviewer = "human-test",
    reason = "Reviewed actual saved PC and scanned clustering evidence.", continue = TRUE))
  expect_identical(annotation$view$stage, "annotation_propose")
  expect_length(.sc_run_load(root)$approvals, 2L)
  candidate <- transfer_action(root, "request", chat_fn = function(system_prompt, user_prompt) {
    calls <<- calls + 1L
    payload <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    value <- list(schema = "scagentkit.annotation.v1", annotations = lapply(payload$evidence$clusters,
      function(cl) list(clusterId = cl$clusterId, label = "Unknown", confidence = "low",
        rationale = "Public software fixture abstention, not a biological conclusion.", markers = list())))
    list(content = .sc_run_provider_json(value), cost_usd = .01)
  })
  expect_identical(candidate$status, "candidate")
  transfer_action(root, "adopt", reviewer = "human-test", reason = "Stage Unknown-only labels for human review.")
  expect_length(.sc_run_load(root)$approvals, 2L)
  annotation <- transfer_review(sc_open(root))
  done <- suppressWarnings(transfer_review(annotation, "approve", reviewer = "human-test",
    reason = "Reviewed the complete provisional Unknown-only annotation.", continue = TRUE))
  expect_identical(done$view$status, "complete")
  history <- jsonlite::read_json(file.path(root, "decision_history.json"))$events
  approvals <- Filter(function(event) identical(event$action, "approved"), history)
  expect_identical(vapply(approvals, function(event) event$details$kind, ""),
    c("strategy", "strategy", "annotation"))
  confirmed <- Filter(function(event) identical(event$action, "transfer_consent_confirmed"), history)
  expect_length(confirmed, 1L)
  expect_identical(confirmed[[1L]]$details$hash, .sc_run_load(root)$config$review$transfer_consent$hash)
  expect_identical(calls, 2L)
  expect_identical(.sc_run_load(root)$files$input$sha256, original_input_hash)
  expect_true(all(sc_result(done)$sc_annotation == "Unknown"))
  expect_identical(ncol(sc_result(done)), 80L)
})
