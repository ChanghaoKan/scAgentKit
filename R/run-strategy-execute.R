# Pure execution adapters for an already validated and approved typed strategy.
# The coordinator owns locks, approval hashes and durable checkpoints. These
# functions operate on the supplied copy and never evaluate model-written code.

.sc_run_strategy_runtime_number <- function(value, name, lower, upper = Inf,
                                            integer = FALSE, lower_open = FALSE) {
  ok <- is.numeric(value) && length(value) == 1L && !is.na(value) &&
    is.finite(value) && value <= upper &&
    if (lower_open) value > lower else value >= lower
  if (!isTRUE(ok) || (integer && value != floor(value)))
    .sc_project_fail(paste0("Strategy runtime: invalid ", name, "."))
  if (integer) as.integer(value) else as.numeric(value)
}

.sc_run_strategy_runtime_settings <- function(plan) {
  if (!is.list(plan)) .sc_project_fail("Strategy runtime requires a validated typed plan.")
  permitted <- list(analysis = c("normalization_method", "scale_factor", "nfeatures", "npcs", "seed"),
                    pcs = c("method", "ndim", "threshold"),
                    batch = c("method", "reason", "group_by_vars", "theta", "lambda", "sigma", "max_iter", "nclust"),
                    clustering = c("resolution", "diagnostic_resolutions"),
                    umap = c("run", "n_neighbors"))
  for (field in names(permitted)) {
    value <- plan[[field]]
    if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
        any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
        length(setdiff(names(value), permitted[[field]])))
      .sc_project_fail(paste0("Strategy runtime: unsupported ", field, " parameters."))
  }
  analysis <- plan$analysis
  if (!identical(analysis$normalization_method, "LogNormalize"))
    .sc_project_fail("Strategy runtime supports only LogNormalize.")
  analysis$scale_factor <- .sc_run_strategy_runtime_number(analysis$scale_factor, "scale_factor", 0, lower_open = TRUE)
  analysis$nfeatures <- .sc_run_strategy_runtime_number(analysis$nfeatures, "nfeatures", 3, .Machine$integer.max, TRUE)
  analysis$npcs <- .sc_run_strategy_runtime_number(analysis$npcs, "npcs", 2, .Machine$integer.max, TRUE)
  analysis$seed <- .sc_run_strategy_runtime_number(analysis$seed, "seed", 0, .Machine$integer.max, TRUE)
  pcs <- plan$pcs
  if (identical(pcs$method, "fixed")) {
    pcs$ndim <- .sc_run_strategy_runtime_number(pcs$ndim, "pcs$ndim", 2, .Machine$integer.max, TRUE)
    if (!is.null(pcs$threshold)) .sc_project_fail("Fixed PC selection cannot also specify a variance threshold.")
  } else if (identical(pcs$method, "computed_variance")) {
    pcs$threshold <- .sc_run_strategy_runtime_number(pcs$threshold, "pcs$threshold", 0, 1, lower_open = TRUE)
    if (pcs$threshold >= 1 || !is.null(pcs$ndim))
      .sc_project_fail("Computed-variance PC selection requires threshold strictly between zero and one, without ndim.")
  } else if (identical(pcs$method, "computed_top50")) {
    .sc_run_strategy_fields(pcs, c("method", "threshold"), name = "strategy runtime pcs")
    pcs$threshold <- .sc_run_strategy_runtime_number(pcs$threshold, "pcs$threshold", 0, 1, lower_open = TRUE)
    if (!pcs$threshold %in% c(.80, .85))
      .sc_project_fail("Computed-top50 PC selection supports only threshold .80 or .85.")
  } else .sc_project_fail("Strategy runtime supports only fixed, computed_variance or computed_top50 PC selection.")
  if (identical(plan$batch$method, "harmony")) {
    plan$batch <- .sc_run_harmony_parameters(plan$batch)
  } else if (!identical(plan$batch$method, "none")) {
    if (identical(plan$batch$method, "manual"))
      .sc_project_fail("Manual batch handling is a pending analyst boundary; automatic strategy execution cannot pass it.")
    .sc_project_fail("This strategy executor supports only none or explicitly approved Harmony batch handling.")
  } else {
    .sc_run_strategy_fields(plan$batch, c("method", "reason"), name = "strategy runtime batch")
  }
  .sc_project_string(plan$batch$reason, "strategy$batch$reason")
  clustering <- plan$clustering
  clustering$resolution <- .sc_run_strategy_runtime_number(clustering$resolution, "clustering$resolution", 0, 2, lower_open = TRUE)
  diagnostics <- clustering$diagnostic_resolutions
  if (is.null(diagnostics)) diagnostics <- numeric()
  if (!is.numeric(diagnostics) || length(diagnostics) > 5L || anyNA(diagnostics) ||
      any(!is.finite(diagnostics)) || any(diagnostics <= 0 | diagnostics > 2) ||
      anyDuplicated(diagnostics))
    .sc_project_fail("Strategy runtime requires at most five unique diagnostic resolutions in (0, 2].")
  clustering$diagnostic_resolutions <- as.numeric(diagnostics)
  umap <- plan$umap
  if (!identical(umap$run, TRUE) && !identical(umap$run, FALSE))
    .sc_project_fail("Strategy runtime requires a logical umap$run.")
  umap$n_neighbors <- .sc_run_strategy_runtime_number(umap$n_neighbors, "umap$n_neighbors", 3, .Machine$integer.max, TRUE)
  list(analysis = analysis, pcs = pcs, batch = plan$batch,
       clustering = clustering, umap = umap)
}

