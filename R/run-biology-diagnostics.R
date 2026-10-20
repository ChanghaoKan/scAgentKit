# Diagnostic computations never supply final analysis embeddings or approvals.
.sc_run_biology_options <- function(value = NULL) {
  if (is.null(value) || identical(value, FALSE)) return(NULL)
  if (identical(value, TRUE)) value <- list()
  defaults <- list(cluster_qc = TRUE, batch_assessment = TRUE)
  if (!is.list(value) || (length(value) && (is.null(names(value)) ||
      anyDuplicated(names(value)) || any(!names(value) %in% names(defaults)))))
    stop("biological_diagnostics accepts cluster_qc and batch_assessment switches only.", call. = FALSE)
  for (key in names(value)) {
    if (!is.logical(value[[key]]) || length(value[[key]]) != 1L || is.na(value[[key]]))
      stop("Biological diagnostic switches must be TRUE or FALSE.", call. = FALSE)
    defaults[[key]] <- value[[key]]
  }
  if (!any(unlist(defaults))) return(NULL)
  c(list(schema = "scagentkit.biology-options.v1"), defaults,
    list(seed = 1234L, nfeatures = 2000L, npcs = 20L, k = 20L,
      resolution = .2, scale_factor = 10000, marker_min_pct = .1,
      marker_logfc_threshold = .25, relaxation_support = 3L,
      min_group_cells = 30L, mad_k = 3, mad_constant = 1.4826,
      diagnostic_only = TRUE))
}

.sc_run_biology_exclusions <- function(species, features) {
  supported <- length(species) == 1L && species %in% c("human", "mouse")
  symbols <- supported && !any(grepl("^ENS(MUS)?G[0-9]+", features))
  stress <- c("FOS", "FOSB", "JUN", "JUNB", "JUND", "ATF3", "DDIT3", "EGR1",
    "IER2", "IER3", "HSPA1A", "HSPA1B", "HSPB1", "DNAJB1")
  if (identical(species, "mouse"))
    stress <- paste0(substr(stress, 1L, 1L), tolower(substring(stress, 2L)))
  ribo <- if (supported) .sc_run_ribo_pattern(species) else NULL
  mt <- if (identical(species, "human")) "^MT[-.]" else "^mt[-.]"
  excluded <- if (symbols) features[grepl(mt, features) |
    grepl(ribo, features) | features %in% stress] else character()
  policy <- list(version = "diagnostic-relaxation-exclusions.v1", species = species,
    symbol_mapping_verified = symbols, mitochondrial_pattern = if (supported) mt else NULL,
    ribosomal_pattern = ribo, stress_genes = as.list(stress),
    excluded_genes = as.list(sort(unique(excluded))),
    boundary = "Conservative literal-symbol software guard, not a diagnostic of cell health. Unresolved Ensembl features cannot qualify for relaxation.")
  policy$hash <- .sc_run_hash(policy)
  policy
}

.sc_run_biology_marker_support <- function(markers, cluster, policy, n = 3L) {
  required <- c("cluster", "gene", "avg_log2FC", "pct.1", "pct.2", "p_val_adj")
  if (!is.data.frame(markers) || !all(required %in% names(markers)))
    return(list(eligible = FALSE, support_count = 0L, top_markers = list(),
      reason = "Diagnostic marker statistics are unavailable."))
  table <- markers[as.character(markers$cluster) == cluster, required, drop = FALSE]
  table <- table[order(-table$avg_log2FC, as.character(table$gene), na.last = TRUE,
    method = "radix"), , drop = FALSE]
  table <- head(table[!duplicated(table$gene), , drop = FALSE], 5L)
  valid <- is.finite(table$avg_log2FC) & is.finite(table$p_val_adj) &
    is.finite(table$pct.1) & is.finite(table$pct.2) &
    table$p_val_adj < .05 & table$avg_log2FC > 0 & table$pct.1 > table$pct.2 &
    !table$gene %in% unlist(policy$excluded_genes, use.names = FALSE)
  valid <- valid & isTRUE(policy$symbol_mapping_verified)
  table$relaxation_support <- valid
  list(eligible = sum(valid) >= n, support_count = as.integer(sum(valid)),
    required_support = n, exclusion_hash = policy$hash,
    top_markers = lapply(seq_len(nrow(table)), function(i) as.list(table[i, , drop = FALSE])),
    reason = if (sum(valid) >= n)
      "Marker eligibility permits proposing a relaxation for review; it does not certify a healthy cell type."
    else "Insufficient tested non-mitochondrial, non-ribosomal, non-stress top markers; relaxation is forbidden.")
}

