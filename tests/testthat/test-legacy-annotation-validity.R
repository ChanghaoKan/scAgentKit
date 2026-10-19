legacy_validity_fixture <- function() {
  counts <- Matrix::Matrix(matrix(1:18, 3, 6, dimnames = list(c("REAL", "OTHER", "G3"), paste0("C", 1:6))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts)
  seu$seurat_clusters <- rep(c("0", "1"), each = 3)
  seu$cell_type <- c("OLD_A", "OLD_B", "OLD_A", "OLD_C", "OLD_D", "OLD_C")
  obj <- AgentSeurat(seu)
  obj@params$markers_filtered <- data.frame(cluster = c("0", "0", "1"), gene = c("REAL", "G3", "OTHER"),
    pct.1 = c(.95, .90, .95), pct.2 = c(.05, .10, .05))
  obj
}

test_that("all-hallucinated raw 0.710 cannot be effectively high or usable", {
  parsed <- list(primary_annotation = "T cell", confidence = "high", annotation_status = "ok",
    supporting_markers = "FORGED", contradicting_markers = character(), recommended_action = "accept",
    hallucinated_markers = "FORGED", hallucination_rate = 1, proportion_assessment = "reasonable")
  markers <- data.frame(gene = c("REAL", "G3"), pct.1 = c(.95, .90), pct.2 = c(.05, .10))
  value <- scAgentKit:::.compute_hybrid_confidence(parsed, markers, data.frame(cell_type = "T cell", score = .85))
  # Retain the independently calculated heuristic, without claiming calibration.
  expect_equal(.3 * .85 + .3 * stats::median(c(.9, .8)) + .2 * 0 + .2 * 1, .710)
  expect_equal(value$score, .710)
  expect_identical(value$raw_confidence_label, "high")
  expect_identical(value$label, "low")
  expect_false(value$label_usable)
  expect_identical(value$evidence_status, "needs_review")
})

test_that("legacy model annotation preserves raw audit but does not report unsupported success", {
  withr::local_options(lifecycle_verbosity = "quiet")
  obj <- legacy_validity_fixture()
  calls <- 0L
  response <- function(...) {
    calls <<- calls + 1L
    '{"primary_annotation":"T cell","confidence":"high","supporting_markers":["FORGED"],"contradicting_markers":[],"alternative_annotations":[],"proportion_assessment":"reasonable","recommended_action":"accept","reasoning":"Offline raw proposal."}'
  }
  out <- suppressWarnings(annot_llm_annotate(obj, chat_fn = response, tissue = "offline fixture", verbose = FALSE, max_retries = 0))
  ann <- out@params$llm_annotations
  expect_identical(calls, 2L) # Gate never causes a retry/model call.
  expect_true(all(c("raw_confidence", "evidence_status", "label_usable", "hybrid_confidence_raw_label") %in% names(ann)))
  expect_true(all(ann$primary_annotation == "T cell"))
  expect_true(all(ann$raw_confidence == "high"))
  expect_true(all(ann$confidence == "low"))
  expect_true(all(ann$hybrid_confidence_label == "low"))
  expect_true(all(!ann$label_usable))
  expect_true(all(ann$evidence_status == "needs_review"))
  expect_false(tail(out@decisions, 1)[[1]]$success)
  expect_length(out@params$llm_annotation_summary$ok_clusters, 0L)
  expect_length(out@params$llm_annotation_summary$schema_ok_clusters, 2L)
  expect_true(length(out@params$llm_annotation_responses) > 0)
  expect_identical(out@data$cell_type, obj@data$cell_type)
})

test_that("legacy application preserves old per-cell labels for blocked proposals and records manual source", {
  withr::local_options(lifecycle_verbosity = "quiet")
  obj <- legacy_validity_fixture()
  obj@params$llm_annotations <- data.frame(cluster = c("0", "1"), primary_annotation = c("Forged", "Foreign support"),
    confidence = "high", annotation_status = "ok", supporting_markers = c("FORGED", "REAL"),
    contradicting_markers = "", recommended_action = "accept")
  out <- suppressWarnings(annot_apply(obj))
  expect_identical(out@data$cell_type, obj@data$cell_type)
  expect_equal(ncol(out@data), ncol(obj@data))
  expect_false(tail(out@decisions, 1)[[1]]$success)
  overridden <- suppressWarnings(annot_apply(obj, manual_overrides = c(`0` = "Author label")))
  expect_identical(unname(overridden@data$cell_type[1:3]), rep("Author label", 3))
  expect_identical(overridden@data$cell_type[4:6], obj@data$cell_type[4:6])
  expect_identical(tail(overridden@decisions, 1)[[1]]$params$annotation_sources[["0"]], "manual_override")
  expect_false(tail(overridden@decisions, 1)[[1]]$params$model_success)
  obj@data$cell_type <- NULL
  fresh <- suppressWarnings(annot_apply(obj))
  expect_identical(unname(fresh@data$cell_type), rep("Unannotated", 6))
})

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

test_that("application accepts saved rescue citations only for the exact current cell and cluster scope", {
  withr::local_options(lifecycle_verbosity = "quiet")
  obj <- legacy_validity_fixture()
  obj@params$llm_annotations <- data.frame(cluster = "0", primary_annotation = "Reviewed lineage",
    annotation_status = "ok", confidence = "high", supporting_markers = "RESCUE", contradicting_markers = "", recommended_action = "accept")
  obj@params$llm_annotation_input_cells <- data.frame(cell_id = colnames(obj@data), cluster = as.character(obj@data$seurat_clusters))
  obj@params$llm_annotation_responses <- list(`0` = list(cluster = "0", marker_evidence = list(citation_genes = "RESCUE")))
  expect_false("RESCUE" %in% obj@params$markers_filtered$gene)
  out <- annot_apply(obj)
  expect_identical(unname(out@data$cell_type[1:3]), rep("Reviewed lineage", 3))
  expect_identical(out@data$cell_type[4:6], obj@data$cell_type[4:6])
  wrong <- obj; wrong@params$llm_annotation_responses[["0"]]$cluster <- "1"
  expect_warning(blocked <- annot_apply(wrong), "needs review")
  expect_identical(blocked@data$cell_type, wrong@data$cell_type)
  moved <- obj; moved@data$seurat_clusters[1] <- "1"
  expect_warning(blocked <- annot_apply(moved), "needs review")
  expect_identical(blocked@data$cell_type, moved@data$cell_type)
  changed <- obj; changed@params$llm_annotation_input_cells$cell_id[1] <- "FOREIGN"
  expect_warning(blocked <- annot_apply(changed), "needs review")
  expect_identical(blocked@data$cell_type, changed@data$cell_type)
})

test_that("grounded accepted counterevidence preserves legacy writeback and manual override behavior", {
  withr::local_options(lifecycle_verbosity="quiet")
  obj <- legacy_validity_fixture()
  obj@params$llm_annotations <- data.frame(cluster="0",primary_annotation="Grounded candidate",
    confidence="high",annotation_status="ok",supporting_markers="REAL",
    contradicting_markers="G3",recommended_action="accept")
  out <- annot_apply(obj)
  expect_identical(unname(out@data$cell_type[1:3]),rep("Grounded candidate",3))
  expect_identical(out@data$cell_type[4:6],obj@data$cell_type[4:6])
  overridden <- annot_apply(obj,manual_overrides=c(`0`="Author label"))
  expect_identical(unname(overridden@data$cell_type[1:3]),rep("Author label",3))
  expect_identical(tail(overridden@decisions,1)[[1]]$params$annotation_sources[["0"]],"manual_override")
})
