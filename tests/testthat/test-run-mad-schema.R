# Deterministic count fixtures verify policy, fingerprint and selection behavior.
# They are software evidence; sample-specific cutoffs are not biological truth.

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
