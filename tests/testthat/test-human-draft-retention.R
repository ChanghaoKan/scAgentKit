human_draft_project <- function() {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  root <- tempfile("human-draft-")
  sc_analyze(env$pbmc_small, root, context = list(species = "human", tissue = "Public PBMC"),
    provider = "mock", plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4,
      diagnostic_resolutions = NULL, umap = FALSE))
  root
}
human_draft_action <- function(root, action, ...) {
  view <- sc_run_suggest(root)
  sc_run_suggest(root, action, project_id = view$project_id, input_hash = view$input_hash,
    expected_revision = view$revision, suggestion_hash = view$suggestion_hash, ...)
}

test_that("adoption preserves explicit initial and later saved human strategy choices", {
  root <- human_draft_project(); on.exit(unlink(root, recursive = TRUE))
  shown <- sc_open(root)
  invisible(capture.output(shown <- sc_review(shown)))
  invisible(capture.output(revised <- sc_review(shown, "revise", plan = list(qc = list(nCount = c(1, NA))),
    reviewer = "human-test", reason = "Save this explicit range before requesting another draft.")))
  before <- sc_open(root)$plan
  human_draft_action(root, "approve", reviewer = "operator", reason = "Offline software-control suggestion.")
  candidate <- before; candidate$analysis$nfeatures <- 120; candidate$analysis$npcs <- 8
  candidate$qc$rules[[1L]]$min <- 10
  if (identical(candidate$qc$schema, "scagentkit.qc.v1")) candidate$qc$filters[[1L]]$min <- 10
  candidate$rationale <- "New model rationale for untouched fields."
  candidate$choice_reasons$hvg <- "Model requested 120 features; this must not replace the author's setting."
  answer <- human_draft_action(root, "request", chat_fn = function(...) .sc_run_provider_json(candidate))
  expect_identical(answer$status, "candidate")
  human_draft_action(root, "adopt", reviewer = "human-test", reason = "Adopt only the untouched choices for further review.")
  state <- .sc_run_load(root); after <- sc_open(root)$plan
  expect_identical(after$analysis, before$analysis)
  expect_identical(after$qc, before$qc)
  expect_identical(after$pcs, before$pcs)
  expect_identical(after$choice_reasons$hvg, before$choice_reasons$hvg)
  expect_identical(after$rationale, candidate$rationale)
  saved <- .sc_run_get(root, state, "strategy_suggestion_adoption")
  expect_true(all(c("analysis", "qc") %in% saved$preserved_human_fields))
  expect_identical(saved$response$content$analysis$nfeatures, 120L)
  expect_identical(saved$adopted_proposal$analysis$nfeatures, 100L)
  expect_length(state$approvals, 0L); expect_null(state$files$analysis)
  expect_true(sc_run_inspect(root)$strategy_review$details$source$matches_current)
  expect_false(sc_run_inspect(root)$strategy_review$details$source$provider_candidate_matches_current)
})

test_that("human annotation row retention is exact-scope and checkpoint protected", {
  root <- .sc_run_root(tempfile("row-retention-"), create = TRUE); on.exit(unlink(root, recursive = TRUE))
  state <- list(files = list(), history = list(), revision = 0L, config = list(input_policy = list()))
  evidence <- list(private = list(input_cells = data.frame(cell_id = c("private-A", "private-B"), cluster = c("00", "1"))))
  state <- .sc_run_put(root, state, "annotation_evidence", evidence)
  row <- function(id, reason) list(clusterId = id, label = "Unknown", confidence = "low", rationale = reason, markers = list())
  before <- list(schema = "scagentkit.annotation.v1", annotations = list(row("00", "Original uncertainty."), row("1", "Original uncertainty.")))
  after <- before; after$annotations[[1L]]$rationale <- "Human explicitly retained this uncertainty."
  state <- .sc_run_put(root, state, "annotation_validated", after)
  state <- .sc_run_draft_track(root, state, "annotation", before, after)
  candidate <- before; candidate$annotations <- lapply(candidate$annotations, function(value) {value$rationale <- "New model uncertainty."; value})
  merged <- .sc_run_merge_model_draft(root, state, "annotation", candidate)
  expect_identical(merged$preserved, "00")
  expect_identical(merged$proposal$annotations[[1L]], after$annotations[[1L]])
  expect_identical(merged$proposal$annotations[[2L]], candidate$annotations[[2L]])
  evidence$private$input_cells$cluster[[2L]] <- "00"
  changed <- .sc_run_put(root, state, "annotation_evidence", evidence)
  expect_length(.sc_run_merge_model_draft(root, changed, "annotation", candidate)$preserved, 0L)
  file <- file.path(root, state$files$human_draft_controls$path)
  cat("changed", file = file, append = TRUE)
  expect_error(.sc_run_draft_controls(root, state), "changed")
})
