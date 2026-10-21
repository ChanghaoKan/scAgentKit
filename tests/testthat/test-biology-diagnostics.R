test_that("diagnostic switches are bounded and marker eligibility is deterministic", {
  options <- .sc_run_biology_options(TRUE)
  expect_true(options$diagnostic_only)
  expect_identical(options$relaxation_support, 3L)
  expect_null(.sc_run_biology_options(FALSE))
  expect_error(.sc_run_biology_options(list(seed = 9)), "switches")
  expect_error(.sc_run_biology_options(list(cluster_qc = "yes")), "TRUE")
  markers <- data.frame(cluster = "0", gene = c("CD3D", "CD3E", "TRAC", "MT-CO1", "FOS"),
    avg_log2FC = 5:1, pct.1 = .8, pct.2 = .1, p_val_adj = .001)
  policy <- .sc_run_biology_exclusions("human", markers$gene)
  result <- .sc_run_biology_marker_support(markers, "0", policy)
  expect_true(result$eligible)
  expect_identical(result$support_count, 3L)
  markers$p_val_adj[1] <- .05
  expect_false(.sc_run_biology_marker_support(markers, "0", policy)$eligible)
  markers$p_val_adj[1] <- .001; markers$pct.2[1] <- .9
  expect_false(.sc_run_biology_marker_support(markers, "0", policy)$eligible)
  markers$pct.2[1] <- .1
  unresolved <- .sc_run_biology_exclusions("human", c(markers$gene, "ENSG000001"))
  expect_false(.sc_run_biology_marker_support(markers, "0", unresolved)$eligible)
  expect_false(.sc_run_biology_exclusions(NULL, markers$gene)$symbol_mapping_verified)
  expect_false(.sc_run_biology_marker_support(data.frame(), "0", policy)$eligible)
})

test_that("diagnostic MAD preserves unavailable metrics rather than inventing thresholds", {
  options <- .sc_run_biology_options(TRUE)
  metrics <- data.frame(nCount = seq_len(60), nFeature = seq_len(60), percent_mt = NA_real_)
  record <- .sc_run_biology_thresholds(metrics, rep("0", 60), options)
  expect_false(record[[1]]$metrics[[3]]$available)
  expect_null(record[[1]]$metrics[[3]]$max)
  result <- .sc_run_biology_threshold_keep(metrics, rep("0", 60), record)
  expect_false(anyNA(result$keep))
  small <- .sc_run_biology_thresholds(metrics[1:5, ], rep("0", 5), options)
  expect_false(any(vapply(small[[1]]$metrics, `[[`, logical(1), "available")))
  expect_true(all(.sc_run_biology_threshold_keep(metrics[1:5, ], rep("0", 5), small)$keep))
})

test_that("public diagnostic computation preserves input and caller RNG", {
  data("pbmc_small", package = "SeuratObject")
  object <- pbmc_small
  config <- list(assay = "RNA", counts_layer = "counts",
    context = list(species = "human", tissue = "blood"),
    biological_diagnostics = .sc_run_biology_options(TRUE))
  qc <- .sc_run_qc_evidence(object, config$context)
  original <- .sc_run_hash(object)
  set.seed(444); rng <- .Random.seed
  record <- suppressWarnings(.sc_run_biology_compute(object, config, qc))
  expect_identical(.sc_run_hash(object), original)
  expect_identical(.Random.seed, rng)
  expect_identical(record$summary$status, "available")
  expect_identical(record$hash, .sc_run_hash(record[setdiff(names(record), "hash")]))
  expect_true(record$diagnostic_only)
  expect_false(record$scientific_approved)
  expect_setequal(names(record$membership), colnames(object))
  expect_false(any(c("cell_id", "embedding") %in% names(record$summary)))
  changed <- object
  counts <- .sc_project_layer(changed, "RNA", "counts", raw_counts = TRUE)
  counts[1, 1] <- counts[1, 1] + 1
  SeuratObject::LayerData(changed, assay = "RNA", layer = "counts") <- counts
  expect_error(.sc_run_biology_compute(changed, config, qc), "differ")
  small <- subset(object, cells = colnames(object)[1:10])
  unavailable <- .sc_run_biology_compute(small, config, .sc_run_qc_evidence(small, config$context))
  expect_identical(unavailable$summary$status, "unavailable")
  expect_false(unavailable$summary$relaxation_allowed)
})

