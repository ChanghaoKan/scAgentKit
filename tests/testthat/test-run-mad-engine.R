# Authored deterministic software controls test grouping, arithmetic, finite
# operations, and audit integrity. Their labels are not biological QC truth.
mad_engine_fixture <- function(with_empty_group = FALSE, mitochondrial = TRUE) {
  n <- if (with_empty_group) 124L else 120L
  genes <- c(if (mitochondrial) "MT-CO1" else "LiteralGeneMT", "RPS3", "HBA1", paste0("LiteralGene", 4:80))
  cells <- c("001", "1", "NA", "cell space", paste0("mad literal ", 5:n))
  counts <- matrix(0, length(genes), n, dimnames = list(genes, cells))
  for (i in seq_len(120L)) {
    local <- (i - 1L) %% 60L + 1L
    scale <- if (i <= 60L) 1L else 4L
    detected <- 20L + local %% 30L
    counts[seq_len(detected), i] <- (2L + local %% 9L) * scale
    counts[1L, i] <- 1L + local %% 10L
  }
  for (i in c(1L, 61L)) {
    counts[, i] <- 0; counts[1L, i] <- 1L
  }
  for (i in c(2L, 62L)) {
    counts[, i] <- 0; counts[2:3, i] <- 2L
  }
  for (i in c(3L, 63L)) counts[1L, i] <- 1000L
  for (i in c(60L, 120L)) {
    counts[, i] <- 100L; counts[1L, i] <- 1L
  }
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE), min.cells = 0, min.features = 0)
  groups <- c(rep(c("quality A", "quality B"), each = 60L), if (with_empty_group) rep("empty quality group", 4L) else character())
  object$quality_group <- factor(groups, levels = c("quality B", "empty quality group", "quality A", "unused level"))
  object$sample <- rep(c("sample 1", "sample 2"), length.out = n)
  object$capture <- "one physical capture"
  object$donor <- rep(c("donor A", "donor B", "donor C"), length.out = n)
  object$condition <- rep(c("Ca", "Ctrl"), length.out = n)
  object$old_annotation <- factor(rep(c("old label", NA_character_), length.out = n), levels = c("old label", "unused label"))
  context <- list(species = "human", tissue = "synthetic software controls",
    columns = list(qc_group = "quality_group", sample = "sample", capture = "capture", donor = "donor", condition = "condition"))
  supplied <- list(grouping = list(method = "column", column = "quality_group", declared_role = "qc_group",
    source = "Explicit authored quality strata; no capture or donor inference."))
  config <- list(context = context, assay = "RNA", counts_layer = "counts",
    qc_mad = scAgentKit:::.sc_run_mad_options(context, supplied),
    prefilter = scAgentKit:::.sc_run_prefilter_options(if (with_empty_group)
      list(method = "min_counts", min_counts = 1L, preapproved = TRUE,
        source = "Explicitly approved zero-count software-control exclusion before scoring.") else NULL))
  list(object = object, context = context, supplied = supplied, config = config)
}

mad_engine_reference <- function(fixture, prefilter = FALSE) {
  qc <- scAgentKit:::.sc_run_qc_evidence(fixture$object, fixture$context)
  pre <- if (prefilter) scAgentKit:::.sc_run_prefilter_evidence(fixture$object, fixture$config) else NULL
  record <- scAgentKit:::.sc_run_mad_evidence(fixture$object, fixture$config, qc, pre)
  qc$mad_record <- record; qc$summary$mad <- record$summary
  qc$evidence_hash <- scAgentKit:::.sc_run_qc_hash(qc)
  list(record = record, qc = qc, prefilter = pre)
}

mad_engine_proposal <- function(record, preset = "keep_all") {
  list(schema = "scagentkit.qc.mad.v1", rationale = "Explicitly review one finite local preset on its immutable candidate panel.",
    risks = list("Synthetic controls cannot establish biological threshold optimality."),
    preset_id = preset, panel_hash = record$panel_hash)
}




