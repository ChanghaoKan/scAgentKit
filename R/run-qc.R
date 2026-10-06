# Input and typed QC operations for the resumable coordinator. All assay
# access uses the shared exact Seurat 5 public-layer helpers. Per-cell records
# remain local; only `summary` is suitable for the approved AI preview.
.sc_run_context <- function(context, seu) {
  if (is.null(context)) context <- list()
  if (!is.list(context) || (length(context) &&
      (is.null(names(context)) || anyNA(names(context)) ||
       any(!nzchar(names(context))) || anyDuplicated(names(context)))))
    .sc_project_fail("`context` must be a named list with unique keys.")
  unknown <- setdiff(names(context), c("species", "tissue", "columns", "notes", "design", "research_goal"))
  if (length(unknown))
    .sc_project_fail(paste0("Unsupported context fields: ", paste(unknown, collapse = ", "), "."))
  for (field in c("species", "tissue", "notes", "research_goal"))
    if (!is.null(context[[field]])) .sc_project_string(context[[field]], paste0("context$", field))
  columns <- context$columns
  if (is.null(columns)) columns <- list()
  if (is.character(columns)) columns <- as.list(columns)
  if (!is.list(columns) || (length(columns) &&
      (is.null(names(columns)) || anyNA(names(columns)) ||
       any(!nzchar(names(columns))) || anyDuplicated(names(columns)))))
    .sc_project_fail("`context$columns` must map unique sample/qc_group/capture/batch/condition/donor roles to metadata column names.")
  unknown <- setdiff(names(columns), c("sample", "qc_group", "capture", "batch", "condition", "group", "donor", "treatment"))
  if (length(unknown)) .sc_project_fail(paste0("Unsupported context column roles: ", paste(unknown, collapse = ", "), "."))
  metadata <- seu[[]]
  .sc_project_ids(rownames(metadata), "Metadata cell IDs")
  if (!setequal(rownames(metadata), colnames(seu)))
    .sc_project_fail("Input metadata must cover every object cell exactly.")
  for (role in names(columns)) {
    column <- columns[[role]]
    .sc_project_string(column, paste0("context$columns$", role))
    if (sum(names(metadata) == column) != 1L)
      .sc_project_fail(paste0("Declared ", role, " metadata column `", column, "` is missing or ambiguous."))
    values <- metadata[colnames(seu), column]
    if (!(is.character(values) || is.factor(values) || is.numeric(values) || is.logical(values)) ||
        anyNA(values) || any(!nzchar(as.character(values))) ||
        (is.numeric(values) && any(!is.finite(values))))
      .sc_project_fail(paste0("Declared ", role, " metadata must contain finite, nonempty, nonmissing atomic values for every cell."))
  }
  result <- list(species = .sc_run_species(context$species, allow_missing = TRUE), tissue = context$tissue,
       columns = columns, notes = context$notes)
  if (!is.null(context$design)) result$design <- .sc_run_strategy_design(context$design)
  if (!is.null(context$research_goal)) result$research_goal <- context$research_goal
  result
}