.sc_run_strategy_runtime_dependencies <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing))
    .sc_project_fail(paste0("Strategy dependency unavailable: ", paste(missing, collapse = ", "),
                           ". Install explicitly before retrying; no automatic skip is supported."))
  invisible(TRUE)
}

.sc_run_strategy_runtime_object <- function(seu, config) {
  if (!inherits(seu, "Seurat")) .sc_project_fail("Strategy execution requires a Seurat object copy.")
  .sc_project_string(config$assay, "strategy assay")
  .sc_project_string(config$counts_layer, "strategy counts_layer")
  .sc_project_string(config$cluster_column, "strategy cluster_column")
  if (!identical(config$counts_layer, "counts") || !identical(config$normalized_layer, "data"))
    .sc_project_fail("Automatic strategy execution requires exact counts and data layer names; custom layers need explicit preparation.")
  counts <- .sc_project_layer(seu, config$assay, "counts", raw_counts = TRUE)
  if (!setequal(colnames(counts), colnames(seu)))
    .sc_project_fail("Strategy counts must cover every source cell exactly.")
  if (!identical(rownames(seu[[]]), colnames(seu)))
    .sc_project_fail("Strategy source metadata must follow the exact object cell order.")
  if (ncol(seu) < 21L)
    .sc_project_fail("Strategy requires at least 21 retained cells for the declared fixed graph k.param=20; no automatic clipping is performed.")
  counts
}

.sc_run_strategy_record <- function(seu, stage, record) {
  existing <- seu@misc$strategy_execution
  if (is.null(existing)) existing <- list(schema = "scagentkit.strategy-execution.v1")
  if (!is.list(existing)) .sc_project_fail("Existing strategy execution evidence is malformed.")
  existing[[stage]] <- record
  seu@misc$strategy_execution <- existing
  seu
}

