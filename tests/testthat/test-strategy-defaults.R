strategy_default_panel <- function() list(panel_hash = paste(rep("a", 64), collapse = ""),
  summary = list(groups = list(list(metrics = list(nCount = list(available = TRUE),
    nFeature = list(available = TRUE), percent_mt = list(available = TRUE)), warnings = character())),
    presets = list(list(preset_id = "keep_all", available = TRUE),
      list(preset_id = "conservative_and3", available = TRUE))))

test_that("one complete MAD fallback chooses AND3 and any unavailable prerequisite keeps all", {
  panel <- strategy_default_panel()
  expect_identical(.sc_run_default_mad_choice(panel)$preset_id, "conservative_and3")
  for (mode in c("missing", "metric", "predicate", "distribution")) {
    changed <- panel
    if (mode == "missing") changed <- NULL
    if (mode == "metric") changed$summary$groups[[1L]]$metrics$percent_mt$available <- FALSE
    if (mode == "predicate") changed$summary$presets[[2L]]$available <- FALSE
    if (mode == "distribution") changed$summary$groups[[1L]]$warnings <- "large-gap distribution warning"
    choice <- .sc_run_default_mad_choice(changed)
    expect_identical(choice$preset_id, "keep_all")
    expect_false(choice$eligible)
    expect_match(choice$reason, "unassessed")
  }
})

test_that("creation uses the shared AND3 fallback while explicit QC choices survive edits", {
  panel <- strategy_default_panel()
  draft <- .sc_ui_plan(dimensions = c(100, 80), mad = panel)
  selector <- Filter(function(rule) identical(rule$op, "mad_preset"), draft$qc$rules)
  expect_identical(selector[[1L]]$preset_id, "conservative_and3")
  explicit <- .sc_ui_plan(list(qc_preset = "keep_all"), dimensions = c(100, 80), mad = panel)
  changed <- .sc_ui_plan(list(resolution = .4), base = explicit)
  expect_identical(changed$qc, explicit$qc)
  unfiltered <- .sc_ui_plan(dimensions = c(100, 80))
  expect_equal(unfiltered$qc$filters[[1L]]$min, 0)
  expect_match(unfiltered$qc$rationale, "unassessed")
})
