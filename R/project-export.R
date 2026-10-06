#' Export a processed object as a portable local evidence project
#'
#' Expression identity covers the complete object and explicit layers. Export
#' performs no analysis, cell deletion, annotation decision, network call, or RDS save.
#' @param object A Seurat or AgentSeurat wrapping exactly one Seurat.
#' @param path New project directory. Existing paths are never overwritten.
#' @param project_id Nonempty literal project ID, never a path.
#' @param assay,counts_layer,normalized_layer Explicit assay and layer names.
#'   Set normalized_layer=NULL explicitly for counts-only evidence.
#' @param cluster_column Existing complete cluster membership column.
#' @param reduction Existing reduction, or NULL for no embedding.
#' @param marker_table,candidate_table,model_records Optional supplied evidence.
#' @param source_annotation Optional original annotation metadata column,
#'   exported as source context rather than a review decision.
#' @param directed_clusters Explicit cluster IDs for targeted T/NK RNA evidence.
#' @param display_name Project display name.
#' @param metadata_allowlist Metadata permitted in per-cell QC records.
#'   orig.ident requires explicit opt-in.
#' @param parameters,provenance Named lists of export parameters and provenance.
#' @param archive Also create a new sibling path.zip archive.
#' @return Invisibly, paths and project/source/bundle identities.
#' @export
sc_project_export <- function(object, path, project_id, assay = "RNA",
                              counts_layer = "counts", normalized_layer = "data",
                              cluster_column = "seurat_clusters", reduction = "umap",
                              marker_table = NULL, candidate_table = NULL,
                              model_records = NULL, source_annotation = NULL,
                              directed_clusters = NULL, display_name = project_id,
                              metadata_allowlist = c("nCount_RNA", "nFeature_RNA", "percent.mt"),
                              parameters = list(), provenance = list(), archive = FALSE) {
  .sc_project_string(path, "path")
  .sc_project_string(project_id, "project_id")
  if (grepl("[/\\\\]", project_id) || project_id %in% c(".", ".."))
    .sc_project_fail("`project_id` must be a literal project ID, never a path.")
  .sc_project_string(display_name, "display_name")
  .sc_project_string(reduction, "reduction", nullable = TRUE)
  .sc_project_string(source_annotation, "source_annotation", nullable = TRUE)
  if (!is.logical(archive) || length(archive) != 1L || is.na(archive)) .sc_project_fail("`archive` must be TRUE or FALSE.")
  path <- path.expand(path)
  if (file.exists(path) || dir.exists(path)) .sc_project_fail("Project path already exists; choose a new directory. Export refuses overwrite.")
  archive_path <- paste0(path, ".zip")
  if (archive && (file.exists(archive_path) || dir.exists(archive_path))) .sc_project_fail("Project archive path already exists; choose a new path. Export refuses overwrite.")
  seu <- .sc_project_unwrap(object)
  identity <- .sc_project_identity(seu, assay, counts_layer, normalized_layer, cluster_column)
  cells <- identity$cells
  membership <- identity$membership
  cluster_ids <- unique(unname(membership))
  cluster_ids <- cluster_ids[order(enc2utf8(cluster_ids), method = "radix")]
  groups <- stats::setNames(lapply(cluster_ids, function(id) cells[membership == id]), cluster_ids)
  if (!is.character(metadata_allowlist) || anyNA(metadata_allowlist) || any(!nzchar(metadata_allowlist)) || anyDuplicated(metadata_allowlist))
    .sc_project_fail("`metadata_allowlist` must contain unique nonempty metadata column names.")
  metadata <- seu@meta.data
  qc_fields <- intersect(metadata_allowlist, names(metadata))
  if (any(vapply(qc_fields, function(field) sum(names(metadata) == field) != 1L, logical(1))))
    .sc_project_fail("Allowlisted metadata column names are ambiguous; make selected field names unique explicitly.")
  for (field in qc_fields) .sc_project_metadata(metadata[[field]], field)
  points <- .sc_project_embedding(seu, cells, reduction)
  cell_records <- lapply(seq_along(cells), function(i) {
    id <- cells[i]
    list(cellId = id, clusterId = membership[[i]],
         qc = stats::setNames(lapply(qc_fields, function(field) .sc_project_scalar(metadata[id, field])), qc_fields))
  })
  markers <- .sc_project_records(marker_table, c("clusterId", "gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"), "marker_table", cluster_ids)
  candidates <- .sc_project_records(candidate_table, c("clusterId", "label", "score", "overlap", "referenceSize", "markers", "source"), "candidate_table", cluster_ids)
  models <- .sc_project_records(model_records, c("clusterId", "callId", "provider", "mode", "strictStatus", "strict", "posthoc", "rawText", "source"), "model_records", cluster_ids)
  parameters <- .sc_project_object(parameters, "parameters")
  if (!is.null(seu@misc$sc_project_prepare) && is.null(parameters$prepare)) parameters$prepare <- seu@misc$sc_project_prepare
  provenance <- .sc_project_object(provenance, "provenance")
  project <- list(schema = "scagentkit.project.v1", projectId = project_id, displayName = display_name,
                  identity = identity[setdiff(names(identity), c("cells", "features", "membership", "counts", "data"))],
                  cells = cell_records,
                  clusters = lapply(cluster_ids, function(id) list(id = id, cellIds = .sc_project_array(groups[[id]]))),
                  embedding = points, markers = markers, candidates = candidates, models = models,
                  parameters = parameters, provenance = provenance,
                  directed = list(panel = "T_NK.v1", clusters = .sc_project_map()))
  if (!is.null(source_annotation)) {
    if (sum(names(metadata) == source_annotation) != 1L) .sc_project_fail("Requested source annotation column is absent or ambiguous.")
    .sc_project_metadata(metadata[[source_annotation]], source_annotation)
    project$sourceAnnotation <- list(column = source_annotation, role = "source_context",
                                    values = lapply(cells, function(id) {
                                      value <- .sc_project_scalar(metadata[id, source_annotation])
                                      list(cellId = id, value = if (is.null(value)) NULL else as.character(value))
                                    }))
  }
  if (is.null(directed_clusters)) directed_clusters <- character()
  if (!is.character(directed_clusters) || anyNA(directed_clusters) || any(!nzchar(directed_clusters)) || anyDuplicated(directed_clusters) || any(!directed_clusters %in% cluster_ids))
    .sc_project_fail("`directed_clusters` must be unique literal IDs of existing clusters; no lineage is inferred.")
  if (length(directed_clusters) && assay != "RNA") .sc_project_fail("The T/NK panel requires an explicitly selected RNA assay; other assays have no inferred program rule.")
  if (length(directed_clusters) && is.null(normalized_layer)) {
    if (!is.null(project$parameters$directedUnavailable)) .sc_project_fail("`parameters$directedUnavailable` is reserved for export availability provenance.")
    project$parameters$directedUnavailable <- list(panel = "T_NK.v1", clusterIds = .sc_project_array(directed_clusters),
                                                  reason = "The explicitly counts-only project has no normalized layer; normalization-dependent T/NK tools are unavailable. No values were imputed or normalized.")
    directed_clusters <- character()
  }
  parent <- dirname(path)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) .sc_project_fail("Cannot create project parent directory.")
  parent <- normalizePath(parent, mustWork = TRUE)
  target <- file.path(parent, basename(path))
  stage <- tempfile(pattern = ".sc-project-", tmpdir = parent)
  if (!dir.create(stage)) .sc_project_fail("Cannot create project staging directory.")
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE), add = TRUE)
  files <- list()
  if (length(directed_clusters)) {
    dir.create(file.path(stage, "directed"))
    for (index in seq_along(directed_clusters)) {
      id <- directed_clusters[index]
      relative <- sprintf("directed/cluster-%04d.json", index)
      asset <- .sc_project_directed(identity, groups, id, metadata[, qc_fields, drop = FALSE], points)
      .sc_project_write_json(file.path(stage, relative), asset)
      record <- .sc_project_file_record(stage, relative)
      files[[length(files) + 1L]] <- record
      project$directed$clusters[[id]] <- list(path = relative, sha256 = record$sha256)
    }
  }
  .sc_project_write_json(file.path(stage, "project.json"), project)
  bundle_digest <- .sc_project_sha_file(file.path(stage, "project.json"))
  files <- c(list(.sc_project_file_record(stage, "project.json")), files)
  manifest <- list(schema = "scagentkit.project-bundle.v1", projectId = project_id,
                   sourceFingerprint = identity$fingerprint, bundleDigest = bundle_digest, files = files)
  .sc_project_write_json(file.path(stage, "manifest.json"), manifest)
  archive_stage <- NULL
  if (archive) {
    archive_stage <- tempfile(pattern = ".sc-project-", tmpdir = parent, fileext = ".zip")
    on.exit(if (!is.null(archive_stage) && file.exists(archive_stage)) unlink(archive_stage), add = TRUE)
    previous <- getwd()
    tryCatch({
      setwd(stage)
      status <- utils::zip(archive_stage, files = c("manifest.json", vapply(files, `[[`, character(1), "path")), flags = "-q9X")
      if (!identical(status, 0L) || !file.exists(archive_stage)) .sc_project_fail("Could not create portable ZIP archive; verify that the local zip utility is available.")
    }, finally = setwd(previous))
  }
  if (file.exists(target) || dir.exists(target) || !file.rename(stage, target)) .sc_project_fail("Cannot publish new project directory; an output path may have appeared during export.")
  if (archive) {
    archive_path <- paste0(target, ".zip")
    if (file.exists(archive_path) || dir.exists(archive_path) || !file.rename(archive_stage, archive_path))
      .sc_project_fail("Project directory was exported, but the new archive could not be published without overwrite.")
  }
  invisible(list(path = target, projectId = project_id, sourceFingerprint = identity$fingerprint,
                 bundleDigest = bundle_digest, archive = if (archive) archive_path else NULL))
}