.sc_run_strategy_pca_evidence <- function(seu, settings, select = TRUE) {
  if (!"pca" %in% names(seu@reductions))
    .sc_project_fail("Strategy PCA reduction is unavailable; execute the basis checkpoint first.")
  embeddings <- SeuratObject::Embeddings(seu[["pca"]])
  deviation <- SeuratObject::Stdev(seu[["pca"]])
  if (!identical(rownames(embeddings), colnames(seu)) ||
      any(!is.finite(embeddings)) || length(deviation) != ncol(embeddings) ||
      length(deviation) != settings$analysis$npcs || any(!is.finite(deviation)) ||
      any(deviation <= 0) || !is.finite(sum(deviation^2)) || sum(deviation^2) <= 0)
    .sc_project_fail("Strategy PCA must contain the exact requested, finite, positive-variance components and exact cell order.")
  fractions <- deviation^2 / sum(deviation^2)
  cumulative <- cumsum(fractions)
  evidence <- list(available_pcs = ncol(embeddings),
                   fraction_per_pc = as.numeric(fractions),
                   cumulative_fraction = as.numeric(cumulative),
                   denominator = "sum of variances of computed PCs only; not total expressed-gene variance",
                   interpretation = "A computational dimensionality rule; not proof of biologically correct populations.",
                   top50_candidates = .sc_run_pc_candidates(deviation))
  # Basis evidence depends only on the PCA computation, so changing the PC
  # selection policy can reuse this checkpoint without recalculating PCA.
  if (identical(select, FALSE)) return(evidence)
  if (!identical(select, TRUE))
    .sc_project_fail("Strategy PCA evidence select must be logical.")
  if (identical(settings$pcs$method, "fixed")) {
    ndim <- settings$pcs$ndim
  } else if (identical(settings$pcs$method, "computed_top50")) {
    candidate <- evidence$top50_candidates$candidates[[if (settings$pcs$threshold == .80) "p80" else "p85"]]
    if (!isTRUE(candidate$supported))
      .sc_project_fail("The approved computed-top50 rule selects fewer than two PCs; revise the rule or approve fixed ndim >= 2. No clipping is performed.")
    ndim <- candidate$ndim
  } else {
    qualifying <- which(cumulative >= settings$pcs$threshold)
    if (!length(qualifying))
      .sc_project_fail("Computed-PC variance did not reach the approved threshold; revise the strategy.")
    ndim <- qualifying[[1L]]
    if (ndim < 2L)
      .sc_project_fail("The approved computed-variance threshold selects only one PC; revise the threshold or explicitly approve a fixed ndim >= 2.")
  }
  if (ndim > ncol(embeddings))
    .sc_project_fail("Approved PC dimensions exceed actually available components; no automatic clipping is performed.")
  selection_evidence <- evidence
  if (identical(settings$pcs$method, "computed_top50")) {
    selection_evidence$all_computed_pc_variance <- evidence[c("fraction_per_pc", "cumulative_fraction", "denominator")]
    selection_evidence$fraction_per_pc <- evidence$top50_candidates$fraction_per_pc
    selection_evidence$cumulative_fraction <- evidence$top50_candidates$cumulative_fraction
    selection_evidence$denominator <- evidence$top50_candidates$denominator
    selection_evidence$selection_reference_pcs <- evidence$top50_candidates$reference_pcs
  }
  c(list(method = settings$pcs$method, ndim = as.integer(ndim),
         threshold = settings$pcs$threshold,
         fraction_at_selected = as.numeric(if (identical(settings$pcs$method, "computed_top50"))
           evidence$top50_candidates$cumulative_fraction[[ndim]] else cumulative[[ndim]])), selection_evidence)
}

