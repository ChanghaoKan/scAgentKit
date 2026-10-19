mito_mapping_fixture <- function(mouse = FALSE, mapping = TRUE) {
  features <- paste0(if (mouse) "ENSMUSG" else "ENSG", sprintf("%011d", 1:4))
  counts <- matrix(rep(c(3, 2, 4, 1), 25), nrow = 4,
    dimnames = list(features, paste0("private-cell-", 1:25)))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  if (mapping) {
    metadata <- data.frame(sc_feature_name = if (mouse) c("mt-Co1", "mt-Nd1", "Cd3d", "Actb") else
      c("MT-CO1", "MT-ND1", "CD3D", "ACTB"), row.names = features)
    seu[["RNA"]] <- SeuratObject::AddMetaData(seu[["RNA"]], metadata)
  }
  seu
}

test_that("human and mouse Ensembl QC uses existing feature annotation exactly", {
  for (mouse in c(FALSE, TRUE)) {
    seu <- mito_mapping_fixture(mouse)
    before <- .sc_run_hash(seu)
    context <- list(species = if (mouse) "mouse" else "human")
    evidence <- .sc_run_qc_evidence(seu, context)
    expect_true(evidence$summary$mitochondrial$available)
    expect_identical(evidence$summary$mitochondrial$feature_count, 2L)
    expect_identical(evidence$summary$mitochondrial$mapping_source, "feature_metadata:sc_feature_name")
    expect_equal(evidence$metrics$percent_mt, rep(50, 25))
    expect_identical(.sc_run_hash(seu), before)
    expect_identical(evidence$feature_ids, rownames(seu))
  }
})

test_that("missing, partial, ambiguous and species-conflicting mappings never fabricate zero", {
  for (mode in c("missing", "partial", "ambiguous", "species")) {
    seu <- mito_mapping_fixture(mapping = mode != "missing")
    metadata <- seu[["RNA"]][[]]
    if (mode == "partial") metadata$sc_feature_name[[1L]] <- NA_character_
    if (mode == "ambiguous") metadata$gene_symbol <- rep("ACTB", 4)
    seu[["RNA"]] <- SeuratObject::AddMetaData(seu[["RNA"]], metadata)
    evidence <- .sc_run_qc_evidence(seu, list(species = if (mode == "species") "mouse" else "human"))
    expect_false(evidence$summary$mitochondrial$available)
    expect_match(evidence$summary$mitochondrial$unavailable_reason, "unavailable, not zero")
    expect_true(all(is.na(evidence$metrics$percent_mt)))
    rule <- list(schema = "scagentkit.qc.v1", rationale = "Negative software control", risks = list(),
      filters = list(list(op = "range", metric = "percent_mt", max = 20)))
    expect_error(.sc_run_qc_validate(rule, evidence), "unavailable")
  }
})
