make_reference_review_fixture <- function() {
  counts <- matrix(c(2, 1, 0, 1, 2, 3, 1, 0), nrow = 2,
                   dimnames = list(c("G1", "G2"), paste0("C", 1:4)))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  seu$seurat_clusters <- c("0", "0", "1", "1")
  obj <- AgentSeurat(seu)
  obj@params$markers_filtered <- data.frame(
    cluster = c("0", "0", "1", "1"), gene = c("G1", "G2", "G1", "G2"))
  obj@params$reference_matches <- data.frame(
    cluster = c("0", "0", "1"), cell_type = c("T cell", "B cell", "T cell"),
    overlap_count = c(1L, 1L, 1L), celltype_size = c(1L, 2L, 1L),
    score = c(1, 0.5, 1), matched_markers = c("G1", "G2", "G1"))
  obj@params$llm_annotations <- data.frame(
    cluster = c("0", "1"), primary_annotation = c(" t CELL ", "B cell"),
    supporting_markers = c("G1", "G2"), contradicting_markers = c("", "G1"),
    annotation_status = "ok", stringsAsFactors = FALSE)
  obj
}

test_that("offline review keeps cells, inputs and independent label conflicts", {
  obj <- make_reference_review_fixture()
  out <- annot_review_evidence(obj)
  review <- out@params$annotation_evidence_review
  expect_identical(review$review_outcome, c("agreement", "conflict"))
  expect_identical(review$reference_normalized, c("t cell", "t cell"))
  expect_identical(review$llm_normalized, c("t cell", "b cell"))
  expect_true(all(review$review_status == "pending"))
  expect_true(all(is.na(review$reviewed_annotation)))
  expect_identical(colnames(out@data), colnames(obj@data))
  expect_identical(out@data@meta.data, obj@data@meta.data)
  expect_identical(review$llm_contradicting_markers, c("", "G1"))
  expect_identical(out@params$annotation_evidence_review_inputs$reference_candidates,
                   obj@params$reference_matches)
  expect_identical(out@params$annotation_evidence_review_inputs$llm_annotations,
                   obj@params$llm_annotations)
  expect_identical(out@params$annotation_evidence_review_cell_ids$cell_id, colnames(obj@data))
  expect_identical(tail(out@decisions, 1)[[1]]$step, "annot_review_evidence")
  expect_equal(tail(out@decisions, 1)[[1]]$params$n_clusters_reviewed, 2)
})

test_that("label-specific support checks all candidates rather than the highest unrelated score", {
  obj <- make_reference_review_fixture()
  obj@params$llm_annotations$primary_annotation[1] <- "B cell"
  obj@params$llm_annotations$supporting_markers[1] <- "G2"
  out <- annot_review_evidence(obj)
  row <- out@params$annotation_evidence_review[1, ]
  expect_identical(row$review_outcome, "conflict")
  expect_equal(row$reference_score, 1)
  expect_equal(row$llm_reference_score, 0.5)
  expect_true(row$llm_label_in_reference)
  expect_identical(row$llm_reference_supporting_markers, "G2")
})

test_that("ties outside displayed top candidates stay unknown unless explicitly mapped", {
  obj <- make_reference_review_fixture()
  all <- obj@params$reference_matches
  all$score[2] <- 1
  all$cell_type[2] <- "CD4 T cell"
  obj@params$reference_matches_all <- all
  out <- annot_review_evidence(obj)
  row <- out@params$annotation_evidence_review[1, ]
  expect_identical(row$review_outcome, "unknown")
  expect_true(row$reference_ambiguous)
  expect_match(row$unknown_reason, "reference_label_tie")
  expect_identical(row$reference_candidates_scope, "all_scored")
  expect_equal(nrow(out@params$annotation_evidence_review_inputs$reference_candidates), 3)
  mapped <- annot_review_evidence(obj, label_map = c("CD4 T cell" = "T cell"))
  expect_identical(mapped@params$annotation_evidence_review$review_outcome[1], "agreement")
  expect_false(mapped@params$annotation_evidence_review$reference_ambiguous[1])
  expect_identical(mapped@params$annotation_evidence_review_inputs$label_map,
                   c("CD4 T cell" = "T cell"))
})

