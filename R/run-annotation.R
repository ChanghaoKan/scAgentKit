# Internal analysis/annotation adapters for the resumable R coordinator.
# Provider calls, approval state, and journaling are deliberately owned by the
# coordinator. These helpers only execute supported local computations.

.sc_run_annotation_option <- function(config, name, default = NULL) {
  value <- config[[name]]
  if (is.null(value)) default else value
}

.sc_run_annotation_options <- function(value, allowed, name) {
  if (is.null(value)) return(list())
  if (!is.list(value) || (length(value) &&
      (is.null(names(value)) || anyNA(names(value)) ||
       any(!nzchar(names(value))) || anyDuplicated(names(value))))) {
    stop(name, " must be a named list.", call. = FALSE)
  }
  foreign <- setdiff(names(value), allowed)
  if (length(foreign)) stop("Unsupported ", name, " settings: ",
                            paste(foreign, collapse = ", "), call. = FALSE)
  value
}

.sc_run_analyze <- function(seu, config) {
  allowed <- c("normalization_method", "scale_factor", "nfeatures", "npcs",
               "dims", "resolution", "seed", "run_umap", "umap_neighbors")
  settings <- .sc_run_annotation_options(config$analysis, allowed, "analysis")
  assay <- .sc_run_annotation_option(config, "assay", "RNA")
  counts_layer <- .sc_run_annotation_option(config, "counts_layer", "counts")
  if (!identical(.sc_run_annotation_option(config, "normalized_layer", "data"), "data")) {
    stop("Standard preparation writes the explicit 'data' layer; select normalized_layer='data'.",
         call. = FALSE)
  }
  cells <- colnames(.sc_project_unwrap(seu))
  out <- do.call(sc_project_prepare, c(list(object = seu, assay = assay,
    counts_layer = counts_layer,
    cluster_column = .sc_run_annotation_option(config, "cluster_column", "seurat_clusters")),
    settings))
  out <- .sc_project_unwrap(out)
  if (!identical(colnames(out), cells)) stop("Analysis changed input cell IDs.", call. = FALSE)
  out
}

.sc_run_empty_markers <- function() {
  data.frame(p_val = numeric(), avg_log2FC = numeric(), pct.1 = numeric(),
             pct.2 = numeric(), p_val_adj = numeric(), cluster = character(),
             gene = character(), stringsAsFactors = FALSE)
}