.sc_run_strategy_normalize_hvg <- function(seu, config, settings, counts) {
  SeuratObject::DefaultAssay(seu) <- config$assay
  cells <- colnames(seu)
  features <- rownames(seu[[config$assay]])
  seu <- Seurat::NormalizeData(seu, assay = config$assay,
                               normalization.method = "LogNormalize",
                               scale.factor = settings$analysis$scale_factor,
                               verbose = FALSE)
  normalized <- .sc_project_layer(seu, config$assay, "data")
  if (!setequal(rownames(normalized), rownames(counts)) || !setequal(colnames(normalized), cells))
    .sc_project_fail("Normalized strategy layer did not preserve the complete counts cell/feature universe.")
  seu <- Seurat::FindVariableFeatures(seu, assay = config$assay,
                                      selection.method = "vst",
                                      nfeatures = settings$analysis$nfeatures,
                                      verbose = FALSE)
  hvg <- SeuratObject::VariableFeatures(seu[[config$assay]])
  if (length(hvg) != settings$analysis$nfeatures || anyDuplicated(hvg) ||
      any(!hvg %in% features))
    .sc_project_fail("HVG selection did not return the exact approved number of available, unique genes; revise the strategy.")
  seu
}

# Approved selection is separate from pure QC, so a doublet decision can change
# its derived object without recomputing QC or the fixed scoring reference.
.sc_run_strategy_selection <- function(seu, config, validated, record) {
  if (is.null(config$doublet_diagnostics) || is.null(validated$doublet) ||
      !identical(record$options, config$doublet_diagnostics))
    .sc_project_fail("Doublet selection requires its exact enabled, approved evidence and options.")
  checked <- .sc_run_doublet_validate_choice(validated$proposal$doublet, record, colnames(seu))
  if (!identical(checked$keep_cells, validated$selected_cells) ||
      !identical(checked$removed_cells, validated$doublet$removed_cells) ||
      !identical(checked$evidence_hash, validated$doublet$evidence_hash))
    .sc_project_fail("Approved doublet selection differs from its fixed prediction/QC intersection.")
  scored <- .sc_run_doublet_attach(seu, record)
  metadata <- scored[[]]
  output <- scored[, checked$keep_cells]
  output@meta.data <- metadata[checked$keep_cells, , drop = FALSE]
  if (!identical(colnames(output), checked$keep_cells) ||
      !identical(output[[]], metadata[checked$keep_cells, , drop = FALSE]))
    .sc_project_fail("Doublet selection changed literal IDs/order or protected metadata.")
  # Recheck exact count scope and score attachment after Seurat's subset.
  counts <- .sc_project_layer(output, config$assay, config$counts_layer, raw_counts = TRUE)
  if (!identical(rownames(counts), record$feature_ids) ||
      !identical(.sc_run_cycle_cell_counts(counts, colnames(output)), record$count_cell_hashes[colnames(output)]))
    .sc_project_fail("Doublet selection changed retained raw counts or source features.")
  .sc_run_strategy_record(output, "selection", list(method = checked$method,
    evidence_hash = record$evidence_hash, selection_hash = validated$dependency_hashes$selection,
    full_input_cells = length(record$cell_ids), qc_cell_ids = colnames(seu),
    retained_cell_ids = checked$keep_cells, removed_cell_ids = checked$removed_cells,
    score_reference = if (is.null(record$prefilter_record)) "fixed_full_input" else "fixed_prefilter_cohort", refit_after_qc = FALSE,
    counts_hash = .sc_project_sparse_hash(counts),
    primitives = c("SeuratObject::AddMetaData", "Seurat public literal-cell subset"),
    notice = "Classes are algorithm predictions, not truth; scores are not calibrated probabilities."))
}

