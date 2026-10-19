test_that("grounded counterevidence requests review without invalidating an accepted grounded label", {
  parsed <- list(primary_annotation="T cell",annotation_status="ok",confidence="high",
    supporting_markers="CD3D",contradicting_markers="MS4A1",recommended_action="accept")
  result <- .annotation_evidence_validity(parsed,c("CD3D","MS4A1"))
  expect_true(result$label_usable)
  expect_identical(result$citation_status,"valid")
  expect_true(result$review_required)
  expect_match(result$review_reasons,"declared_counterevidence")
  expect_length(result$reasons,0L)
  parsed$recommended_action <- "flag_for_review"
  expect_false(.annotation_evidence_validity(parsed,c("CD3D","MS4A1"))$label_usable)
  parsed$recommended_action <- "accept"; parsed$contradicting_markers <- "FORGED"
  forged <- .annotation_evidence_validity(parsed,c("CD3D","MS4A1"))
  expect_false(forged$label_usable)
  expect_identical(forged$citation_status,"invalid")
})


test_that("recorded unsupported support cannot be reported as citation-valid", {
  parsed <- list(primary_annotation="T cell",annotation_status="ok",confidence="high",
    supporting_markers="CD3D",contradicting_markers=character(),recommended_action="accept",
    hallucination_rate=1)
  value <- .annotation_evidence_validity(parsed,"CD3D")
  expect_false(value$label_usable)
  expect_identical(value$citation_status,"invalid")
})