.sc_run_markers <- function(seu, config) {
  seu <- .sc_project_unwrap(seu)
  allowed <- c("only_pos", "min_pct", "logfc_threshold", "top_n", "log2fc_cut", "padj_cut")
  requested <- .sc_run_annotation_options(config$markers, allowed, "markers")
  settings <- utils::modifyList(list(only_pos = FALSE, min_pct = 0.25,
    logfc_threshold = 0, top_n = 30L, log2fc_cut = 1, padj_cut = 0.05), requested)
  if (!is.logical(settings$only_pos) || length(settings$only_pos) != 1L || is.na(settings$only_pos))
    stop("markers$only_pos must be TRUE or FALSE.", call. = FALSE)
  for (key in c("min_pct", "logfc_threshold", "log2fc_cut", "padj_cut", "top_n")) {
    v <- settings[[key]]
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) ||
        (key %in% c("min_pct", "padj_cut") && (v < 0 || v > 1)) ||
        (key == "logfc_threshold" && v < 0) ||
        (key == "top_n" && (v < 1 || v != floor(v) || v > .Machine$integer.max)))
      stop("Invalid markers$", key, ".", call. = FALSE)
  }
  assay <- .sc_run_annotation_option(config, "assay", "RNA")
  cluster_column <- .sc_run_annotation_option(config, "cluster_column", "seurat_clusters")
  normalized_layer <- .sc_run_annotation_option(config, "normalized_layer", "data")
  if (is.null(normalized_layer)) stop("Marker testing requires an explicit normalized layer.", call. = FALSE)
  identity <- .sc_project_identity(seu, assay,
    .sc_run_annotation_option(config, "counts_layer", "counts"),
    normalized_layer, cluster_column)
  # Give the existing marker engine an isolated exact-layer view. This avoids
  # implicit selection of data.* layers, changes to Idents, or mutation of the
  # supplied object. Both full expression layers remain sparse.
  working <- Seurat::CreateSeuratObject(counts = identity$counts, assay = assay,
                                        min.cells = 0, min.features = 0)
  if (!identical(rownames(working), rownames(identity$counts)) ||
      !identical(colnames(working), identity$cells))
    stop("Marker preparation would rename source feature or cell IDs; prepare literal IDs explicitly.", call. = FALSE)
  SeuratObject::LayerData(working, assay = assay, layer = "data") <- identity$data
  working$seurat_clusters <- unname(identity$membership)
  SeuratObject::Idents(working) <- working$seurat_clusters
  agent <- AgentSeurat(working)
  agent <- sc_find_markers(agent, only_pos = settings$only_pos,
    min_pct = settings$min_pct, logfc_threshold = settings$logfc_threshold)
  if (!nrow(agent@params$all_markers)) agent@params$all_markers <- .sc_run_empty_markers()
  # Some Wilcoxon implementations produce tiny floating roundoff outside [0,1].
  # Preserve exact returned values and clamp only bounded numerical noise.
  for (field in c("p_val", "p_val_adj")) {
    raw <- agent@params$all_markers[[field]]
    if (any(!is.finite(raw)) || any(raw < -1e-10 | raw > 1 + 1e-10))
      stop("Marker p-values outside numerical tolerance; no evidence was accepted.", call. = FALSE)
    agent@params$all_markers[[paste0(field, "_raw")]] <- raw
    agent@params$all_markers[[field]] <- pmax(0, pmin(1, raw))
  }

  agent <- sc_markers_summary(agent, top_n = settings$top_n,
    log2fc_cut = settings$log2fc_cut, padj_cut = settings$padj_cut, output_path = NULL)
  markers <- agent@params$all_markers
  summary <- as.data.frame(agent@params$markers_filtered)
  markers$cluster <- as.character(markers$cluster)
  summary$cluster <- as.character(summary$cluster)
  attr(markers, "cluster_column") <- attr(summary, "cluster_column") <- cluster_column
  list(markers = markers, marker_summary = summary,
       summary_lines = agent@params$markers_summary,
       cycling_score = agent@params$cluster_cycling_score,
       cluster_column = cluster_column, parameters = settings)
}

.sc_run_annotation_marker_records <- function(table) {
  required <- c("cluster", "gene", "avg_log2FC", "pct.1", "pct.2", "p_val_adj")
  if (!is.data.frame(table) || !all(required %in% names(table)))
    stop("Markers require cluster, gene, avg_log2FC, pct.1, pct.2, p_val_adj columns.", call. = FALSE)
  if (anyNA(table$cluster) || anyNA(table$gene) ||
      any(!nzchar(as.character(table$cluster))) || any(!nzchar(as.character(table$gene))))
    stop("Marker cluster and gene IDs must be nonempty literal strings.", call. = FALSE)
  lapply(seq_len(nrow(table)), function(i) list(clusterId = as.character(table$cluster[i]),
    gene = as.character(table$gene[i]), avgLog2FC = unname(table$avg_log2FC[i]),
    pct1 = unname(table$pct.1[i]), pct2 = unname(table$pct.2[i]),
    pAdj = unname(table$p_val_adj[i]), source = "Seurat::FindAllMarkers"))
}

.sc_run_annotation_candidate_records <- function(table) {
  if (is.null(table)) return(list())
  if (!is.data.frame(table) || !all(names(.empty_reference_matches()) %in% names(table)))
    stop("Candidates must be a saved local reference match table.", call. = FALSE)
  lapply(seq_len(nrow(table)), function(i) list(clusterId = as.character(table$cluster[i]),
    label = as.character(table$cell_type[i]), score = unname(table$score[i]),
    overlap = unname(table$overlap_count[i]), referenceSize = unname(table$celltype_size[i]),
    markers = .sc_project_array(.review_genes(table$matched_markers[i])),
    source = "local_marker_reference"))
}