test_that("diagnostic checkpoint joins the first review without becoming final PCA", {
  data("pbmc_small", package = "SeuratObject")
  root <- tempfile("biology-review-")
  on.exit(unlink(root, recursive = TRUE))
  proposal <- list(schema = "scagentkit.strategy.v1", rationale = "Software control.",
    risks = list("No biological validation."), inferences = list(),
    qc = list(schema = "scagentkit.qc.rules.v1", rationale = "Keep positive-count fixture cells.",
      risks = list(), remove_if = "any", rules = list(list(op = "range", metric = "nCount", min = 1L))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 50L, npcs = 10L, seed = 1L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No technical design supplied."),
    clustering = list(resolution = .4, diagnostic_resolutions = c(.2, .4)),
    umap = list(run = FALSE, n_neighbors = 10L))
  out <- suppressWarnings(sc_run(pbmc_small, root, context = list(species = "human", tissue = "blood"),
    strategy = TRUE, biological_diagnostics = TRUE, strategy_proposal = proposal))
  expect_identical(out$status, "awaiting_review")
  state <- .sc_run_load(root)
  expect_true("biology_diagnostics" %in% names(state$files))
  expect_false("strategy_basis" %in% names(state$files))
  expect_null(state$approved)
  expect_length(state$approvals, 0L)
  review <- .sc_run_strategy_review_verify(root, state)
  expect_true(review$details$biology$diagnostic_only)
  expect_length(review$details$risk_flags$fields, 5L)
  expect_identical(review$details$risk_flags$stage, "strategy")
  expect_gt(length(review$details$diagnostic_thresholds$table), 0L)
  evidence <- .sc_run_get(root, state, "strategy_evidence")
  empty <- .sc_run_get(root, state, "strategy_validated")
  empty$proposal$qc$rules <- list()
  empty$proposal$qc$remove_if <- "all"
  empty <- .sc_run_strategy_validate(empty$proposal, evidence,
    retained_scope = empty$qc_validated$retained_scope)
  thresholds <- .sc_run_biology_threshold_review(empty, evidence)
  expect_identical(thresholds$table, list())
  expect_identical(thresholds$remove_if, "all")
  expect_identical(thresholds$minimum_prefilter_counts, review$details$diagnostic_thresholds$minimum_prefilter_counts)
  risk <- review$details$risk_flags
  expect_identical(.sc_run_biology_risks(risk, evidence), risk)
  invalid <- risk; invalid$fields[[1]]$value <- "certain_doublet"
  expect_error(.sc_run_biology_risks(invalid, evidence), "enumeration")
  invalid <- risk; invalid$evidence_hash <- strrep("0", 64)
  expect_error(.sc_run_biology_risks(invalid, evidence), "stale")
  invalid <- risk; invalid$fields[[1]]$evidence_ids <- list("invented")
  expect_error(.sc_run_biology_risks(invalid, evidence), "evidence")
  expect_silent(.sc_run_biology_verify(.sc_run_get(root, state, "biology_diagnostics"),
    .sc_run_get(root, state, "qc_evidence"), state$config))
  changed <- .sc_run_get(root, state, "biology_diagnostics")
  changed$membership[1] <- "changed"
  expect_error(.sc_run_biology_verify(changed, .sc_run_get(root, state, "qc_evidence")),
    "changed")
  node <- sc_run_inspect(root)$review_node
  sc_run_review(root, "approve", node$kind, node$project_id, node$input_hash,
    node$proposal_hash, node$review_hash, node$expected_revision,
    reviewer = "benchmark-policy:fixed", reason = "Explicit mock software acceptance, not biological validation.")
  continued <- suppressWarnings(sc_run_resume(root))
  expect_identical(continued$status, "awaiting_review")
  updated <- .sc_run_load(root)
  expect_identical(updated$pending$kind, "strategy") # measured resolution gate
  basis <- .sc_run_get(root, updated, "strategy_basis")
  diagnostic <- .sc_run_get(root, updated, "biology_diagnostics")
  expect_identical(ncol(SeuratObject::Embeddings(basis, "pca")), 10L)
  expect_false(identical(SeuratObject::Embeddings(basis, "pca"), diagnostic$embedding))
  expect_identical(updated$files$biology_diagnostics, state$files$biology_diagnostics)
})