.sc_project_scalar <- function(value) {
  if (length(value) != 1L || is.na(value)) return(NULL)
  if (is.factor(value)) return(as.character(value))
  unname(value)
}
.sc_project_metadata <- function(value, name) {
  if (!(is.character(value) || is.factor(value) || is.logical(value) || is.numeric(value)) ||
      (is.numeric(value) && (any(is.nan(value)) || any(!is.finite(value[!is.na(value)])))))
    .sc_project_fail(paste0("Metadata `", name, "` must be atomic with finite numeric values or actual missing values."))
  invisible(TRUE)
}
.sc_project_object <- function(value, name) {
  if (!is.list(value) || (length(value) && (is.null(names(value)) || anyNA(names(value)) || any(!nzchar(names(value))) || anyDuplicated(names(value)))))
    .sc_project_fail(paste0("`", name, "` must be a named JSON object list."))
  .sc_project_finite(value, name)
  .sc_project_json_check(value)
  .sc_project_map(value)
}
.sc_project_finite <- function(value, name) {
  if (is.list(value)) {
    for (item in value) .sc_project_finite(item, name)
  } else if (is.numeric(value) && any(!is.finite(value[!is.na(value)]))) {
    .sc_project_fail(paste0("Non-finite supplied values in ", name, "."))
  }
  invisible(TRUE)
}
.sc_project_number <- function(value, name, fraction = FALSE, integer = FALSE) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
      (fraction && (value < 0 || value > 1)) || (integer && (value < 0 || value != floor(value))))
    .sc_project_fail(paste0(name, " must be one finite ", if (fraction) "number in [0,1]" else if (integer) "nonnegative integer" else "number", "."))
  invisible(TRUE)
}
.sc_project_records <- function(value, fields, name, cluster_ids) {
  if (is.null(value)) return(list())
  if (is.data.frame(value)) {
    if (anyDuplicated(names(value)) || !all(fields %in% names(value))) .sc_project_fail(paste0("`", name, "` requires columns: ", paste(fields, collapse = ", "), "."))
    rows <- lapply(seq_len(nrow(value)), function(i) lapply(value[i, fields, drop = FALSE], function(item) {
      if (is.list(item)) item[[1L]] else .sc_project_scalar(item)
    }))
  } else if (is.list(value)) rows <- unname(value)
  else .sc_project_fail(paste0("`", name, "` must be a data frame or a list of records."))
  seen <- character()
  for (i in seq_along(rows)) {
    row <- rows[[i]]
    if (!is.list(row) || is.null(names(row)) || anyDuplicated(names(row)) || !all(fields %in% names(row))) .sc_project_fail(paste0("Each ", name, " record must contain its documented UI fields."))
    row <- row[fields]
    if (is.factor(row$clusterId)) row$clusterId <- as.character(row$clusterId)
    .sc_project_string(row$clusterId, paste0(name, "$clusterId"))
    if (!row$clusterId %in% cluster_ids) .sc_project_fail(paste0(name, " refers to a foreign cluster ID."))
    .sc_project_finite(row, name)
    for (field in intersect(fields, c("gene", "label", "callId", "provider", "mode", "strictStatus", "source"))) {
      if (is.factor(row[[field]])) row[[field]] <- as.character(row[[field]])
      .sc_project_string(row[[field]], paste0(name, "$", field))
    }
    if (name == "marker_table") {
      .sc_project_number(row$avgLog2FC, "marker_table$avgLog2FC")
      for (field in c("pct1", "pct2", "pAdj")) .sc_project_number(row[[field]], paste0(name, "$", field), fraction = TRUE)
      key <- .sc_project_json(list(clusterId = row$clusterId, gene = row$gene))
      if (key %in% seen) .sc_project_fail("Duplicate cluster/gene marker record.")
      seen <- c(seen, key)
    } else if (name == "candidate_table") {
      .sc_project_number(row$score, "candidate_table$score", fraction = TRUE)
      for (field in c("overlap", "referenceSize")) .sc_project_number(row[[field]], paste0(name, "$", field), integer = TRUE)
      if (row$overlap > row$referenceSize) .sc_project_fail("Candidate overlap exceeds its reference size.")
      markers <- unlist(row$markers, use.names = FALSE)
      if (length(markers) && (!is.character(markers) || anyNA(markers) || any(!nzchar(markers)) || anyDuplicated(markers)))
        .sc_project_fail("Candidate markers must be unique nonempty literal gene strings.")
      row$markers <- .sc_project_array(markers)
    } else {
      if (!row$strictStatus %in% c("not_run", "valid", "format_rejected", "network_failed")) .sc_project_fail("Unknown strict model status.")
      for (field in c("strict", "posthoc")) if (!is.null(row[[field]])) row[[field]] <- .sc_project_object(row[[field]], paste0(name, "$", field))
      if (!is.null(row$strict$status) && !identical(row$strict$status, row$strictStatus)) .sc_project_fail("Strict model status fields disagree.")
      if (row$strictStatus == "valid") .sc_project_string(row$strict$label, "valid strict model label")
      if (!is.null(row$rawText) && (!is.character(row$rawText) || length(row$rawText) != 1L || is.na(row$rawText))) .sc_project_fail("Model rawText must be nullable plain text.")
      if (row$callId %in% seen) .sc_project_fail("Duplicate model call ID.")
      seen <- c(seen, row$callId)
    }
    rows[[i]] <- row
  }
  rows
}
.sc_project_embedding <- function(object, cells, reduction) {
  if (is.null(reduction)) return(NULL)
  if (sum(names(object@reductions) == reduction) != 1L) .sc_project_fail(paste0("Reduction `", reduction, "` is absent or ambiguous. Supply an existing reduction or set reduction=NULL explicitly."))
  values <- SeuratObject::Embeddings(object[[reduction]])
  .sc_project_ids(rownames(values), "Embedding cell IDs")
  if (ncol(values) < 2L || !setequal(rownames(values), cells) || any(!is.finite(values[, 1:2, drop = FALSE])))
    .sc_project_fail("Embedding must have finite two-dimensional coordinates covering every object cell exactly.")
  list(name = reduction, points = lapply(cells, function(id) list(cellId = id, x = unname(values[id, 1L]), y = unname(values[id, 2L]))))
}
.sc_project_write_json <- function(path, value) {
  bytes <- paste0(.sc_project_json(value, pretty = TRUE), "\n")
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(charToRaw(enc2utf8(bytes)), connection)
  invisible(path)
}
.sc_project_file_record <- function(root, path) list(path = path, bytes = unname(file.info(file.path(root, path))$size), sha256 = .sc_project_sha_file(file.path(root, path)))