.sc_run_annotation_evidence <- function(seu, markers, context, reference = NULL,
                                        cluster_column = NULL) {
  seu <- .sc_project_unwrap(seu)
  if (is.list(markers) && !is.data.frame(markers)) {
    if (is.null(cluster_column)) cluster_column <- markers$cluster_column
    table <- markers$marker_summary
  } else {
    table <- markers
    if (is.null(cluster_column)) cluster_column <- attr(markers, "cluster_column")
  }
  if (is.null(cluster_column)) cluster_column <- "seurat_clusters"
  .sc_project_string(cluster_column, "cluster_column")
  metadata <- seu[[]]
  if (sum(names(metadata) == cluster_column) != 1L)
    stop("Selected cluster column is absent or ambiguous.", call. = FALSE)
  cells <- colnames(seu)
  .sc_project_ids(cells, "Annotation cell IDs")
  .sc_project_ids(rownames(metadata), "Annotation metadata cell IDs")
  if (!setequal(cells, rownames(metadata))) stop("Annotation metadata cell IDs differ.", call. = FALSE)
  membership <- as.character(metadata[cells, cluster_column])
  if (anyNA(membership) || any(!nzchar(membership))) stop("Annotation requires complete literal cluster IDs.", call. = FALSE)
  cluster_ids <- sort(unique(membership), method = "radix")
  records <- .sc_run_annotation_marker_records(table)
  records <- .sc_project_records(records, c("clusterId", "gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source"),
                                 "marker_table", cluster_ids)
  context <- .sc_project_object(context, "context")
  input_cells <- data.frame(cell_id = cells, cluster = membership, stringsAsFactors = FALSE)
  matches <- all_matches <- .empty_reference_matches()
  provenance <- list(status = "not_supplied", mode = "independent_local_reference")
  if (!is.null(reference)) {
    if (is.character(reference) && length(reference) == 1L)
      reference <- annot_load_reference(reference, tissue_filter = context$tissue, species = context$species)
    else {
      reference <- .validate_marker_reference(reference)
      if (!is.null(context$tissue) && "tissue" %in% names(reference)) {
        keep <- tolower(as.character(reference$tissue)) %in% c(tolower(context$tissue), "all")
        reference <- reference[!is.na(keep) & keep, , drop = FALSE]
      }
      if (!is.null(context$species) && "species" %in% names(reference)) {
        keep <- tolower(as.character(reference$species)) %in% tolower(context$species)
        reference <- reference[!is.na(keep) & keep, , drop = FALSE]
      }
      attr(reference, "tissue_filter") <- context$tissue
      attr(reference, "species") <- context$species
    }
    local_object <- seu
    local_object$seurat_clusters <- stats::setNames(membership, cells)
    agent <- AgentSeurat(local_object)
    agent@params$markers_filtered <- table
    agent <- annot_match_reference(agent, reference)
    matches <- agent@params$reference_matches
    all_matches <- agent@params$reference_matches_all
    provenance <- c(list(status = "matched", mode = "independent_local_reference"),
                    agent@params$reference_provenance)
  }
  # The public summary intentionally omits database labels, cell IDs, and
  # metadata values. The LLM sees an independent aggregate evidence branch.
  summary <- list(schema = "scagentkit.annotation-evidence.v1", context = context,
    clusters = lapply(cluster_ids, function(id) list(clusterId = id,
      cellCount = sum(membership == id),
      markers = unname(Filter(function(x) identical(x$clusterId, id), records)))))
  list(summary = summary, private = list(input_cells = input_cells,
    cluster_column = cluster_column, candidates = matches,
    candidates_all = all_matches, reference_provenance = provenance))
}