test_that("missing, failed and unsupported annotations are unknown", {
  obj <- make_reference_review_fixture()
  obj@params$llm_annotations$annotation_status[1] <- "failed"
  obj@params$llm_annotations$primary_annotation[2] <- NA_character_
  out <- annot_review_evidence(obj)
  expect_true(all(out@params$annotation_evidence_review$review_outcome == "unknown"))
  expect_match(out@params$annotation_evidence_review$unknown_reason[1], "llm_annotation_failed")
  expect_match(out@params$annotation_evidence_review$unknown_reason[2], "llm_label_missing")
  obj <- make_reference_review_fixture()
  obj@params$llm_annotations$supporting_markers[1] <- ""
  obj@params$llm_annotations$contradicting_markers[2] <- "NOT_INPUT"
  out <- annot_review_evidence(obj)
  expect_true(all(out@params$annotation_evidence_review$review_outcome == "unknown"))
  expect_match(out@params$annotation_evidence_review$unknown_reason[1], "no_llm_support")
  expect_identical(out@params$annotation_evidence_review$markers_missing[2], "NOT_INPUT")
  obj@params$llm_annotations <- NULL
  expect_true(all(annot_review_evidence(obj)@params$annotation_evidence_review$review_outcome == "unknown"))
})

test_that("saved displayed rescue evidence is admissible and missing DB evidence is preserved", {
  obj <- make_reference_review_fixture()
  obj@params$llm_annotations$supporting_markers[1] <- "RESCUE"
  obj@params$llm_annotation_responses <- list(
    "0" = list(marker_evidence = list(citation_genes = c("G1", "G2", "RESCUE"))))
  out <- annot_review_evidence(obj)
  expect_identical(out@params$annotation_evidence_review$review_outcome[1], "agreement")
  expect_identical(out@params$annotation_evidence_review$markers_missing[1], "")
  obj@params$reference_matches$matched_markers[1] <- "DB_NOT_INPUT"
  out <- annot_review_evidence(obj)
  expect_identical(out@params$annotation_evidence_review$review_outcome[1], "unknown")
  expect_identical(out@params$annotation_evidence_review$reference_markers_missing[1], "DB_NOT_INPUT")
})

test_that("reference load filters tissue/species and records pinned-file provenance", {
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path))
  ref <- data.frame(cell_type = c("T cell", "Mouse T", "Hepatocyte"),
                    marker = c("G1", "G2", "ALB"),
                    tissue = c(" Blood ", "blood", "liver"),
                    species = c(" HUMAN ", "mouse", "human"))
  write.table(ref, path, sep = "\t", row.names = FALSE, quote = FALSE)
  loaded <- annot_load_reference(path, tissue_filter = "blood", species = "human")
  expect_identical(loaded$cell_type, "T cell")
  expect_identical(attr(loaded, "source_path"), normalizePath(path))
  expect_identical(attr(loaded, "source_md5"), unname(tools::md5sum(path)))
  expect_equal(attr(loaded, "n_input_rows"), 3)
  out <- annot_match_reference(make_reference_review_fixture(), loaded)
  expect_identical(out@params$reference_provenance$source_md5, attr(loaded, "source_md5"))
  expect_identical(tail(out@decisions, 1)[[1]]$params$reference_provenance$source_path,
                   normalizePath(path))
  expect_identical(out@params$reference_data, loaded)
})

