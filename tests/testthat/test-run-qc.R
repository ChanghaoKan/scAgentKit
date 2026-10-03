run_qc_fixture <- function() {
  counts <- Matrix::Matrix(matrix(c(0, 1, 2, 0, 1, 4, 0, 0, 3, 6, 4, 0,
                                   0, 1, 1, 2, 1, 0, 1, 0, 0, 0, 0, 0), nrow = 4,
                                  dimnames = list(c("MT-CO1", "GeneA", "GeneB", "GeneC"),
                                                  c("001", "1", "NA", "cell space", "Ca", "zero"))), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts, assay = "RNA")
  seu$sample_id <- c("sample a", "sample a", "sample a", "sample b", "sample b", "sample b")
  seu$capture_id <- c("cap1", "cap1", "cap2", "cap2", "cap2", "cap2")
  seu$condition <- rep(c("Ca", "Ctrl"), 3)
  seu$private_note <- "never send personal metadata"
  seu$old_annotation <- c("T", "T", "unknown", "B", "B", "unassigned")
  seu
}

run_qc_context <- function() {
  list(species = "human", tissue = "synthetic test", notes = "Known synthetic low count test cells.",
       columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"))
}

run_qc_proposal <- function(filters = list(list(op = "range", metric = "nCount", min = 1))) {
  list(schema = "scagentkit.qc.v1", rationale = "Retain cells with measured counts in this synthetic test.",
       risks = c("Thresholds require biological review."), filters = filters)
}

test_that("run input validates raw matrices without repairing literal IDs or source order", {
  seu <- run_qc_fixture()
  counts <- SeuratObject::LayerData(seu, assay = "RNA", layer = "counts")
  input <- scAgentKit:::.sc_run_input(counts, context = list(species = "human"))
  expect_identical(colnames(input$seu), colnames(counts))
  expect_identical(rownames(input$seu), rownames(counts))
  expect_s4_class(SeuratObject::LayerData(input$seu, layer = "counts"), "sparseMatrix")
  expect_true(input$diagnostics$raw_counts_validated)
  expect_match(paste(input$diagnostics$warnings, collapse = " "), "No sample.*No capture")
  expect_null(input$context$columns$batch)
  expect_error(scAgentKit:::.sc_run_input(log1p(counts)), "integer counts")
  renamed <- counts
  rownames(renamed)[2] <- "Gene_A"
  expect_error(scAgentKit:::.sc_run_input(renamed), "rename")
  duplicated <- counts
  colnames(duplicated)[2] <- colnames(duplicated)[1]
  expect_error(scAgentKit:::.sc_run_input(duplicated), "unique")
  unnamed <- counts
  colnames(unnamed) <- NULL
  expect_error(scAgentKit:::.sc_run_input(unnamed), "unique")
})

test_that("run input rejects normalized layers and split layer ambiguity", {
  seu <- run_qc_fixture()
  SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(SeuratObject::LayerData(seu, layer = "counts"))
  expect_error(scAgentKit:::.sc_run_input(seu, counts_layer = "data"), "normalized")
  expect_error(scAgentKit:::.sc_run_input(seu, counts_layer = "scale.data"), "normalized")
  split <- seu
  split[["RNA"]] <- split(split[["RNA"]], f = split$sample_id)
  expect_error(scAgentKit:::.sc_run_input(split), "Exact layer|Split")
  expect_error(scAgentKit:::.sc_run_input(split, counts_layer = "counts.sample a"), "every object cell|full-cell")
})

test_that("run context validates declarations and does not infer biological batch", {
  seu <- run_qc_fixture()
  before <- seu
  input <- scAgentKit:::.sc_run_input(seu, context = run_qc_context())
  expect_identical(seu, before)
  expect_null(input$context$columns$batch)
  expect_null(input$context$columns$donor)
  context <- run_qc_context()
  context$columns$batch <- "condition"
  expect_match(paste(scAgentKit:::.sc_run_input(seu, context)$diagnostics$warnings, collapse = " "), "batch and condition")
  context$columns$capture <- "missing"
  expect_error(scAgentKit:::.sc_run_input(seu, context), "missing or ambiguous")
  context <- run_qc_context()
  seu$capture_id[1] <- NA
  expect_error(scAgentKit:::.sc_run_input(seu, context), "nonmissing")
  expect_error(scAgentKit:::.sc_run_input(before, list(species = "human", execute = "system()")), "Unsupported context")
  expect_error(scAgentKit:::.sc_run_input(before, list(columns = list(unknown = "condition"))), "Unsupported context column")
})

test_that("local RDS is hashed and processed entry requires evidence and explicit reason", {
  seu <- run_qc_fixture()
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(seu, path)
  input <- scAgentKit:::.sc_run_input(path, run_qc_context())
  expect_identical(input$source$type, "local_rds")
  expect_identical(input$source$rds_sha256, digest::digest(path, file = TRUE, algo = "sha256"))
  expect_error(scAgentKit:::.sc_run_input(seu, start_stage = "processed"), "processed_reason")
  expect_error(scAgentKit:::.sc_run_input(seu, start_stage = "processed", processed_reason = "Already prepared elsewhere."), "Exact layer")
  SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(SeuratObject::LayerData(seu, layer = "counts"))
  seu$seurat_clusters <- rep(c("0", "1"), 3)
  input <- scAgentKit:::.sc_run_input(seu, run_qc_context(), start_stage = "processed", processed_reason = "Externally normalized and clustered on these exact cells.")
  expect_true(input$processed)
  expect_identical(input$seu, seu)
  expect_match(input$diagnostics$processed_reason, "Externally normalized")
  expect_error(scAgentKit:::.sc_run_input(SeuratObject::LayerData(seu, layer = "counts"), start_stage = "processed"), "counts matrix")
})

test_that("QC evidence uses actual sample capture aggregates and keeps per-cell data private", {
  seu <- run_qc_fixture()
  evidence <- scAgentKit:::.sc_run_qc_evidence(seu, run_qc_context())
  expect_identical(evidence$metrics$cell_id, colnames(seu))
  expect_equal(evidence$metrics$nCount, c(3, 5, 13, 4, 2, 0))
  expect_equal(evidence$metrics$nFeature, c(2, 2, 3, 3, 2, 0))
  expect_equal(evidence$metrics$percent_mt[1:5], c(0, 20, 300 / 13, 0, 50))
  expect_true(is.na(evidence$metrics$percent_mt[6]))
  expect_length(evidence$summary$groups, 3)
  expect_equal(vapply(evidence$summary$groups, `[[`, integer(1), "cells"), c(2L, 1L, 3L))
  expect_setequal(evidence$summary$grouping_roles, c("sample", "capture"))
  public <- scAgentKit:::.sc_project_json(evidence$summary)
  expect_false(grepl("cell_id|cell space|private_note|never send|old_annotation|Ctrl", public))
  expect_false("condition" %in% names(evidence$metrics))
  expect_false("donor" %in% names(evidence$metrics))
  expect_identical(evidence$evidence_hash, scAgentKit:::.sc_run_qc_hash(evidence))
})

test_that("unavailable mitochondrial measurements remain explicit rather than fabricated zero", {
  seu <- run_qc_fixture()
  evidence <- scAgentKit:::.sc_run_qc_evidence(seu, list(species = "unknown"))
  expect_false(evidence$summary$mitochondrial$available)
  expect_true(all(is.na(evidence$metrics$percent_mt)))
  expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(list(op = "range", metric = "percent_mt", max = 50))), evidence), "unavailable")
  genes <- seu
  rownames(genes[["RNA"]])[1] <- "GeneMT"
  evidence <- scAgentKit:::.sc_run_qc_evidence(genes, list(species = "human"))
  expect_false(evidence$summary$mitochondrial$available)
  expect_match(evidence$summary$mitochondrial$unavailable_reason, "not zero")
})