.sc_run_annotation_validate <- function(proposal, evidence) {
  object_fields <- function(value, fields, name) {
    if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
        anyDuplicated(names(value)) || !setequal(names(value), fields))
      stop(name, " must contain exactly: ", paste(fields, collapse = ", "), ".", call. = FALSE)
  }
  object_fields(proposal, c("schema", "annotations"), "Annotation proposal")
  if (!identical(proposal$schema, "scagentkit.annotation.v1"))
    stop("Unsupported annotation proposal schema.", call. = FALSE)
  entries <- proposal$annotations
  if (!is.list(entries) || !is.null(names(entries)) || !length(entries))
    stop("Annotation annotations must be a nonempty JSON array.", call. = FALSE)
  if (!is.list(evidence$summary$clusters) || !length(evidence$summary$clusters) ||
      !is.data.frame(evidence$private$input_cells))
    stop("Saved annotation evidence is incomplete.", call. = FALSE)
  clusters <- evidence$summary$clusters
  ids <- vapply(clusters, function(x) x$clusterId, character(1))
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids))
    stop("Saved annotation evidence has invalid cluster IDs.", call. = FALSE)
  normalized <- lapply(entries, function(entry) {
    object_fields(entry, c("clusterId", "label", "confidence", "rationale", "markers"), "Annotation row")
    .sc_project_string(entry$clusterId, "annotation clusterId")
    if (!entry$clusterId %in% ids) stop("Annotation proposal refers to a foreign cluster ID.", call. = FALSE)
    # Reuse the existing strict annotation validator for common typed fields.
    parsed <- .validate_annotation_response(list(cluster = entry$clusterId,
      primary_annotation = entry$label, confidence = entry$confidence,
      supporting_markers = entry$markers, contradicting_markers = list(),
      alternative_annotations = list(), proportion_assessment = "reasonable",
      recommended_action = "flag_for_review", reasoning = entry$rationale),
      expected_cluster = entry$clusterId)
    genes <- parsed$supporting_markers
    if (anyDuplicated(genes)) stop("Annotation marker citations must be unique.", call. = FALSE)
    source <- clusters[[match(entry$clusterId, ids)]]
    admissible <- vapply(source$markers, function(x) x$gene, character(1))
    if (any(!genes %in% admissible)) stop("Annotation cites genes absent from the supplied cluster evidence.", call. = FALSE)
    if (!length(genes) && !tolower(trimws(parsed$primary_annotation)) %in% c("unknown", "unannotated"))
      stop("A known annotation requires supporting marker evidence; use Unknown when uncertain.", call. = FALSE)
    list(clusterId = entry$clusterId, label = parsed$primary_annotation,
         confidence = parsed$confidence, rationale = parsed$reasoning,
         markers = .sc_project_array(genes))
  })
  supplied_ids <- vapply(normalized, function(x) x$clusterId, character(1))
  if (anyDuplicated(supplied_ids)) stop("Duplicate annotation cluster ID.", call. = FALSE)
  if (!setequal(supplied_ids, ids)) stop("Annotation proposal must include every evidence cluster exactly once.", call. = FALSE)
  out <- list(schema = proposal$schema,
              annotations = normalized[match(ids, supplied_ids)])
  attr(out, "input_cells") <- evidence$private$input_cells
  attr(out, "cluster_column") <- evidence$private$cluster_column
  class(out) <- c("sc_run_annotation_proposal", "list")
  out
}

.sc_run_annotation_apply <- function(seu, proposal, column = "sc_annotation") {
  seu <- .sc_project_unwrap(seu)
  .sc_project_string(column, "annotation column")
  if (!inherits(proposal, "sc_run_annotation_proposal") ||
      is.null(attr(proposal, "input_cells")) || is.null(attr(proposal, "cluster_column")))
    stop("Validate the proposal against saved evidence before annotation apply.", call. = FALSE)
  metadata <- seu[[]]
  cluster_column <- attr(proposal, "cluster_column")
  if (sum(names(metadata) == cluster_column) != 1L)
    stop("Approved annotation cluster column is absent or ambiguous.", call. = FALSE)
  cells <- colnames(seu)
  current <- data.frame(cell_id = cells, cluster = as.character(metadata[cells, cluster_column]),
                        stringsAsFactors = FALSE)
  if (!identical(.review_input_alignment(attr(proposal, "input_cells"), current), "verified"))
    stop("Approved annotation cell IDs or cluster assignments differ from the current object.", call. = FALSE)
  fields <- c(label = column, confidence = paste0(column, "_confidence"),
              rationale = paste0(column, "_rationale"))
  if (any(unname(fields) %in% names(metadata)))
    stop("Annotation output columns already exist; choose a new column to preserve prior annotations.", call. = FALSE)
  ids <- vapply(proposal$annotations, function(x) x$clusterId, character(1))
  for (field in names(fields)) {
    mapping <- stats::setNames(vapply(proposal$annotations, function(x) x[[field]], character(1)), ids)
    values <- unname(mapping[current$cluster])
    if (anyNA(values)) stop("Approved annotation does not cover every current cell.", call. = FALSE)
    seu[[fields[[field]]]] <- stats::setNames(values, cells)
  }
  if (!identical(colnames(seu), cells)) stop("Annotation changed the cell universe.", call. = FALSE)
  seu
}