# An independent NormalizeData/HVG checkpoint, reusable across cycle choices.
.sc_run_strategy_preprocess <- function(seu, config, plan) {
  settings <- .sc_run_strategy_runtime_settings(plan)
  .sc_run_strategy_runtime_dependencies(c("Seurat", "SeuratObject", "Matrix"))
  counts <- .sc_run_strategy_runtime_object(seu, config)
  if (settings$analysis$nfeatures > nrow(counts))
    .sc_project_fail("Approved HVG feature count exceeds available genes; no automatic clipping is performed.")
  cells <- colnames(seu); features <- rownames(seu[[config$assay]])
  metadata <- seu[[]]
  seu <- .sc_run_strategy_normalize_hvg(seu, config, settings, counts)
  normalized <- .sc_project_layer(seu, config$assay, "data")
  if (!identical(colnames(seu), cells) || !identical(rownames(seu[[config$assay]]), features) ||
      !identical(seu[[]], metadata) ||
      !identical(.sc_project_sparse_hash(.sc_project_layer(seu, config$assay, "counts", raw_counts = TRUE)),
                 .sc_project_sparse_hash(counts)))
    .sc_project_fail("Strategy preprocessing changed source counts, metadata, or literal IDs.")
  .sc_run_strategy_record(seu, "preprocess", list(
    parameters = settings$analysis[c("normalization_method", "scale_factor", "nfeatures")],
    assay = config$assay, counts_layer = config$counts_layer, normalized_layer = "data",
    cell_ids = cells, feature_ids = features,
    counts_hash = .sc_project_sparse_hash(counts), normalized_hash = .sc_project_sparse_hash(normalized),
    variable_features = SeuratObject::VariableFeatures(seu[[config$assay]]),
    primitives = c("Seurat::NormalizeData", "Seurat::FindVariableFeatures")))
}

