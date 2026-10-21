entry_qc_input <- function() {
  e <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = e)
  x <- e$pbmc_small
  x$sample <- rep(c("A", "B"), each = 40)
  x
}
entry_qc_context <- function() list(species = "human", tissue = "software fixture",
  columns = list(sample = "sample"))

test_that("main entry binds sample-aware MAD choices without automatic quality deletion", {
  x <- sc_analyze(entry_qc_input(), tempfile(), entry_qc_context(),
    plan = list(analysis = list(nfeatures = 100L, npcs = 6L), pcs = 4L, umap = FALSE))
  expect_identical(x$view$status, "awaiting_review")
  panel <- x$view$strategy_review$details$mad_panel
  expect_identical(panel$grouping$column, "sample")
  expect_length(panel$groups, 2L)
  expect_identical(x$plan$qc$schema, "scagentkit.qc.rules.v1")
  expect_length(x$plan$qc$rules, 1L)
  expect_identical(x$plan$qc$rules[[1]]$op, "mad_preset")
  expect_identical(x$plan$qc$rules[[1]]$preset_id, "keep_all")
  expect_match(x$plan$qc$rationale, "No additional QC")
  expect_match(x$plan$qc$rationale, "QC remains unassessed")
  expect_match(paste(x$plan$qc$risks, collapse = " "), "empty-droplet")
  expect_length(.sc_run_get(x$project_dir, .sc_run_load(x$project_dir), "strategy_validated")$qc_validated$keep_cells, 80L)
  alternative <- .sc_ui_plan(list(qc_preset = "low_counts3"), base = x$plan)
  expect_identical(alternative$qc$rules[[1]]$preset_id, "low_counts3")
  expect_identical(alternative$qc$rules[[1]]$panel_hash, panel$panel_hash)
  expect_identical(panel$method$high_rna_action, "flag only; no high-count/high-feature deletion")
  expect_identical(panel$method$ribo_hb_action, "diagnostic only; no deletion")
})

test_that("undeclared samples disable implicit pooled MAD and QC edits stay bound", {
  cfg <- .sc_ui_mad_setup(list())
  expect_identical(cfg, FALSE)
  expect_null(.sc_run_mad_options(list(), cfg))
  expect_identical(.sc_ui_mad_setup(entry_qc_context())$grouping$declared_role, "sample")
})

test_that("public review can explicitly select saved MAD after removing its last selector", {
  x <- sc_analyze(entry_qc_input(), tempfile(), entry_qc_context(),
    plan = list(analysis = list(nfeatures = 100L, npcs = 6L), pcs = 4L, umap = FALSE))
  panel_hash <- x$view$strategy_review$details$mad_panel$panel_hash
  for (rules in list(list(), list(list(op = "range", metric = "nCount", min = 1, max = NULL, group = NULL)))) {
    draft <- x$plan
    draft$qc$rules <- rules
    draft$qc$remove_if <- "all"
    sc_run_propose(x$project_dir, draft, "author", "Explicitly remove the MAD selector for this review.")
    invisible(capture.output(shown <- sc_review(x)))
    expect_identical(shown$plan$qc$rules, rules)
    invisible(capture.output(prose <- sc_review(shown, "revise", reviewer = "author",
      reason = "Retain the reviewed QC policy.", plan = list(rationale = "Reviewed software fixture."))))
    expect_identical(prose$plan$qc$rules, rules)
    invisible(capture.output(selected <- sc_review(prose, "revise", reviewer = "author",
      reason = "Explicitly select the saved MAD candidate.", plan = list(qc_preset = "keep_all"))))
    expect_identical(selected$plan$qc$rules, c(rules,
      list(list(op = "mad_preset", preset_id = "keep_all", panel_hash = panel_hash))))
    expect_identical(selected$plan$qc$remove_if, "all")
    expect_identical(selected$view$status, "awaiting_review")
    expect_null(.sc_run_load(x$project_dir)$files$qc_object)
  }
})


test_that("entry panel retains explicit unavailable and heuristic warning states", {
  opts <- .sc_run_mad_options(list(), list(grouping=list(method="single", id="synthetic",
    source="Explicit single-group metric unit fixture; never an automatic default.")))
  small <- .sc_run_mad_metric(seq_len(20), "nCount", opts)
  expect_false(small$available)
  expect_match(paste(small$unavailable_reasons, collapse = " "), "Fewer than 30")
  constant <- .sc_run_mad_metric(rep(12, 40), "nCount", opts)
  expect_false(constant$available)
  expect_null(constant$exact$lower_raw)
  expect_match(paste(constant$unavailable_reasons, collapse = " "), "MAD is zero")
  missing <- .sc_run_mad_metric(rep(NA_real_, 40), "percent_mt", opts)
  expect_false(missing$available)
  expect_equal(missing$measured, 0)
  expect_null(missing$exact$upper_raw)
  split <- .sc_run_mad_metric(c(rep(1, 30), rep(10000, 30)), "nCount", opts)
  expect_true(length(split$warnings) > 0L)
  expect_match(paste(split$warnings, collapse = " "), "not proof of multimodality")
})