.sc_run_biology_thresholds <- function(metrics, groups, options) {
  stopifnot(length(groups) == nrow(metrics), !anyNA(groups))
  lapply(sort(unique(as.character(groups)), method = "radix"), function(group) {
    selected <- as.character(groups) == group
    measured <- lapply(c("nCount", "nFeature", "percent_mt"), function(metric) {
      x <- .sc_run_mad_metric(metrics[[metric]][selected], metric,
        list(min_group_cells = options$min_group_cells, k = options$mad_k,
          mad_constant = options$mad_constant))
      # Match the existing MAD policy: count/feature lower tails, MT upper tail.
      list(metric = metric, available = x$available,
        min = if (x$available && metric != "percent_mt") max(0, ceiling(x$exact$lower_raw)) else NULL,
        max = if (x$available && metric == "percent_mt") min(100, x$exact$upper_raw) else NULL,
        distribution = .sc_run_qc_distribution(metrics[[metric]][selected]),
        diagnostics = x)
    })
    list(group = group, cells = sum(selected), metrics = measured)
  })
}

.sc_run_biology_threshold_keep <- function(metrics, groups, thresholds) {
  keep <- rep(TRUE, nrow(metrics))
  assessed <- rep(FALSE, nrow(metrics))
  for (entry in thresholds) {
    selected <- as.character(groups) == entry$group
    for (rule in entry$metrics) if (isTRUE(rule$available)) {
      x <- metrics[[rule$metric]]
      assessed[selected] <- TRUE
      if (!is.null(rule$min)) keep[selected] <- keep[selected] & x[selected] >= rule$min
      if (!is.null(rule$max)) keep[selected] <- keep[selected] & x[selected] <= rule$max
    }
  }
  list(keep = keep, assessed = assessed)
}

