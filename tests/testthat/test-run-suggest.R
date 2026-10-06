# Small saved-table fixtures exercise the coordinator without scientific work
# or HTTP. Actual end-to-end Seurat and browser validation is separate.
suggestion_fixture <- function(external = FALSE, budget = if (external) .05 else 0,
                               provider_name = "mock", pending = TRUE) {
  root <- tempfile("suggestion-fixture-"); dir.create(root)
  cells <- data.frame(cell_id = c("private-cell-A", "private-cell-B"),
    cluster = c("01", "NA"), stringsAsFactors = FALSE)
  marker <- function(id, gene) list(clusterId = id, gene = gene,
    avgLog2FC = 2, pct1 = .8, pct2 = .1, pAdj = .001,
    source = "saved software-control marker table")
  evidence <- list(summary = list(schema = "scagentkit.annotation-evidence.v1",
    reference_mode = "independent", clusters = list(
      list(clusterId = "01", cellCount = 1L, markers = list(marker("01", "ALB"))),
      list(clusterId = "NA", cellCount = 1L, markers = list(marker("NA", "CD3D"))))),
    private = list(input_cells = cells, cluster_column = "source_cluster",
      candidates = .empty_reference_matches(), candidates_all = .empty_reference_matches(),
      reference_provenance = list(status = "not_supplied", mode = "independent_local_reference")))
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(
    evidence$summary$clusters, function(row) list(clusterId = row$clusterId,
      label = "Unknown", confidence = "low", rationale = "Original manual uncertainty.", markers = list())))
  provider <- .sc_run_provider_spec(list(name = provider_name, model = "software-control-v1",
    external = external, reservation_usd = if (external) .01 else 0))$metadata
  config <- list(context = list(species = "human", tissue = "synthetic"),
    annotation_column = "fresh_type", provider = provider, budget = budget,
    review = list(allow_external = external), strategy = FALSE)
  state <- list(project_id = "run-suggestion-fixture", status = "awaiting_configuration",
    stage = "annotation_propose", revision = 0L, history = list(), nodes = list(),
    files = list(), approvals = list(), transfer_hashes = character(), completed = character(),
    config = config, config_hash = .sc_run_hash(config),
    implementation_hash = .sc_run_implementation(), source = list(), diagnostics = list(),
    pending = NULL, approved = NULL, failure = NULL)
  state <- .sc_run_put(root, state, "input", cells)
  state$input_hash <- state$files$input$sha256
  state <- .sc_run_put(root, state, "annotation_evidence", evidence)
  if (pending) {
    validated <- .sc_run_annotation_validate(proposal, evidence)
    state <- .sc_run_put(root, state, "manual_annotation", proposal)
    state <- .sc_run_put(root, state, "annotation_validated", validated)
    state <- .sc_run_annotation_review_publish(root, state, validated, evidence)
    state <- .sc_run_pending(state, "annotation", validated, .sc_run_hash(evidence), "annotation_apply")
  }
  .sc_run_save(root, state)
  list(root = root, state = state, evidence = evidence, proposal = proposal)
}

suggestion_action <- function(fixture, action, simulate = TRUE, view = NULL, ...) {
  if (is.null(view)) view <- sc_run_suggest(fixture$root, "preview", simulate = simulate)
  sc_run_suggest(fixture$root, action, project_id = view$project_id,
    input_hash = view$input_hash, expected_revision = view$revision,
    suggestion_hash = view$suggestion_hash, reviewer = "offline software QA",
    reason = "Review the exact software-control scope.", simulate = simulate, ...)
}

test_that("suggestion preview is read-only, aggregate-only and explicit about simulation", {
  f <- suggestion_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  before <- .sc_project_sha_file(file.path(f$root, "state.rds"))
  preview <- sc_run_suggest(f$root, "preview", simulate = TRUE)
  expect_true(preview$available); expect_true(preview$can_approve)
  expect_true(preview$preview$simulated); expect_match(preview$preview$notice, "SIMULATED")
  expect_true(preview$preview$external); expect_identical(preview$preview$provider$api_key_env, NULL)
  expect_false(grepl("private-cell", preview$preview$user_prompt, fixed = TRUE))
  expect_identical(before, .sc_project_sha_file(file.path(f$root, "state.rds")))
  expect_false(file.exists(file.path(f$root, "provider", "ledger.json")))
  normal <- sc_run_suggest(f$root, "preview", simulate = FALSE)
  expect_false(identical(preview$preview$request_hash, normal$preview$request_hash))
  expect_error(suggestion_action(f, "request", view = preview), "Approve the exact")
})