test_that("MAD record preserves original sparse input and typed metadata while quality groups remain independent of captures", {
  f <- mad_engine_fixture(); before <- serialize(f$object, NULL, version = 2L)
  set.seed(191); rng <- .Random.seed
  built <- mad_engine_reference(f); record <- built$record
  expect_identical(.Random.seed, rng)
  expect_identical(serialize(f$object, NULL, version = 2L), before)
  expect_s4_class(SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts"), "sparseMatrix")
  expect_identical(record$cell_ids, colnames(f$object))
  expect_identical(names(record$group_map), colnames(f$object))
  expect_identical(unname(record$group_map), as.character(f$object$quality_group))
  expect_identical(length(record$summary$groups), 2L)
  expect_identical(length(unique(f$object$capture)), 1L)
  expect_identical(vapply(record$summary$groups, `[[`, character(1), "value"), c("quality A", "quality B"))
  expect_identical(record$context_hash, scAgentKit:::.sc_run_hash(f$context))
  expect_identical(record$counts_hash, built$qc$counts_hash)
  expect_identical(record$summary$stage_counts$pre_score_cells, 120L)
  expect_identical(record$summary$method$default_preset_id, "keep_all")
  expect_identical(record$summary$method$high_rna_action, "flag only; no high-count/high-feature deletion")
  expect_true(record$summary$diagnostics$percent_ribo$available)
  expect_true(record$summary$diagnostics$percent_hb$available)
  expect_identical(record$summary$diagnostics$percent_ribo$pattern, "^(RP[SL][0-9]+[ALXY]?[0-9]*|RPSA|RPLP[012]|RPL36AL)$")
  expect_false(grepl(record$summary$diagnostics$percent_hb$pattern, "HBEGF"))
  expect_false(grepl(record$summary$diagnostics$percent_ribo$pattern, "RPS6KA1"))
  aggregate_json <- jsonlite::toJSON(record$summary, auto_unbox = TRUE, null = "null", na = "null")
  expect_false(grepl('"cell_id"|"cell_ids"|mad literal|cell space', aggregate_json))
  expect_silent(scAgentKit:::.sc_run_mad_verify(record))
  checked <- scAgentKit:::.sc_run_mad_validate(mad_engine_proposal(record), built$qc)
  expect_identical(checked$keep_cells, record$cell_ids)
  expect_identical(checked$retention$retained, 120L)
  expect_identical(checked$evidence_hash, built$qc$evidence_hash)
  expect_identical(checked$summary$post_qc_cells, 120L)
  for (id in c("conservative_and3", "low_counts3", "low_features3", "high_mt3", "any_quality3")) {
    check <- scAgentKit:::.sc_run_mad_validate(mad_engine_proposal(record, id), built$qc)
    expect_identical(check$keep_cells, record$selections[[id]])
    expect_identical(check$retention$retained, length(check$keep_cells))
  }
  # These source controls are deliberately high RNA. Quality presets never
  # delete an upper-count/upper-feature flag alone.
  for (cell in colnames(f$object)[c(60L, 120L)]) {
    index <- match(cell, record$flags$cell_id)
    expect_true(record$flags$high_rna_count[index])
    expect_true(cell %in% record$selections$conservative_and3)
    expect_true(cell %in% record$selections$any_quality3)
  }
  path <- tempfile(fileext = ".rds"); on.exit(unlink(path), add = TRUE)
  saveRDS(record, path); restarted <- readRDS(path)
  expect_identical(restarted, record); expect_silent(scAgentKit:::.sc_run_mad_verify(restarted))
})

test_that("prefilter-empty groups retain known zero, while unavailable group quality decisions stay unknown", {
  f <- mad_engine_fixture(with_empty_group = TRUE)
  built <- mad_engine_reference(f, prefilter = TRUE); record <- built$record
  expect_identical(length(record$cell_ids), 124L)
  expect_identical(length(record$prefilter_cells), 120L)
  expect_identical(record$prefilter_hash, built$prefilter$evidence_hash)
  expect_identical(record$summary$stage_counts$original_cells, 124L)
  empty <- Filter(function(group) identical(group$value, "empty quality group"), record$summary$groups)[[1L]]
  expect_identical(empty$before, 4L); expect_identical(empty$pre_score, 0L)
  expect_null(empty$metrics$nCount$exact$lower_raw)
  for (panel in record$summary$presets) {
    projected <- Filter(function(group) identical(group$value, "empty quality group"), panel$groups)[[1L]]
    expect_true(panel$available); expect_identical(projected$retained, 0L)
    expect_identical(projected$fraction_retained, 0)
  }
  keep <- scAgentKit:::.sc_run_mad_validate(mad_engine_proposal(record), built$qc)
  expect_identical(keep$keep_cells, colnames(f$object)[1:120])
  expect_identical(keep$summary$prefilter_removed, 4L)
  # Without the explicit prefilter, the four-cell actual group is insufficient.
  unsupported <- mad_engine_reference(f)$record
  all <- unsupported$summary$presets[[1L]]
  expect_true(all$available); expect_identical(all$retained, 124L)
  for (panel in unsupported$summary$presets[-1L]) {
    expect_false(panel$available); expect_null(panel$retained)
    expect_null(panel$fraction_retained)
    projected <- Filter(function(group) identical(group$value, "empty quality group"), panel$groups)[[1L]]
    expect_null(projected$retained)
  }
})


test_that("distribution warning is deterministic and does not claim majority quality or choose an optimal preset", {
  warn <- scAgentKit:::.sc_run_mad_multimodal_warning(c(seq(1, 2, length.out = 30L), seq(20, 21, length.out = 30L)))
  expect_length(warn, 1L); expect_match(warn, "heuristic.*not proof")
  expect_identical(scAgentKit:::.sc_run_mad_multimodal_warning(rep(1, 60L)), character())
  expect_identical(scAgentKit:::.sc_run_mad_multimodal_warning(1:60), character())
  record <- mad_engine_reference(mad_engine_fixture())$record
  expect_match(paste(record$summary$warnings, collapse = " "), "No preset is universally best")
  expect_match(paste(record$summary$groups[[1L]]$warnings, collapse = " "), "cannot determine whether most cells are poor")
})
