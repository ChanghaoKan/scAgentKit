# Authored count/design/PCA fixtures verify typed policy and cache boundaries.
# These tests do not invoke Harmony or establish biological integration quality.
harmony_schema_fixture <- function(processed = FALSE, confounded_after_qc = FALSE) {
  cells <- sprintf("HARMONY-LOCAL-CELL-%03d", seq_len(120L))
  genes <- c("MT-CO1", paste0("HarmonyPrivateGene", 2:100))
  values <- outer(seq_along(genes), seq_along(cells), function(g, cell)
    1 + (g * cell + g^2 + cell^2) %% 9L)
  batch <- rep(c("batch-A", "batch-B"), each = 60L)
  treatment <- rep(rep(c("Ctrl", "Case"), each = 30L), 2L)
  if (confounded_after_qc) {
    excluded <- (batch == "batch-A" & treatment == "Case") |
      (batch == "batch-B" & treatment == "Ctrl")
    values[, excluded] <- values[, excluded] + 1000
  }
  counts <- Matrix::Matrix(values, sparse = TRUE)
  dimnames(counts) <- list(genes, cells)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$technical_id <- batch; seu$biological_id <- treatment
  seu$sample_id <- rep(c("sample-A", "sample-B", "sample-C", "sample-D"), length.out = 120L)
  seu$donor_id <- rep(c("donor-1", "donor-2", "donor-3"), length.out = 120L)
  seu$private_note <- "PERSONAL-HARMONY-METADATA-LOCAL"
  if (processed) {
    SeuratObject::LayerData(seu, assay = "RNA", layer = "data") <- log1p(counts)
    seu$existing_clusters <- rep(c("01", "03"), length.out = 120L)
  }
  context <- scAgentKit:::.sc_run_context(list(species = "human", tissue = "synthetic tissue",
    columns = list(sample = "sample_id", donor = "donor_id", batch = "technical_id", treatment = "biological_id"),
    design = list(type = "Declared synthetic crossed technical/treatment software fixture", technical_batch = TRUE),
    research_goal = "Verify typed corrections and exact cached PCA without biological performance claims."), seu)
  config <- list(context = context, assay = "RNA", counts_layer = "counts", normalized_layer = "data",
    start_stage = if (processed) "processed" else "qc", cluster_column = if (processed) "existing_clusters" else "sc_strategy_clusters",
    processed_reason = if (processed) "Reuse supplied fixture normalization and literal clusters." else NULL)
  qc <- scAgentKit:::.sc_run_qc_evidence(seu, context)
  evidence <- scAgentKit:::.sc_run_strategy_evidence(seu, config, qc)
  list(seu = seu, counts = counts, context = context, config = config, qc = qc, evidence = evidence)
}

harmony_schema_proposal <- function(processed = FALSE, method = "none") {
  batch <- if (method == "harmony") list(method = "harmony", group_by_vars = "technical_id",
    theta = 2, lambda = 1, sigma = .1, max_iter = 5L, nclust = 6L,
    reason = "Explicit synthetic technical embedding correction for software validation only.") else
    list(method = method, reason = "Explicit reviewed software fixture batch decision.")
  list(schema = "scagentkit.strategy.v1", rationale = "Review technical design and PC policy together.",
    risks = character(), inferences = character(),
    qc = if (processed) NULL else list(schema = "scagentkit.qc.v1", rationale = "Explicit measured positive-count rule.",
      risks = character(), filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = if (processed) NULL else list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 32L, npcs = 8L, seed = 11L),
    pcs = if (processed) NULL else list(method = "fixed", ndim = 5L), batch = batch,
    clustering = if (processed) NULL else list(resolution = .4),
    umap = if (processed) NULL else list(run = FALSE, n_neighbors = 10L))
}

harmony_schema_rehash <- function(evidence) {
  evidence$evidence_hash <- scAgentKit:::.sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])
  evidence
}

harmony_schema_changes <- function(before, after) {
  names(before)[!vapply(names(before), function(key) identical(before[[key]], after[[key]]), logical(1))]
}

