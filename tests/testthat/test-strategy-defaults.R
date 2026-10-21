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
  expect_identical(unfiltered$qc$schema, "scagentkit.qc.rules.v1")
  expect_identical(unfiltered$qc$rules, list())
  expect_identical(unfiltered$qc$remove_if, "any")
  expect_match(unfiltered$qc$rationale, "unassessed")
})


test_that("facade edits preserve hash-bound replacement policies and their authored logic", {
  panel <- strategy_default_panel()
  draft <- .sc_ui_plan(list(qc = list(nCount = c(1, 1000))), dimensions = c(100, 80), mad = panel)
  draft$qc$schema <- "scagentkit.qc.rules.v2"
  draft$qc$remove_if <- "all"
  draft$qc$diagnostic_hash <- strrep("b", 64)
  draft$qc$membership_hash <- strrep("c", 64)
  draft$qc$replacements <- list(list(cluster_id = "0", metric = "nCount", min = 2,
    reason = "Explicit hash-bound synthetic replacement."))
  saved <- draft$qc[c("schema", "diagnostic_hash", "membership_hash", "replacements")]
  prose <- .sc_ui_plan(list(rationale = "An explanatory edit.", pcs = 5), base = draft)
  expect_identical(prose$qc, draft$qc)
  preset <- .sc_ui_plan(list(qc_preset = "keep_all"), base = draft)
  expect_identical(preset$qc[names(saved)], saved)
  expect_identical(preset$qc$remove_if, "all")
  expect_identical(preset$qc$rules[[1L]], draft$qc$rules[[1L]])
  expect_identical(preset$qc$rules[[2L]]$panel_hash, panel$panel_hash)
  expect_identical(preset$qc$rules[[2L]]$preset_id, "keep_all")
  ranges <- .sc_ui_plan(list(qc = list(nCount = c(3, NA))), base = draft)
  expect_identical(ranges$qc[names(saved)], saved)
  expect_identical(ranges$qc$remove_if, "any")
  expect_identical(ranges$qc$rules[[1L]], list(op = "range", metric = "nCount", min = 3))
  expect_identical(ranges$qc$rules[[2L]], draft$qc$rules[[2L]])
  expect_error(.sc_ui_plan(list(qc = list()), base = draft), "named list")
})

test_that("only explicit preset edits restore a selector from the saved MAD panel", {
  panel <- strategy_default_panel()
  empty <- .sc_ui_plan(dimensions = c(100, 80))
  ranges <- .sc_ui_plan(list(qc = list(nCount = c(1, 1000))), base = empty)
  replacement <- ranges
  replacement$qc$schema <- "scagentkit.qc.rules.v2"
  replacement$qc$diagnostic_hash <- strrep("b", 64)
  replacement$qc$membership_hash <- strrep("c", 64)
  replacement$qc$replacements <- list(list(cluster_id = "0", metric = "nCount", min = 2,
    reason = "Explicit hash-bound synthetic replacement."))
  for (draft in list(empty, ranges, replacement)) {
    draft$qc$remove_if <- "all"
    prose <- .sc_ui_plan(list(rationale = "An explanatory edit."), base = draft, mad = panel)
    expect_identical(prose$qc, draft$qc)
    range_edit <- .sc_ui_plan(list(qc = list(nCount = c(3, NA))), base = draft, mad = panel)
    expect_identical(range_edit$qc$rules, list(list(op = "range", metric = "nCount", min = 3)))
    selected <- .sc_ui_plan(list(qc_preset = "keep_all"), base = draft, mad = panel)
    expect_identical(selected$qc$rules, c(draft$qc$rules,
      list(list(op = "mad_preset", preset_id = "keep_all", panel_hash = panel$panel_hash))))
    unchanged <- setdiff(names(draft$qc), "rules")
    expect_identical(selected$qc[unchanged], draft$qc[unchanged])
    expect_error(.sc_ui_plan(list(qc_preset = "keep_all"), base = draft), "saved MAD candidate panel")
  }
})
