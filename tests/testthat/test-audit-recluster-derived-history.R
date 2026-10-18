test_that("same-count reclustering archives derived summaries without discarding raw audits", {
  withr::local_options(lifecycle_verbosity = "quiet")
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  old <- as.character(SeuratObject::Idents(obj@data))
  obj@data$seurat_clusters <- old
  replacement <- c(tail(old, 1), head(old, -1))
  expect_equal(sort(as.integer(table(old))), sort(as.integer(table(replacement))))
  expect_false(identical(old, replacement))
  nested_audit <- list(raw_response = '{"old_cluster":"0","label":"historical"}')
  annotations <- data.frame(subcluster = "0", cell_type_fine = "old label")
  annotations$response_audit <- I(list(nested_audit))
  obj@params$subcluster_results <- list(old_lineage = list(
    annotations = annotations, markers = data.frame(cluster = "0", gene = "old marker")))
  obj@params$llm_annotation_summary <- list(status = "complete", clusters = c("0", "1"))
  obj@params$reference_match_interpretation <- list(cluster = "0", note = "old candidate")
  fields <- c("subcluster_results", "llm_annotation_summary", "reference_match_interpretation")
  previous_values <- obj@params[fields]
  obj@params$llm_annotation_responses <- list(historical = "retain exact raw model response")
  prior_history <- list(list(reason = "earlier invalidation", fields = list(old = "retain exact old audit")))
  obj@params$invalidated_cluster_annotations <- prior_history
  testthat::local_mocked_bindings(FindClusters = function(object, ...) {
    object$seurat_clusters <- replacement
    SeuratObject::Idents(object) <- replacement
    object
  }, .package = "Seurat")
  changed <- sc_cluster(obj, .5)
  expect_identical(as.character(changed@data$seurat_clusters), replacement)
  for (field in fields) expect_null(changed@params[[field]], info = field)
  history <- changed@params$invalidated_cluster_annotations
  expect_length(history, 2L)
  expect_identical(history[[1]], prior_history[[1]])
  expect_match(history[[2]]$reason, "recluster|[Cc]luster")
  expect_identical(history[[2]]$fields, previous_values)
  expect_identical(changed@params$llm_annotation_responses, obj@params$llm_annotation_responses)
  expect_identical(head(changed@scripts, length(obj@scripts)), obj@scripts)
  # Another call with no active derived summary must not duplicate historical data.
  repeated <- sc_cluster(changed, .5)
  expect_identical(repeated@params$invalidated_cluster_annotations, history)
  expect_identical(obj@params[fields], previous_values)
})
