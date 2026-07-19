make_annot_apply_fixture <- function() {
  counts <- matrix(
    c(2, 0, 1, 0, 3, 1, 0, 2),
    nrow = 2,
    dimnames = list(c("G1", "G2"), paste0("C", 1:4))
  )
  seu <- Seurat::CreateSeuratObject(counts = counts)
  seu$seurat_clusters <- c("0", "0", "1", "1")
  obj <- AgentSeurat(seu)
  obj@params$llm_annotations <- data.frame(
    cluster = c("0", "1"),
    primary_annotation = c("T cell", "Ambiguous"),
    recommended_action = c("accept", "reject"),
    stringsAsFactors = FALSE
  )
  obj
}

test_that("annot_apply keeps LLM-rejected clusters by default", {
  obj <- make_annot_apply_fixture()
  out <- annot_apply(obj)

  expect_equal(ncol(out@data), 4)
  expect_setequal(unique(out@data$cell_type), c("T cell", "Ambiguous"))
  expect_false(tail(out@decisions, 1)[[1]]$params$drop_rejected)
  expect_length(tail(out@decisions, 1)[[1]]$params$rejected_clusters, 0)
})

test_that("annot_apply drops rejected clusters only when explicitly requested", {
  obj <- make_annot_apply_fixture()
  out <- annot_apply(obj, drop_rejected = TRUE)

  expect_equal(ncol(out@data), 2)
  expect_true(all(out@data$seurat_clusters == "0"))
  expect_true(tail(out@decisions, 1)[[1]]$params$drop_rejected)
  expect_equal(tail(out@decisions, 1)[[1]]$params$rejected_clusters, "1")
})