test_that("request and exact transfer approval preserve scientific proposals and never compute", {
  f <- suggestion_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  approved <- suggestion_action(f, "approve")
  expect_identical(approved$status, "approved")
  state <- .sc_run_load(f$root)
  expect_identical(state$pending, f$state$pending); expect_identical(state$approvals, f$state$approvals)
  same <- suggestion_action(f, "approve", view = approved)
  expect_identical(same$revision, approved$revision)
  candidate <- suggestion_action(f, "request", view = approved)
  expect_identical(candidate$status, "candidate"); expect_true(candidate$can_adopt)
  expect_true(all(vapply(candidate$candidate$annotations, function(row) row$label == "Unknown", logical(1))))
  expect_identical(candidate$response$cost_state, "known"); expect_equal(candidate$response$cost_usd, 0)
  after <- .sc_run_load(f$root)
  expect_identical(after$pending, f$state$pending); expect_identical(after$files, f$state$files)
  expect_identical(after$completed, f$state$completed); expect_null(after$output)
  cached <- suggestion_action(f, "request", view = candidate)
  expect_true(cached$response$cached); expect_identical(cached$candidate, candidate$candidate)
  ledger <- .sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))
  expect_length(ledger$entries, 1L)
  adopted <- suggestion_action(f, "adopt", view = cached)
  expect_identical(adopted$status, "awaiting_review")
  expect_identical(adopted$review_node$kind, "annotation")
  expect_false(identical(adopted$pending$hash, f$state$pending$hash))
  source <- adopted$annotation_review$details$source
  expect_identical(source$kind, "mock"); expect_true(source$suggestion$simulated)
  expect_true(source$suggestion$matches_current)
  expect_match(source$suggestion$interpretation, "SIMULATED")
  expect_identical(source$reference_dependency, "not_dispatched")
  expect_true(source$reference_prompt$simulated)
  expect_length(.sc_run_load(f$root)$approvals, 0L)
  # A fresh proposal binding can read the identical approved payload/cache,
  # while the previously adopted scientific snapshot stays authoritative.
  review_hash <- adopted$review_node$review_hash
  fresh <- sc_run_suggest(f$root, "preview", simulate = TRUE)
  expect_false(fresh$can_approve); expect_true(fresh$can_request)
  recached <- suggestion_action(f, "request", view = fresh)
  expect_true(recached$response$cached)
  inspected <- sc_run_inspect(f$root)
  expect_identical(inspected$review_node$review_hash, review_hash)
  expect_identical(inspected$annotation_review$details$source, source)
  expect_length(.sc_run_provider_read(file.path(f$root, "provider", "ledger.json"))$entries, 1L)
})

test_that("strict suggestion identity, revision and changed evidence fail closed", {
  f <- suggestion_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  initial <- sc_run_suggest(f$root, "preview", simulate = TRUE)
  bad <- initial; bad$project_id <- "foreign-project"
  expect_error(suggestion_action(f, "approve", view = bad), "Foreign project")
  bad <- initial; bad$input_hash <- strrep("f", 64)
  expect_error(suggestion_action(f, "approve", view = bad), "changed input")
  bad <- initial; bad$suggestion_hash <- strrep("a", 64)
  expect_error(suggestion_action(f, "approve", view = bad), "Stale suggestion")
  approved <- suggestion_action(f, "approve", view = initial)
  expect_error(suggestion_action(f, "approve", view = initial), "revision")
  expect_error(sc_run_suggest(f$root, "approve", project_id = initial$project_id,
    input_hash = initial$input_hash, suggestion_hash = initial$suggestion_hash,
    reviewer = "QA", reason = "Explicit."), "expected_revision")
  writeLines("changed evidence", file.path(f$root, f$state$files$annotation_evidence$path))
  expect_error(sc_run_suggest(f$root, "preview", simulate = TRUE), "changed")
})

test_that("unsupported, overlong and truncated model proposals are durable cached failures", {
  cases <- list(
    function(proposal) { proposal$annotations[[1]]$label <- "Liver-like"; proposal$annotations[[1]]$markers <- list("HALLUCINATED"); list(content = .sc_project_json(proposal), cost_usd = 0) },
    function(proposal) { proposal$annotations[[1]]$rationale <- paste(rep("x", 241L), collapse = ""); list(content = .sc_project_json(proposal), cost_usd = 0) },
    function(proposal) list(content = .sc_project_json(proposal), cost_usd = 0, response_metadata = list(finish_reason = "length")))
  for (case in cases) {
    f <- suggestion_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE), add = TRUE)
    approved <- suggestion_action(f, "approve", simulate = FALSE)
    calls <- 0L
    fn <- function(...) { calls <<- calls + 1L; case(f$proposal) }
    failed <- suggestion_action(f, "request", simulate = FALSE, view = approved, chat_fn = fn)
    expect_identical(failed$status, "failed")
    expect_true(failed$response$status %in% c("invalid_response", "truncated_response"))
    expect_null(failed$candidate)
    again <- suggestion_action(f, "request", simulate = FALSE, view = failed, chat_fn = fn)
    expect_true(again$response$cached); expect_identical(calls, 1L)
    expect_identical(.sc_run_load(f$root)$pending, f$state$pending)
  }
})

