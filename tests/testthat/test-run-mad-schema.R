# Deterministic count fixtures verify policy, fingerprint and selection behavior.
# They are software evidence; sample-specific cutoffs are not biological truth.
mad_schema_fixture <- function(enabled = TRUE, prefilter = FALSE, processed = FALSE) {
  cells <- sprintf("MAD-CELL-LOCAL-%03d", seq_len(120L))
  genes <- c("MT-CO1", "RPL3", "HBB", paste0("MadPrivateGene", 4:100))
  values <- outer(seq_along(genes), seq_along(cells), function(g, cell) {
    detected <- ((g + 3 * cell) %% 80L) < (35L + cell %% 24L)
    as.numeric(detected) * (1 + (g * cell + cell^2) %% 13L)
  })
  values[, 61:120] <- values[, 61:120] * 4
  values[1, ] <- 1 + seq_along(cells) %% 3L
  # Two measured joint low-count/low-feature/high-mitochondrial outliers.
  values[, c(1, 61)] <- 0
  values[1:3, c(1, 61)] <- c(10, 1, 1)
  if (prefilter) values[, c(2, 62)] <- 0
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(genes, cells)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$quality_unit <- factor(rep(c("quality-A", "quality-B"), each = 60L))
  seu$sample_id <- rep(c("sample-A", "sample-B"), each = 60L)
  seu$capture_id <- rep(c("capture-1", "capture-2"), length.out = 120L)
  seu$donor_id <- rep(c("donor-X", "donor-Y", "donor-Z"), length.out = 120L)
  seu$private_note <- "PERSONAL-MAD-METADATA-LOCAL"
  if (processed) {
    SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
    seu$existing_clusters <- rep(c("01", "03"), length.out = 120L)
  }
  context <- scAgentKit:::.sc_run_context(list(species = "human", tissue = "synthetic tissue",
    columns = list(sample = "sample_id", qc_group = "quality_unit", capture = "capture_id", donor = "donor_id"),
    design = list(type = "Synthetic groups crossed with capture and donor", technical_batch = FALSE),
    research_goal = "Verify typed preset and exact cell scope without a provider."), seu)
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    start_stage = if (processed) "processed" else "qc", cluster_column = if (processed) "existing_clusters" else "sc_strategy_clusters",
    processed_reason = if (processed) "Reuse supplied fixture counts, normalization and literal clusters." else NULL)
  baseline <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  qc <- baseline; mad <- pre <- NULL
  if (prefilter) {
    config$prefilter <- scAgentKit:::.sc_run_prefilter_options(list(method = "min_counts", min_counts = 1L,
      source = "Explicitly preapproved synthetic zero-count exclusion", preapproved = TRUE))
    pre <- scAgentKit:::.sc_run_prefilter_evidence(seu, config)
  }
  if (enabled) {
    config$qc_mad <- scAgentKit:::.sc_run_mad_options(context, list(grouping = list(method = "column",
      column = "quality_unit", declared_role = "qc_group", source = "Explicit synthetic quality units distinct from captures and donors")))
    mad <- scAgentKit:::.sc_run_mad_evidence(seu, config, baseline, prefilter_record = pre)
    qc$mad_record <- mad; qc$summary$mad <- mad$summary
    qc$evidence_hash <- scAgentKit:::.sc_run_qc_hash(qc)
  }
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc,
    mad_record = mad, prefilter_record = pre)
  list(seu = seu, counts = counts, context = context, config = config, baseline = baseline,
    qc = qc, mad = mad, prefilter = pre, evidence = evidence)
}

mad_schema_proposal <- function(f, preset = "keep_all", processed = FALSE) {
  list(schema = "scagentkit.strategy.v1", rationale = "Review all quality groups together on measured software evidence.",
    risks = character(), inferences = character(),
    qc = if (processed) NULL else if (is.null(f$mad)) list(schema = "scagentkit.qc.v1",
      rationale = "Explicit positive-count range rule.", risks = character(),
      filters = list(list(op = "range", metric = "nCount", min = 1L))) else
      list(schema = "scagentkit.qc.mad.v1", rationale = "Explicit complete-panel preset choice.",
        risks = character(), preset_id = preset, panel_hash = f$mad$panel_hash),
    analysis = if (processed) NULL else list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 32L, npcs = 8L, seed = 11L), pcs = if (processed) NULL else list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No integration is requested in this software fixture."),
    clustering = if (processed) NULL else list(resolution = .4),
    umap = if (processed) NULL else list(run = FALSE, n_neighbors = 10L))
}

mad_schema_rehash <- function(evidence) {
  evidence$evidence_hash <- scAgentKit:::.sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])
  evidence
}