.sc_run_input <- function(input, context = list(), assay = "RNA", counts_layer = "counts",
                          start_stage = "qc", processed_reason = NULL,
                          cluster_column = "seurat_clusters", normalized_layer = "data") {
  .sc_project_string(assay, "assay")
  .sc_project_string(counts_layer, "counts_layer")
  if (!is.character(start_stage) || length(start_stage) != 1L ||
      is.na(start_stage) || !start_stage %in% c("qc", "processed"))
    .sc_project_fail("`start_stage` must be 'qc' or 'processed'.")
  if (grepl("^(data|scale\\.data|normalized)(\\.|$)", counts_layer, ignore.case = TRUE))
    .sc_project_fail("Input requires genuine raw counts; normalized/data/scale.data layers cannot be selected as counts.")
  source <- list(type = NULL, path = NULL, rds_sha256 = NULL)
  if (is.character(input) && length(input) == 1L && !is.na(input)) {
    if (!file.exists(input) || dir.exists(input)) .sc_project_fail("Input RDS path must be an existing local file.")
    source <- list(type = "local_rds", path = normalizePath(input, mustWork = TRUE),
                   rds_sha256 = .sc_project_sha_file(input))
    input <- tryCatch(readRDS(input), error = function(e)
      .sc_project_fail("Input RDS could not be read; provide a valid locally saved counts matrix or Seurat RDS, then retry in the same empty project directory."))
    if (!identical(source$rds_sha256, .sc_project_sha_file(source$path)))
      .sc_project_fail("Input RDS changed while it was being read; retry with a stable local file.")
  }
  matrix_input <- is.matrix(input) || inherits(input, "Matrix")
  if (matrix_input) {
    .sc_project_matrix(input, "Input counts matrix", raw_counts = TRUE)
    if (counts_layer != "counts") .sc_project_fail("Matrix input requires counts_layer='counts'.")
    if (start_stage != "qc") .sc_project_fail("A counts matrix cannot start at the processed stage; provide a processed Seurat object.")
    if (any(grepl("[_|]", rownames(input))))
      .sc_project_fail("Seurat would rename feature IDs containing '_' or '|'; rename them explicitly before input.")
    # Pass the original matrix, preserving literal source cell and feature order.
    seu <- Seurat::CreateSeuratObject(counts = input, assay = assay, min.cells = 0, min.features = 0)
    input_type <- "counts_matrix"
  } else {
    seu <- .sc_project_unwrap(input)
    input_type <- if (inherits(input, "Seurat")) "Seurat" else "AgentSeurat"
  }
  if (is.null(source$type)) source$type <- input_type
  .sc_project_ids(colnames(seu), "Complete object cell IDs")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  if (!setequal(colnames(counts), colnames(seu)))
    .sc_project_fail("Selected raw counts layer must cover every object cell exactly; explicitly join or reconstruct split layers first.")
  context <- .sc_run_context(context, seu)
  processed <- identical(start_stage, "processed")
  if (processed) {
    .sc_project_string(processed_reason, "processed_reason")
    .sc_project_string(normalized_layer, "normalized_layer")
    .sc_project_identity(seu, assay = assay, counts_layer = counts_layer,
                         normalized_layer = normalized_layer, cluster_column = cluster_column)
  }
  warnings <- character()
  for (role in c("sample", "capture")) if (is.null(context$columns[[role]]))
    warnings <- c(warnings, paste0("No ", role, " column declared; QC cannot assess separate ", role, " groups."))
  if (is.null(context$species)) warnings <- c(warnings, "Species was not declared; mitochondrial percentage is unavailable.")
  if (!is.null(context$columns$batch) && !is.null(context$columns$condition) &&
      identical(context$columns$batch, context$columns$condition))
    warnings <- c(warnings, "The same column is explicitly declared as batch and condition; integration requires an independent reviewed decision and is not performed by typed QC.")
  list(seu = seu, context = context, source = source, processed = processed,
       diagnostics = list(input_type = input_type, start_stage = start_stage,
                          assay = assay, counts_layer = counts_layer,
                          cell_count = ncol(counts), feature_count = nrow(counts),
                          raw_counts_validated = TRUE, sparse_counts = inherits(counts, "sparseMatrix"),
                          processed_reason = if (processed) processed_reason else NULL,
                          warnings = warnings))
}

.sc_run_qc_distribution <- function(value) {
  available <- value[is.finite(value)]
  quantiles <- if (length(available))
    stats::quantile(available, probs = c(0, .05, .25, .5, .75, .95, .99, 1), names = FALSE) else
    rep(NA_real_, 8L)
  list(n = length(value), measured = length(available), missing = sum(!is.finite(value)),
       min = quantiles[1L], p05 = quantiles[2L], p25 = quantiles[3L],
       median = quantiles[4L], p75 = quantiles[5L], p95 = quantiles[6L],
       p99 = quantiles[7L], max = quantiles[8L],
       mean = if (length(available)) mean(available) else NA_real_)
}

