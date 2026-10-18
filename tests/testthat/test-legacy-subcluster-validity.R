legacy_gate_response <- function(support = "FORGED", contradict = character(), action = "accept") {
  as.character(jsonlite::toJSON(list(primary_annotation = "Unsupported subtype", confidence = "high",
    supporting_markers = as.list(support), contradicting_markers = as.list(contradict), alternative_annotations = list(),
    proportion_assessment = "reasonable", recommended_action = action, reasoning = "Raw offline proposal."),
    auto_unbox = TRUE))
}

test_that("subcluster citation validity is separate from response schema and raw proposal", {
  withr::local_options(lifecycle_verbosity = "quiet")
  markers <- data.frame(gene = "REAL", avg_log2FC = 2, pct.1 = .9, pct.2 = .1)
  call <- function(support = "FORGED", contradict = character(), action = "accept")
    scAgentKit:::.annotate_one_subcluster_with_llm("Lineage", "0", 100, 1, markers,
      "offline fixture", chat_fn = function(...) legacy_gate_response(support, contradict, action), max_retries = 0)
  bad <- call()
  expect_identical(bad$annotation_status, "ok")
  expect_identical(bad$evidence_status, "needs_review")
  expect_false(bad$label_usable)
  expect_identical(bad$raw_confidence, "high")
  expect_identical(bad$confidence, "low")
  expect_identical(bad$primary_annotation, "Unsupported subtype")
  expect_true(length(bad$response_audit) > 0)
  good <- call("REAL")
  expect_true(good$label_usable)
  expect_identical(good$evidence_status, "usable")
  expect_false(call(c("REAL", "FORGED"))$label_usable)
  expect_false(call("REAL", "REAL")$label_usable)
  expect_false(call("REAL", action = "flag_for_review")$label_usable)
  expect_false(call(character())$label_usable)
})

test_that("blocked fine-label proposals preserve heterogeneous old labels and are not success", {
  withr::local_options(lifecycle_verbosity = "quiet")
  root <- tempfile(); dir.create(root); withr::local_dir(root)
  counts <- Matrix::Matrix(matrix(1, 3, 6, dimnames = list(c("REAL", "G2", "G3"), paste0("C", 1:6))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts)
  seu$cell_type <- rep("Lineage", 6)
  seu$cell_type_fine <- rep(c("OLD_A", "OLD_B"), 3)
  obj <- AgentSeurat(seu)
  fake <- function(...) list(cells = colnames(seu), cell_idx = seq_len(6),
    cell_type_fine = rep("FORGED LABEL", 6), subcluster_id = rep("Lineage_sub0", 6),
    writeback_eligible = rep(FALSE, 6), resolution_used = .5, umap_path = NULL,
    annotations = data.frame(subcluster = "0", cell_type_fine = "FORGED LABEL",
      annotation_status = "ok", evidence_status = "needs_review", label_usable = FALSE))
  testthat::local_mocked_bindings(.subcluster_one_broad = fake, .package = "scAgentKit")
  out <- suppressWarnings(annot_subcluster(obj, function(...) stop("No provider call expected"),
    target = "Lineage", min_cells_per_broad = 1, verbose = FALSE))
  expect_identical(out@data$cell_type_fine, seu$cell_type_fine)
  expect_equal(ncol(out@data), 6)
  expect_false(tail(out@decisions, 1)[[1]]$success)
  expect_identical(out@params$subcluster_results$Lineage$annotations$evidence_status, "needs_review")
})
