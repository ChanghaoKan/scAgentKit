annotation_safety_json <- function() {
  '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["CD3D"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"CD3D supports the T lineage."}'
}

annotation_safety_response <- function(...) {
  value <- jsonlite::fromJSON(annotation_safety_json(), simplifyVector = FALSE)
  updates <- list(...)
  for (name in names(updates)) value[name] <- updates[name]
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"))
}


test_that("annotation validator preserves arrays and checks an optional cluster echo", {
  withr::local_options(lifecycle_verbosity="quiet")
  parse <- function(raw, ...) scAgentKit:::.validate_annotation_response(
    jsonlite::fromJSON(raw, simplifyVector = FALSE), ...
  )
  out <- parse(annotation_safety_json())
  expect_identical(out$supporting_markers, "CD3D")
  expect_identical(out$contradicting_markers, character(0))
  expect_equal(parse(annotation_safety_response(cluster = "0"), expected_cluster = "0")$cluster, "0")
  expect_error(parse(annotation_safety_response(cluster = "9"), expected_cluster = "0"), "cluster ID")
  expect_error(parse(annotation_safety_response(cluster = 0), expected_cluster = "0"), "scalar string")
  expect_error(parse(annotation_safety_response(primary_annotation = "NK cell"), vocabulary = "T cell"), "strict vocabulary")
  expect_equal(parse(annotation_safety_response(primary_annotation = "Unknown"), vocabulary = "T cell")$primary_annotation, "Unknown")
})
