# Local background evidence and the executable analysis-strategy allowlist.
# These helpers do not call a provider, modify a Seurat object, or execute code
# supplied in a proposal. Only `summary` is suitable for an approved request.

.sc_run_strategy_fields <- function(value, required, optional = character(), name) {
  if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
      any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
      !all(required %in% names(value)) || length(setdiff(names(value), c(required, optional))))
    stop(name, " requires exactly its supported named fields: ",
         paste(c(required, optional), collapse = ", "), ". Arbitrary code and unsupported operations are rejected.", call. = FALSE)
  value
}

.sc_run_strategy_text <- function(value, name, limit = 4000L) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(trimws(value)) || nchar(value, type = "chars") > limit)
    stop(name, " must be one nonempty text string of at most ", limit, " characters.", call. = FALSE)
  unname(value)
}

.sc_run_strategy_array <- function(value, name) {
  if (is.list(value)) {
    if (!is.null(names(value)) || length(value) > 100L ||
        !all(vapply(value, function(x) is.character(x) && length(x) == 1L &&
          !is.na(x) && nzchar(trimws(x)) && nchar(x, type = "chars") <= 4000L, logical(1))))
      stop(name, " must be an unnamed array of at most 100 nonempty text strings.", call. = FALSE)
    value <- if (length(value)) vapply(value, identity, character(1)) else character()
  }
  if (!is.character(value) || !is.null(names(value)) || length(value) > 100L ||
      anyNA(value) || any(!nzchar(trimws(value))) || any(nchar(value, type = "chars") > 4000L))
    stop(name, " must be an unnamed text array, possibly empty.", call. = FALSE)
  unname(value)
}

.sc_run_strategy_number <- function(value, name, minimum = -Inf, maximum = Inf,
                                    integer = FALSE, open_min = FALSE, open_max = FALSE) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
      value < minimum || value > maximum || (open_min && value == minimum) ||
      (open_max && value == maximum) ||
      (integer && (value != floor(value) || abs(value) > .Machine$integer.max)))
    stop("Invalid ", name, "; use one finite ", if (integer) "integer" else "number",
         " within the supported bounds.", call. = FALSE)
  if (integer) as.integer(value) else unname(as.numeric(value))
}

.sc_run_strategy_group_counts <- function(values) {
  levels <- unique(as.character(values))
  n <- tabulate(match(as.character(values), levels), nbins = length(levels))
  lapply(seq_along(levels), function(i) list(value = levels[[i]], cells = as.integer(n[[i]])))
}

.sc_run_strategy_pairs <- function(left, right, left_name, right_name) {
  left <- as.character(left); right <- as.character(right)
  keys <- paste0(nchar(enc2utf8(left), type = "bytes"), ":", left,
                 nchar(enc2utf8(right), type = "bytes"), ":", right)
  first <- !duplicated(keys); unique_keys <- keys[first]
  counts <- tabulate(match(keys, unique_keys), nbins = length(unique_keys))
  left_values <- left[first]; right_values <- right[first]
  rows <- lapply(seq_along(counts), function(i) {
    stats::setNames(list(left_values[[i]], right_values[[i]], as.integer(counts[[i]])),
                    c(left_name, right_name, "cells"))
  })
  list(rows = rows, left = left_values, right = right_values)
}

.sc_run_strategy_batch_audit <- function(roles) {
  batch <- roles$batch
  group_role <- if (!is.null(roles$group)) "group" else if (!is.null(roles$condition)) "condition" else
    if (!is.null(roles$treatment)) "treatment" else NULL
  sample <- roles$sample
  sample_batch <- if (!is.null(sample) && !is.null(batch))
    .sc_run_strategy_pairs(sample, batch, "sample", "batch")$rows else list()
  base <- list(status = "missing_information", batch_declared = !is.null(batch),
    group_role = group_role, batch_levels = if (is.null(batch)) 0L else length(unique(batch)),
    group_levels = if (is.null(group_role)) 0L else length(unique(roles[[group_role]])),
    table = list(), sample_batch_sizes = sample_batch,
    design_rank = NULL, design_columns = NULL, full_rank = NULL,
    connected_components = NULL, complete_confounding = NULL,
    group_determined_by_batch = NULL, batch_determined_by_group = NULL,
    interpretation = "Only declared metadata facts are audited; group/condition/treatment is not inferred as technical batch, and capture is not inferred as donor.")
  if (is.null(batch)) {
    base$reason <- "No technical batch column is declared; batch correction cannot be selected automatically."
    return(base)
  }
  if (base$batch_levels < 2L) {
    base$status <- "single_batch"; base$reason <- "The declared batch has one observed level; no between-batch correction is applicable."
    return(base)
  }
  if (is.null(group_role)) {
    base$reason <- "No group/condition/treatment column is declared; biological group versus batch confounding cannot be assessed."
    return(base)
  }
  group <- roles[[group_role]]
  pairs <- .sc_run_strategy_pairs(batch, group, "batch", group_role)
  base$table <- pairs$rows
  if (base$group_levels < 2L) {
    base$status <- "single_group"; base$reason <- "One biological group is observed; between-group confounding is not assessable."
    return(base)
  }
  # Rank of intercept + batch + group indicators equals B + G minus the
  # connected components of the observed bipartite design. This avoids a dense
  # cells-by-levels design matrix and detects confounding despite distinct names.
  batches <- unique(batch); groups <- unique(group)
  b <- match(pairs$left, batches); g <- match(pairs$right, groups)
  parent <- seq_len(length(batches) + length(groups))
  find <- function(node) {
    while (parent[[node]] != node) {
      parent[[node]] <<- parent[[parent[[node]]]]
      node <- parent[[node]]
    }
    node
  }
  for (i in seq_along(b)) {
    left <- find(b[[i]]); right <- find(length(batches) + g[[i]])
    if (left != right) parent[[right]] <- left
  }
  components <- length(unique(vapply(seq_along(parent), find, integer(1))))
  base$connected_components <- components
  base$design_rank <- length(batches) + length(groups) - components
  base$design_columns <- length(batches) + length(groups) - 1L
  base$full_rank <- identical(base$design_rank, base$design_columns)
  base$group_determined_by_batch <- all(tabulate(b, nbins = length(batches)) == 1L)
  base$batch_determined_by_group <- all(tabulate(g, nbins = length(groups)) == 1L)
  base$complete_confounding <- base$group_determined_by_batch
  base$status <- if (base$complete_confounding) "complete_confounding" else
    if (!base$full_rank) "rank_deficient" else
      if (length(b) < length(batches) * length(groups)) "incomplete_overlap" else "crossed_design"
  base$reason <- if (!base$full_rank)
    "Declared batch and biological group are not independently estimable in this observed additive design; technical correction could erase biology." else
    "The observed additive batch/group design has full rank. This is a design check, not evidence that integration is scientifically necessary or beneficial."
  base
}