harmony_schema_cached_basis <- function(root, f, validated) {
  basis <- f$seu
  dimensions <- validated$proposal$analysis$npcs
  # Explicit synthetic positive variances and embeddings; no PCA was fitted.
  embeddings <- outer(seq_len(ncol(basis)), seq_len(dimensions), function(cell, pc)
    sin(cell * pc / 17) + cos(cell / (pc + 1)))
  dimnames(embeddings) <- list(colnames(basis), paste0("PC_", seq_len(dimensions)))
  basis[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = embeddings,
    stdev = sqrt(rev(seq_len(dimensions))), assay = "RNA", key = "PC_")
  plan <- validated$proposal; plan$batch <- list(method = "none", reason = "No correction while reading authored PCA evidence.")
  measured <- scAgentKit:::.sc_run_strategy_pca_evidence(basis,
    scAgentKit:::.sc_run_strategy_runtime_settings(plan), select = FALSE)
  basis@misc$strategy_execution <- list(schema = "scagentkit.strategy-execution.v1", basis = list(
    dependency_hash = validated$dependency_hashes$basis, parameters = validated$proposal$analysis, pca = measured))
  state <- list(config = f$config, files = list())
  state <- scAgentKit:::.sc_run_put(root, state, "strategy_basis", basis)
  list(state = state, basis = basis, measured = measured)
}

test_that("explicit treatment roles contribute facts and biological design audits", {
  f <- harmony_schema_fixture()
  expect_identical(f$context$columns$treatment, "biological_id")
  expect_identical(f$evidence$private$roles$treatment, unname(f$seu$biological_id))
  expect_identical(f$evidence$summary$batch_group_audit$group_role, "treatment")
  expect_true(f$evidence$summary$batch_group_audit$full_rank)
  expect_identical(f$evidence$summary$capabilities$batch, c("none", "manual", "harmony"))
  expect_false("harmony_execution" %in% f$evidence$summary$capabilities$unsupported)
  prompt <- scAgentKit:::.sc_run_request("strategy", f$evidence$summary, f$config)
  expect_false(grepl("HARMONY-LOCAL-CELL|HarmonyPrivateGene|PERSONAL-HARMONY|donor-[123]", prompt$user_prompt))
  changed <- f$seu; changed$biological_id <- rep(NA_character_, 120L)
  expect_error(scAgentKit:::.sc_run_context(f$context, changed), "finite|nonmissing")
})

test_that("none and manual keep the existing canonical methods and scientific hash payload", {
  f <- harmony_schema_fixture()
  for (method in c("none", "manual")) {
    v <- scAgentKit:::.sc_run_strategy_validate(harmony_schema_proposal(method = method), f$evidence)
    expect_identical(v$proposal$batch, harmony_schema_proposal(method = method)$batch)
    expect_identical(v$dependency_hashes$batch,
      scAgentKit:::.sc_run_hash(list(pcs = v$dependency_hashes$pcs, method = method)))
    expect_identical(v$executable, method == "none")
    expect_false("harmony" %in% names(v))
    if (method == "manual") expect_identical(v$blockers[[1]]$code, "manual_required")
  }
})

test_that("Harmony requires exact explicit fields and eligible retained design without package gating", {
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal(method = "harmony")
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_true(v$executable)
  expect_identical(v$proposal$batch$group_by_vars, "technical_id")
  expect_identical(v$harmony$audit$status, "reviewed_design_supported")
  expect_identical(v$applicability$harmony$selected_roles, "batch")
  expect_true(v$applicability$harmony$joint_rank$full_rank)
  e <- f$evidence; e$summary$dependencies$harmony <- list(available = FALSE, version = NULL, strategy_supported = TRUE)
  e <- harmony_schema_rehash(e)
  missing <- scAgentKit:::.sc_run_strategy_validate(p, e)
  expect_true(missing$executable)
  expect_identical(v$dependency_hashes, missing$dependency_hashes)
  for (field in setdiff(names(p$batch), c("method", "reason"))) {
    bad <- p; bad$batch[[field]] <- NULL
    expect_error(scAgentKit:::.sc_run_strategy_validate(bad, f$evidence), "supported named fields")
  }
  for (field in c("code", "cells", "reduction_use", "auto_select", "drop_samples")) {
    bad <- p; bad$batch[[field]] <- "arbitrary operation"
    expect_error(scAgentKit:::.sc_run_strategy_validate(bad, f$evidence), "supported named fields")
  }
  bad <- p; bad$batch$group_by_vars <- "biological_id"
  expect_error(scAgentKit:::.sc_run_strategy_validate(bad, f$evidence), "treatment|cannot directly correct")
  e <- f$evidence; e$summary$declared_roles$sample <- "technical_id"
  e <- harmony_schema_rehash(e)
  expect_error(scAgentKit:::.sc_run_strategy_validate(p, e), "map uniquely")
})

