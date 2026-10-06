qc_preview_fixture <- function(features = c("MT-CO1", "GeneA", "GeneB")) {
  metrics <- data.frame(
    cell_id = c("001", "1", "NA", "cell space", "Ca", "Ctrl", "tail"),
    nCount = c(0, 2, 5, 12, 6, 20, 5), nFeature = c(0, 2, 3, 4, 2, 5, 3),
    percent_mt = c(NA, 5, 25, 1, 40, 10, 2),
    sample = c("sample|a", "sample|a", "sample|a", rep("sample b", 4)),
    capture = c("cap1", "cap1", "cap2", rep("cap2", 4)),
    stringsAsFactors = FALSE)
  evidence <- list(
    summary = list(schema = "scagentkit.qc.evidence.v1", cells = 7L,
      features = length(features), mitochondrial = list(available = TRUE,
        feature_count = 1L, pattern = "^MT-", unavailable_reason = NULL)),
    metrics = metrics, feature_ids = features,
    counts_hash = "fixture-counts", cell_hash = "fixture-cells",
    features_hash = scAgentKit:::.sc_run_qc_preview_cells_hash(features),
    group_columns = list(sample = "source_sample", capture = "source_capture"))
  evidence$evidence_hash <- scAgentKit:::.sc_run_qc_hash(evidence)
  evidence
}

qc_preview_proposal <- function(filters = list(
    list(op = "range", metric = "nCount", min = 3, max = 12),
    list(op = "range", metric = "nFeature", min = 3, max = 4),
    list(op = "range", metric = "percent_mt", max = 20))) {
  list(schema = "scagentkit.qc.v1", rationale = "Explicit synthetic comparison, not optimal thresholds.",
       risks = "Marker expression is not a QC gold standard.", filters = filters)
}

test_that("QC preview preserves exact scope order and overlapping reasons", {
  evidence <- qc_preview_fixture()
  before <- evidence
  preview <- scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence)
  expect_identical(evidence, before)
  expect_identical(preview$schema, "scagentkit.qc.preview.v1")
  expect_identical(preview$keep_cells, c("cell space", "tail"))
  expect_identical(preview$remove_cells, c("001", "1", "NA", "Ca", "Ctrl"))
  expect_identical(preview$metrics$cell_id, evidence$metrics$cell_id)
  expect_equal(preview$retention$retained, 2L)
  expect_equal(vapply(preview$filter_impacts, `[[`, numeric(1), "independently_removed"), c(3, 4, 2))
  expect_identical(preview$filter_impacts[[1]]$low_cells, c("001", "1"))
  expect_identical(preview$filter_impacts[[1]]$high_cells, "Ctrl")
  expect_identical(preview$filter_impacts[[3]]$exclusively_removed_cells, "NA")
  expect_equal(unlist(preview$overlap$counts[[1]]), c(3, 3, 0))
  expect_equal(unlist(preview$overlap$counts[[2]]), c(3, 4, 1))
  expect_equal(unlist(preview$overlap$counts[[3]]), c(0, 1, 2))
  expect_equal(sum(vapply(preview$patterns, `[[`, integer(1), "count")), 7L)
  expect_equal(sum(vapply(preview$patterns, `[[`, numeric(1), "removed")), 5L)
  zero_pattern <- Filter(function(pattern) "001" %in% pattern$cell_ids, preview$patterns)[[1]]
  expect_identical(zero_pattern$filter_ids, c("filter1", "filter2"))
  expect_identical(zero_pattern$reason_ids, c("filter1:low", "filter2:low"))
  expect_identical(zero_pattern$unavailable_filter_ids, "filter3")
  expect_match(preview$overlap$interpretation, "unavailable.*separately")
  expect_identical(preview, scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence))
})