.sc_run_qc_hash <- function(evidence) {
  inputs <- list(summary = evidence$summary, metrics = evidence$metrics,
                      counts_hash = evidence$counts_hash, cell_hash = evidence$cell_hash,
                      features_hash = evidence$features_hash,
                      feature_ids = evidence$feature_ids,
                      group_columns = evidence$group_columns)
  # Optional MAD evidence is bound explicitly. Keeping this field absent when
  # disabled preserves the existing range-QC fingerprint exactly.
  if (!is.null(evidence$mad_record)) inputs$mad_evidence_hash <- evidence$mad_record$evidence_hash
  digest::digest(inputs,
                 algo = "sha256", serialize = TRUE, serializeVersion = 2L)
}

.sc_run_qc_groups <- function(metrics) {
  roles <- intersect(c("sample", "capture"), names(metrics))
  if (!length(roles)) return(list(list(selector = NULL, indices = seq_len(nrow(metrics)))))
  # A length-prefixed key avoids concatenation collisions for arbitrary literals.
  parts <- lapply(roles, function(role) paste0(nchar(enc2utf8(metrics[[role]]), type = "bytes"), ":", metrics[[role]]))
  keys <- do.call(paste0, parts)
  unique_keys <- unique(keys)
  lapply(unique_keys, function(key) {
    indices <- which(keys == key)
    selector <- stats::setNames(lapply(roles, function(role) metrics[[role]][indices[1L]]), roles)
    list(selector = selector, indices = indices)
  })
}

.sc_run_qc_evidence <- function(seu, context = list(), assay = "RNA", counts_layer = "counts") {
  seu <- .sc_project_unwrap(seu)
  context <- .sc_run_context(context, seu)
  if (grepl("^(data|scale\\.data|normalized)(\\.|$)", counts_layer, ignore.case = TRUE))
    .sc_project_fail("QC requires genuine raw counts, not a normalized layer.")
  counts <- .sc_project_layer(seu, assay, counts_layer, raw_counts = TRUE)
  cells <- colnames(seu)
  .sc_project_ids(cells, "Complete object cell IDs")
  if (!setequal(cells, colnames(counts))) .sc_project_fail("QC counts must cover every object cell exactly.")
  counts <- counts[, cells, drop = FALSE]
  total <- as.numeric(Matrix::colSums(counts))
  if (any(!is.finite(total))) .sc_project_fail("Raw-count column totals must be finite; QC cannot summarize overflowing totals.")
  detected <- as.numeric(Matrix::colSums(counts > 0))
  species <- if (is.null(context$species)) "" else tolower(trimws(context$species))
  pattern <- if (species %in% c("human", "homo sapiens", "homo_sapiens")) "^MT-" else
    if (species %in% c("mouse", "mus musculus", "mus_musculus")) "^mt-" else NULL
  mt_genes <- if (is.null(pattern)) character() else grep(pattern, rownames(counts), value = TRUE)
  mt <- rep(NA_real_, length(cells))
  if (length(mt_genes)) {
    numerator <- as.numeric(Matrix::colSums(counts[mt_genes, , drop = FALSE]))
    measured <- total > 0
    mt[measured] <- 100 * numerator[measured] / total[measured]
  }
  metrics <- data.frame(cell_id = cells, nCount = total, nFeature = detected,
                        percent_mt = mt, stringsAsFactors = FALSE, check.names = FALSE)
  metadata <- seu[[]]
  for (role in intersect(c("sample", "capture"), names(context$columns)))
    metrics[[role]] <- as.character(metadata[cells, context$columns[[role]]])
  grouped <- .sc_run_qc_groups(metrics)
  groups <- lapply(seq_along(grouped), function(i) {
    group <- grouped[[i]]
    list(group_id = paste0("group", i), selector = group$selector,
         cells = length(group$indices), zero_count_cells = sum(total[group$indices] == 0),
         metrics = stats::setNames(lapply(c("nCount", "nFeature", "percent_mt"),
                     function(metric) .sc_run_qc_distribution(metrics[[metric]][group$indices])),
                                  c("nCount", "nFeature", "percent_mt")))
  })
  mt_reason <- if (length(mt_genes)) NULL else if (is.null(pattern))
    "Species is unspecified or unsupported; declare human/mouse with matching gene symbols, or omit percent_mt filtering." else
    "No mitochondrial genes match the declared species symbol convention; percentage is unavailable, not zero."
  summary <- list(schema = "scagentkit.qc.evidence.v1", assay = assay, counts_layer = counts_layer,
                  cells = ncol(counts), features = nrow(counts),
                  grouping_roles = intersect(c("sample", "capture"), names(context$columns)),
                  mitochondrial = list(available = length(mt_genes) > 0L,
                                       feature_count = length(mt_genes), pattern = pattern,
                                       unavailable_reason = mt_reason),
                  groups = groups,
                  interpretation = c("Quantiles summarize the supplied raw counts, before any filtering.",
                                     "Sample and capture are used only when their actual metadata columns were explicitly declared.",
                                     "Batch/condition/donor are not inferred or used as filtering groups; batch integration is a separate reviewed operation.",
                                     "Threshold ranges are inclusive; unavailable measurements cannot be silently treated as zero."))
  evidence <- list(summary = summary, metrics = metrics,
                   counts_hash = .sc_project_sparse_hash(.sc_project_matrix(counts, "QC counts", raw_counts = TRUE)),
                   cell_hash = .sc_project_sha_text(.sc_project_json(.sc_project_array(cells))),
                   features_hash = .sc_project_sha_text(.sc_project_json(.sc_project_array(rownames(counts)))),
                   group_columns = context$columns[intersect(c("sample", "capture"), names(context$columns))],
                   feature_ids = rownames(counts))
  evidence$evidence_hash <- .sc_run_qc_hash(evidence)
  evidence
}