test_that("empty references and no overlap are safe typed tables and unknown review", {
  obj <- make_reference_review_fixture()
  empty <- data.frame(cell_type = character(), marker = character())
  out <- annot_match_reference(obj, empty)
  expect_s3_class(out@params$reference_matches, "data.frame")
  expect_equal(nrow(out@params$reference_matches), 0)
  expect_equal(nrow(out@params$reference_matches_all), 0)
  expect_true(all(annot_review_evidence(out)@params$annotation_evidence_review$review_outcome == "unknown"))
  ref <- data.frame(cell_type = c("T cell", "B cell"), marker = c("ABSENT1", "ABSENT2"))
  out <- annot_match_reference(obj, ref, top_n_candidates = 1)
  expect_equal(nrow(out@params$reference_matches), 0)
  expect_equal(nrow(out@params$reference_matches_all), 4)
  expect_true(all(out@params$reference_matches_all$score == 0))
})

test_that("reference matching retains all candidates beyond the prompt limit", {
  obj <- make_reference_review_fixture()
  ref <- data.frame(cell_type = c("T cell", "B cell", "NK cell"), marker = "G1")
  out <- annot_match_reference(obj, ref, top_n_candidates = 1)
  expect_equal(nrow(out@params$reference_matches), 2)
  expect_equal(nrow(out@params$reference_matches_all), 6)
  expect_true(all(annot_review_evidence(out)@params$annotation_evidence_review$reference_ambiguous))
})

test_that("malformed reference and review inputs fail explicitly", {
  obj <- make_reference_review_fixture()
  expect_error(annot_match_reference(obj, list()), "data frame")
  expect_error(annot_match_reference(obj, data.frame(cell_type = "T", marker = NA_character_)),
               "non-empty")
  expect_error(annot_match_reference(obj, data.frame(cell_type = "T", marker = "G1"),
                                     top_n_candidates = 0), "positive integer")
  expect_error(annot_review_evidence(obj, label_map = c("T", "B")), "named character")
  expect_error(annot_review_evidence(obj, label_map = c("T" = "T", " t " = "B")), "unique")
  obj@params$llm_annotations <- rbind(obj@params$llm_annotations, obj@params$llm_annotations[1, ])
  expect_error(annot_review_evidence(obj), "at most one")
  obj <- make_reference_review_fixture()
  obj@params$reference_matches$score[1] <- Inf
  expect_error(annot_review_evidence(obj), "finite")
})

test_that("serialized saved evidence replays deterministically without a provider", {
  out <- annot_review_evidence(make_reference_review_fixture(),
                               label_map = c("B cell" = "B lineage"))
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path))
  saveRDS(out, path)
  loaded <- readRDS(path)
  replayed <- annot_review_evidence(
    loaded, label_map = loaded@params$annotation_evidence_review_inputs$label_map)
  expect_identical(replayed@params$annotation_evidence_review,
                   out@params$annotation_evidence_review)
  expect_identical(replayed@params$annotation_evidence_review_cell_ids,
                   out@params$annotation_evidence_review_cell_ids)
  expect_identical(replayed@params$annotation_evidence_review_inputs,
                   out@params$annotation_evidence_review_inputs)
  expect_length(replayed@decisions, length(out@decisions) + 1L)
})

test_that("orphaned saved clusters remain unknown rather than agreeing without cells", {
  obj <- make_reference_review_fixture()
  obj@data$seurat_clusters <- rep("0", ncol(obj@data))
  obj@params$markers_filtered$cluster <- "9"
  obj@params$reference_matches <- obj@params$reference_matches[1, , drop = FALSE]
  obj@params$reference_matches$cluster <- "9"
  obj@params$llm_annotations <- obj@params$llm_annotations[1, , drop = FALSE]
  obj@params$llm_annotations$cluster <- "9"
  out <- annot_review_evidence(obj)
  row <- out@params$annotation_evidence_review[
    out@params$annotation_evidence_review$cluster == "9", ]
  expect_identical(row$review_outcome, "unknown")
  expect_identical(row$unknown_reason, "cluster_not_in_current_data")
  expect_identical(row$alignment_status, "unverified")
  expect_false("9" %in% out@params$annotation_evidence_review_cell_ids$cluster)
  expect_identical(colnames(out@data), colnames(obj@data))
})