test_that("QC group filters have exact declared sample capture scope", {
  evidence <- qc_preview_fixture()
  proposal <- qc_preview_proposal(list(
    list(op = "range", metric = "nCount", min = 1),
    list(op = "range", metric = "nCount", max = 10,
         group = list(capture = "cap2", sample = "sample b"))))
  preview <- scAgentKit:::.sc_run_qc_preview_build(proposal, evidence)
  expect_identical(preview$filter_impacts[[2]]$scope_cells, c("cell space", "Ca", "Ctrl", "tail"))
  expect_identical(preview$filter_impacts[[2]]$filter$group,
                   list(sample = "sample b", capture = "cap2"))
  expect_identical(preview$keep_cells, c("1", "NA", "Ca", "tail"))
  expect_length(preview$distributions$groups, 3L)
  group <- preview$distributions$groups[[3]]
  expect_identical(group$selector, list(sample = "sample b", capture = "cap2"))
  expect_equal(group$before$cells, 4L)
  expect_equal(group$retained$cells, 2L)
  expect_equal(group$removed$cells, 2L)
  expect_identical(preview$distributions$groups[[1]]$selector$sample, "sample|a")
  expect_false("batch" %in% names(preview$metrics))
})

test_that("QC unavailable measurements never become zero or implicit removal", {
  evidence <- qc_preview_fixture()
  mt_only <- qc_preview_proposal(list(list(op = "range", metric = "percent_mt", max = 20)))
  expect_error(scAgentKit:::.sc_run_qc_preview_build(mt_only, evidence), "unavailable")
  preview <- scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence)
  expect_identical(preview$filter_impacts[[3]]$unavailable_cells, "001")
  expect_identical(preview$unavailable$zero_count_cells, "001")
  expect_true(is.na(preview$metrics$percent_mt[1]))
  global <- preview$distributions$global
  expect_equal(global$before$metrics$percent_mt$measured, 6L)
  expect_equal(global$before$metrics$percent_mt$missing, 1L)
  expect_equal(global$removed$metrics$percent_mt$missing, 1L)
  expect_equal(global$retained$metrics$percent_mt$missing, 0L)
  keep_zero <- qc_preview_proposal(list(list(op = "range", metric = "nCount", min = 0)))
  preview <- scAgentKit:::.sc_run_qc_preview_build(keep_zero, evidence)
  expect_identical(preview$keep_cells, evidence$metrics$cell_id)
  expect_equal(preview$distributions$global$removed$cells, 0L)
  expect_true(is.na(preview$distributions$global$removed$metrics$nCount$median))
  expect_equal(preview$distributions$global$removed$metrics$nCount$measured, 0L)
})

test_that("explicit sensitivity comparisons report exact intersections without optimizing", {
  evidence <- qc_preview_fixture()
  candidate <- qc_preview_proposal(list(list(op = "range", metric = "nCount", min = 1)))
  preview <- scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence,
    sensitivity = list(list(id = "counts only", proposal = candidate)))
  comparison <- preview$sensitivity[[1]]
  expect_identical(comparison$intersection_cells, c("cell space", "tail"))
  expect_identical(comparison$added_cells, c("1", "NA", "Ca", "Ctrl"))
  expect_identical(comparison$removed_from_primary_cells, character())
  expect_equal(comparison$jaccard, 2 / 6)
  expect_equal(comparison$retention$retained, 6L)
  expect_identical(comparison$keep_cell_hash,
    scAgentKit:::.sc_run_qc_preview_cells_hash(evidence$metrics$cell_id[-1]))
  expect_identical(preview$keep_cells, c("cell space", "tail"))
  expect_length(preview$canonical_parameters$sensitivity, 1L)
  expect_false("optimal" %in% names(preview))
  expect_identical(comparison$groups[[3]]$added_cells, c("Ca", "Ctrl"))
  expect_match(paste(preview$interpretation, collapse = " "), "not suggested optimal")
})

test_that("QC preview validates every candidate and fails closed on unsupported input", {
  evidence <- qc_preview_fixture()
  proposal <- qc_preview_proposal()
  candidate <- list(id = "same", proposal = proposal)
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = rep(list(candidate), 7)), "at most six")
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(a = candidate)), "array")
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(candidate, candidate)), "unique")
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(list(id = "primary", proposal = proposal))), "reserved")
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(list(id = "extra", proposal = proposal, code = "stop()"))), "exactly")
  unsupported <- proposal
  unsupported$filters[[1]]$metric <- "hallucinated"
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(list(id = "invalid", proposal = unsupported))), "Unsupported QC metric")
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, evidence,
    sensitivity = list(list(id = "missing", proposal = qc_preview_proposal(
      list(list(op = "range", metric = "percent_mt", max = 20)))))), "unavailable")
  changed <- evidence
  changed$metrics$nCount[2] <- 200
  expect_error(scAgentKit:::.sc_run_qc_preview_build(proposal, changed), "evidence.*changed")
})