.sc_run_strategy_basis <- function(seu, config, plan, preprocessed = FALSE, cycle_record = NULL) {
  settings <- .sc_run_strategy_runtime_settings(plan)
  .sc_run_strategy_runtime_dependencies(c("Seurat", "SeuratObject", "Matrix", "irlba"))
  counts <- .sc_run_strategy_runtime_object(seu, config)
  if (!identical(preprocessed, FALSE) && !identical(preprocessed, TRUE))
    .sc_project_fail("Strategy basis preprocessed must be logical.")
  if (settings$analysis$nfeatures > nrow(counts))
    .sc_project_fail("Approved HVG feature count exceeds available genes; no automatic clipping is performed.")
  if (settings$analysis$npcs >= min(settings$analysis$nfeatures, ncol(seu)))
    .sc_project_fail("Approved PCA components must be strictly fewer than both requested HVGs and retained cells.")
  cells <- colnames(seu); features <- rownames(seu[[config$assay]])
  metadata <- seu[[]]
  cycle <- NULL
  if (!is.null(cycle_record)) {
    if (is.null(config$cycle_diagnostics))
      .sc_project_fail("Cycle basis scoring requires explicitly enabled cycle_diagnostics.")
    .sc_run_cycle_verify(cycle_record)
    if (!identical(cycle_record$options, config$cycle_diagnostics))
      .sc_project_fail("Cycle basis options differ from the saved diagnostic reference.")
    cycle <- .sc_run_cycle_validate_choice(plan$cycle, cycle_record, cells)
    # The coordinator can attach at the QC checkpoint. A preexisting exact
    # attachment is checked; a partial or changed attachment is rejected.
    columns <- cycle_record$summary$columns
    present <- columns %in% names(metadata)
    if (any(present)) {
      expected <- cycle_record$scores[match(cells, cycle_record$cell_ids), unname(columns), drop = FALSE]
      rownames(expected) <- cells
      if (!all(present) || !identical(metadata[, unname(columns), drop = FALSE], expected))
        .sc_project_fail("Attached cycle scores differ from the fixed full-input reference.")
      counts_for_cells <- .sc_run_cycle_cell_counts(counts, cells)
      if (!identical(counts_for_cells, cycle_record$count_cell_hashes[cells]))
        .sc_project_fail("Basis source counts differ from the fixed cycle reference.")
    } else seu <- .sc_run_cycle_attach(seu, cycle_record)
  } else if (!is.null(plan$cycle) || !is.null(config$cycle_diagnostics))
    .sc_project_fail("Cycle strategy basis requires its saved full-input diagnostic reference.")
  # Removing only our own derived artifacts avoids an accidental stale-graph
  # reuse while preserving unrelated caller graphs and old metadata columns.
  for (name in c("sc_strategy_nn", "sc_strategy_snn", "pca", "umap"))
    if (name %in% names(seu)) seu[[name]] <- NULL
  SeuratObject::DefaultAssay(seu) <- config$assay
  if (isTRUE(preprocessed)) {
    previous <- seu@misc$strategy_execution$preprocess
    normalized <- .sc_project_layer(seu, config$assay, "data")
    hvg <- SeuratObject::VariableFeatures(seu[[config$assay]])
    if (!is.list(previous) ||
        !identical(previous$parameters, settings$analysis[c("normalization_method", "scale_factor", "nfeatures")]) ||
        !identical(previous$assay, config$assay) ||
        !identical(previous$cell_ids, cells) || !identical(previous$feature_ids, features) ||
        !identical(previous$counts_hash, .sc_project_sparse_hash(counts)) ||
        !identical(previous$normalized_hash, .sc_project_sparse_hash(normalized)) ||
        !identical(previous$variable_features, hvg) || length(hvg) != settings$analysis$nfeatures)
      .sc_project_fail("Preprocessed strategy checkpoint is absent, changed, or incompatible; regenerate NormalizeData/HVG explicitly.")
  } else {
    # This legacy path deliberately retains its original output record shape.
    seu <- .sc_run_strategy_normalize_hvg(seu, config, settings, counts)
    hvg <- SeuratObject::VariableFeatures(seu[[config$assay]])
  }
  regressors <- if (is.null(cycle)) character() else cycle$regressors
  seu <- if (length(regressors))
    Seurat::ScaleData(seu, assay = config$assay, features = hvg, vars.to.regress = regressors,
                     do.center = TRUE, do.scale = TRUE, verbose = FALSE) else
    Seurat::ScaleData(seu, assay = config$assay, features = hvg,
                     do.center = TRUE, do.scale = TRUE, verbose = FALSE)
  # scale.data is necessarily dense for the HVGs only. Raw counts are never
  # converted to a dense matrix; no all-gene scaling fallback is permitted.
  scaled <- SeuratObject::LayerData(seu[[config$assay]], layer = "scale.data", fast = FALSE)
  if (!setequal(rownames(scaled), hvg) || !identical(colnames(scaled), cells) ||
      any(!is.finite(scaled)))
    .sc_project_fail("HVG-only scaling did not produce finite values for the exact approved genes and cell order.")
  sum_squares <- as.numeric(Matrix::rowSums(scaled * scaled))
  if (any(!is.finite(sum_squares)) || any(sum_squares <= 0))
    .sc_project_fail("Selected HVGs include zero-variance or invalid genes; revise the approved feature count rather than silently dropping genes.")
  seu <- Seurat::RunPCA(seu, assay = config$assay, features = hvg,
                        npcs = settings$analysis$npcs, reduction.name = "pca",
                        seed.use = settings$analysis$seed, approx = TRUE,
                        verbose = FALSE)
  if (!identical(colnames(seu), cells) || !identical(rownames(seu[[config$assay]]), features) ||
      !identical(seu[[]][, names(metadata), drop = FALSE], metadata))
    .sc_project_fail("Strategy basis changed source metadata, cell, or feature order.")
  pca <- .sc_run_strategy_pca_evidence(seu, settings, select = FALSE)
  record <- list(
    parameters = settings$analysis, cells = length(cells), features = length(features),
    variable_features = hvg, scaled_feature_count = length(hvg),
    scale_scope = "approved HVGs only", regressors = regressors,
    pca = pca, batch_method = "none", batch_reason = settings$batch$reason,
    primitives = c("Seurat::NormalizeData", "Seurat::FindVariableFeatures", "Seurat::ScaleData", "Seurat::RunPCA"),
    reuse = "Same computed-PC cumulative variance rule as sc_select_pcs, with runtime bounds and finite-variance validation.")
  if (isTRUE(preprocessed)) {
    record$preprocessed <- TRUE
    record$primitives <- c("Seurat::ScaleData", "Seurat::RunPCA")
  }
  if (!is.null(cycle)) {
    record$cycle <- cycle
    record$cycle_method <- cycle$method
  }
  .sc_run_strategy_record(seu, "basis", record)
}

