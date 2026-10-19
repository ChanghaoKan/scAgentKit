transfer_privacy_input <- function() {
  env <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = env)
  env$pbmc_small
}

test_that("rare declared groups and cell-ID-like values cannot enter a provider request", {
  seu <- transfer_privacy_input()
  seu$sample <- c(rep("common", 76), rep("private-rare", 4))
  context <- list(species = "human", columns = list(sample = "sample"))
  policy <- .sc_run_metadata_transfer_policy(seu, context)
  expect_true(policy$blocked); expect_identical(policy$rare_role_columns, "sample")
  expect_false(grepl("private-rare", .sc_run_provider_json(policy)))
  expect_error(.sc_run_request("strategy", list(), list(context = context, metadata_transfer_policy = policy)), "No model request")
  seu$sample <- rep(colnames(seu)[[1L]], ncol(seu))
  policy <- .sc_run_metadata_transfer_policy(seu, context)
  expect_true(policy$blocked); expect_identical(policy$cell_id_role_columns, "sample")
  expect_length(policy$rare_role_columns, 0L)
  expect_true(.sc_run_metadata_transfer_policy(seu, list(species = "human", notes = paste("Inspect", colnames(seu)[[2L]])))$context_mentions_cell_ids)
})

test_that("a privacy block preserves the local modern strategy and cannot dispatch", {
  seu <- transfer_privacy_input(); seu$sample <- c(rep("common", 76), rep("private-rare", 4))
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  sc_analyze(seu, root, context = list(species = "human", columns = list(sample = "sample")), provider = "mock",
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  view <- sc_run_inspect(root); before <- .sc_run_load(root)$pending
  preview <- sc_run_suggest(root)
  expect_false(preview$available)
  expect_match(preview$blocked_reason, "No model request")
  expect_identical(view$status, "awaiting_review")
  expect_identical(.sc_run_load(root)$pending, before)
  expect_false(file.exists(file.path(root, "provider", "ledger.json")))
  expect_length(.sc_run_load(root)$approvals, 0L)
})

test_that("a model cannot disable the standard raw project's measured review gate", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  sc_analyze(transfer_privacy_input(), root, list(species = "human"),
    plan = list(analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  state <- .sc_run_load(root); evidence <- .sc_run_get(root, state, "strategy_evidence")
  proposal <- .sc_run_get(root, state, "manual_strategy")
  expect_true(evidence$summary$require_three_gates)
  proposal$clustering$diagnostic_resolutions <- NULL
  expect_error(.sc_run_strategy_validate(proposal, evidence), "cannot remove the second")
  expect_length(state$approvals, 0L)
})