.sc_project_panel <- list(t_identity = c("CD3D", "CD3E", "CD3G", "TRAC", "TRBC1", "TRBC2"),
                          cd8_subtype = c("CD8A", "CD8B"), nk_identity = c("KLRD1", "KLRF1", "NCR1", "NCAM1"),
                          nk_nonexclusive = "FCGR3A", shared_cytotoxic = c("NKG7", "GNLY", "PRF1", "GZMB", "GZMA", "GZMH", "CTSW", "CST7"),
                          b_candidate_control = c("MS4A1", "CD79A", "CD79B"))
.sc_project_distribution <- function(values) {
  values <- as.numeric(values)
  if (!length(values)) return(list(n = 0L, mean = NULL, q0 = NULL, q25 = NULL, q50 = NULL, q75 = NULL, q90 = NULL, max = NULL))
  if (any(!is.finite(values))) .sc_project_fail("Directed numeric measurements must be finite.")
  q <- stats::quantile(values, c(0, .25, .5, .75, .9, 1), names = FALSE, type = 7)
  list(n = length(values), mean = mean(values), q0 = q[1], q25 = q[2], q50 = q[3], q75 = q[4], q90 = q[5], max = q[6])
}
.sc_project_gene_summary <- function(identity, ids) {
  genes <- unname(unlist(.sc_project_panel))
  lapply(genes, function(gene) {
    measured <- gene %in% identity$features
    normalized <- measured && !is.null(identity$data)
    counts <- if (measured) as.numeric(identity$counts[gene, ids]) else NULL
    data <- if (normalized) as.numeric(identity$data[gene, ids]) else NULL
    detected <- if (measured) counts > 0 else NULL
    list(gene = gene, panel_group = names(.sc_project_panel)[vapply(.sc_project_panel, function(group) gene %in% group, logical(1))],
         assay = identity$assay, detection_layer = identity$countsLayer, normalized_layer = identity$normalizedLayer,
         n_cells = length(ids), measurement_status = if (measured) "measured" else "missing",
         counts_status = if (measured) "measured" else "missing", normalized_status = if (normalized) "measured" else "missing",
         detected_n = if (measured) sum(detected) else NULL, detected_fraction = if (measured) mean(detected) else NULL,
         raw_counts = if (measured) .sc_project_distribution(counts) else NULL,
         normalized = list(all = if (normalized) .sc_project_distribution(data) else NULL,
                           detected = if (normalized) .sc_project_distribution(data[detected]) else NULL))
  })
}
.sc_project_anchors <- function(identity, ids, anchors) {
  measured <- anchors[anchors %in% identity$features]
  missing <- setdiff(anchors, measured)
  observed <- if (length(measured)) as.integer(Matrix::colSums(identity$counts[measured, ids, drop = FALSE] > 0)) else rep(0L, length(ids))
  list(anchors = .sc_project_array(anchors), measured_anchors = .sc_project_array(measured), missing_anchors = .sc_project_array(missing), observed_n = observed, missing_n = length(missing))
}
.sc_project_coexpression <- function(identity, ids, threshold = 2L) {
  t <- .sc_project_anchors(identity, ids, .sc_project_panel$t_identity)
  nk <- .sc_project_anchors(identity, ids, .sc_project_panel$nk_identity)
  b <- .sc_project_anchors(identity, ids, .sc_project_panel$b_candidate_control)
  t_gate <- t$observed_n >= threshold; nk_gate <- nk$observed_n >= threshold
  classes <- ifelse(t_gate & nk_gate, "both", ifelse(t_gate, "t_only", ifelse(nk_gate, "nk_only", "neither")))
  category_n <- as.list(stats::setNames(as.integer(table(factor(classes, levels = c("t_only", "nk_only", "both", "neither")))), c("t_only", "nk_only", "both", "neither")))
  possible <- function(observation) ifelse(observation$observed_n >= threshold, TRUE, ifelse(observation$observed_n + observation$missing_n < threshold, FALSE, NA))
  summary <- list(assay = identity$assay, layer = identity$countsLayer, n_cells = length(ids), rule_version = "rna-observed-panel-v1", threshold_n = threshold,
                  threshold_status = "exploratory_uncalibrated", anchors = list(t = t$anchors, nk = nk$anchors),
                  measured_anchors = list(t = t$measured_anchors, nk = nk$measured_anchors), missing_anchors = list(t = t$missing_anchors, nk = nk$missing_anchors),
                  counts = category_n, fractions = lapply(category_n, function(n) n / length(ids)), observed_t_gate_n = sum(t_gate), observed_nk_gate_n = sum(nk_gate),
                  observed_b_control_gate_n = sum(b$observed_n >= threshold), t_anchor_detected_n_distribution = .sc_project_distribution(t$observed_n),
                  nk_anchor_detected_n_distribution = .sc_project_distribution(nk$observed_n), n_complete_gate_coverage = if (t$missing_n == 0L && nk$missing_n == 0L) length(ids) else 0L,
                  t_gate_indeterminate_due_missing_n = sum(is.na(possible(t))), nk_gate_indeterminate_due_missing_n = sum(is.na(possible(nk))),
                  interpretation = "Observed anchor detection is uncalibrated; low counts or missing genes are not negative lineage evidence. T/NK coexpression identifies neither NKT cells nor doublets.")
  list(summary = summary, t = t, nk = nk, b = b, t_gate = t_gate, nk_gate = nk_gate,
       t_possible = possible(t), nk_possible = possible(nk), classes = classes)
}
.sc_project_depth <- function(metadata, ids, config) {
  if (!all(c("nCount_RNA", "nFeature_RNA") %in% names(metadata))) return(rep(NA, length(ids)))
  umi <- metadata[ids, "nCount_RNA"]; features <- metadata[ids, "nFeature_RNA"]
  if (!is.numeric(umi) || !is.numeric(features)) .sc_project_fail("Actual nCount_RNA/nFeature_RNA metadata must be numeric for directed QC.")
  low <- umi < config$nCount_RNA_lt | features < config$nFeature_RNA_lt
  low[is.na(umi) | is.na(features)] <- NA
  low
}
.sc_project_qc_summary <- function(identity, metadata, ids) {
  qc_fields <- unique(c("nCount_RNA", "nFeature_RNA", "percent.mt", names(metadata)))
  fields <- lapply(qc_fields, function(field) {
    present <- field %in% names(metadata)
    values <- if (present) metadata[ids, field] else NULL
    numeric <- is.numeric(values)
    measured <- present && any(!is.na(values))
    list(field = field, measurement_status = if (measured) "measured" else "missing", n_cells = length(ids),
         n_available = if (present) sum(!is.na(values)) else 0L,
         distribution = if (numeric && measured) .sc_project_distribution(values[!is.na(values)]) else NULL,
         values = if (present && !numeric && measured) as.list(table(as.character(values), useNA = "no")) else NULL)
  })
  configs <- list(list(id = "lower", nCount_RNA_lt = 500, nFeature_RNA_lt = 250), list(id = "primary", nCount_RNA_lt = 1000, nFeature_RNA_lt = 500), list(id = "higher", nCount_RNA_lt = 1500, nFeature_RNA_lt = 750))
  sensitivity <- lapply(configs, function(config) {
    low <- .sc_project_depth(metadata, ids, config)
    adequate <- ids[!is.na(low) & !low]
    list(config = config, n_cells = length(ids), n_evaluable = sum(!is.na(low)), low_depth_n = if (all(is.na(low))) NULL else sum(low, na.rm = TRUE),
         at_nCount_boundary_n = if ("nCount_RNA" %in% names(metadata)) sum(metadata[ids, "nCount_RNA"] == config$nCount_RNA_lt, na.rm = TRUE) else NULL,
         at_nFeature_boundary_n = if ("nFeature_RNA" %in% names(metadata)) sum(metadata[ids, "nFeature_RNA"] == config$nFeature_RNA_lt, na.rm = TRUE) else NULL,
         above_depth_threshold_n = length(adequate), above_depth_observed_coexpression = if (length(adequate)) .sc_project_coexpression(identity, adequate)$summary else NULL)
  })
  list(n_cells = length(ids), fields = fields, low_depth_n = sensitivity[[2L]]$low_depth_n, low_depth_config = configs[[2L]], sensitivity = sensitivity,
       threshold_status = "exploratory_uncalibrated", interpretation = "Actual available QC only; missing values are null. Descriptive low-depth flags remove no cells and cannot establish biological absence.")
}
.sc_project_directed <- function(identity, groups, cluster_id, metadata, embedding) {
  ids <- groups[[cluster_id]]
  genes <- unname(unlist(.sc_project_panel))
  co <- .sc_project_coexpression(identity, ids)
  qc_fields <- unique(c("nCount_RNA", "nFeature_RNA", "percent.mt", names(metadata)))
  config <- list(id = "primary", nCount_RNA_lt = 1000, nFeature_RNA_lt = 500)
  low <- .sc_project_depth(metadata, ids, config)
  observed_status <- function(n, missing) if (n >= 2L) "observed_threshold_met" else if (missing > 0L) "below_observed_threshold_missing_anchors" else "below_observed_threshold"
  point_ids <- if (is.null(embedding)) character() else vapply(embedding$points, `[[`, character(1), "cellId")
  cells <- lapply(seq_along(ids), function(i) {
    id <- ids[i]
    point <- if (is.null(embedding)) NULL else embedding$points[[match(id, point_ids)]]
    list(cell_id = id, cluster_id = cluster_id,
         counts = stats::setNames(lapply(genes, function(gene) if (gene %in% identity$features) as.numeric(identity$counts[gene, id]) else NULL), genes),
         normalized = stats::setNames(lapply(genes, function(gene) if (!is.null(identity$data) && gene %in% identity$features) as.numeric(identity$data[gene, id]) else NULL), genes),
         qc = stats::setNames(lapply(qc_fields, function(field) if (field %in% names(metadata)) .sc_project_scalar(metadata[id, field]) else NULL), qc_fields),
         umap = if (is.null(point)) NULL else list(x = point$x, y = point$y),
         t_anchor_detected_n = co$t$observed_n[i], nk_anchor_detected_n = co$nk$observed_n[i], t_missing_anchor_n = co$t$missing_n, nk_missing_anchor_n = co$nk$missing_n,
         t_gate = co$t_gate[i], nk_gate = co$nk_gate[i], t_identity_gate_possible = .sc_project_scalar(co$t_possible[i]), nk_identity_gate_possible = .sc_project_scalar(co$nk_possible[i]),
         t_gate_status = observed_status(co$t$observed_n[i], co$t$missing_n), nk_gate_status = observed_status(co$nk$observed_n[i], co$nk$missing_n),
         coexpression_class = co$classes[i], low_depth = .sc_project_scalar(low[i]))
  })
  other_ids <- setdiff(names(groups), cluster_id)
  controls <- lapply(other_ids, function(id) {
    control_ids <- groups[[id]]; control <- .sc_project_coexpression(identity, control_ids)
    gate <- control$t_gate | control$nk_gate | control$b$observed_n >= 2L
    list(cluster_id = id, n_cells = length(control_ids), designation = "candidate_control_unverified_correlated",
         selection = list(rule = "observed >=2 T, NK or B anchors in >=20% of cells", rule_status = "exploratory_uncalibrated",
                          selected_candidate_lymphocyte = mean(gate) >= .2, observed_lymphocyte_gate_n = sum(gate), observed_lymphocyte_gate_fraction = mean(gate),
                          b_anchors = .sc_project_array(.sc_project_panel$b_candidate_control),
                          fraction_threshold_sensitivity = lapply(c(.1, .2, .3), function(threshold) list(threshold = threshold, selected = mean(gate) >= threshold))),
         panel = .sc_project_gene_summary(identity, control_ids), coexpression = control$summary, qc = .sc_project_qc_summary(identity, metadata, control_ids),
         limitation = "Candidate controls are selected from observed expression, unverified, and correlated with this analysis.")
  })
  selected <- other_ids[vapply(controls, function(control) control$selection$selected_candidate_lymphocyte, logical(1))]
  selected_ids <- unlist(groups[selected], use.names = FALSE)
  rest_ids <- setdiff(identity$cells, ids)
  source <- list(object_fingerprint = identity$fingerprint, identity_algorithm = identity$algorithm, assay = identity$assay,
                 layers = list(counts = identity$countsLayer, data = identity$normalizedLayer), n_features_counts = length(identity$features),
                 n_features_data = if (is.null(identity$data)) NULL else length(identity$features), counts_integer_nonnegative_validated = TRUE,
                 cell_join = "Exact cell_id; no array-position joins",
                 normalization = list(method = NULL, scale_factor = NULL, provenance = "Existing values; no normalization recomputed and no normalization method inferred."))
  asset <- list(schema_version = "scAgentKit.directed_expression.v2", rule_version = "rna-observed-panel-v1", source = source,
                inventory = list(n_cells = length(identity$cells), n_input_cells = length(identity$cells), n_clusters = length(groups), counts_by_cluster = lapply(groups, length)),
                scope = list(cluster_id = cluster_id, n_cells = length(ids), cell_ids = .sc_project_array(ids), cell_ids_sha256 = .sc_project_sha_text(.sc_project_json(.sc_project_array(ids)))),
                coverage = list(panel_gene_n = length(genes), measured_gene_n = sum(genes %in% identity$features), missing_genes = .sc_project_array(setdiff(genes, identity$features)),
                                scope_n_cells = length(ids), denominator = "All exact selected-cluster cells, including low-depth cells"),
                panel = .sc_project_gene_summary(identity, ids), coexpression = co$summary,
                identity_threshold_sensitivity = lapply(1:3, function(threshold) .sc_project_coexpression(identity, ids, threshold)$summary),
                qc = .sc_project_qc_summary(identity, metadata, ids), cells = cells, candidate_controls = controls,
                comparisons = list(all_rest = list(n_cells = length(rest_ids), panel = if (length(rest_ids)) .sc_project_gene_summary(identity, rest_ids) else list()),
                                   candidate_lymphocyte = list(cluster_ids = .sc_project_array(selected), n_cells = length(selected_ids), panel = if (length(selected_ids)) .sc_project_gene_summary(identity, selected_ids) else list()),
                                   interpretation = "Both denominators are observed expression comparisons; neither confirms identity."),
                limitations = .sc_project_array(c("Exploratory uncalibrated rules do not provide biological probabilities.", "Missing genes and unavailable normalized/QC values are null; measured zeros remain zeros.",
                                                  "T/NK coexpression establishes neither NKT identity nor doublets.", "No cells removed or values recomputed; full matrix remains local.")))
  asset$package_id <- .sc_project_sha_text(.sc_project_json(asset))
  asset
}