.sc_run_bundle <- function(seu, markers, candidates, project_dir, config) {
  seu <- .sc_project_unwrap(seu)
  .sc_project_string(project_dir, "project_dir")
  if (!dir.exists(project_dir) && !dir.create(project_dir, recursive = TRUE))
    stop("Cannot create bundle parent directory.", call. = FALSE)
  project_dir <- normalizePath(project_dir, mustWork = TRUE)
  table <- if (is.list(markers) && !is.data.frame(markers)) markers$marker_summary else markers
  if (is.list(candidates) && !is.data.frame(candidates)) candidates <- candidates$private$candidates
  marker_records <- .sc_run_annotation_marker_records(table)
  candidate_records <- .sc_run_annotation_candidate_records(candidates)
  column <- .sc_run_annotation_option(config, "annotation_column", "sc_annotation")
  source_annotation <- if (!is.null(config$source_annotation)) config$source_annotation
                       else if (column %in% names(seu[[]])) column else NULL
  assay <- .sc_run_annotation_option(config, "assay", "RNA")
  reduction <- if (!is.null(config$reduction)) config$reduction
               else if ("umap" %in% names(seu@reductions)) "umap" else NULL
  target <- file.path(project_dir, "bundle")
  stage <- tempfile(".sc-run-bundle-", tmpdir = project_dir)
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE), add = TRUE)
  exported <- sc_project_export(seu, stage,
    project_id = .sc_run_annotation_option(config, "project_id", basename(project_dir)),
    assay = assay, counts_layer = .sc_run_annotation_option(config, "counts_layer", "counts"),
    normalized_layer = .sc_run_annotation_option(config, "normalized_layer", "data"),
    cluster_column = .sc_run_annotation_option(config, "cluster_column", "seurat_clusters"),
    reduction = reduction, marker_table = marker_records, candidate_table = candidate_records,
    source_annotation = source_annotation,
    metadata_allowlist = c(paste0("nCount_", assay), paste0("nFeature_", assay), "percent.mt"),
    parameters = list(coordinatorSchema = "scagentkit.run.v1",
      analysis = .sc_project_map(.sc_run_annotation_option(config, "analysis", list())),
      markers = .sc_project_map(.sc_run_annotation_option(config, "markers", list())),
      annotationColumn = column, batchIntegration = "skip/manual"),
    provenance = list(generatedBy = "sc_run", localDirectory = TRUE), archive = FALSE)
  if (file.exists(target) || dir.exists(target)) {
    manifest_file <- file.path(target, "manifest.json")
    project_file <- file.path(target, "project.json")
    saved <- tryCatch(jsonlite::fromJSON(manifest_file, simplifyVector = FALSE), error = function(e) NULL)
    valid_files <- !is.null(saved) && is.list(saved$files) && length(saved$files) &&
      all(vapply(saved$files, function(item) {
        if (!is.character(item$path) || length(item$path) != 1L ||
            grepl("(^|[/\\\\])\\.\\.([/\\\\]|$)|^[/\\\\]", item$path)) return(FALSE)
        path <- file.path(target, item$path)
        file.exists(path) && identical(.sc_project_sha_file(path), item$sha256)
      }, logical(1)))
    if (!valid_files || !file.exists(project_file) ||
        !identical(saved$sourceFingerprint, exported$sourceFingerprint) ||
        !identical(saved$bundleDigest, exported$bundleDigest) ||
        !identical(.sc_project_sha_file(project_file), exported$bundleDigest))
      stop("Existing bundle differs from the current object/evidence or is corrupt; preserve it and choose a new project directory.", call. = FALSE)
    exported$path <- target
    return(exported)
  }
  if (!file.rename(stage, target)) stop("Cannot atomically publish the managed bundle directory.", call. = FALSE)
  exported$path <- target
  exported
}