test_that("explicit qc_group is complete and independent of capture sample and donor", {
  f <- mad_schema_fixture()
  expect_identical(f$context$columns$qc_group, "quality_unit")
  expect_identical(f$evidence$private$roles$qc_group, as.character(f$seu$quality_unit))
  expect_identical(f$evidence$summary$declared_roles$qc_group, "quality_unit")
  expect_identical(f$evidence$summary$role_sizes$qc_group,
    list(list(value = "quality-A", cells = 60L), list(value = "quality-B", cells = 60L)))
  expect_false(identical(f$evidence$private$roles$qc_group, f$evidence$private$roles$capture))
  for (invalid in list(rep(NA_character_, 120L), rep("", 120L), rep(Inf, 120L))) {
    changed <- f$seu; changed$quality_unit <- invalid
    expect_error(scAgentKit:::.sc_run_context(f$context, changed), "finite|nonempty|nonmissing")
  }
  changed <- f$context; changed$columns$qc_group <- "missing_column"
  expect_error(scAgentKit:::.sc_run_context(changed, f$seu), "missing or ambiguous")
  for (role in c("capture", "donor", "condition", "batch"))
    expect_error(scAgentKit:::.sc_run_mad_options(f$context, list(grouping = list(method = "column",
      column = "quality_unit", declared_role = role, source = "No grouping inference"))), "qc_group or sample")
})

test_that("MAD strategy binds a local panel while provider evidence remains aggregate", {
  f <- mad_schema_fixture(prefilter = TRUE); before <- f$seu
  e <- scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc,
    mad_record = f$mad, prefilter_record = f$prefilter)
  expect_identical(f$seu, before)
  expect_identical(e$summary$qc_mad, f$mad$summary)
  expect_identical(e$private$mad_record, f$mad)
  expect_identical(e$private$prefilter_record, f$prefilter)
  expect_identical(e$summary$prefilter, f$prefilter$summary)
  expect_identical(e$summary$qc_mad$stage_counts$pre_score_cells, 118L)
  expect_identical(e$summary$capabilities$qc, "typed_mad_preset")
  expect_identical(e$summary$capabilities$qc_presets,
    c("keep_all", "conservative_and3", "low_counts3", "low_features3", "high_mt3", "any_quality3"))
  prompt <- scAgentKit:::.sc_run_request("strategy", e$summary, f$config)
  expect_match(prompt$user_prompt, "qc_mad|qc.mad")
  expect_false(grepl("MAD-CELL-LOCAL|MadPrivateGene|PERSONAL-MAD|group_map|prefilter_cells|cell_ids|selections", prompt$user_prompt))
  expect_identical(e$evidence_hash, scAgentKit:::.sc_run_hash(e[setdiff(names(e), "evidence_hash")]))
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, f$config, f$qc,
    prefilter_record = f$prefilter), "MAD evidence is missing|changed")
})

test_that("MAD preset execution is the exact prefilter intersection with local policy flags", {
  f <- mad_schema_fixture(prefilter = TRUE)
  p <- mad_schema_proposal(f)
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(v$qc_validated$keep_cells, f$prefilter$keep_cells)
  expect_identical(v$qc_validated$evidence_hash, f$qc$evidence_hash)
  expect_identical(v$applicability$qc_mad$preset_id, "keep_all")
  expect_identical(v$applicability$qc_mad$stage_counts$post_qc_cells, 118L)
  p <- mad_schema_proposal(f, "conservative_and3")
  selected <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_identical(selected$qc_validated$keep_cells, f$mad$selections$conservative_and3)
  expect_true(all(selected$qc_validated$keep_cells %in% f$prefilter$keep_cells))
  expect_lt(length(selected$qc_validated$keep_cells), length(v$qc_validated$keep_cells))
  output <- scAgentKit:::.sc_run_qc_apply(f$seu, selected$qc_validated, f$qc)
  expect_identical(colnames(output), selected$qc_validated$keep_cells)
  expect_identical(output[[]][, names(f$seu[[]]), drop = FALSE],
    f$seu[[]][selected$qc_validated$keep_cells, , drop = FALSE])
  expect_identical(scAgentKit:::.sc_project_layer(output, "RNA", "counts", raw_counts = TRUE),
    scAgentKit:::.sc_project_layer(f$seu, "RNA", "counts", raw_counts = TRUE)[, sort(selected$qc_validated$keep_cells), drop = FALSE])
  changed <- f$seu; changed$quality_unit <- unname(rev(as.character(changed$quality_unit)))
  expect_error(scAgentKit:::.sc_run_qc_apply(changed, selected$qc_validated, f$qc), "grouping metadata changed")
})

test_that("MAD preset and panel affect scientific dependencies while explanatory text does not", {
  f <- mad_schema_fixture(); p <- mad_schema_proposal(f)
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  changed <- v$proposal; changed$rationale <- "New strategy wording."
  changed$qc$rationale <- "New quality-policy wording."; changed$qc$risks <- "New uncertainty wording."
  same <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  expect_identical(v$dependency_hashes, same$dependency_hashes)
  changed$qc$preset_id <- "conservative_and3"
  revised <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  expect_true(all(!vapply(names(v$dependency_hashes), function(key)
    identical(v$dependency_hashes[[key]], revised$dependency_hashes[[key]]), logical(1))))
  changed <- v$proposal; changed$qc$panel_hash <- strrep("0", 64L)
  expect_error(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence), "panel hash|stale")
  for (preset in c("auto_best", "per_sample", "custom_code", "keep_all_then_auto")) {
    changed <- v$proposal; changed$qc$preset_id <- preset
    expect_error(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence), "Unsupported MAD preset")
  }
  changed <- v$proposal; changed$qc$threshold <- 0.5
  expect_error(scAgentKit:::.sc_run_strategy_validate(changed, f$evidence), "supported named fields")
})