test_that("typed QC predicts inclusive global and group retention using literal values", {
  evidence <- scAgentKit:::.sc_run_qc_evidence(run_qc_fixture(), run_qc_context())
  proposal <- run_qc_proposal(list(list(op = "range", metric = "nCount", min = 2, max = 13),
                                 list(op = "range", metric = "nCount", max = 10,
                                      group = list(sample = "sample a", capture = "cap2"))))
  validated <- scAgentKit:::.sc_run_qc_validate(proposal, evidence)
  expect_identical(validated$keep_cells, c("001", "1", "cell space", "Ca"))
  expect_equal(validated$retention$retained, 4)
  expect_equal(validated$retention$removed, 2)
  expect_equal(vapply(validated$retention$groups, `[[`, integer(1), "retained"), c(2L, 0L, 2L))
  expect_identical(validated$proposal$filters[[2]]$group, list(sample = "sample a", capture = "cap2"))
  expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(list(op = "range", metric = "nCount", min = 1, group = list(sample = "hallucinated")))), evidence), "does not match")
  expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(list(op = "range", metric = "nCount", min = 1, group = list(batch = "Ca")))), evidence), "sample/capture")
})

test_that("missing QC cannot drop cells implicitly but explicit measured exclusions are order independent", {
  evidence <- scAgentKit:::.sc_run_qc_evidence(run_qc_fixture(), run_qc_context())
  mt <- list(op = "range", metric = "percent_mt", max = 30)
  counts <- list(op = "range", metric = "nCount", min = 1)
  expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(mt)), evidence), "unavailable")
  one <- scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(mt, counts)), evidence)
  two <- scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(counts, mt)), evidence)
  expect_identical(one$keep_cells, two$keep_cells)
  expect_identical(one$keep_cells, c("001", "1", "NA", "cell space"))
})