test_that("Harmony design blockers use the post-QC cohort and retain explicit provenance", {
  f <- harmony_schema_fixture(confounded_after_qc = TRUE)
  p <- harmony_schema_proposal(method = "harmony")
  expect_true(scAgentKit:::.sc_run_strategy_validate(p, f$evidence)$executable)
  p$qc$filters[[1]]$max <- 10000
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  expect_false(v$executable)
  expect_equal(v$applicability$retained_cells, 60L)
  expect_true("factor_biology_confounded" %in% vapply(v$blockers, `[[`, character(1), "code"))
  expect_false(v$applicability$harmony$joint_rank$full_rank)
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal(method = "harmony")
  e <- f$evidence; e$summary$background_facts$design$technical_batch <- FALSE
  e <- harmony_schema_rehash(e)
  blocked <- scAgentKit:::.sc_run_strategy_validate(p, e)
  expect_false(blocked$executable)
  expect_true("technical_provenance_missing" %in% vapply(blocked$blockers, `[[`, character(1), "code"))
  f <- harmony_schema_fixture(processed = TRUE)
  processed <- scAgentKit:::.sc_run_strategy_validate(harmony_schema_proposal(TRUE, "harmony"), f$evidence)
  expect_false(processed$executable)
  expect_true("processed_harmony_unsupported" %in% vapply(processed$blockers, `[[`, character(1), "code"))
  expect_null(processed$qc_validated)
})

test_that("the top50 PC policy is finite and leaves raw PCA dependencies reusable", {
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal()
  old <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  for (threshold in c(.80, .85)) {
    changed <- p; changed$pcs <- list(method = "computed_top50", threshold = threshold)
    v <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
    expect_identical(v$proposal$pcs, changed$pcs)
    expect_identical(v$dependency_hashes$basis, old$dependency_hashes$basis)
    expect_identical(harmony_schema_changes(old$dependency_hashes, v$dependency_hashes),
      c("pcs", "batch", "neighbors", "clustering", "umap"))
  }
  for (threshold in c(.79999999, .80000001, .84, .9, 0, 1, NA_real_, Inf)) {
    bad <- p; bad$pcs <- list(method = "computed_top50", threshold = threshold)
    expect_error(scAgentKit:::.sc_run_strategy_validate(bad, f$evidence), "threshold|Invalid")
  }
  bad <- p; bad$pcs <- list(method = "computed_top50", threshold = .80, ndim = 3L)
  expect_error(scAgentKit:::.sc_run_strategy_validate(bad, f$evidence), "supported named fields")
  legacy <- p; legacy$pcs <- list(method = "computed_variance", threshold = .84)
  expect_identical(scAgentKit:::.sc_run_strategy_validate(legacy, f$evidence)$proposal$pcs, legacy$pcs)
})

test_that("Harmony fingerprints bind scientific parameters metadata and design but exclude reasons", {
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal(method = "harmony")
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  reason <- p; reason$batch$reason <- "Revised explanation; same scientific correction."
  expect_identical(scAgentKit:::.sc_run_strategy_validate(reason, f$evidence)$dependency_hashes, v$dependency_hashes)
  for (field in c("theta", "lambda", "sigma", "max_iter", "nclust")) {
    changed <- p; changed$batch[[field]] <- if (field == "sigma") .2 else p$batch[[field]] + 1
    after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
    expect_identical(harmony_schema_changes(v$dependency_hashes, after), c("batch", "neighbors", "clustering", "umap"))
  }
  e <- f$evidence; e$private$roles$donor <- rev(e$private$roles$donor); e <- harmony_schema_rehash(e)
  after <- scAgentKit:::.sc_run_strategy_validate(p, e)$dependency_hashes
  expect_identical(harmony_schema_changes(v$dependency_hashes, after), c("batch", "neighbors", "clustering", "umap"))
  e <- f$evidence; e$summary$background_facts$design$notes <- "Added reviewed technical provenance."
  e <- harmony_schema_rehash(e)
  after <- scAgentKit:::.sc_run_strategy_validate(p, e)$dependency_hashes
  expect_identical(harmony_schema_changes(v$dependency_hashes, after), c("batch", "neighbors", "clustering", "umap"))
  changed <- p; changed$clustering$resolution <- .6
  after <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)$dependency_hashes
  expect_identical(harmony_schema_changes(v$dependency_hashes, after), "clustering")
})

