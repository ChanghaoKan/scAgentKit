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

test_that("MAD options require an explicit independent grouping role and finite supported settings", {
  f <- mad_engine_fixture(); options <- scAgentKit:::.sc_run_mad_options
  expect_null(options(list(), NULL)); expect_null(options(list(), FALSE))
  expect_error(options(f$context, TRUE), "supported named fields")
  expect_identical(options(f$context, f$config$qc_mad), f$config$qc_mad)
  expect_identical(f$config$qc_mad$min_group_cells, 30L)
  expect_identical(f$config$qc_mad$mad_constant, 1.4826)
  expect_identical(f$config$qc_mad$k, 3)
  roundtrip <- jsonlite::fromJSON(jsonlite::toJSON(f$config$qc_mad, auto_unbox = TRUE), simplifyVector = FALSE)
  expect_identical(options(f$context, roundtrip), f$config$qc_mad)
  for (field in c("k", "min_group_cells", "mad_constant")) {
    bad <- f$supplied; bad[[field]] <- 2
    expect_error(options(f$context, bad), "supports exactly")
  }
  for (role in c("capture", "donor", "batch", "condition")) {
    bad <- f$supplied; bad$grouping$declared_role <- role
    expect_error(options(f$context, bad), "never inferred")
  }
  bad <- f$supplied; bad$grouping$column <- "capture"
  expect_error(options(f$context, bad), "must match")
  bad <- f$supplied; bad$grouping$source <- " "
  expect_error(options(f$context, bad), "provenance")
  bad <- f$supplied; bad$grouping$declared_role <- NULL
  expect_error(options(f$context, bad), "supported named fields")
  bad <- f$supplied; bad$code <- "subset(object)"
  expect_error(options(f$context, bad), "supported named fields")
  sample <- f$supplied; sample$grouping$column <- "sample"; sample$grouping$declared_role <- "sample"
  expect_identical(options(f$context, sample)$grouping$declared_role, "sample")
  single <- options(list(), list(grouping = list(method = "single", id = "explicit whole input",
    source = "User explicitly declares one quality group; no sample is guessed.")))
  expect_identical(single$grouping$id, "explicit whole input")
})

test_that("MAD arithmetic records log10(x+1), raw mt, scaled constant, exact thresholds and conservative unknowns", {
  opts <- mad_engine_fixture()$config$qc_mad
  metric <- scAgentKit:::.sc_run_mad_metric
  counts <- rep(c(0, 9, 99, 999, 9999), each = 12L)
  result <- metric(counts, "nCount", opts)
  expect_true(result$available)
  expect_identical(result$transform, "log10(x+1)")
  expect_identical(result$exact$median, 2)
  expect_identical(result$exact$mad_raw, 1)
  expect_identical(result$exact$scaled_mad, 1.4826)
  expect_equal(result$exact$lower_transformed, 2 - 3 * 1.4826, tolerance = 0)
  expect_equal(result$exact$upper_raw, 10^(2 + 3 * 1.4826) - 1, tolerance = 0)
  expect_identical(result$display$upper_raw, signif(result$exact$upper_raw, 6L))
  mt <- metric(rep(c(40, 50, 60), each = 20L), "percent_mt", opts)
  expect_true(mt$available); expect_identical(mt$transform, "identity")
  expect_null(mt$exact$lower_raw)
  expect_equal(mt$exact$upper_raw, 50 + 3 * 14.826, tolerance = 1e-13)
  expect_match(mt$tail, "upper deletion")
  for (values in list(rep(100, 60L), 100 + seq(0, 1e-10, length.out = 60L))) {
    zero <- metric(values, "nCount", opts)
    expect_false(zero$available); expect_match(paste(zero$unavailable_reasons, collapse = " "), "zero or near zero")
    expect_null(zero$exact$lower_transformed); expect_null(zero$exact$upper_transformed)
    expect_null(zero$exact$lower_raw); expect_null(zero$exact$upper_raw)
    expect_true(is.finite(zero$exact$median))
  }
  small <- metric(1:29, "nFeature", opts)
  expect_false(small$available); expect_match(paste(small$unavailable_reasons, collapse = " "), "Fewer than 30")
  expect_null(small$exact$lower_raw)
  for (value in c(NA_real_, Inf, -Inf)) {
    missing <- metric(c(1:59, value), "nCount", opts)
    expect_false(missing$available); expect_identical(missing$missing, 1L)
    expect_null(missing$exact$upper_raw)
  }
  invalid <- metric(c(rep(50, 59L), 101), "percent_mt", opts)
  expect_false(invalid$available); expect_match(paste(invalid$unavailable_reasons, collapse = " "), "domain")
  empty <- metric(numeric(), "percent_mt", opts)
  expect_false(empty$available); expect_null(empty$exact$median)
  expect_null(empty$exact$upper_raw)
})