test_that("exact initial cell mappings verify both branches and ignore cell order", {
  obj <- make_reference_review_fixture()
  obj <- annot_match_reference(obj, data.frame(cell_type = "T cell", marker = "G1"))
  input <- data.frame(cell_id = colnames(obj@data),
                      cluster = as.character(obj@data$seurat_clusters))
  expect_identical(obj@params$reference_match_input_cells, input)
  expect_identical(tail(obj@decisions, 1)[[1]]$params$reference_match_input_cells, input)
  obj@params$llm_annotation_input_cells <- input
  out <- annot_review_evidence(obj)
  expect_true(all(out@params$annotation_evidence_review$alignment_status == "verified"))
  expect_identical(out@params$annotation_evidence_review$review_outcome, c("agreement", "conflict"))
  obj@data <- obj@data[, rev(colnames(obj@data))]
  reordered <- annot_review_evidence(obj)
  expect_true(all(reordered@params$annotation_evidence_review$alignment_status == "verified"))
  expect_identical(reordered@params$annotation_evidence_review$review_outcome,
                   out@params$annotation_evidence_review$review_outcome)
})

test_that("reclustering and changed cell IDs invalidate cached agreements and replay offline", {
  obj <- make_reference_review_fixture()
  obj <- annot_match_reference(obj, data.frame(cell_type = "T cell", marker = "G1"))
  obj@params$llm_annotation_input_cells <- obj@params$reference_match_input_cells
  original <- obj
  obj@data$seurat_clusters <- c("1", "1", "0", "0")
  out <- annot_review_evidence(obj)
  expect_true(all(out@params$annotation_evidence_review$alignment_status == "mismatch"))
  expect_true(all(out@params$annotation_evidence_review$review_outcome == "unknown"))
  expect_true(all(out@params$annotation_evidence_review$unknown_reason == "input_alignment_mismatch"))
  expect_identical(out@params$annotation_evidence_review_inputs$reference_match_input_cells,
                   original@params$reference_match_input_cells)
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path))
  saveRDS(out, path)
  replayed <- annot_review_evidence(readRDS(path))
  expect_identical(replayed@params$annotation_evidence_review,
                   out@params$annotation_evidence_review)
  expect_identical(replayed@params$annotation_evidence_review_inputs,
                   out@params$annotation_evidence_review_inputs)
  colnames(original@data) <- paste0("NEW", seq_len(ncol(original@data)))
  changed_ids <- annot_review_evidence(original)
  expect_true(all(changed_ids@params$annotation_evidence_review$review_outcome == "unknown"))
  expect_true(all(changed_ids@params$annotation_evidence_review$alignment_status == "mismatch"))
})

test_that("missing branch fingerprints are unverified and malformed fingerprints mismatch", {
  obj <- make_reference_review_fixture()
  legacy <- annot_review_evidence(obj)
  expect_true(all(legacy@params$annotation_evidence_review$alignment_status == "unverified"))
  expect_identical(legacy@params$annotation_evidence_review$review_outcome, c("agreement", "conflict"))
  obj <- annot_match_reference(obj, data.frame(cell_type = "T cell", marker = "G1"))
  partial <- annot_review_evidence(obj)
  expect_true(all(partial@params$annotation_evidence_review$reference_alignment_status == "verified"))
  expect_true(all(partial@params$annotation_evidence_review$llm_alignment_status == "unverified"))
  expect_true(all(partial@params$annotation_evidence_review$alignment_status == "unverified"))
  obj@params$llm_annotation_input_cells <- data.frame(cell_id = c("C1", "C1"), cluster = "0")
  invalid <- annot_review_evidence(obj)
  expect_true(all(invalid@params$annotation_evidence_review$alignment_status == "mismatch"))
  expect_true(all(invalid@params$annotation_evidence_review$review_outcome == "unknown"))
})