test_that("PC review distinguishes a not-yet-computed rule from a bound authored PCA cache", {
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal()
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  root <- tempfile("harmony-schema-pc-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  empty <- list(config = f$config, files = list())
  pending <- scAgentKit:::.sc_run_strategy_pc_review(root, empty, v, f$evidence)
  expect_identical(pending$status, "pending_computation")
  expect_identical(pending$policy, p$pcs)
  expect_false(any(c("actual", "artifact", "available_pcs", "ndim") %in% names(pending)))
  cached <- harmony_schema_cached_basis(root, f, v)
  actual <- scAgentKit:::.sc_run_strategy_pc_review(root, cached$state, v, f$evidence)
  expect_identical(actual$status, "computed")
  expect_identical(actual$actual, cached$measured)
  expect_identical(actual$artifact, cached$state$files$strategy_basis)
  expect_identical(actual$basis_dependency_hash, v$dependency_hashes$basis)
  expect_true(actual$actual$top50_candidates$shortfall)
  expect_identical(actual$actual$top50_candidates$reference_pcs, 8L)
  changed <- p; changed$pcs <- list(method = "computed_top50", threshold = .85)
  revised <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  second <- scAgentKit:::.sc_run_strategy_pc_review(root, cached$state, revised, f$evidence)
  expect_identical(second$actual, actual$actual)
  expect_identical(second$artifact, actual$artifact)
  manual <- p; manual$batch$method <- "manual"
  blocked <- scAgentKit:::.sc_run_strategy_validate(manual, f$evidence)
  expect_identical(scAgentKit:::.sc_run_strategy_pc_review(root, cached$state, blocked, f$evidence)$actual, actual$actual)
  basis <- cached$basis; basis@misc$strategy_execution$basis$dependency_hash <- strrep("0", 64L)
  wrong <- scAgentKit:::.sc_run_put(root, cached$state, "strategy_basis", basis)
  expect_error(scAgentKit:::.sc_run_strategy_pc_review(root, wrong, v, f$evidence), "dependency fingerprint")
  path <- file.path(root, cached$state$files$strategy_basis$path)
  saveRDS(list(tampered = TRUE), path)
  expect_error(scAgentKit:::.sc_run_strategy_pc_review(root, cached$state, v, f$evidence), "artifact changed")
})

test_that("a cached Harmony review binds its corrected artifact and exact PCA producer", {
  f <- harmony_schema_fixture(); p <- harmony_schema_proposal(method = "harmony")
  v <- scAgentKit:::.sc_run_strategy_validate(p, f$evidence)
  root <- tempfile("harmony-schema-cache-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cached <- harmony_schema_cached_basis(root, f, v)
  corrected <- cached$basis
  corrected@misc$strategy_execution$batch <- list(dependency_hash = v$dependency_hashes$batch,
    basis_sha256 = cached$state$files$strategy_basis$sha256)
  state <- scAgentKit:::.sc_run_put(root, cached$state, "strategy_batch", corrected)
  bound <- scAgentKit:::.sc_run_strategy_batch_review(root, state, v, f$evidence)
  expect_identical(bound$artifact, state$files$strategy_batch)
  expect_identical(bound$dependency_hash, v$dependency_hashes$batch)
  expect_identical(bound$basis_sha256, state$files$strategy_basis$sha256)
  changed <- p; changed$batch$reason <- "Different explanation; same correction."
  reason <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  expect_identical(scAgentKit:::.sc_run_strategy_batch_review(root, state, reason, f$evidence), bound)
  changed$batch$theta <- 3
  parameter <- scAgentKit:::.sc_run_strategy_validate(changed, f$evidence)
  expect_error(scAgentKit:::.sc_run_strategy_batch_review(root, state, parameter, f$evidence), "dependency fingerprint")
  corrected@misc$strategy_execution$batch$basis_sha256 <- strrep("0", 64L)
  wrong <- scAgentKit:::.sc_run_put(root, state, "strategy_batch", corrected)
  expect_error(scAgentKit:::.sc_run_strategy_batch_review(root, wrong, v, f$evidence), "basis|fingerprint")
})