.sc_run_qc_validate <- function(proposal, evidence) {
  if (!is.list(evidence) || is.null(evidence$metrics) ||
      !identical(evidence$evidence_hash, .sc_run_qc_hash(evidence)))
    .sc_project_fail("QC evidence is missing or changed; regenerate the evidence and obtain a fresh proposal/approval.")
  if (!is.null(evidence$mad_record)) .sc_run_mad_verify(evidence$mad_record)
  if (!is.list(proposal) || is.null(names(proposal)) || anyDuplicated(names(proposal)) ||
      anyNA(names(proposal)) || any(!nzchar(names(proposal))))
    .sc_project_fail("QC proposal must be a named typed object; empty/unstructured responses are not executable.")
  if (identical(proposal$schema, "scagentkit.qc.mad.v1"))
    return(.sc_run_mad_validate(proposal, evidence))
  if (identical(proposal$schema, "scagentkit.qc.rules.v1"))
    return(.sc_run_qc_rules_validate(proposal, evidence))
  allowed <- c("schema", "rationale", "risks", "filters")
  if (length(setdiff(names(proposal), allowed)) || !all(allowed %in% names(proposal)))
    .sc_project_fail("QC proposal supports exactly schema, rationale, risks, and filters; arbitrary code, genes, integration, and unsupported operations are rejected.")
  if (!identical(proposal$schema, "scagentkit.qc.v1")) .sc_project_fail("Unsupported QC proposal schema.")
  .sc_project_string(proposal$rationale, "proposal$rationale")
  risks <- proposal$risks
  if (is.list(risks)) {
    if (length(risks) && !all(vapply(risks, function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x), logical(1))))
      .sc_project_fail("QC risks must contain nonempty text strings.")
    risks <- unlist(risks, use.names = FALSE)
    if (!length(risks)) risks <- character()
  }
  if (!is.character(risks) || anyNA(risks) || any(!nzchar(risks)))
    .sc_project_fail("QC risks must be a text array, possibly empty.")
  filters <- proposal$filters
  if (!is.list(filters) || !length(filters) || !is.null(names(filters)))
    .sc_project_fail("QC filters must be a nonempty array of supported typed range operations; an empty response is not an implicit keep-all decision.")
  metrics <- evidence$metrics
  .sc_project_ids(metrics$cell_id, "QC evidence cell IDs")
  keep <- rep(TRUE, nrow(metrics))
  unavailable <- list()
  canonical <- lapply(seq_along(filters), function(i) {
    filter <- filters[[i]]
    if (!is.list(filter) || is.null(names(filter)) || anyDuplicated(names(filter)) ||
        anyNA(names(filter)) || any(!nzchar(names(filter))) ||
        length(setdiff(names(filter), c("op", "metric", "min", "max", "group"))) ||
        !all(c("op", "metric") %in% names(filter)))
      .sc_project_fail(paste0("QC filter ", i, " has missing or unsupported fields; only range/metric/min/max/group are allowed."))
    if (!identical(filter$op, "range")) .sc_project_fail("Typed QC supports only op='range'; no model-generated code is executed.")
    .sc_project_string(filter$metric, "filter$metric")
    if (!filter$metric %in% c("nCount", "nFeature", "percent_mt"))
      .sc_project_fail("Unsupported QC metric; supported metrics are nCount, nFeature, and percent_mt.")
    bounds <- lapply(c("min", "max"), function(bound) {
      value <- filter[[bound]]
      if (!is.null(value) && (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0))
        .sc_project_fail(paste0("QC ", bound, " must be one finite nonnegative number or NULL."))
      if (!is.null(value) && filter$metric %in% c("nCount", "nFeature") && value != floor(value))
        .sc_project_fail("nCount/nFeature QC bounds must be integers.")
      if (!is.null(value) && filter$metric == "percent_mt" && value > 100)
        .sc_project_fail("percent_mt bounds must be between 0 and 100.")
      # JSON readers may store whole-valued bounds as integers. The scientific
      # policy and its dependency hash must survive a browser/file roundtrip.
      if (is.null(value)) NULL else unname(as.numeric(value))
    })
    names(bounds) <- c("min", "max")
    if (all(vapply(bounds, is.null, logical(1)))) .sc_project_fail("Every QC range must declare at least one bound.")
    if (!is.null(bounds$min) && !is.null(bounds$max) && bounds$min > bounds$max)
      .sc_project_fail("QC range min cannot exceed max.")
    selector <- filter$group
    selected <- rep(TRUE, nrow(metrics))
    if (!is.null(selector)) {
      if (!is.list(selector) || !length(selector) || is.null(names(selector)) ||
          anyNA(names(selector)) || any(!nzchar(names(selector))) || anyDuplicated(names(selector)) ||
          length(setdiff(names(selector), c("sample", "capture"))))
        .sc_project_fail("QC group must select explicitly declared sample/capture literal values only.")
      # Canonicalize roles, independent of JSON object field order.
      selector <- selector[intersect(c("sample", "capture"), names(selector))]
      for (role in names(selector)) {
        .sc_project_string(selector[[role]], paste0("filter$group$", role))
        if (!role %in% names(metrics)) .sc_project_fail(paste0("QC group role `", role, "` was not declared in input context."))
        selected <- selected & metrics[[role]] == selector[[role]]
      }
      if (!any(selected)) .sc_project_fail("QC group selector does not match any actual sample/capture group; hallucinated or stale group values are rejected.")
    }
    values <- metrics[[filter$metric]]
    missing <- selected & !is.finite(values)
    unavailable[[i]] <<- list(metric = filter$metric, cells = missing)
    measured <- selected & !missing
    eligible <- rep(TRUE, nrow(metrics))
    if (!is.null(bounds$min)) eligible[measured] <- eligible[measured] & values[measured] >= bounds$min
    if (!is.null(bounds$max)) eligible[measured] <- eligible[measured] & values[measured] <= bounds$max
    keep <<- keep & eligible
    list(op = "range", metric = filter$metric, min = bounds$min, max = bounds$max, group = selector)
  })
  for (item in unavailable) if (any(item$cells & keep))
    .sc_project_fail(paste0("QC metric `", item$metric, "` is unavailable for one or more otherwise retained cells; review the diagnostics instead of silently removing them."))
  if (!any(keep)) .sc_project_fail("QC proposal would remove every cell; revise the proposal before approval.")
  group_records <- .sc_run_qc_groups(metrics)
  retention_groups <- lapply(seq_along(group_records), function(i) {
    group <- group_records[[i]]
    before <- length(group$indices)
    after <- sum(keep[group$indices])
    list(group_id = paste0("group", i), selector = group$selector,
         before = before, retained = after, removed = before - after,
         fraction_retained = after / before)
  })
  list(proposal = list(schema = "scagentkit.qc.v1", rationale = proposal$rationale,
                       risks = unname(risks), filters = canonical),
       retention = list(before = nrow(metrics), retained = sum(keep), removed = sum(!keep),
                        fraction_retained = mean(keep), groups = retention_groups),
       keep_cells = metrics$cell_id[keep], evidence_hash = evidence$evidence_hash)
}

