test_that(".validate_cited_markers detects out-of-input gene citations", {
  parsed <- list(
    supporting_markers    = c("CD3D", "CD8A", "FAKE1"),
    contradicting_markers = c("CD19", "BOGUS")
  )
  input <- c("CD3D", "CD8A", "CD8B", "CD3E", "CD19", "MS4A1")

  res <- scAgentKit:::.validate_cited_markers(parsed, input)

  expect_setequal(res$hallucinated, c("FAKE1", "BOGUS"))
  # rate is computed over supporting only: 1/3 of supporting was hallucinated
  expect_equal(res$rate, 1 / 3)
})

test_that(".validate_cited_markers is case-insensitive", {
  parsed <- list(
    supporting_markers    = c("cd3d", "Cd8a"),
    contradicting_markers = character(0)
  )
  input <- c("CD3D", "CD8A", "CD3E")

  res <- scAgentKit:::.validate_cited_markers(parsed, input)
  expect_length(res$hallucinated, 0)
  expect_equal(res$rate, 0)
})

test_that(".validate_cited_markers handles empty inputs gracefully", {
  parsed <- list(supporting_markers = character(0),
                 contradicting_markers = character(0))
  res <- scAgentKit:::.validate_cited_markers(parsed, c("CD3D"))
  expect_length(res$hallucinated, 0)
  expect_true(is.na(res$rate))

  res2 <- scAgentKit:::.validate_cited_markers(parsed, character(0))
  expect_length(res2$hallucinated, 0)
  expect_true(is.na(res2$rate))
})

test_that(".validate_cited_markers trims whitespace", {
  parsed <- list(supporting_markers    = c("  CD3D ", "CD8A"),
                 contradicting_markers = character(0))
  input <- c("CD3D", "CD8A")
  res <- scAgentKit:::.validate_cited_markers(parsed, input)
  expect_length(res$hallucinated, 0)
})