.sc_run_strategy_neighbors <- function(seu, config, plan) {
  settings <- .sc_run_strategy_runtime_settings(plan)
  packages <- c("Seurat", "SeuratObject", "Matrix", "RcppAnnoy")
  if (settings$umap$run) packages <- c(packages, "uwot")
  .sc_run_strategy_runtime_dependencies(packages)
  .sc_run_strategy_runtime_object(seu, config)
  pca <- .sc_run_strategy_pca_evidence(seu, settings)
  reduction <- if (identical(settings$batch$method, "harmony")) "harmony" else "pca"
  if (identical(reduction, "harmony")) {
    record <- seu@misc$strategy_execution$batch
    if (!is.list(record) ||
        !identical(record$choice[setdiff(names(record$choice), "reason")],
          settings$batch[setdiff(names(settings$batch), "reason")]) ||
        !"harmony" %in% names(seu@reductions))
      .sc_project_fail("Approved Harmony checkpoint is unavailable or its parameters changed.")
    if (!identical(record$source, .sc_run_harmony_source()))
      .sc_project_fail("Cached Harmony dependency versions or public method implementation changed; revise and recompute that batch checkpoint explicitly.")
    embeddings <- SeuratObject::Embeddings(seu[["harmony"]])
    if (!identical(rownames(embeddings), colnames(seu)) || ncol(embeddings) != pca$ndim || any(!is.finite(embeddings)))
      .sc_project_fail("Harmony dimensions must match the approved PCs and exact source cell order.")
  }
  if (settings$umap$run && settings$umap$n_neighbors >= ncol(seu))
    .sc_project_fail("Approved UMAP n_neighbors must be fewer than retained cells; no automatic clipping is performed.")
  for (name in c("sc_strategy_nn", "sc_strategy_snn", "umap"))
    if (name %in% names(seu)) seu[[name]] <- NULL
  cells <- colnames(seu)
  seu <- Seurat::FindNeighbors(seu, reduction = reduction, dims = seq_len(pca$ndim),
                               k.param = 20L, nn.method = "annoy", n.trees = 50L,
                               prune.SNN = 1 / 15, compute.SNN = TRUE,
                               graph.name = c("sc_strategy_nn", "sc_strategy_snn"),
                               verbose = FALSE)
  for (name in c("sc_strategy_nn", "sc_strategy_snn")) {
    graph <- seu[[name]]
    if (!inherits(graph, "Graph") || !identical(rownames(graph), cells) ||
        !identical(colnames(graph), cells))
      .sc_project_fail("Strategy neighbor graphs did not preserve exact source cell order.")
  }
  if (settings$umap$run) {
    seu <- Seurat::RunUMAP(seu, reduction = reduction, dims = seq_len(pca$ndim),
                           n.neighbors = settings$umap$n_neighbors,
                           reduction.name = "umap", umap.method = "uwot",
                           metric = "cosine", seed.use = settings$analysis$seed,
                           n.components = 2L, verbose = FALSE)
    embedding <- SeuratObject::Embeddings(seu[["umap"]])
    if (!identical(rownames(embedding), cells) || ncol(embedding) != 2L ||
        any(!is.finite(embedding)))
      .sc_project_fail("Strategy UMAP did not preserve finite two-dimensional embeddings for the exact source cell order.")
  }
  .sc_run_strategy_record(seu, "neighbors", list(
    reduction = reduction, pcs = pca, k_param = 20L, nn_method = "annoy", n_trees = 50L,
    prune_snn = 1 / 15, graph_names = c("sc_strategy_nn", "sc_strategy_snn"),
    umap = list(run = settings$umap$run, n_neighbors = settings$umap$n_neighbors,
                method = if (settings$umap$run) "uwot" else NULL,
                metric = if (settings$umap$run) "cosine" else NULL,
                seed = settings$analysis$seed),
    batch_method = settings$batch$method, original_graphs_used = FALSE))
}