.sc_run_strategy_dependencies <- function() {
  packages <- c("Seurat", "SeuratObject", "harmony", "scDblFinder", "SingleCellExperiment")
  stats::setNames(lapply(packages, function(package) {
    available <- requireNamespace(package, quietly = TRUE)
    list(available = available,
         version = if (available) as.character(utils::packageVersion(package)) else NULL,
         strategy_supported = package %in% c("Seurat", "SeuratObject"))
  }), packages)
}

.sc_run_strategy_evidence <- function(seu, config, qc_evidence, cycle_record = NULL,
                                      doublet_record = NULL, mad_record = NULL,
                                      prefilter_record = NULL) {
  seu <- .sc_project_unwrap(seu)
  if (!is.list(config) || !is.list(config$context)) stop("Strategy evidence requires validated context.", call. = FALSE)
  if (!is.list(qc_evidence) || is.null(qc_evidence$evidence_hash) ||
      !identical(qc_evidence$evidence_hash, .sc_run_qc_hash(qc_evidence)))
    stop("Strategy requires intact actual QC evidence.", call. = FALSE)
  assay <- .sc_run_annotation_option(config, "assay", "RNA")
  counts_layer <- .sc_run_annotation_option(config, "counts_layer", "counts")
  normalized_layer <- .sc_run_annotation_option(config, "normalized_layer", "data")
  start_stage <- .sc_run_annotation_option(config, "start_stage", "qc")
  if (!start_stage %in% c("qc", "processed")) stop("Unsupported strategy start stage.", call. = FALSE)
  cells <- colnames(seu)
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  if (!setequal(colnames(counts), cells) || !identical(cells, qc_evidence$metrics$cell_id))
    stop("Strategy source cells differ from actual QC evidence.", call. = FALSE)
  counts <- counts[, cells, drop = FALSE]
  if (!identical(.sc_project_sparse_hash(.sc_project_matrix(counts, "Strategy counts", raw_counts = TRUE)), qc_evidence$counts_hash) ||
      !identical(rownames(counts), qc_evidence$feature_ids))
    stop("Strategy source counts/features differ from actual QC evidence.", call. = FALSE)
  prefilter_enabled <- !is.null(config$prefilter)
  if (!prefilter_enabled && !is.null(prefilter_record))
    stop("Prefilter evidence requires an explicitly enabled prefilter.", call. = FALSE)
  if (prefilter_enabled) {
    .sc_run_prefilter_verify(prefilter_record)
    if (!identical(prefilter_record$options, config$prefilter) ||
        !identical(config$prefilter, .sc_run_prefilter_options(config$prefilter)) ||
        !identical(prefilter_record$cell_ids, cells) ||
        !identical(prefilter_record$feature_ids, rownames(counts)) ||
        !identical(prefilter_record$counts_hash, qc_evidence$counts_hash) ||
        !identical(prefilter_record$context_hash, .sc_run_hash(config$context)) ||
        !identical(prefilter_record$group_columns,
          config$context$columns[names(prefilter_record$group_columns)]))
      stop("Prefilter evidence options or source scope differ from the actual QC input.", call. = FALSE)
  }
  mad_enabled <- !is.null(config$qc_mad)
  if (!mad_enabled && (!is.null(mad_record) || !is.null(qc_evidence$mad_record)))
    stop("MAD evidence requires explicitly enabled qc_mad; legacy range QC is unchanged.", call. = FALSE)
  if (mad_enabled) {
    .sc_run_mad_verify(mad_record)
    if (!identical(mad_record, qc_evidence$mad_record) ||
        !identical(mad_record$summary, qc_evidence$summary$mad) ||
        !identical(mad_record$options, config$qc_mad) ||
        !identical(config$qc_mad, .sc_run_mad_options(config$context, config$qc_mad)))
      stop("MAD evidence panel or options differ from the enabled immutable QC configuration.", call. = FALSE)
    if (!identical(mad_record$cell_ids, cells) ||
        !identical(mad_record$feature_ids, rownames(counts)) ||
        !identical(mad_record$counts_hash, qc_evidence$counts_hash) ||
        !identical(mad_record$context_hash, .sc_run_hash(config$context)) ||
        !identical(mad_record$prefilter_record, prefilter_record) ||
        !identical(mad_record$prefilter_hash, if (prefilter_enabled) prefilter_record$evidence_hash else NULL))
      stop("MAD evidence source, context or prefilter differs from the actual QC input.", call. = FALSE)
    baseline_qc <- qc_evidence
    baseline_qc$mad_record <- NULL; baseline_qc$summary$mad <- NULL
    if (!identical(mad_record$qc_evidence_hash, .sc_run_qc_hash(baseline_qc)))
      stop("MAD evidence statistics refer to different baseline QC measurements.", call. = FALSE)
  }
  cycle_enabled <- !is.null(config$cycle_diagnostics)
  if (!cycle_enabled && !is.null(cycle_record))
    stop("Cycle evidence requires explicitly enabled cycle_diagnostics.", call. = FALSE)
  if (cycle_enabled) {
    .sc_run_cycle_verify(cycle_record)
    if (!identical(cycle_record$options, config$cycle_diagnostics) ||
        !identical(config$cycle_diagnostics, .sc_run_cycle_options(config$context, config$cycle_diagnostics)))
      stop("Cycle evidence options differ from the enabled diagnostics configuration.", call. = FALSE)
    if (!identical(cycle_record$cell_ids, cells) ||
        !identical(cycle_record$feature_ids, rownames(counts)) ||
        !identical(cycle_record$counts_hash, qc_evidence$counts_hash) ||
        !identical(cycle_record$count_cell_hashes, .sc_run_cycle_cell_counts(counts, cells)) ||
        !identical(cycle_record$summary$assay, assay) ||
        !identical(cycle_record$summary$counts_layer, counts_layer))
      stop("Cycle evidence source cells, raw counts, features, or assay differ from actual QC evidence.", call. = FALSE)
  }
  doublet_enabled <- !is.null(config$doublet_diagnostics)
  if (!doublet_enabled && !is.null(doublet_record))
    stop("Doublet evidence requires explicitly enabled doublet_diagnostics.", call. = FALSE)
  if (doublet_enabled) {
    .sc_run_doublet_verify(doublet_record)
    if (!identical(doublet_record$options, config$doublet_diagnostics) ||
        !identical(config$doublet_diagnostics,
          .sc_run_doublet_options(config$context, config$doublet_diagnostics)))
      stop("Doublet evidence options differ from the enabled diagnostics configuration.", call. = FALSE)
    if (!identical(doublet_record$cell_ids, cells) ||
        !identical(doublet_record$feature_ids, rownames(counts)) ||
        !identical(doublet_record$counts_hash, qc_evidence$counts_hash) ||
        !identical(doublet_record$count_cell_hashes, .sc_run_cycle_cell_counts(counts, cells)) ||
        !identical(doublet_record$summary$assay, assay) ||
        !identical(doublet_record$summary$counts_layer, counts_layer))
      stop("Doublet evidence source cells, raw counts, features, or assay differ from actual QC evidence.", call. = FALSE)
    if (!identical(doublet_record$capture_map,
        .sc_run_doublet_captures(seu, config$doublet_diagnostics, cells)))
      stop("Doublet evidence capture/loading-unit assignments differ from declared source metadata.", call. = FALSE)
    if (!identical(doublet_record$prefilter_record, prefilter_record) ||
        !identical(doublet_record$prefilter_hash, if (prefilter_enabled) prefilter_record$evidence_hash else NULL))
      stop("Doublet evidence pre-score cohort differs from the enabled prefilter.", call. = FALSE)
  }
  context <- config$context; columns <- context$columns
  if (is.null(columns)) columns <- list()
  metadata <- seu[[]]
  roles <- list()
  for (role in names(columns)) {
    if (!role %in% c("sample", "qc_group", "capture", "batch", "group", "condition", "treatment", "donor"))
      stop("Unsupported strategy metadata role: ", role, ".", call. = FALSE)
    column <- columns[[role]]
    .sc_project_string(column, paste0("context$columns$", role))
    if (sum(names(metadata) == column) != 1L)
      stop("Declared strategy column is missing or ambiguous: ", column, ".", call. = FALSE)
    values <- metadata[cells, column]
    if (!(is.atomic(values) || is.factor(values)) || anyNA(values) ||
        any(!nzchar(as.character(values))) || (is.numeric(values) && any(!is.finite(values))))
      stop("Declared strategy metadata must be complete finite atomic values: ", role, ".", call. = FALSE)
    roles[[role]] <- as.character(values)
  }
  if (mad_enabled) {
    expected_groups <- .sc_run_mad_groups(seu, config$qc_mad, cells)
    if (!identical(mad_record$group_map, expected_groups))
      stop("MAD QC grouping assignments differ from explicitly declared source metadata.", call. = FALSE)
  }
  if (prefilter_enabled) {
    for (role in intersect(c("sample", "qc_group", "capture"), names(prefilter_record$metrics))) {
      expected <- if (identical(role, "capture") && is.null(roles$capture) && doublet_enabled)
        unname(doublet_record$capture_map) else roles[[role]]
      if (!identical(prefilter_record$metrics[[role]], expected))
        stop("Prefilter grouping assignments differ from declared source metadata.", call. = FALSE)
    }
  }
  detection <- counts > 0
  background <- list(species = context$species, tissue = context$tissue,
    columns = columns, design = context$design, research_goal = context$research_goal, notes = context$notes,
    provenance = "user_declared_facts; absence is retained and model inferences cannot overwrite facts")
  missing_roles <- setdiff(c("sample", "capture", "batch", "group"), names(columns))
  missing <- c(setdiff(c("species", "tissue", "design", "research_goal"), names(context)),
    if (length(missing_roles)) paste0("columns.", missing_roles) else character())
  for (name in intersect(c("species", "tissue", "design", "research_goal"), names(context)))
    if (is.null(context[[name]])) missing <- c(missing, name)
  normalized <- tryCatch(.sc_project_layer(seu, assay, normalized_layer), error = function(e) NULL)
  processed <- identical(start_stage, "processed")
  if (processed && (is.null(normalized) || !setequal(colnames(normalized), cells)))
    stop("Processed strategy reuse requires the declared exact normalized layer for every source cell.", call. = FALSE)
  cluster_column <- .sc_run_annotation_option(config, "cluster_column", "seurat_clusters")
  if (processed && (sum(names(metadata) == cluster_column) != 1L ||
      anyNA(metadata[cells, cluster_column]) || any(!nzchar(as.character(metadata[cells, cluster_column])))))
    stop("Processed strategy reuse requires the declared complete literal cluster column.", call. = FALSE)
  audit <- .sc_run_strategy_batch_audit(roles)
  # Aggregate tables are explicit evidence; immutable exact cell values remain
  # local. Size limits are handled by the existing approved request boundary.
  summary <- list(schema = "scagentkit.strategy.evidence.v1", start_stage = start_stage,
    background_facts = background, missing_facts = unique(missing), declared_roles = columns,
    role_sizes = lapply(roles[intersect(c("sample", "qc_group", "capture", "batch", "group", "condition", "treatment"), names(roles))], .sc_run_strategy_group_counts),
    quality = qc_evidence$summary,
    input = list(cells = length(cells), features = nrow(counts),
      expressed_features = sum(Matrix::rowSums(detection) > 0), assay = assay,
      counts_layer = counts_layer, normalized_layer = normalized_layer,
      normalized_layer_available = !is.null(normalized), sparse_counts = inherits(counts, "sparseMatrix"),
      existing_reductions = names(seu@reductions),
      reused_cluster_count = if (processed) length(unique(as.character(metadata[cells, cluster_column]))) else NULL,
      processed_reason = if (processed) config$processed_reason else NULL),
    batch_group_audit = audit, dependencies = .sc_run_strategy_dependencies(),
    capabilities = list(qc = if (processed) "reuse_only" else if (mad_enabled) "typed_mad_preset" else "typed_range",
      normalization = if (processed) "reuse_only" else "LogNormalize",
      pcs = if (processed) "reuse_only" else c("fixed", "computed_variance", "computed_top50"),
      batch = if (processed) c("none", "manual") else c("none", "manual", "harmony"), clustering = if (processed) "reuse_only" else "explicit_resolution_with_optional_local_sweep",
      umap = if (processed) "reuse_only" else "explicit_local_umap",
      unsupported = c("harmony_execution", "cycle_scoring", "cycle_regression", "cycling_cell_deletion", "doublet_scoring", "doublet_removal", "subclustering")),
    interpretation = c("User facts and measured metadata are immutable evidence; proposed inferences are separate statements, not established facts.",
      "A PC variance threshold is a descriptive selection policy, not a proof of biological resolution.",
      "Cycle regression is not deletion of cycling cells. A doublet score is not permission to remove cells.",
      "Only the aggregate summary may enter a separately approved provider request. Exact cell IDs and expression detection remain local."))
  if (!processed) {
    summary$capabilities$unsupported <- setdiff(summary$capabilities$unsupported, "harmony_execution")
    summary$dependencies$harmony$strategy_supported <- TRUE
    summary$harmony_dependency <- list(available_at_evidence = summary$dependencies$harmony$available,
      version_at_evidence = summary$dependencies$harmony$version,
      policy = "Optional runtime dependency; absence is repairable before the explicitly approved Harmony stage and is not a permanent design gate.")
    summary$interpretation <- c(summary$interpretation,
      "Harmony is available only with explicit supported parameters and an eligible reviewed technical design; sample/donor/capture/treatment roles are not interchangeable.",
      "computed_top50 uses variance of the first min(50, actually computed PCs); 80/85% are finite empirical policies, not total gene variance or a universal optimum. Actual diagnostics are deferred until approved QC and PCA complete.")
  }
  if (prefilter_enabled) summary$prefilter <- prefilter_record$summary
  if (mad_enabled) {
    summary$qc_mad <- mad_record$summary
    summary$capabilities$qc_presets <- vapply(mad_record$summary$presets, `[[`, character(1), "preset_id")
    summary$interpretation <- c(summary$interpretation,
      "QC groups are declared independently of capture/loading units and donors; one central strategy approval selects one named preset for the complete panel.",
      "MAD candidates are descriptive software policies, not universal biological optima. High RNA, ribosomal and haemoglobin diagnostics do not authorize deletion.")
  }
  if (cycle_enabled) {
    summary$cycle_diagnostics <- cycle_record$summary
    summary$capabilities$cycle <- if (processed) c("cycle_scoring", "none") else
      c("cycle_scoring", "none", "full", "difference")
    summary$capabilities$unsupported <- setdiff(summary$capabilities$unsupported,
      if (processed) "cycle_scoring" else c("cycle_scoring", "cycle_regression"))
  }
  if (doublet_enabled) {
    summary$doublet_diagnostics <- doublet_record$summary
    scored <- identical(doublet_record$summary$status, "available")
    summary$capabilities$doublet <- if (!scored) "keep" else if (processed)
      c("doublet_scoring", "keep") else c("doublet_scoring", "keep", "remove_predicted")
    if (scored) {
      summary$capabilities$unsupported <- setdiff(summary$capabilities$unsupported,
        if (processed) "doublet_scoring" else c("doublet_scoring", "doublet_removal"))
      for (package in c("scDblFinder", "SingleCellExperiment"))
        summary$dependencies[[package]]$strategy_supported <- TRUE
    }
  }
  evidence <- list(summary = summary, qc = qc_evidence,
    private = list(cell_ids = cells, feature_ids = rownames(counts),
      feature_detection = detection, roles = roles,
      reused_cluster_column = if (processed) cluster_column else NULL,
      reused_clusters = if (processed) as.character(metadata[cells, cluster_column]) else NULL))
  if (cycle_enabled) evidence$private$cycle_record <- cycle_record
  if (doublet_enabled) evidence$private$doublet_record <- doublet_record
  if (prefilter_enabled) evidence$private$prefilter_record <- prefilter_record
  if (mad_enabled) evidence$private$mad_record <- mad_record
  evidence$evidence_hash <- .sc_run_hash(evidence)
  evidence
}