test_that("unsupported model operations empty responses and malformed bounds fail closed", {
  evidence <- scAgentKit:::.sc_run_qc_evidence(run_qc_fixture(), run_qc_context())
  expect_error(scAgentKit:::.sc_run_qc_validate(NULL, evidence), "typed object")
  proposal <- run_qc_proposal()
  proposal$code <- "system('false')"
  expect_error(scAgentKit:::.sc_run_qc_validate(proposal, evidence), "arbitrary code")
  proposal <- run_qc_proposal(list())
  expect_error(scAgentKit:::.sc_run_qc_validate(proposal, evidence), "nonempty array")
  bad_filters <- list(list(op = "R", metric = "nCount", min = 1),
                      list(op = "range", metric = "doublet", min = 1),
                      list(op = "range", metric = "nCount", min = .5),
                      list(op = "range", metric = "nCount", min = Inf),
                      list(op = "range", metric = "nCount", min = -1),
                      list(op = "range", metric = "nCount", min = "1"),
                      list(op = "range", metric = "nCount"),
                      list(op = "range", metric = "nCount", min = 10, max = 1),
                      list(op = "range", metric = "percent_mt", max = 101),
                      list(op = "range", metric = "nCount", min = 100),
                      list(op = "range", metric = "nCount", min = 1, genes = "HALLUCINATED"))
  for (filter in bad_filters) expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(list(filter)), evidence))
})

test_that("QC apply operates on a copy with literal cell IDs and historical metadata", {
  seu <- run_qc_fixture()
  before <- seu
  evidence <- scAgentKit:::.sc_run_qc_evidence(seu, run_qc_context())
  validated <- scAgentKit:::.sc_run_qc_validate(run_qc_proposal(), evidence)
  output <- scAgentKit:::.sc_run_qc_apply(seu, validated, evidence)
  expect_identical(seu, before)
  expect_identical(colnames(output), c("001", "1", "NA", "cell space", "Ca"))
  expect_identical(output$old_annotation, seu$old_annotation[1:5])
  expect_identical(output$condition, seu$condition[1:5])
  expect_equal(unname(output$percent.mt), evidence$metrics$percent_mt[1:5])
  expect_s4_class(SeuratObject::LayerData(output, layer = "counts"), "sparseMatrix")
})

test_that("QC apply rejects edited evidence approval counts cell order and grouping metadata", {
  seu <- run_qc_fixture()
  evidence <- scAgentKit:::.sc_run_qc_evidence(seu, run_qc_context())
  validated <- scAgentKit:::.sc_run_qc_validate(run_qc_proposal(), evidence)
  changed <- evidence
  changed$metrics$nCount[1] <- 1000
  expect_error(scAgentKit:::.sc_run_qc_validate(run_qc_proposal(), changed), "evidence.*changed")
  changed <- validated
  changed$keep_cells <- "001"
  expect_error(scAgentKit:::.sc_run_qc_apply(seu, changed, evidence), "result was changed")
  changed <- validated
  changed$evidence_hash <- "old"
  expect_error(scAgentKit:::.sc_run_qc_apply(seu, changed, evidence), "stale approval")
  changed <- seu
  counts <- SeuratObject::LayerData(changed, layer = "counts")
  counts[2, 1] <- 20
  SeuratObject::LayerData(changed, layer = "counts") <- counts
  expect_error(scAgentKit:::.sc_run_qc_apply(changed, validated, evidence), "raw counts changed")
  changed <- seu
  rownames(changed[["RNA"]])[1] <- "OtherMT"
  expect_error(scAgentKit:::.sc_run_qc_apply(changed, validated, evidence), "feature IDs changed")
  reordered <- Seurat::CreateSeuratObject(
    counts = SeuratObject::LayerData(seu, layer = "counts")[, rev(colnames(seu))],
    meta.data = seu[[]][rev(colnames(seu)), , drop = FALSE]
  )
  expect_error(scAgentKit:::.sc_run_qc_apply(reordered, validated, evidence), "IDs or order changed")
  changed <- seu
  changed$capture_id[1] <- "new capture"
  expect_error(scAgentKit:::.sc_run_qc_apply(changed, validated, evidence), "metadata changed")
})