.sc_run_biology_compute <- function(seu, config, qc, prefilter = NULL) {
  options <- config$biological_diagnostics
  if (is.null(options)) return(NULL)
  if (!identical(qc$evidence_hash, .sc_run_qc_hash(qc)))
    stop("Diagnostic QC evidence changed.", call. = FALSE)
  counts <- .sc_project_layer(seu, config$assay, config$counts_layer, raw_counts = TRUE)
  cells <- qc$metrics$cell_id
  if (!identical(sort(colnames(counts)), sort(cells)))
    stop("Diagnostic counts and QC cell scope disagree.", call. = FALSE)
  if (!identical(.sc_project_sparse_hash(.sc_project_matrix(counts, "Diagnostic counts",
      raw_counts = TRUE)), qc$counts_hash) || !identical(rownames(counts), qc$feature_ids))
    stop("Diagnostic counts differ from the saved QC evidence.", call. = FALSE)
  eligible <- if (is.null(prefilter)) cells else prefilter$keep_cells
  if (!is.null(prefilter)) {
    .sc_run_prefilter_verify(prefilter)
    if (!identical(prefilter$counts_hash, qc$counts_hash) ||
        !identical(prefilter$cell_ids, cells))
      stop("Diagnostic prefilter belongs to different input.", call. = FALSE)
  }
  # Zero-count cells cannot be normalized; excluding them from a diagnostic
  # does not remove them from the scientific input or approve a QC decision.
  eligible <- eligible[Matrix::colSums(counts[, eligible, drop = FALSE]) > 0]
  policy <- .sc_run_biology_exclusions(config$context$species, rownames(counts))
  record <- list(schema = "scagentkit.biology-diagnostic.v1", options = options,
    qc_evidence_hash = qc$evidence_hash, counts_hash = qc$counts_hash,
    context_hash = .sc_run_hash(config$context),
    prefilter_hash = if (is.null(prefilter)) NULL else prefilter$evidence_hash,
    minimum_counts = if (is.null(prefilter$options$min_counts)) 0 else prefilter$options$min_counts,
    exclusions = policy, cell_ids = cells, diagnostic_cells = eligible,
    diagnostic_only = TRUE, scientific_approved = FALSE)
  compute <- function() {
    if (length(eligible) < 21L) stop("Fewer than 21 positive-count diagnostic cells.", call. = FALSE)
    object <- SeuratObject::CreateSeuratObject(counts = counts[, eligible, drop = FALSE])
    object <- Seurat::NormalizeData(object, normalization.method = "LogNormalize",
      scale.factor = options$scale_factor, verbose = FALSE)
    object <- Seurat::FindVariableFeatures(object, selection.method = "vst",
      nfeatures = min(options$nfeatures, nrow(object) - 1L), verbose = FALSE)
    features <- SeuratObject::VariableFeatures(object)
    npcs <- min(options$npcs, length(features) - 1L, ncol(object) - 1L)
    if (npcs < 2L) stop("Too few variable features for diagnostic PCA.", call. = FALSE)
    object <- Seurat::ScaleData(object, features = features, verbose = FALSE)
    object <- Seurat::RunPCA(object, features = features, npcs = npcs,
      seed.use = options$seed, verbose = FALSE)
    object <- Seurat::FindNeighbors(object, dims = seq_len(npcs),
      k.param = min(options$k, ncol(object) - 1L), verbose = FALSE)
    object <- Seurat::FindClusters(object, resolution = options$resolution,
      algorithm = 1L, random.seed = options$seed, verbose = FALSE)
    membership <- stats::setNames(as.character(SeuratObject::Idents(object)), colnames(object))
    markers <- if (!isTRUE(options$cluster_qc) || length(unique(membership)) < 2L) data.frame() else
      Seurat::FindAllMarkers(object, assay = "RNA", slot = "data", only.pos = TRUE,
        test.use = "wilcox", min.pct = options$marker_min_pct,
        logfc.threshold = options$marker_logfc_threshold, random.seed = options$seed,
        verbose = FALSE)
    list(membership = membership, embedding = SeuratObject::Embeddings(object, "pca"),
      features = features, markers = markers, actual_npcs = npcs)
  }
  # Preserve caller RNG and save explicit unavailable diagnostics on numerical
  # failures; invalid scientific bindings above still block.
  had_rng <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_rng) prior_rng <- get(".Random.seed", envir = .GlobalEnv)
  on.exit(if (had_rng) assign(".Random.seed", prior_rng, envir = .GlobalEnv) else
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  result <- tryCatch(compute(), error = function(e) e)
  if (inherits(result, "error")) {
    record$summary <- list(status = "unavailable", reason = conditionMessage(result),
      diagnostic_only = TRUE, relaxation_allowed = FALSE)
  } else {
    record <- c(record, result)
    record$membership_hash <- .sc_run_hash(result$membership)
    metrics <- qc$metrics[match(names(result$membership), cells), , drop = FALSE]
    groups <- result$membership
    cluster_thresholds <- .sc_run_biology_thresholds(metrics, groups, options)
    global_thresholds <- .sc_run_biology_thresholds(metrics, rep("all", nrow(metrics)), options)
    sample_groups <- if ("sample" %in% names(metrics)) metrics$sample else rep("all", nrow(metrics))
    sample_thresholds <- .sc_run_biology_thresholds(metrics, sample_groups, options)
    global <- .sc_run_biology_threshold_keep(metrics, rep("all", nrow(metrics)), global_thresholds)
    sample <- .sc_run_biology_threshold_keep(metrics, sample_groups, sample_thresholds)
    cluster <- .sc_run_biology_threshold_keep(metrics, groups, cluster_thresholds)
    record$summary <- list(status = "available", diagnostic_only = TRUE,
      options = options, actual_npcs = result$actual_npcs,
      diagnostic_cells = length(eligible), excluded_from_diagnostic = length(setdiff(cells, eligible)),
      membership_hash = record$membership_hash, exclusions = policy,
      thresholds = list(global = global_thresholds, sample = sample_thresholds, cluster = cluster_thresholds),
      clusters = lapply(sort(unique(groups), method = "radix"), function(id) {
        index <- groups == id
        list(cluster_id = id, cells = sum(index),
          removed_global = sum(!global$keep[index]),
          removed_sample = sum(!sample$keep[index]),
          removed_cluster = sum(!cluster$keep[index]),
          disproportionately_removed = mean(!global$keep[index]) > .5 || mean(!sample$keep[index]) > .5,
          marker_support = .sc_run_biology_marker_support(result$markers, id, policy,
            options$relaxation_support))
      }),
      interpretation = "Diagnostic partition only; thresholds are comparisons, not executed QC. Final PCA and clustering must be recalculated after human approval.")
    if (!isTRUE(options$cluster_qc)) {
      record$summary$thresholds <- NULL
      record$summary$clusters <- NULL
    }
    if (isTRUE(options$batch_assessment)) {
      metadata <- seu[[]]
      roles <- lapply(config$context$columns, function(column)
        as.character(metadata[eligible, column]))
      factors <- roles[intersect(c("batch", "condition"), names(roles))]
      factors <- Filter(function(x) length(unique(x)) > 1L, factors)
      record$summary$batch <- tryCatch({
        rank <- if (length(factors)) .sc_run_harmony_rank(factors) else NULL
        allowed <- isTRUE(config$context$design$technical_batch) && isTRUE(rank$full_rank)
        batch <- .sc_run_batch_evidence(result$embedding, roles,
          unname(result$membership), design_supported = allowed)
        batch$design_rank <- rank
        batch
      }, error = function(e) list(schema = "scagentkit.batch-evidence.v1",
        status = "insufficient_evidence", recommendation = "none",
        reason = paste("Batch diagnostics could not be computed:", conditionMessage(e))))
    }
  }
  record$hash <- .sc_run_hash(record)
  record
}