test_that("unknown delivery and interrupted reservations never automatically repeat", {
  f <- suggestion_fixture(TRUE); on.exit(unlink(f$root, recursive = TRUE))
  approved <- suggestion_action(f, "approve", simulate = FALSE)
  calls <- 0L; fn <- function(...) { calls <<- calls + 1L; stop("Sensitive HTTP body is not retained.") }
  failed <- suggestion_action(f, "request", simulate = FALSE, view = approved, chat_fn = fn)
  expect_identical(failed$response$status, "delivery_uncertain")
  expect_equal(failed$preview$held_usd, .01)
  expect_false(grepl("Sensitive HTTP", failed$response$error, fixed = TRUE))
  again <- suggestion_action(f, "request", simulate = FALSE, view = failed, chat_fn = fn)
  expect_true(again$response$cached); expect_identical(calls, 1L)
  g <- suggestion_fixture(TRUE); on.exit(unlink(g$root, recursive = TRUE), add = TRUE)
  approved <- suggestion_action(g, "approve", simulate = FALSE)
  withr::local_options(scAgentKit.provider_crash = "after_dispatch")
  interrupted <- suggestion_action(g, "request", simulate = FALSE, view = approved,
    chat_fn = function(...) stop("must not be called"))
  expect_identical(interrupted$response$status, "interrupted")
  expect_equal(interrupted$preview$held_usd, .01)
  hold <- suggestion_action(g, "request", simulate = FALSE, view = interrupted,
    chat_fn = function(...) stop("must not be called"))
  expect_identical(hold$response$status, "accounting_hold")
  expect_length(.sc_run_provider_read(file.path(g$root, "provider", "ledger.json"))$entries, 1L)
})

test_that("budget stops before callbacks and manual configuration cannot be enabled by simulation", {
  f <- suggestion_fixture(TRUE, budget = .005); on.exit(unlink(f$root, recursive = TRUE))
  approved <- suggestion_action(f, "approve", simulate = FALSE)
  out <- suggestion_action(f, "request", simulate = FALSE, view = approved,
    chat_fn = function(...) stop("must not dispatch"))
  expect_identical(out$response$status, "budget_stop")
  expect_false(file.exists(file.path(f$root, "provider", "ledger.json")))
  manual <- suggestion_fixture(provider_name = "manual")
  on.exit(unlink(manual$root, recursive = TRUE), add = TRUE)
  preview <- sc_run_suggest(manual$root, "preview")
  expect_false(preview$available); expect_match(preview$blocked_reason, "no configured provider")
  expect_error(sc_run_suggest(manual$root, "preview", simulate = TRUE), "immutable mock")
})

test_that("discard and later manual edits retain truthful historical suggestion provenance", {
  f <- suggestion_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  approved <- suggestion_action(f, "approve")
  candidate <- suggestion_action(f, "request", view = approved)
  discarded <- suggestion_action(f, "discard", view = candidate)
  expect_identical(discarded$status, "discarded")
  expect_identical(.sc_run_load(f$root)$pending, f$state$pending)
  expect_error(suggestion_action(f, "adopt", view = discarded), "No current")
  g <- suggestion_fixture(); on.exit(unlink(g$root, recursive = TRUE), add = TRUE)
  approved <- suggestion_action(g, "approve")
  candidate <- suggestion_action(g, "request", view = approved)
  suggestion_action(g, "adopt", view = candidate)
  proposal <- g$proposal; proposal$annotations[[1]]$rationale <- "A subsequent manual review note."
  state <- .sc_run_load(g$root)
  .sc_run_propose_locked(g$root, state, proposal, "manual analyst", "Independent manual revision.", drive = FALSE)
  source <- sc_run_inspect(g$root)$annotation_review$details$source
  expect_identical(source$kind, "manual")
  expect_false(source$suggestion$matches_current); expect_true(source$suggestion$simulated)
  fresh <- sc_run_suggest(g$root, "preview", simulate = TRUE)
  expect_error(suggestion_action(g, "adopt", view = modifyList(fresh,
    list(suggestion_hash = candidate$suggestion_hash))), "Stale suggestion")
})
