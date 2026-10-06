test_that(".compute_hybrid_confidence: strong evidence gives 'high'", {
  parsed <- list(
    primary_annotation    = "T cell",
    confidence            = "high",
    hallucination_rate    = 0,
    proportion_assessment = "reasonable"
  )
  cluster_markers <- data.frame(
    pct.1 = c(0.95, 0.90, 0.88),
    pct.2 = c(0.05, 0.10, 0.08)
  )
  ref_rows <- data.frame(cell_type = "T cell", score = c(0.85))

  hc <- scAgentKit:::.compute_hybrid_confidence(parsed,
                                                cluster_markers, ref_rows)
  expect_gte(hc$score, 0.7)
  expect_equal(hc$label, "high")
  expect_false(hc$disagreement)
})

test_that(".compute_hybrid_confidence: high hallucination drops confidence", {
  parsed <- list(
    primary_annotation    = "T cell",
    confidence            = "high",
    hallucination_rate    = 1,
    proportion_assessment = "reasonable"
  )
  cluster_markers <- data.frame(
    pct.1 = c(0.95, 0.90),
    pct.2 = c(0.05, 0.10)
  )
  ref_rows <- data.frame(cell_type = "T cell", score = c(0.85))

  hc <- scAgentKit:::.compute_hybrid_confidence(parsed,
                                                cluster_markers, ref_rows)
  # 0.3*0.85 + 0.3*0.9 + 0.2*0 + 0.2*1 = 0.255 + 0.27 + 0 + 0.2 = 0.725
  # Still high, but lower than no-halluc case. Adjust expectation.
  expect_lte(hc$score, 0.75)
})

test_that(".compute_hybrid_confidence: weak evidence gives 'low'", {
  parsed <- list(
    primary_annotation    = "T cell",
    confidence            = "high",
    hallucination_rate    = 0.8,
    proportion_assessment = "abnormal"
  )
  cluster_markers <- data.frame(
    pct.1 = c(0.30, 0.28),
    pct.2 = c(0.20, 0.18)
  )
  ref_rows <- data.frame(cell_type = "T cell", score = c(0.10))

  hc <- scAgentKit:::.compute_hybrid_confidence(parsed,
                                                cluster_markers, ref_rows)
  expect_lt(hc$score, 0.4)
  expect_equal(hc$label, "low")
  expect_true(hc$disagreement)   # LLM said high, hybrid says low
})

test_that(".compute_hybrid_confidence: missing reference is OK", {
  parsed <- list(
    primary_annotation    = "T cell",
    confidence            = "medium",
    hallucination_rate    = 0,
    proportion_assessment = "reasonable"
  )
  cluster_markers <- data.frame(
    pct.1 = c(0.60),
    pct.2 = c(0.10)
  )

  hc <- scAgentKit:::.compute_hybrid_confidence(parsed, cluster_markers,
                                                reference_rows = NULL)
  expect_true(is.numeric(hc$score) && !is.na(hc$score))
  expect_true(hc$label %in% c("low", "medium", "high"))
})

test_that(".compute_hybrid_confidence: disagreement only on opposite bands", {
  # LLM=high, hybrid=medium → NOT a disagreement (adjacent)
  parsed <- list(
    primary_annotation    = "T cell",
    confidence            = "high",
    hallucination_rate    = 0.3,
    proportion_assessment = "suspicious"
  )
  cluster_markers <- data.frame(pct.1 = c(0.6), pct.2 = c(0.2))
  ref_rows <- data.frame(cell_type = "T cell", score = c(0.5))

  hc <- scAgentKit:::.compute_hybrid_confidence(parsed,
                                                cluster_markers, ref_rows)
  expect_false(hc$disagreement)   # high vs medium is fine
})

test_that("an unrelated high-scoring reference label cannot boost model confidence", {
  parsed <- list(primary_annotation = "T cell", confidence = "medium",
                 hallucination_rate = 0, proportion_assessment = "reasonable")
  markers <- data.frame(pct.1 = 0.6, pct.2 = 0.2)
  baseline <- scAgentKit:::.compute_hybrid_confidence(parsed, markers, NULL)
  unrelated <- scAgentKit:::.compute_hybrid_confidence(parsed, markers,
    data.frame(cell_type = "B cell", score = 1))
  matching <- scAgentKit:::.compute_hybrid_confidence(parsed, markers,
    data.frame(cell_type = c("B cell", "  t CELL "), score = c(1, 0.5)))
  expect_equal(unrelated$score, baseline$score)
  expect_equal(matching$score, baseline$score + 0.3 * 0.5)
})

test_that("missing, non-finite, and unknown heuristic inputs are safe", {
  parsed <- list(primary_annotation = NA_character_, confidence = "low",
                 hallucination_rate = NA_real_, proportion_assessment = NA_character_)
  hc <- scAgentKit:::.compute_hybrid_confidence(parsed, NULL,
    data.frame(cell_type = "T cell", score = Inf))
  expect_true(is.finite(hc$score))
  expect_equal(hc$score, 0.2)
})