.sc_run_strategy_cluster <- function(seu, config, plan) {
  settings <- .sc_run_strategy_runtime_settings(plan)
  .sc_run_strategy_runtime_dependencies(c("Seurat", "SeuratObject", "Matrix"))
  .sc_run_strategy_runtime_object(seu, config)
  graph <- seu[["sc_strategy_snn"]]
  cells <- colnames(seu)
  if (!inherits(graph, "Graph") || !identical(rownames(graph), cells) ||
      !identical(colnames(graph), cells))
    .sc_project_fail("Strategy clustering requires the exact fresh strategy SNN graph; execute the neighbor checkpoint first.")
  if (config$cluster_column %in% names(seu[[]]))
    .sc_project_fail("Strategy cluster output column already exists; choose a fresh cluster_column to preserve source labels.")
  resolutions <- sort(unique(c(settings$clustering$resolution,
                                settings$clustering$diagnostic_resolutions)))
  assignments <- lapply(resolutions, function(resolution) {
    # Calling the public graph method instead of the Seurat method avoids its
    # incidental seurat_clusters and *_snn_res.* metadata overwrites.
    result <- Seurat::FindClusters(graph, resolution = resolution, algorithm = 1L,
                                   random.seed = settings$analysis$seed,
                                   n.start = 10L, n.iter = 10L, verbose = FALSE)
    if (!is.data.frame(result) || ncol(result) != 1L || !setequal(rownames(result), cells))
      .sc_project_fail("Louvain clustering did not return one membership per exact source cell.")
    labels <- as.character(result[cells, 1L])
    if (length(labels) != length(cells) || anyNA(labels) || any(!nzchar(labels)))
      .sc_project_fail("Louvain clustering returned invalid cell memberships.")
    stats::setNames(labels, cells)
  })
  chosen_index <- which(resolutions == settings$clustering$resolution)
  chosen <- assignments[[chosen_index]]
  evidence <- lapply(seq_along(resolutions), function(index) {
    sizes <- table(assignments[[index]])
    list(resolution = resolutions[[index]], chosen = index == chosen_index,
         n_clusters = length(sizes), min_cluster_size = min(as.integer(sizes)),
         max_cluster_size = max(as.integer(sizes)),
         cluster_sizes = stats::setNames(as.list(as.integer(sizes)), names(sizes)),
         ari_vs_chosen = .adjusted_rand_index(chosen, assignments[[index]]),
         ari_vs_previous = if (index > 1L)
           .adjusted_rand_index(assignments[[index - 1L]], assignments[[index]]) else NULL)
  })
  original_metadata <- seu[[]]
  seu[[config$cluster_column]] <- factor(chosen[cells])
  if (!identical(seu[[]][, names(original_metadata), drop = FALSE], original_metadata) ||
      !identical(colnames(seu), cells))
    .sc_project_fail("Strategy clustering changed original metadata or source cell order.")
  .sc_run_strategy_record(seu, "cluster", list(
    method = "Louvain", algorithm = 1L, graph_name = "sc_strategy_snn",
    cluster_column = config$cluster_column,
    resolution = settings$clustering$resolution, seed = settings$analysis$seed,
    n_start = 10L, n_iter = 10L, candidates = evidence,
    diagnostic_assignments = stats::setNames(assignments, as.character(resolutions)),
    chosen_cluster_count = length(unique(chosen)),
    diagnostic_interpretation = "Resolution counts and ARI are computational sensitivity summaries, not proof of biological correctness.",
    primitives = c("Seurat::FindClusters", ".adjusted_rand_index")))
}