test_that("finite panel treats strict equality, display rounding, high RNA and diagnostic percentages correctly", {
  opts <- mad_engine_fixture()$config$qc_mad
  baseline_mt <- rep(c(40, 50, 60), each = 20L)
  bound <- scAgentKit:::.sc_run_mad_metric(baseline_mt, "percent_mt", opts)$exact$upper_raw
  mt <- c(baseline_mt, bound, bound + 1e-7)
  cells <- paste0("boundary ", seq_along(mt))
  metrics <- data.frame(cell_id = cells, nCount = rep(c(100, 200, 300), length.out = length(mt)),
    nFeature = rep(c(10, 20, 30), length.out = length(mt)), percent_mt = mt,
    percent_ribo = 100, percent_hb = 100, stringsAsFactors = FALSE)
  built <- scAgentKit:::.sc_run_mad_compute(metrics, stats::setNames(rep("same literal", length(cells)), cells), cells, opts)
  expect_false(built$flags$high_mt[61L]); expect_true(built$flags$high_mt[62L])
  exact <- built$groups[[1L]]$metrics$percent_mt$exact$upper_raw
  expect_identical(signif(mt[62L], 6L), signif(exact, 6L))
  expect_identical(built$selections$high_mt3, cells[-62L])
  expect_identical(built$selections$keep_all, cells)
  expect_false(any(c("percent_ribo", "percent_hb", "high_rna_count", "high_rna_feature") %in%
    unlist(lapply(scAgentKit:::.sc_run_mad_presets(), `[[`, "required_metrics"), use.names = FALSE)))
})

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
  expect_identical(record$summary$diagnostics$percent_ribo$pattern, "^RP[SL]")
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

test_that("unavailable mitochondrial genes and MAD zero block required presets without silently discarding cells", {
  f <- mad_engine_fixture(mitochondrial = FALSE); built <- mad_engine_reference(f)
  record <- built$record
  expect_true(all(is.na(record$metrics$percent_mt)))
  expect_true(all(is.na(record$flags$high_mt)))
  expect_identical(record$selections$keep_all, record$cell_ids)
  expect_null(record$selections$conservative_and3)
  expect_null(record$selections$high_mt3)
  expect_null(record$selections$any_quality3)
  expect_true(is.character(record$selections$low_counts3))
  expect_error(scAgentKit:::.sc_run_mad_validate(mad_engine_proposal(record, "conservative_and3"), built$qc), "unavailable")
  counts <- SeuratObject::LayerData(f$object, assay = "RNA", layer = "counts")
  rownames(counts)[2:3] <- c("LiteralRibo", "LiteralHb")
  object <- Seurat::CreateSeuratObject(counts, min.cells = 0, min.features = 0)
  object$quality_group <- f$object$quality_group; object$sample <- f$object$sample
  object$capture <- f$object$capture; object$donor <- f$object$donor; object$condition <- f$object$condition
  f$object <- object; missing <- mad_engine_reference(f)$record
  expect_true(all(is.na(missing$metrics$percent_ribo)))
  expect_true(all(is.na(missing$metrics$percent_hb)))
  expect_false(missing$summary$diagnostics$percent_ribo$available)
  expect_false(missing$summary$diagnostics$percent_hb$available)
  constant <- data.frame(cell_id = paste0("constant", 1:60), nCount = 100,
    nFeature = 10, percent_mt = 0, percent_ribo = NA_real_, percent_hb = NA_real_)
  computed <- scAgentKit:::.sc_run_mad_compute(constant,
    stats::setNames(rep("constant sample", 60L), constant$cell_id), constant$cell_id, f$config$qc_mad)
  expect_identical(computed$selections$keep_all, constant$cell_id)
  expect_true(all(vapply(computed$presets[-1L], function(row) is.null(row$retained), logical(1))))
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

test_that("panel approval rejects hallucinations, stale bindings and internally inconsistent rehashed flags", {
  f <- mad_engine_fixture(); built <- mad_engine_reference(f); record <- built$record
  validate <- scAgentKit:::.sc_run_mad_validate
  for (field in c("code", "filters", "genes", "threshold", "integration")) {
    proposal <- mad_engine_proposal(record); proposal[[field]] <- "unsupported"
    expect_error(validate(proposal, built$qc), "supported named fields")
  }
  proposal <- mad_engine_proposal(record, "optimize_retention")
  expect_error(validate(proposal, built$qc), "Unsupported MAD preset")
  proposal <- mad_engine_proposal(record); proposal$panel_hash <- paste(rep("0", 64L), collapse = "")
  expect_error(validate(proposal, built$qc), "stale approval")
  proposal <- mad_engine_proposal(record); proposal$risks <- list(code = "named array")
  expect_error(validate(proposal, built$qc), "unnamed text array")
  tampered <- record; tampered$flags$low_count[1L] <- !tampered$flags$low_count[1L]
  expect_error(scAgentKit:::.sc_run_mad_verify(tampered), "changed")
  tampered$flags_hash <- scAgentKit:::.sc_run_hash(tampered$flags)
  tampered$panel_hash <- scAgentKit:::.sc_run_mad_panel_hash(tampered)
  tampered$summary$panel_hash <- tampered$panel_hash
  tampered$evidence_hash <- scAgentKit:::.sc_run_mad_hash(tampered)
  expect_error(scAgentKit:::.sc_run_mad_verify(tampered), "exact thresholds, flags")
  qc <- built$qc; qc$metrics$nCount[1L] <- qc$metrics$nCount[1L] + 1
  qc$evidence_hash <- scAgentKit:::.sc_run_qc_hash(qc)
  expect_error(validate(mad_engine_proposal(record), qc), "different or changed")
  bad <- f$object; bad$quality_group[1L] <- NA
  expect_error(scAgentKit:::.sc_run_mad_groups(bad, f$config$qc_mad, colnames(bad)), "nonmissing")
  duplicated <- record; duplicated$cell_ids[2L] <- duplicated$cell_ids[1L]
  duplicated$evidence_hash <- scAgentKit:::.sc_run_mad_hash(duplicated)
  expect_error(scAgentKit:::.sc_run_mad_verify(duplicated), "unique")
})