.sc_run_qc_apply <- function(seu, validated, evidence) {
  seu <- .sc_project_unwrap(seu)
  if (!identical(validated$evidence_hash, evidence$evidence_hash))
    .sc_project_fail("QC validation belongs to different evidence; stale approval cannot be applied.")
  checked <- .sc_run_qc_validate(validated$proposal, evidence)
  if (!identical(checked$keep_cells, validated$keep_cells) || !identical(checked$retention, validated$retention))
    .sc_project_fail("Validated QC result was changed; obtain a fresh validation and approval.")
  cells <- colnames(seu)
  if (!identical(cells, evidence$metrics$cell_id))
    .sc_project_fail("Input cell IDs or order changed after QC evidence was generated; approval is stale.")
  counts <- .sc_project_layer(seu, evidence$summary$assay, evidence$summary$counts_layer, raw_counts = TRUE)
  if (!identical(.sc_project_sha_text(.sc_project_json(.sc_project_array(rownames(counts)))), evidence$features_hash))
    .sc_project_fail("Input feature IDs changed after QC evidence was generated; approval is stale.")
  if (!identical(.sc_project_sparse_hash(counts), evidence$counts_hash))
    .sc_project_fail("Input raw counts changed after QC evidence was generated; approval is stale.")
  # Verify that metadata grouping, which changes operation scope, remains exact.
  metadata <- seu[[]]
  for (role in intersect(c("sample", "capture"), names(evidence$metrics))) {
    # The aggregate summary records roles; the local evidence stores the source column.
    column <- evidence$group_columns[[role]]
    if (is.null(column) || sum(names(metadata) == column) != 1L ||
        !identical(as.character(metadata[cells, column]), evidence$metrics[[role]]))
      .sc_project_fail("Input sample/capture metadata changed after QC evidence; approval is stale.")
  }
  if (!is.null(evidence$mad_record)) {
    record <- evidence$mad_record
    .sc_run_mad_verify(record)
    if (!identical(.sc_run_mad_groups(seu, record$options, cells), record$group_map))
      .sc_project_fail("Input QC grouping metadata changed after MAD evidence; approval is stale.")
    prefilter <- record$prefilter_record
    if (!is.null(prefilter)) {
      .sc_run_prefilter_verify(prefilter)
      for (role in names(prefilter$group_columns)) {
        column <- prefilter$group_columns[[role]]
        if (sum(names(metadata) == column) != 1L ||
            !identical(as.character(metadata[cells, column]), prefilter$metrics[[role]]))
          .sc_project_fail("Input prefilter grouping metadata changed after MAD evidence; approval is stale.")
      }
    }
  }
  output <- seu[, checked$keep_cells]
  if (!identical(colnames(output), checked$keep_cells))
    .sc_project_fail("QC subset changed literal cell IDs or order unexpectedly; no result was returned.")
  # Seurat subset can recalculate count-derived metadata with another numeric
  # type. Restore every caller column by exact literal cell scope before adding
  # new diagnostics, retaining factors, missing values and original types.
  retained_metadata <- metadata[checked$keep_cells, , drop = FALSE]
  output@meta.data <- retained_metadata
  metrics <- evidence$metrics[match(colnames(output), evidence$metrics$cell_id), , drop = FALSE]
  diagnostic_names <- c(paste0("nCount_", evidence$summary$assay),
    paste0("nFeature_", evidence$summary$assay), "percent.mt")
  diagnostic_values <- list(metrics$nCount, metrics$nFeature, metrics$percent_mt)
  for (i in seq_along(diagnostic_names))
    if (!diagnostic_names[[i]] %in% names(retained_metadata))
      output[[diagnostic_names[[i]]]] <- diagnostic_values[[i]]
  output
}