.sc_run_biology_verify <- function(record, qc, config = NULL) {
  if (!is.list(record) || !identical(record$schema, "scagentkit.biology-diagnostic.v1") ||
      !identical(record$hash, .sc_run_hash(record[setdiff(names(record), "hash")])))
    stop("Biological diagnostic checkpoint changed; obtain a fresh review.", call. = FALSE)
  original <- qc
  original$biology_record <- NULL; original$summary$biology <- NULL
  original$evidence_hash <- .sc_run_qc_hash(original)
  if (!identical(record$qc_evidence_hash, original$evidence_hash) ||
      !identical(record$counts_hash, qc$counts_hash) ||
      !identical(record$cell_ids, qc$metrics$cell_id))
    stop("Biological diagnostics belong to different QC input.", call. = FALSE)
  if (!is.null(config) && (!identical(record$options, config$biological_diagnostics) ||
      !identical(record$context_hash, .sc_run_hash(config$context))))
    stop("Biological diagnostic settings or declared design changed.", call. = FALSE)
  if (identical(record$summary$status, "available") &&
      (!identical(record$membership_hash, .sc_run_hash(record$membership)) ||
       !identical(names(record$membership), record$diagnostic_cells) ||
       !identical(rownames(record$embedding), record$diagnostic_cells) ||
       !identical(record$summary$membership_hash, record$membership_hash)))
    stop("Diagnostic membership changed; existing drafts and approvals are stale.", call. = FALSE)
  invisible(TRUE)
}