test_that("legacy range semantics and fingerprint payload are unchanged without MAD opt-in", {
  f <- mad_schema_fixture(enabled = FALSE)
  old <- digest::digest(list(summary = f$qc$summary, metrics = f$qc$metrics,
    counts_hash = f$qc$counts_hash, cell_hash = f$qc$cell_hash, features_hash = f$qc$features_hash,
    feature_ids = f$qc$feature_ids, group_columns = f$qc$group_columns),
    algo = "sha256", serialize = TRUE, serializeVersion = 2L)
  expect_identical(f$qc$evidence_hash, old)
  expect_false(any(c("qc_mad", "prefilter") %in% names(f$evidence$summary)))
  expect_false(any(c("mad_record", "prefilter_record") %in% names(f$evidence$private)))
  p <- mad_schema_proposal(f)
  legacy <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  p$qc$filters[[1]]$min <- as.numeric(p$qc$filters[[1]]$min)
  expect_identical(legacy, scAgentKit:::.sc_run_strategy_validate(p, f$evidence))
  enabled <- mad_schema_fixture()
  expect_error(scAgentKit:::.sc_run_strategy_validate(mad_schema_proposal(f), enabled$evidence), "requires an explicit.*mad.v1")
  expect_error(scAgentKit:::.sc_run_strategy_validate(mad_schema_proposal(enabled), f$evidence), "explicitly enabled qc_mad")
})

test_that("MAD evidence cannot be detached altered or rebound under a fresh outer hash", {
  f <- mad_schema_fixture(prefilter = TRUE); p <- mad_schema_proposal(f)
  for (location in c("private", "qc", "summary")) {
    e <- f$evidence
    if (location == "private") e$private$mad_record <- NULL
    if (location == "qc") e$qc$mad_record <- NULL
    if (location == "summary") e$summary$qc_mad <- NULL
    e <- mad_schema_rehash(e)
    expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "intact local panel evidence")
  }
  e <- f$evidence; e$private$mad_record$flags$low_count[1] <- !e$private$mad_record$flags$low_count[1]
  e <- mad_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "MAD evidence is missing or changed")
  e <- f$evidence; e$summary$qc_mad$method$k <- 5
  e <- mad_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "summary differs")
  e <- f$evidence; e$private$roles$qc_group <- rev(e$private$roles$qc_group)
  e <- mad_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "Prefilter grouping|MAD QC grouping")
  config <- f$config; config$context$research_goal <- "Changed interpretation context"
  expect_error(scAgentKit:::.sc_run_strategy_evidence(f$seu, config, f$qc,
    mad_record = f$mad, prefilter_record = f$prefilter), "source scope|context or prefilter")
  changed <- f$seu
  counts <- SeuratObject::LayerData(changed, assay = "RNA", layer = "counts")
  counts[4, 5] <- counts[4, 5] + 1
  SeuratObject::LayerData(changed, assay = "RNA", layer = "counts") <- counts
  qc <- scAgentKit:::.sc_run_qc_evidence(changed, f$context)
  qc$mad_record <- f$mad; qc$summary$mad <- f$mad$summary
  qc$evidence_hash <- scAgentKit:::.sc_run_qc_hash(qc)
  expect_error(scAgentKit:::.sc_run_strategy_evidence(changed, f$config, qc,
    mad_record = f$mad, prefilter_record = f$prefilter), "Prefilter evidence options or source scope|MAD evidence source")
})

test_that("MAD and prefilter settings bind calculation scope while disabled hashes retain old fields", {
  f <- mad_schema_fixture(enabled = FALSE)
  fields <- c("context", "assay", "counts_layer", "normalized_layer", "cluster_column", "start_stage")
  expect_identical(scAgentKit:::.sc_run_strategy_scope_config_hash(f$config),
    scAgentKit:::.sc_run_hash(f$config[fields]))
  enabled <- mad_schema_fixture(prefilter = TRUE)
  expected <- c(fields, "prefilter", "qc_mad")
  expect_identical(scAgentKit:::.sc_run_strategy_scope_config_hash(enabled$config),
    scAgentKit:::.sc_run_hash(enabled$config[expected]))
  changed <- enabled$config; changed$qc_mad$grouping$source <- "Changed declaration"
  expect_false(identical(scAgentKit:::.sc_run_strategy_scope_config_hash(enabled$config),
    scAgentKit:::.sc_run_strategy_scope_config_hash(changed)))
})
