



test_that("the local gate rejects unresolved, partial, disabled and fabricated evidence without semantic claims", {
  valid <- list(primary_annotation = "T cell", annotation_status = "ok", confidence = "high",
    supporting_markers = "REAL", contradicting_markers = character(), recommended_action = "accept")
  gate <- scAgentKit:::.annotation_evidence_validity
  expect_true(gate(valid, "REAL")$label_usable)
  for (edits in list(list(primary_annotation = "Unknown"), list(annotation_status = "partial"),
    list(annotation_status = "failed"),
    list(contradicting_markers = "FORGED"), list(recommended_action = "reject"),
    list(supporting_markers = character()))) {
    x <- valid; x[names(edits)] <- edits
    expect_false(gate(x, "REAL")$label_usable)
  }
  disabled <- gate(valid, "REAL", validation_enabled = FALSE)
  expect_false(disabled$label_usable)
  expect_identical(disabled$status, "needs_review")
  expect_match(disabled$limitation, "not label semantic validation")
})