.sc_run_strategy_validate <- function(proposal, evidence) {
  if (!is.list(evidence) || is.null(evidence$summary) || is.null(evidence$qc) || is.null(evidence$private))
    stop("Strategy evidence is absent or malformed.", call. = FALSE)
  if (!is.null(evidence$evidence_hash) &&
      !identical(evidence$evidence_hash, .sc_run_hash(evidence[setdiff(names(evidence), "evidence_hash")])))
    stop("Strategy evidence changed; obtain a fresh proposal and approval.", call. = FALSE)
  prefilter_enabled <- !is.null(evidence$summary$prefilter)
  if (prefilter_enabled != !is.null(evidence$private$prefilter_record))
    stop("Enabled prefilter requires intact local evidence and its aggregate summary.", call. = FALSE)
  if (prefilter_enabled) {
    prefilter <- evidence$private$prefilter_record
    .sc_run_prefilter_verify(prefilter)
    if (!identical(evidence$summary$prefilter, prefilter$summary) ||
        !identical(prefilter$cell_ids, evidence$private$cell_ids) ||
        !identical(prefilter$feature_ids, evidence$private$feature_ids) ||
        !identical(prefilter$counts_hash, evidence$qc$counts_hash) ||
        !identical(prefilter$context, evidence$summary$background_facts[names(prefilter$context)]) ||
        !identical(prefilter$group_columns,
          evidence$summary$declared_roles[names(prefilter$group_columns)]))
      stop("Prefilter evidence summary or source differs from the strategy input.", call. = FALSE)
    for (role in intersect(c("sample", "qc_group", "capture"), names(prefilter$metrics))) {
      expected <- if (identical(role, "capture") && is.null(evidence$private$roles$capture) &&
          !is.null(evidence$private$doublet_record))
        unname(evidence$private$doublet_record$capture_map) else evidence$private$roles[[role]]
      if (!identical(prefilter$metrics[[role]], expected))
        stop("Prefilter grouping assignments differ from declared strategy metadata.", call. = FALSE)
    }
  }
  mad_enabled <- identical(evidence$summary$capabilities$qc, "typed_mad_preset") ||
    !is.null(evidence$summary$qc_mad)
  if (mad_enabled != !is.null(evidence$summary$qc_mad) ||
      mad_enabled != !is.null(evidence$private$mad_record) ||
      mad_enabled != !is.null(evidence$qc$mad_record) ||
      mad_enabled != !is.null(evidence$qc$summary$mad))
    stop("Enabled MAD QC requires intact local panel evidence and its aggregate summaries.", call. = FALSE)
  if (mad_enabled) {
    mad <- evidence$private$mad_record
    .sc_run_mad_verify(mad)
    if (!identical(mad, evidence$qc$mad_record) ||
        !identical(evidence$summary$qc_mad, mad$summary) ||
        !identical(evidence$qc$summary$mad, mad$summary) ||
        !identical(evidence$summary$quality, evidence$qc$summary))
      stop("MAD panel summary differs from its verified local evidence.", call. = FALSE)
    if (!identical(mad$cell_ids, evidence$private$cell_ids) ||
        !identical(mad$feature_ids, evidence$private$feature_ids) ||
        !identical(mad$counts_hash, evidence$qc$counts_hash) ||
        !identical(mad$context_hash, .sc_run_hash(mad$context)) ||
        !identical(mad$context, evidence$summary$background_facts[names(mad$context)]) ||
        !identical(mad$prefilter_record, evidence$private$prefilter_record) ||
        !identical(mad$prefilter_hash, if (prefilter_enabled) prefilter$evidence_hash else NULL))
      stop("MAD panel source, context or prefilter differs from the strategy input.", call. = FALSE)
    grouping <- mad$options$grouping
    groups <- if (identical(grouping$method, "column"))
      stats::setNames(enc2utf8(unname(evidence$private$roles[[grouping$declared_role]])), evidence$private$cell_ids) else
      stats::setNames(enc2utf8(rep(grouping$id, length(evidence$private$cell_ids))), evidence$private$cell_ids)
    if (!identical(mad$group_map, groups))
      stop("MAD QC grouping assignments differ from declared strategy metadata.", call. = FALSE)
  }
  cycle_enabled <- !is.null(evidence$summary$cycle_diagnostics)
  if (cycle_enabled != !is.null(evidence$private$cycle_record))
    stop("Enabled cycle diagnostics require intact local cycle evidence and its aggregate summary.", call. = FALSE)
  if (cycle_enabled) {
    .sc_run_cycle_verify(evidence$private$cycle_record)
    if (!identical(evidence$summary$cycle_diagnostics, evidence$private$cycle_record$summary))
      stop("Cycle diagnostics summary differs from its verified local evidence.", call. = FALSE)
    if (!identical(evidence$private$cycle_record$cell_ids, evidence$private$cell_ids) ||
        !identical(evidence$private$cycle_record$feature_ids, evidence$private$feature_ids) ||
        !identical(evidence$private$cycle_record$counts_hash, evidence$qc$counts_hash))
      stop("Cycle evidence source differs from the strategy's actual QC evidence.", call. = FALSE)
  }
  doublet_enabled <- !is.null(evidence$summary$doublet_diagnostics)
  if (doublet_enabled != !is.null(evidence$private$doublet_record))
    stop("Enabled doublet diagnostics require intact local doublet evidence and its aggregate summary.", call. = FALSE)
  if (doublet_enabled) {
    .sc_run_doublet_verify(evidence$private$doublet_record)
    if (!identical(evidence$summary$doublet_diagnostics, evidence$private$doublet_record$summary))
      stop("Doublet diagnostics summary differs from its verified local evidence.", call. = FALSE)
    if (!identical(evidence$private$doublet_record$cell_ids, evidence$private$cell_ids) ||
        !identical(evidence$private$doublet_record$feature_ids, evidence$private$feature_ids) ||
        !identical(evidence$private$doublet_record$counts_hash, evidence$qc$counts_hash))
      stop("Doublet evidence source differs from the strategy's actual QC evidence.", call. = FALSE)
    if (!identical(evidence$private$doublet_record$prefilter_record, evidence$private$prefilter_record) ||
        !identical(evidence$private$doublet_record$prefilter_hash, if (prefilter_enabled) prefilter$evidence_hash else NULL))
      stop("Doublet scoring prefilter differs from the strategy's declared pre-score cohort.", call. = FALSE)
    if (identical(evidence$private$doublet_record$options$capture$method, "column") &&
        !identical(evidence$private$doublet_record$capture_map,
          stats::setNames(evidence$private$roles$capture, evidence$private$cell_ids)))
      stop("Doublet evidence capture/loading-unit assignments differ from the strategy's declared source metadata.", call. = FALSE)
  }
  proposal <- .sc_run_strategy_fields(proposal,
    c("schema", "rationale", "risks", "inferences", "qc", "analysis", "pcs", "batch", "clustering", "umap"),
    optional = c(if (cycle_enabled) "cycle" else character(),
      if (doublet_enabled) "doublet" else character()), name = "Strategy proposal")
  if (!identical(proposal$schema, "scagentkit.strategy.v1")) stop("Unsupported strategy proposal schema.", call. = FALSE)
  rationale <- .sc_run_strategy_text(proposal$rationale, "strategy$rationale")
  risks <- .sc_run_strategy_array(proposal$risks, "strategy$risks")
  inferences <- .sc_run_strategy_array(proposal$inferences, "strategy$inferences")
  batch <- .sc_run_strategy_fields(proposal$batch, c("method", "reason"),
    optional = c("group_by_vars", "theta", "lambda", "sigma", "max_iter", "nclust"), name = "strategy$batch")
  method <- .sc_run_strategy_text(batch$method, "strategy$batch$method", 80L)
  if (!method %in% c("none", "manual", "harmony"))
    stop("Batch method '", method, "' is unsupported in the coordinated strategy. Use none, manual, or explicit supported Harmony parameters.", call. = FALSE)
  processed <- identical(evidence$summary$start_stage, "processed")
  qc_validated <- NULL
  if (processed) {
    for (field in c("qc", "analysis", "pcs", "clustering", "umap"))
      if (!is.null(proposal[[field]])) stop("Processed entry reuses existing analysis: strategy$", field, " must be explicit NULL.", call. = FALSE)
    analysis <- pcs <- clustering <- umap <- NULL
    keep <- evidence$private$cell_ids
  } else {
    if (!identical(evidence$summary$input$counts_layer, "counts"))
      stop("Raw coordinated strategy requires the exact canonical counts_layer='counts'; explicitly prepare alternate source layers before processed reuse.", call. = FALSE)
    qc_schema <- if (is.list(proposal$qc)) proposal$qc$schema else NULL
    if (mad_enabled && !isTRUE(qc_schema %in% c("scagentkit.qc.mad.v1", "scagentkit.qc.rules.v1")))
      stop("Enabled qc_mad requires an explicit scagentkit.qc.mad.v1 preset choice or scagentkit.qc.rules.v1 combination; legacy ranges cannot silently change meaning.", call. = FALSE)
    if (!mad_enabled && identical(qc_schema, "scagentkit.qc.mad.v1"))
      stop("MAD presets require explicitly enabled qc_mad and an intact local panel; legacy range QC remains unchanged.", call. = FALSE)
    qc_validated <- .sc_run_qc_validate(proposal$qc, evidence$qc)
    keep <- qc_validated$keep_cells
  }
  # QC remains a separately reusable checkpoint and its preview always reports
  # the pure QC decision. Doublet removal is an explicit additional intersection,
  # evaluated before any analysis or cycle-regression applicability check.
  qc_keep <- keep
  doublet <- NULL
  if (doublet_enabled) {
    choice <- if ("doublet" %in% names(proposal)) proposal$doublet else
      list(method = "keep", reason = "Diagnostics only; no removal requested.")
    doublet <- .sc_run_doublet_validate_choice(choice,
      evidence$private$doublet_record, qc_keep,
      cycle_record = if (cycle_enabled) evidence$private$cycle_record else NULL)
    if (processed && !identical(doublet$method, "keep"))
      stop("Processed entry reuses its analysis foundation; doublet removal requires a raw entry and rebuilt downstream analysis.", call. = FALSE)
    keep <- doublet$keep_cells
    if (!identical(keep, qc_keep[qc_keep %in% keep]) ||
        !identical(doublet$removed_cells, qc_keep[!qc_keep %in% keep]))
      stop("Doublet choice must preserve literal QC cell order and report its exact complementary removal set.", call. = FALSE)
  }
  if (!processed) {
    retained <- length(keep)
    # The current adapter uses a fixed 20-neighbor graph; do not silently clip.
    if (retained < 21L) stop("The supported strategy graph requires at least 21 projected retained cells for k.param=20; revise QC or doublet removal, or supply a processed object.", call. = FALSE)
    indices <- match(keep, evidence$private$cell_ids)
    if (anyNA(indices)) stop("Projected strategy cells do not match local evidence.", call. = FALSE)
    expressed <- sum(Matrix::rowSums(evidence$private$feature_detection[, indices, drop = FALSE]) > 0)
    if (expressed < 3L) stop("Fewer than three genes are actually expressed after the proposed cell selection; standard strategy analysis is not applicable.", call. = FALSE)
    analysis <- .sc_run_strategy_fields(proposal$analysis,
      c("normalization_method", "scale_factor", "nfeatures", "npcs", "seed"), name = "strategy$analysis")
    if (!identical(analysis$normalization_method, "LogNormalize"))
      stop("Coordinated strategy supports normalization_method='LogNormalize' only; other methods require explicit external preparation.", call. = FALSE)
    analysis <- list(normalization_method = "LogNormalize",
      scale_factor = .sc_run_strategy_number(analysis$scale_factor, "analysis$scale_factor", 0, open_min = TRUE),
      nfeatures = .sc_run_strategy_number(analysis$nfeatures, "analysis$nfeatures", 3, min(evidence$summary$input$features, expressed), integer = TRUE),
      npcs = .sc_run_strategy_number(analysis$npcs, "analysis$npcs", 2, integer = TRUE),
      seed = .sc_run_strategy_number(analysis$seed, "analysis$seed", 0, .Machine$integer.max, integer = TRUE))
    if (analysis$npcs >= min(analysis$nfeatures, retained))
      stop("Requested npcs must be smaller than both requested HVGs and projected retained cells; implicit clipping is not supported.", call. = FALSE)
    pcs <- .sc_run_strategy_fields(proposal$pcs, "method", c("ndim", "threshold"), "strategy$pcs")
    if (identical(pcs$method, "fixed")) {
      .sc_run_strategy_fields(pcs, c("method", "ndim"), name = "strategy$pcs fixed")
      pcs <- list(method = "fixed", ndim = .sc_run_strategy_number(pcs$ndim, "pcs$ndim", 2, analysis$npcs, integer = TRUE))
    } else if (identical(pcs$method, "computed_variance")) {
      .sc_run_strategy_fields(pcs, c("method", "threshold"), name = "strategy$pcs computed_variance")
      pcs <- list(method = "computed_variance", threshold = .sc_run_strategy_number(pcs$threshold,
        "pcs$threshold", 0, 1, open_min = TRUE, open_max = TRUE))
    } else if (identical(pcs$method, "computed_top50")) {
      .sc_run_strategy_fields(pcs, c("method", "threshold"), name = "strategy$pcs computed_top50")
      threshold <- .sc_run_strategy_number(pcs$threshold, "pcs$threshold", 0, 1, open_min = TRUE, open_max = TRUE)
      if (!threshold %in% c(.80, .85))
        stop("computed_top50 supports exactly threshold=0.80 or 0.85; arbitrary thresholds are not silently rounded.", call. = FALSE)
      pcs <- list(method = "computed_top50", threshold = threshold)
    } else stop("Unsupported PC selection method; use fixed, computed_variance or computed_top50 with its exact typed parameters.", call. = FALSE)
    clustering <- .sc_run_strategy_fields(proposal$clustering, "resolution", "diagnostic_resolutions", "strategy$clustering")
    resolution <- .sc_run_strategy_number(clustering$resolution, "clustering$resolution", 0, 2, open_min = TRUE)
    diagnostics <- clustering$diagnostic_resolutions
    if (is.list(diagnostics) && is.null(names(diagnostics)) && length(diagnostics) &&
        all(vapply(diagnostics, function(x) is.numeric(x) && length(x) == 1L, logical(1))))
      diagnostics <- unlist(diagnostics, use.names = FALSE)
    if (!is.null(diagnostics) && (!is.numeric(diagnostics) || !length(diagnostics) || length(diagnostics) > 5L ||
        any(!is.finite(diagnostics)) || any(diagnostics <= 0 | diagnostics > 2) || anyDuplicated(diagnostics)))
      stop("diagnostic_resolutions must be at most five unique finite resolutions in (0,2], or omitted/NULL.", call. = FALSE)
    clustering <- list(resolution = resolution, diagnostic_resolutions = if (is.null(diagnostics)) NULL else sort(unname(diagnostics)))
    umap <- .sc_run_strategy_fields(proposal$umap, c("run", "n_neighbors"), name = "strategy$umap")
    if (!is.logical(umap$run) || length(umap$run) != 1L || is.na(umap$run))
      stop("strategy$umap$run must be TRUE or FALSE.", call. = FALSE)
    umap <- list(run = umap$run, n_neighbors = .sc_run_strategy_number(umap$n_neighbors,
      "umap$n_neighbors", 3, retained - 1L, integer = TRUE))
    if (!identical(evidence$summary$input$normalized_layer, "data"))
      stop("Raw strategy preparation writes the explicit 'data' layer; select normalized_layer='data'.", call. = FALSE)
    for (package in c("Seurat", "SeuratObject"))
      if (!isTRUE(evidence$summary$dependencies[[package]]$available))
        stop("Required dependency '", package, "' is unavailable; strategy analysis cannot execute.", call. = FALSE)
  }
  cycle <- NULL
  if (cycle_enabled) {
    choice <- if ("cycle" %in% names(proposal)) proposal$cycle else
      list(method = "none", reason = "Cycle diagnostics only; no regression was requested.")
    cycle <- .sc_run_cycle_validate_choice(choice, evidence$private$cycle_record, keep)
    if (processed && !identical(cycle$method, "none"))
      stop("Processed entry reuses its analysis foundation; cycle regression requires a raw entry and a rebuilt basis.", call. = FALSE)
  }
  role_indices <- match(keep, evidence$private$cell_ids)
  projected_roles <- lapply(evidence$private$roles, function(values) values[role_indices])
  harmony <- .sc_run_harmony_choice(batch, evidence, projected_roles, processed)
  batch <- harmony$choice
  audit <- .sc_run_strategy_batch_audit(projected_roles)
  warnings <- character()
  for (role in c("sample", "capture", "batch"))
    if (is.null(projected_roles[[role]])) warnings <- c(warnings, paste0("No ", role, " role was declared; its sample-specific or technical effects are not assessable and are not inferred."))
  if (is.null(projected_roles$group) && is.null(projected_roles$condition) && is.null(projected_roles$treatment))
    warnings <- c(warnings, "No biological group/condition/treatment role was declared; group-batch confounding cannot be assessed.")
  if (isTRUE(audit$complete_confounding) || identical(audit$full_rank, FALSE))
    warnings <- c(warnings, audit$reason)
  if (!isTRUE(evidence$summary$background_facts$design$technical_batch))
    warnings <- c(warnings, "Technical batch provenance has not been explicitly declared TRUE; no technical correction is inferred.")
  canonical <- list(schema = "scagentkit.strategy.v1", rationale = rationale,
    risks = risks, inferences = inferences, qc = if (processed) NULL else qc_validated$proposal,
    analysis = analysis, pcs = pcs, batch = batch, clustering = clustering, umap = umap)
  if (cycle_enabled) canonical$cycle <- cycle$choice
  if (doublet_enabled) canonical$doublet <- doublet$choice
  blockers <- harmony$blockers
  qc_rules <- if (processed) NULL else if (identical(qc_validated$proposal$schema, "scagentkit.qc.rules.v1"))
    qc_validated$proposal[c("schema", "remove_if", "rules")] else if (mad_enabled)
    qc_validated$proposal[c("schema", "preset_id", "panel_hash")] else qc_validated$proposal$filters
  qc_hash <- .sc_run_hash(list(counts_hash = evidence$qc$counts_hash,
    evidence_hash = evidence$qc$evidence_hash, rules = qc_rules,
    retained_cell_ids = qc_keep, start_stage = evidence$summary$start_stage))
  if (doublet_enabled) {
    doublet_hash <- .sc_run_hash(list(evidence_hash = doublet$evidence_hash,
      method = doublet$method))
    selection_hash <- .sc_run_hash(list(qc = qc_hash,
      doublet_evidence_hash = doublet$evidence_hash, method = doublet$method,
      retained_cell_ids = keep))
  }
  if (cycle_enabled || doublet_enabled) {
    preprocess_inputs <- list(qc = qc_hash,
      analysis = if (processed) NULL else analysis[setdiff(names(analysis), "npcs")],
      assay = evidence$summary$input$assay, counts_layer = evidence$summary$input$counts_layer,
      normalized_layer = evidence$summary$input$normalized_layer,
      processed_clusters = if (processed) evidence$private$reused_clusters else NULL)
    if (doublet_enabled) {
      preprocess_inputs$qc <- NULL
      preprocess_inputs <- c(list(selection = selection_hash), preprocess_inputs)
    }
    preprocess_hash <- .sc_run_hash(preprocess_inputs)
    basis_inputs <- list(preprocess = preprocess_hash,
      npcs = if (processed) NULL else analysis$npcs)
    if (cycle_enabled) {
      cycle_hash <- .sc_run_hash(list(evidence_hash = cycle$evidence_hash, method = cycle$method))
      basis_inputs$cycle <- cycle_hash
    }
    basis_hash <- .sc_run_hash(basis_inputs)
  } else {
    basis_hash <- .sc_run_hash(list(qc = qc_hash, analysis = analysis,
      assay = evidence$summary$input$assay, counts_layer = evidence$summary$input$counts_layer,
      normalized_layer = evidence$summary$input$normalized_layer,
      processed_clusters = if (processed) evidence$private$reused_clusters else NULL))
  }
  pcs_hash <- .sc_run_hash(list(basis = basis_hash, pcs = pcs))
  # Preserve the none/manual dependency payload. Harmony binds its complete
  # scientific parameters and exact projected declared metadata/design; reasons
  # authorize and explain the choice but do not alter the computation.
  batch_inputs <- list(pcs = pcs_hash, method = batch$method)
  if (identical(batch$method, "harmony")) {
    metadata_roles <- intersect(c("sample", "donor", "batch", "group", "condition", "treatment"), names(projected_roles))
    batch_inputs$parameters <- batch[setdiff(names(batch), "reason")]
    batch_inputs$metadata <- projected_roles[metadata_roles]
    batch_inputs$declared_roles <- evidence$summary$declared_roles[metadata_roles]
    batch_inputs$design <- evidence$summary$background_facts$design
  }
  batch_hash <- .sc_run_hash(batch_inputs)
  neighbors_hash <- .sc_run_hash(list(pcs = pcs_hash, batch = batch_hash, k_param = 20L))
  hashes <- list(qc = qc_hash, basis = basis_hash, pcs = pcs_hash, batch = batch_hash,
    neighbors = neighbors_hash,
    clustering = .sc_run_hash(list(neighbors = neighbors_hash, clustering = clustering)),
    umap = .sc_run_hash(list(neighbors = neighbors_hash, umap = umap)))
  if (cycle_enabled || doublet_enabled) {
    extra_hashes <- list()
    if (doublet_enabled) extra_hashes <- list(selection = selection_hash, doublet = doublet_hash)
    extra_hashes$preprocess <- preprocess_hash
    if (cycle_enabled) extra_hashes$cycle <- cycle_hash
    hashes <- c(hashes["qc"], extra_hashes, hashes[setdiff(names(hashes), "qc")])
  }
  validated <- list(proposal = canonical, qc_validated = qc_validated, executable = isTRUE(harmony$executable),
    blockers = blockers,
    applicability = list(start_stage = evidence$summary$start_stage, retained_cells = length(keep),
      expressed_features_after_qc = if (processed) evidence$summary$input$expressed_features else expressed,
      batch_group_audit = audit, warnings = unique(warnings),
      user_facts = evidence$summary$background_facts, inferences = inferences,
      unsupported = evidence$summary$capabilities$unsupported,
      processed_reuse = processed), dependency_hashes = hashes)
  if (identical(batch$method, "harmony")) {
    validated$harmony <- harmony
    validated$applicability$harmony <- harmony$applicability
    validated$applicability$harmony_audit <- harmony$audit
  }
  if (cycle_enabled) {
    validated$cycle <- cycle
    validated$applicability$cycle <- cycle$applicability
  }
  if (mad_enabled) {
    validated$applicability$qc_mad <- list(panel_hash = evidence$private$mad_record$panel_hash,
      evidence_hash = evidence$private$mad_record$evidence_hash,
      preset_id = if (processed) NULL else if (identical(qc_validated$proposal$schema, "scagentkit.qc.rules.v1"))
        qc_validated$summary$preset_id else qc_validated$proposal$preset_id,
      impact = if (processed) NULL else qc_validated$summary,
      retention = if (processed) NULL else qc_validated$retention,
      stage_counts = c(evidence$private$mad_record$summary$stage_counts,
        list(post_qc_cells = length(qc_keep), final_selected_cells = length(keep))))
  }
  if (doublet_enabled) {
    validated$doublet <- doublet
    validated$selected_cells <- keep
    # Exact IDs are deliberately local review evidence. Only the diagnostic
    # aggregate summary above is eligible for an approved provider request.
    impact <- doublet$impact
    impact$method <- doublet$method
    impact$evidence_hash <- doublet$evidence_hash
    impact$selection_hash <- selection_hash
    impact$qc_keep_cell_ids <- qc_keep
    impact$selected_cell_ids <- keep
    impact$removed_cell_ids <- doublet$removed_cells
    impact$scoring_status <- evidence$private$doublet_record$summary$status
    impact$processed_reuse <- processed
    validated$applicability$doublet <- impact
  }
  validated
}
