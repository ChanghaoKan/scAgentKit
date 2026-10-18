recommend_workspace_input <- function() {
  set.seed(704)
  x <- matrix(rpois(100 * 80, 3), 100, dimnames = list(c("MT-CO1", paste0("GENE", 2:100)), paste0("cell", 1:80)))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(x, sparse = TRUE))
  seu$sample <- rep(c("A", "B"), each = 40)
  seu$capture <- rep(c("load1", "load2"), each = 40)
  seu$condition <- rep(c("control", "treated"), 40)
  seu
}
recommend_workspace_begin <- function() {
  path <- tempfile()
  suppressWarnings(sc_analyze(recommend_workspace_input(), path,
    context = list(species = "human", tissue = "software control", research_goal = "Offline recommendation workflow",
      columns = list(sample = "sample"))))
  path
}
recommend_workspace_facts <- function(path, facts, node = sc_run_inspect(path)$review_node) {
  do.call(sc_run_review, c(list(project_dir = path, action = "facts", facts = facts,
    reviewer = "author", reason = "Explicit experimental facts; no scientific approval"),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")]))
}

test_that("main review contains bound measured recommendations and explicit unassessed optional paths", {
  path <- recommend_workspace_begin(); view <- sc_run_inspect(path)
  rec <- view$strategy_review$details$recommendations
  expect_identical(rec$schema, "scagentkit.recommendations.v1")
  expect_setequal(vapply(rec$steps, `[[`, character(1), "id"), c("qc", "doublet", "pcs", "batch", "resolution"))
  expect_identical(rec$binding$input_hash, view$input_hash)
  expect_identical(rec$binding$config_hash, view$config_hash)
  expect_identical(rec$binding$evidence_hash, view$strategy_review$evidence_hash)
  expect_true(rec$fact_editable)
  expect_true(length(rec$fact_fields) > 0L)
  expect_true(nzchar(rec$next_decision))
  expect_false(view$scientific_assessment$certified_qc)
  expect_true(all(c("doublet", "batch") %in% view$scientific_assessment$unassessed_steps))
  expect_length(.sc_run_load(path)$approvals, 0L)
})

test_that("facts are snapshot-bound and rebuild diagnostics without approval or authority mutation", {
  path <- recommend_workspace_begin(); before <- sc_run_inspect(path); old <- .sc_run_load(path)
  input <- old$files$input; old_review <- old$files$strategy_review
  out <- recommend_workspace_facts(path, list(batch = list(technical_batch = FALSE, source = "Author declares one technical preparation")))
  expect_identical(out$status, "ready")
  expect_identical(out$stage, "prefilter")
  state <- .sc_run_load(path)
  expect_identical(state$files$input, input)
  expect_length(state$approvals, 0L)
  expect_null(state$pending)
  expect_true(file.exists(file.path(path, old_review$path)))
  expect_false(identical(state$config_hash, old$config_hash))
  expect_false(state$config$context$design$technical_batch)
  expect_error(recommend_workspace_facts(path, list(batch = list(technical_batch = TRUE, source = "stale")), before$review_node), "Stale|current|review")
  out <- sc_run_continue(path, out$project_id, out$input_hash, out$revision)
  expect_identical(out$status, "awaiting_review")
  view <- sc_run_inspect(path); rec <- view$strategy_review$details$recommendations
  batch <- Filter(function(x) x$id == "batch", rec$steps)[[1L]]
  expect_identical(batch$status, "recommend_skip")
  known <- Filter(function(field) identical(field$key, "batch.technical_batch"), rec$fact_fields)
  expect_length(known, 1L)
  expect_identical(known[[1L]]$value, FALSE)
  expect_true("columns.sample" %in% vapply(rec$fact_fields, `[[`, character(1), "key"))
  expect_identical(.sc_run_load(path)$files$input, input)
  expect_false(identical(view$review_node$review_hash, before$review_node$review_hash))
  expect_length(.sc_run_load(path)$approvals, 0L)
})

test_that("invalid facts fail before writes and approvals close the fact-edit boundary", {
  path <- recommend_workspace_begin()
  snapshot <- function() readBin(file.path(path, "state.rds"), "raw", n = file.info(file.path(path, "state.rds"))$size)
  before <- snapshot()
  expect_error(recommend_workspace_facts(path, list(columns = list(capture = "not_a_column"))), "metadata|column")
  expect_identical(snapshot(), before)
  expect_error(recommend_workspace_facts(path, list(batch = list(technical_batch = "yes"))), "logical|boolean")
  expect_identical(snapshot(), before)
  expect_error(recommend_workspace_facts(path, list(executable_R = "system('bad')")), "supported|Unknown|fields")
  expect_identical(snapshot(), before)
  node <- sc_run_inspect(path)$review_node
  sc_run_approve(path, node$proposal_hash, "author", "Approve current complete plan")
  before <- snapshot()
  expect_error(recommend_workspace_facts(path, list(batch = list(technical_batch = FALSE, source = "late")), node), "Stale|initial|approval|review")
  expect_identical(snapshot(), before)
})


test_that("recommendation bindings reject altered saved projections", {
  path <- recommend_workspace_begin(); record <- sc_run_inspect(path)$strategy_review
  expect_invisible(.sc_run_recommendations_verify(record))
  record$details$recommendations$binding$evidence_hash <- paste(rep("0", 64), collapse = "")
  expect_error(.sc_run_recommendations_verify(record), "binding|stale")
})


test_that("legacy assessment remains readable and explicitly unavailable", {
  path <- recommend_workspace_begin(); state <- .sc_run_load(path)
  record <- .sc_run_get(path, state, "strategy_review")
  record$details$recommendations <- NULL
  record$hash <- .sc_run_strategy_review_hash(record)
  expect_invisible(.sc_run_recommendations_verify(record))
  state <- .sc_run_put(path, state, "strategy_review", record)
  assessment <- .sc_run_scientific_assessment(path, state)
  expect_false(assessment$certified_qc)
  expect_identical(assessment$qc_choice, "legacy_unassessed")
  expect_match(assessment$message, "older immutable review")
})
