test_that("coverage keeps absolute support and states its small-denominator limit", {
  scoring <- scAgentKit:::.sc_run_reference_scoring()
  expect_identical(scoring$ranking_interpretation, "descriptive_coverage_only")
  expect_match(scoring$small_reference_warning, "1/1.*10/20")
  expect_false(scoring$semantic_validation)
})

test_that("saved marker contrasts expose directions without claiming lineage counterevidence", {
  records <- list(
    list(gene = "HIGH", avgLog2FC = 2, pct1 = .8, pct2 = .1, pAdj = .01),
    list(gene = "LOW", avgLog2FC = -1, pct1 = .1, pct2 = .7, pAdj = .02),
    list(gene = "MIXED", avgLog2FC = 1, pct1 = .1, pct2 = .6),
    list(gene = "TIED", avgLog2FC = 0, pct1 = .5, pct2 = .5),
    list(gene = "MISSING", avgLog2FC = NA_real_, pct1 = .8, pct2 = .2),
    list(gene = "BAD", avgLog2FC = Inf, pct1 = 2, pct2 = .2))
  out <- scAgentKit:::.sc_run_saved_expression_review(records)
  expect_identical(vapply(out$records, `[[`, character(1), "direction"),
    c("higher_in_cluster", "lower_in_cluster", "discordant_contrasts", "no_direction", "incomplete", "incomplete"))
  expect_equal(out$records[[1]]$detection_difference, .7)
  expect_identical(out$records[[1]]$statistics, records[[1]])
  expect_identical(out$negative_lineage_panel, "not_assessed")
  expect_false(out$semantic_validation)
  expect_identical(scAgentKit:::.sc_run_saved_expression_review(list())$status, "not_supplied")
})