test_that("optional gene panels disclose unavailable and unknown features without expression scoring", {
  evidence <- qc_preview_fixture()
  genes <- list(T = c("GeneA", "CD3D"), B = "GeneB")
  preview <- scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence,
                                               gene_panels = genes)
  panel <- preview$unavailable$gene_panels[[1]]
  expect_true(panel$availability_assessed)
  expect_identical(panel$available_genes, "GeneA")
  expect_identical(panel$unavailable_genes, "CD3D")
  expect_identical(panel$unknown_genes, character())
  expect_false(panel$expression_assessed)
  expect_false(any(c("quality_score", "expression", "identity") %in% names(panel)))
  expect_match(panel$interpretation, "not zero expression")
  expect_identical(preview$canonical_parameters$gene_panels, genes)
  unknown <- evidence
  unknown$feature_ids <- NULL
  unknown$evidence_hash <- scAgentKit:::.sc_run_qc_hash(unknown)
  panel <- scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), unknown,
    gene_panels = genes)$unavailable$gene_panels[[1]]
  expect_false(panel$availability_assessed)
  expect_identical(panel$unknown_genes, c("GeneA", "CD3D"))
  expect_identical(panel$unavailable_genes, character())
  changed <- evidence
  changed$feature_ids[1] <- "other"
  changed$evidence_hash <- scAgentKit:::.sc_run_qc_hash(changed)
  expect_error(scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), changed), "feature IDs changed")
  for (panels in list(c("GeneA"), list(c("GeneA")), list(T = c("GeneA", "GeneA")),
                       list(T = NA_character_), list(T = "")))
    expect_error(scAgentKit:::.sc_run_qc_preview_build(qc_preview_proposal(), evidence,
                                                  gene_panels = panels), "gene panel")
})

test_that("QC preview agrees with exact sparse Seurat application and leaves input intact", {
  counts <- Matrix::Matrix(matrix(c(0, 2, 1, 0, 1, 4, 1, 1, 0, 0, 0, 0,
                                   1, 8, 4, 3, 0, 2, 1, 1, 1, 1, 0, 0),
    nrow = 4, dimnames = list(c("MT-CO1", "GeneA", "GeneB", "GeneC"),
                             c("001", "1", "NA", "cell space", "Ca", "Ctrl"))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$sample_id <- c("sample a", "sample a", "sample a", "sample b", "sample b", "sample b")
  seu$old_annotation <- factor(c("prior", NA, "prior", "other", "other", "prior"))
  before <- seu
  evidence <- scAgentKit:::.sc_run_qc_evidence(seu,
    list(species = "human", columns = list(sample = "sample_id")))
  proposal <- qc_preview_proposal(list(list(op = "range", metric = "nCount", min = 3, max = 10),
                                      list(op = "range", metric = "percent_mt", max = 25)))
  preview <- scAgentKit:::.sc_run_qc_preview_build(proposal, evidence)
  validated <- scAgentKit:::.sc_run_qc_validate(preview$canonical_parameters$proposal, evidence)
  output <- scAgentKit:::.sc_run_qc_apply(seu, validated, evidence)
  expect_identical(seu, before)
  expect_identical(preview$keep_cells, colnames(output))
  expect_identical(preview$remove_cells, colnames(seu)[!colnames(seu) %in% colnames(output)])
  expect_identical(output$old_annotation, seu$old_annotation[match(colnames(output), colnames(seu))])
  expect_s4_class(SeuratObject::LayerData(output, layer = "counts"), "sparseMatrix")
  expect_identical(SeuratObject::LayerData(output, layer = "counts"),
    SeuratObject::LayerData(seu, layer = "counts")[, preview$keep_cells, drop = FALSE])
})
