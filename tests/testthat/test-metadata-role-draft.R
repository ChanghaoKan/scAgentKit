metadata_role_fixture <- function(multiple = TRUE) {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  seu <- env$pbmc_small
  seu$orig.ident <- "private-study-code"
  seu$patient_name <- "private-person-name"
  if (multiple) {
    seu$sample <- rep(c("private-sample-A", "private-sample-B"), each = 40)
    seu$condition <- c(rep("control", 36), rep("private-rare-diagnosis", 4), rep("treated", 40))
    seu$donor <- paste0("private-donor-", seq_len(80))
  }
  seu
}
metadata_role_begin <- function(provider = NULL, disable_mad = FALSE) {
  root <- tempfile("metadata-role-")
  args <- list(input = metadata_role_fixture(), project_dir = root,
    context = list(species = "human", tissue = "Public PBMC", research_goal = "Offline mapping-draft validation"),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, diagnostic_resolutions = NULL, umap = FALSE),
    provider = provider)
  if (disable_mad) args$qc_mad <- FALSE
  do.call(sc_analyze, args)
  root
}
metadata_role_save <- function(root, column) {
  node <- sc_run_inspect(root)$review_node
  do.call(sc_run_review, c(list(project_dir = root, action = "facts", facts = list(columns = list(sample = column)),
    reviewer = "human-test", reason = "Reviewed the sample grouping declaration, not a scientific approval."),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")]))
}

test_that("candidate summaries whitelist columns, aggregate values and suppress rare identifiers", {
  seu <- metadata_role_fixture(); before <- .sc_run_hash(seu)
  value <- .sc_run_metadata_roles(seu, list(species = "human"), TRUE)
  expect_null(value$context$columns$sample)
  expect_identical(value$summary$status, "needs_selection")
  expect_setequal(vapply(value$summary$candidates, `[[`, "", "column"), c("orig.ident", "sample", "condition", "donor"))
  text <- .sc_run_provider_json(value$summary)
  expect_false(grepl("private-|patient_name", text))
  expect_true(grepl("control|treated", text))
  expect_false(value$summary$privacy$cell_ids_included)
  expect_false(value$summary$privacy$per_cell_values_included)
  expect_identical(.sc_run_hash(seu), before)
  donor <- Filter(function(row) row$column == "donor", value$summary$candidates)[[1L]]
  expect_equal(donor$rare_groups_suppressed, 80)
  expect_length(donor$safe_value_counts, 0L)
})

test_that("only one complete candidate may be a sample fallback and never a technical-batch inference", {
  value <- .sc_run_metadata_roles(metadata_role_fixture(FALSE), list(species = "human"), TRUE)
  expect_identical(value$context$columns$sample, "orig.ident")
  expect_identical(value$summary$selection_source, "single_candidate_rule")
  expect_null(value$context$columns$batch); expect_null(value$context$design$technical_batch)
  seu <- metadata_role_fixture(FALSE); seu[["orig.ident"]] <- NULL; seu$condition <- rep(c("control", "treated"), each = 40)
  value <- .sc_run_metadata_roles(seu, list(species = "human"), TRUE)
  expect_identical(value$context$columns$sample, "condition")
  expect_null(value$context$columns$batch); expect_null(value$context$columns$condition)
  seu$condition[[1L]] <- NA_character_
  value <- .sc_run_metadata_roles(seu, list(species = "human"), TRUE)
  expect_null(value$context$columns$sample)
})

test_that("multiple candidates disable automatic pooling and explicit facts rebuild grouped MAD without approval", {
  root <- metadata_role_begin(); on.exit(unlink(root, recursive = TRUE))
  state <- .sc_run_load(root); view <- sc_run_inspect(root)
  expect_null(state$config$context$columns$sample); expect_null(state$config$qc_mad)
  expect_identical(state$config$metadata_role_draft$status, "needs_selection")
  expect_true("columns.sample" %in% vapply(view$strategy_review$details$recommendations$fact_fields, `[[`, "", "key"))
  evidence <- .sc_run_get(root, state, "strategy_evidence")
  request <- .sc_run_request("strategy", evidence$summary, state$config)
  expect_false(grepl("private-|patient_name", request$user_prompt))
  expect_match(request$system_prompt, "mapping DRAFT")
  metadata_role_save(root, "sample")
  state <- .sc_run_load(root)
  expect_identical(state$config$context$columns$sample, "sample")
  expect_identical(state$config$qc_mad$grouping$method, "column")
  expect_identical(state$config$qc_mad$grouping$column, "sample")
  expect_length(state$approvals, 0L); expect_null(state$files$analysis)
  refreshed <- sc_run_resume(root)
  expect_identical(refreshed$status, "awaiting_review")
  expect_false(is.null(.sc_run_load(root)$files$qc_mad))
  expect_length(.sc_run_load(root)$approvals, 0L)
  expect_identical(.sc_run_get(root, .sc_run_load(root), "input")[[]], metadata_role_fixture()[[]])
})

test_that("an explicit MAD-off setting survives role declaration", {
  root <- metadata_role_begin(disable_mad = TRUE); on.exit(unlink(root, recursive = TRUE))
  expect_false(.sc_run_load(root)$config$input_policy$automatic_mad)
  metadata_role_save(root, "sample")
  expect_null(.sc_run_load(root)$config$qc_mad)
})

test_that("a model mapping suggestion persists as an inference until the author declares facts", {
  root <- metadata_role_begin(provider = "mock"); on.exit(unlink(root, recursive = TRUE))
  action <- function(name, ...) {
    view <- sc_run_suggest(root)
    sc_run_suggest(root, name, project_id = view$project_id, input_hash = view$input_hash,
      expected_revision = view$revision, suggestion_hash = view$suggestion_hash, ...)
  }
  action("approve", reviewer = "operator", reason = "Explicit offline fixture request.")
  proposal <- .sc_run_get(root, .sc_run_load(root), "manual_strategy")
  proposal$inferences <- list("Metadata role draft: sample=sample; two complete aggregate groups need author confirmation. No technical batch is inferred.")
  value <- action("request", chat_fn = function(...) .sc_run_provider_json(proposal))
  expect_identical(value$status, "candidate")
  action("adopt", reviewer = "human-test", reason = "Stage this mapping draft for review.")
  state <- .sc_run_load(root)
  expect_null(state$config$context$columns$sample)
  expect_length(state$approvals, 0L); expect_null(state$files$analysis)
  expect_match(.sc_run_get(root, state, "manual_strategy")$inferences[[1L]], "Metadata role draft")
})
