# Local, scoped reference evidence. These adapters never call a model, read a
# credential, compute expression, or change the supplied Seurat object.
.sc_run_reference_normalize <- function(x) tolower(trimws(as.character(x)))

.sc_run_reference_map <- function(value, name, labels = FALSE) {
  if (is.null(value) || !length(value)) return(stats::setNames(character(), character()))
  if (!is.character(value) || is.null(names(value)) || anyNA(value) ||
      anyNA(names(value)) || any(!nzchar(trimws(value))) ||
      any(!nzchar(trimws(names(value)))))
    stop(name, " must be a named character vector of nonempty values.", call. = FALSE)
  value <- stats::setNames(trimws(unname(value)), trimws(names(value)))
  keys <- if (labels) .sc_run_reference_normalize(names(value)) else names(value)
  if (anyDuplicated(keys)) stop(name, " keys must be unique.", call. = FALSE)
  .sc_run_reference_resolve(names(value), value, labels)
  value
}

.sc_run_reference_resolve <- function(values, mapping, labels = FALSE) {
  normalize <- if (labels) .sc_run_reference_normalize else trimws
  keys <- normalize(names(mapping))
  targets <- normalize(unname(mapping))
  vapply(normalize(as.character(values)), function(value) {
    visited <- character()
    while (value %in% keys) {
      if (value %in% visited) stop("Cyclic alias or label mapping.", call. = FALSE)
      visited <- c(visited, value)
      next_value <- targets[match(value, keys)]
      # Identity entries are useful declarations, not cycles.
      if (identical(value, next_value)) break
      value <- next_value
    }
    value
  }, character(1), USE.NAMES = FALSE)
}

.sc_run_reference_relations <- function(value, mapping) {
  if (is.null(value)) value <- data.frame(child = character(), parent = character(),
                                         lineage = character(), stringsAsFactors = FALSE)
  if (!is.data.frame(value) || !all(c("child", "parent") %in% names(value)) ||
      anyDuplicated(names(value)) || length(setdiff(names(value), c("child", "parent", "lineage"))))
    stop("label_relations requires child, parent, and optional lineage columns.", call. = FALSE)
  for (field in c("child", "parent")) {
    if (!is.character(value[[field]]) || anyNA(value[[field]]) ||
        any(!nzchar(trimws(value[[field]]))))
      stop("label_relations ", field, " must contain nonempty character values.", call. = FALSE)
    value[[field]] <- trimws(value[[field]])
  }
  if (!"lineage" %in% names(value)) value$lineage <- rep(NA_character_, nrow(value))
  if (!is.character(value$lineage) || any(!is.na(value$lineage) & !nzchar(trimws(value$lineage))))
    stop("label_relations lineage must be character or explicitly unavailable (NA).", call. = FALSE)
  value$lineage <- trimws(value$lineage)
  value <- value[, c("child", "parent", "lineage"), drop = FALSE]
  child <- .sc_run_reference_resolve(value$child, mapping, TRUE)
  parent <- .sc_run_reference_resolve(value$parent, mapping, TRUE)
  if (any(child == parent) || anyDuplicated(child))
    stop("label_relations requires unique children and distinct child/parent labels.", call. = FALSE)
  for (start in child) {
    visited <- character(); node <- start
    while (node %in% child) {
      if (node %in% visited) stop("Cyclic label_relations.", call. = FALSE)
      visited <- c(visited, node); node <- parent[match(node, child)]
    }
  }
  declarations <- split(rep(.sc_run_reference_normalize(value$lineage), 2L), c(child, parent))
  if (any(vapply(declarations, function(x) length(unique(x[!is.na(x)])) > 1L, logical(1))))
    stop("Conflicting explicit lineage declarations.", call. = FALSE)
  rownames(value) <- NULL
  value
}

.sc_run_reference_options <- function(value = NULL) {
  value <- .sc_run_annotation_options(value,
    c("top_n", "symbol_aliases", "label_map", "label_relations", "ai_mode", "provenance"),
    "reference_review")
  top_n <- if (is.null(value$top_n)) 5L else value$top_n
  if (!is.numeric(top_n) || length(top_n) != 1L || !is.finite(top_n) ||
      top_n < 1 || top_n != floor(top_n) || top_n > .Machine$integer.max)
    stop("reference_review$top_n must be one positive integer.", call. = FALSE)
  mode <- if (is.null(value$ai_mode)) "independent" else value$ai_mode
  if (!is.character(mode) || length(mode) != 1L || is.na(mode) ||
      !mode %in% c("independent", "guided"))
    stop("reference_review$ai_mode must be independent or guided.", call. = FALSE)
  aliases <- .sc_run_reference_map(value$symbol_aliases, "symbol_aliases")
  labels <- .sc_run_reference_map(value$label_map, "label_map", TRUE)
  provenance <- .sc_run_annotation_options(value$provenance,
    c("version", "source_url", "license", "retrieved_at", "original_sha256",
      "source_sha256", "preparation_note"), "reference provenance")
  for (field in names(provenance)) {
    x <- provenance[[field]]
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x)))
      stop("Reference provenance ", field, " must be one nonempty string.", call. = FALSE)
    provenance[[field]] <- trimws(x)
    if (field %in% c("original_sha256", "source_sha256") &&
        !grepl("^[0-9a-f]{64}$", provenance[[field]]))
      stop("Reference provenance ", field, " must be a lowercase SHA256.", call. = FALSE)
  }
  list(top_n = as.integer(top_n), symbol_aliases = aliases, label_map = labels,
       label_relations = .sc_run_reference_relations(value$label_relations, labels),
       ai_mode = mode, provenance = provenance)
}

.sc_run_reference_symbols <- function(genes, aliases) {
  original <- trimws(as.character(genes))
  canonical <- .sc_run_reference_resolve(original, aliases)
  changed <- unique(data.frame(original = original[original != canonical],
    canonical = canonical[original != canonical], stringsAsFactors = FALSE))
  list(original = .sc_project_array(original), canonical = .sc_project_array(canonical),
       unique = .sc_project_array(unique(canonical)),
       duplicate_count = length(canonical) - length(unique(canonical)),
       alias_resolutions = lapply(seq_len(nrow(changed)), function(i)
         list(original = changed$original[i], canonical = changed$canonical[i])))
}

.sc_run_reference_scoring <- function() list(
  formula = "unique hits / unique reference genes", quantity = "reference-marker coverage",
  denominator = "unique canonical reference genes", calibrated_probability = FALSE)

.sc_run_reference_evidence <- function(seu, table, context, reference = NULL,
                                       cluster_column = "seurat_clusters", options = NULL) {
  options <- .sc_run_reference_options(options)
  seu <- .sc_project_unwrap(seu)
  metadata <- seu[[]]; cells <- colnames(seu)
  .sc_project_ids(cells, "Reference evidence cell IDs")
  .sc_project_string(cluster_column, "reference cluster_column")
  if (sum(names(metadata) == cluster_column) != 1L ||
      !identical(rownames(metadata), cells))
    stop("Reference evidence requires aligned, unambiguous cluster metadata.", call. = FALSE)
  membership <- as.character(metadata[[cluster_column]])
  if (anyNA(membership) || any(!nzchar(membership)))
    stop("Reference evidence requires complete literal cluster IDs.", call. = FALSE)
  ids <- sort(unique(membership), method = "radix")
  if (!is.data.frame(table) || anyDuplicated(names(table)) ||
      !all(c("cluster", "gene") %in% names(table)) || anyNA(table$cluster) ||
      anyNA(table$gene) || any(!nzchar(as.character(table$cluster))) ||
      any(!nzchar(trimws(as.character(table$gene)))) ||
      any(!as.character(table$cluster) %in% ids))
    stop("Reference marker table requires current cluster IDs and nonempty genes.", call. = FALSE)
  table <- table[, c("cluster", "gene"), drop = FALSE]
  table$cluster <- as.character(table$cluster); table$gene <- trimws(as.character(table$gene))
  marker_original <- table
  table$gene <- .sc_run_reference_resolve(table$gene, options$symbol_aliases)
  table <- unique(table); rownames(table) <- NULL
  features <- .sc_run_reference_resolve(rownames(seu), options$symbol_aliases)
  context <- .sc_project_object(context, "reference context")
  requested <- lapply(c("species", "tissue"), function(field) {
    value <- context[[field]]
    if (is.null(value)) return(NULL)
    .sc_project_string(value, paste0("reference context$", field))
    if (field == "species") .sc_run_species(value) else trimws(value)
  }); names(requested) <- c("species", "tissue")
  provenance <- list(status = "not_supplied", mode = "local_marker_reference",
    species = requested$species, tissue_filter = requested$tissue,
    scope = list(method = "trimmed_case_insensitive_exact", tissue_all_rows = 0L,
                 species_method = "explicit_human_mouse_aliases",
                 unavailable_columns = list(), excluded_unavailable_rows = 0L),
    license = "unknown", source_path = NULL, source_md5 = NULL, source_sha256 = NULL,
    source_url = NULL, requested_url = NULL, source_url_verified = NULL,
    source_version = NULL, marker_column = NULL, retrieved_at = NULL,
    source_file_status = "not_recorded", n_input_rows = 0L, n_scoped_rows = 0L,
    n_unique_pairs = 0L, duplicate_pair_count = 0L,
    feature_scope = list(assay = SeuratObject::DefaultAssay(seu),
                        source = "default_assay_feature_ids"),
    scoring = .sc_run_reference_scoring(), symbol_aliases = as.list(options$symbol_aliases),
    marker_symbols = .sc_run_reference_symbols(marker_original$gene, options$symbol_aliases))
  matches <- all_matches <- .empty_reference_matches()
  scoped <- data.frame(cell_type = character(), marker = character(), stringsAsFactors = FALSE)
  if (!is.null(reference)) {
    if (is.character(reference) && length(reference) == 1L && !is.na(reference))
      reference <- annot_load_reference(reference)
    if (!is.data.frame(reference) || anyDuplicated(names(reference)))
      stop("Reference must be an unambiguous data frame or readable local file.", call. = FALSE)
    reference <- .validate_marker_reference(reference)
    provenance$n_input_rows <- nrow(reference)
    provenance$adapter <- lapply(c("species", "tissue_filter", "cancer_only", "n_celltypes", "n_input_rows"),
                                function(field) attr(reference, field))
    names(provenance$adapter) <- c("species", "tissue_filter", "cancer_only", "n_celltypes", "n_input_rows")
    for (field in c("source_path", "source_md5", "source_url", "requested_url",
                    "source_url_verified", "source_version", "marker_column", "retrieved_at", "license")) {
      value <- attr(reference, field)
      if (!is.null(value)) provenance[[field]] <- value
    }
    for (field in names(options$provenance)) {
      target <- switch(field, version = "source_version", field)
      provenance[[target]] <- options$provenance[[field]]
    }
    if (is.null(provenance$license) || (length(provenance$license) == 1L &&
        (is.na(provenance$license) || !nzchar(provenance$license)))) provenance$license <- "unknown"
    path <- provenance$source_path
    if (is.character(path) && length(path) == 1L && !is.na(path) && file.exists(path) &&
        !dir.exists(path) && file.access(path, 4L) == 0L) {
      if (!is.null(options$provenance$source_sha256))
        provenance$declared_source_sha256 <- options$provenance$source_sha256
      provenance$source_sha256 <- digest::digest(file = path, algo = "sha256")
      observed_md5 <- unname(tools::md5sum(path))
      provenance$source_file_status <- if (!is.null(provenance$source_md5) &&
        !identical(observed_md5, provenance$source_md5)) "recorded_md5_mismatch" else "readable"
      provenance$observed_source_md5 <- observed_md5
    } else if (!is.null(path)) provenance$source_file_status <- "unavailable"
    provenance$reference_symbols <- .sc_run_reference_symbols(reference$marker, options$symbol_aliases)
    missing <- c(setdiff(c("species", "tissue"), names(reference)),
                 names(requested)[vapply(requested, is.null, logical(1))])
    if (!nrow(reference)) provenance$status <- "empty_reference" else if (length(missing)) {
      provenance$status <- "scope_unavailable"
      provenance$scope$unavailable_columns <- .sc_project_array(unique(missing))
    } else {
      for (field in c("species", "tissue")) {
        if (!is.character(reference[[field]]) && !is.factor(reference[[field]]))
          stop("Reference scope columns must be character values.", call. = FALSE)
      }
      species <- .sc_run_species_values(reference$species)
      tissue <- .sc_run_reference_normalize(reference$tissue)
      available <- !is.na(species) & nzchar(species) & !is.na(tissue) & nzchar(tissue)
      provenance$scope$excluded_unavailable_rows <- sum(!available)
      keep <- available & species == .sc_run_reference_normalize(requested$species) &
        tissue %in% c(.sc_run_reference_normalize(requested$tissue), "all")
      scoped <- reference[keep, , drop = FALSE]
      provenance$n_scoped_rows <- nrow(scoped)
      provenance$scope$tissue_all_rows <- sum(tissue[keep] == "all")
      provenance$status <- if (!any(available)) "scope_unavailable" else if (!nrow(scoped))
        "scope_mismatch" else "matched"
      if (nrow(scoped)) {
        scoped$marker <- .sc_run_reference_resolve(scoped$marker, options$symbol_aliases)
        unique_pair <- !duplicated(scoped[, c("cell_type", "marker"), drop = FALSE])
        provenance$duplicate_pair_count <- sum(!unique_pair)
        scoped <- scoped[unique_pair, , drop = FALSE]
        provenance$n_unique_pairs <- nrow(scoped)
        local <- seu
        local$seurat_clusters <- stats::setNames(membership, cells)
        agent <- AgentSeurat(local); agent@params$markers_filtered <- table
        agent <- annot_match_reference(agent, scoped, top_n_candidates = options$top_n)
        matches <- agent@params$reference_matches; all_matches <- agent@params$reference_matches_all
        if (!nrow(matches)) provenance$status <- "no_overlap"
      }
    }
  }
  by_type <- split(scoped$marker, scoped$cell_type)
  per_cluster <- lapply(ids, function(id) {
    all <- all_matches[all_matches$cluster == id, , drop = FALSE]
    positive <- all[all$overlap_count > 0L, , drop = FALSE]
    best <- if (nrow(positive)) max(positive$score) else NA_real_
    genes <- table$gene[table$cluster == id]
    candidates <- lapply(seq_len(nrow(all)), function(i) {
      row <- all[i, , drop = FALSE]; ref_genes <- unique(by_type[[row$cell_type]])
      list(clusterId = id, label = row$cell_type, score = unname(row$score),
        overlap = unname(row$overlap_count), referenceSize = unname(row$celltype_size),
        markers = .sc_project_array(intersect(genes, ref_genes)),
        referenceGenes = .sc_project_array(ref_genes),
        availableGenes = .sc_project_array(intersect(ref_genes, features)),
        unmeasuredGenes = .sc_project_array(setdiff(ref_genes, features)),
        notInTopMarkers = .sc_project_array(setdiff(intersect(ref_genes, features), genes)),
        formula = .sc_run_reference_scoring()$formula,
        tiedBest = is.finite(best) && abs(row$score - best) <= 1e-12,
        source = "local_marker_reference")
    })
    shown <- head(Filter(function(x) x$overlap > 0L, candidates), options$top_n)
    status <- provenance$status
    if (status %in% c("matched", "no_overlap")) status <- if (!length(genes))
      "missing_marker_information" else if (length(shown)) "matched" else "no_overlap"
    list(clusterId = id, cellCount = sum(membership == id), status = status,
      candidates = shown, all_candidates = candidates,
      marker_symbols = .sc_run_reference_symbols(marker_original$gene[marker_original$cluster == id],
                                                options$symbol_aliases))
  })
  list(schema = "scagentkit.reference-evidence.v1", matches = matches, all_matches = all_matches,
       provenance = provenance, per_cluster = per_cluster)
}

.sc_run_joint_label_relation <- function(label, reference_label, options) {
  raw <- .sc_run_reference_normalize(c(label, reference_label))
  canonical <- .sc_run_reference_resolve(c(label, reference_label), options$label_map, TRUE)
  if (identical(raw[1], raw[2])) return(list(status = "exact_label", relation = "normalized_name"))
  if (identical(canonical[1], canonical[2])) return(list(status = "mapped_name", relation = "explicit_label_map"))
  relations <- options$label_relations
  child <- .sc_run_reference_resolve(relations$child, options$label_map, TRUE)
  parent <- .sc_run_reference_resolve(relations$parent, options$label_map, TRUE)
  ancestors <- function(node) {
    out <- character()
    while (node %in% child) { node <- parent[match(node, child)]; out <- c(out, node) }
    out
  }
  if (canonical[1] %in% ancestors(canonical[2]) || canonical[2] %in% ancestors(canonical[1]))
    return(list(status = "granularity", relation = "explicit_ancestor_descendant"))
  lineages <- split(rep(.sc_run_reference_normalize(relations$lineage), 2L), c(child, parent))
  first <- unique(stats::na.omit(lineages[[canonical[1]]]))
  second <- unique(stats::na.omit(lineages[[canonical[2]]]))
  if (length(first) == 1L && length(second) == 1L && !identical(first, second))
    return(list(status = "lineage_disagreement", relation = "distinct_explicit_lineages"))
  list(status = "unresolved_label_difference", relation = "no_declared_equivalence_or_lineage_difference")
}

.sc_run_joint_citations <- function(row, supplied) {
  genes <- unname(unlist(row$markers, use.names = FALSE))
  if (is.null(genes)) genes <- character()
  if (!is.character(genes) || anyNA(genes) || any(!nzchar(genes)) || anyDuplicated(genes))
    stop("Joint evidence citations must be unique nonempty gene strings.", call. = FALSE)
  markers <- supplied$markers
  if (is.null(markers)) markers <- list()
  lapply(genes, function(gene) {
    hits <- Filter(function(x) is.list(x) && identical(x$gene, gene), markers)
    if (length(hits) > 1L) stop("Joint evidence marker statistics are ambiguous.", call. = FALSE)
    list(gene = gene, status = if (length(hits)) "supplied" else "unavailable",
         statistics = if (length(hits)) hits[[1]] else NULL)
  })
}

.sc_run_joint_row <- function(row, supplied) {
  if (!is.list(row) || !all(c("clusterId", "label", "confidence", "rationale", "markers") %in% names(row)))
    stop("Joint evidence requires a typed annotation row.", call. = FALSE)
  for (field in c("clusterId", "label", "confidence", "rationale"))
    .sc_project_string(row[[field]], paste0("joint evidence ", field))
  list(clusterId = row$clusterId, label = row$label, confidence = row$confidence,
       rationale = row$rationale, citations = .sc_run_joint_citations(row, supplied))
}

.sc_run_joint_source <- function(source) {
  if (is.null(source)) return(list(kind = "unknown"))
  if (!is.list(source)) stop("Joint evidence source must be recorded metadata.", call. = FALSE)
  out <- source[intersect(c("kind", "manual", "provider_response", "reference_dependency"), names(source))]
  if (!is.null(source$configured_provider))
    out$configured_provider <- .sc_run_annotation_review_provider(source$configured_provider)
  if (is.list(out$provider_response)) {
    out$provider_response <- out$provider_response[intersect(c("status", "kind", "artifact_sha256",
      "request_hash", "response_hash", "cached", "usage", "cost_usd", "matches_current"),
      names(out$provider_response))]
    out$provider_response$provider <- .sc_run_annotation_review_provider(source$provider_response$provider)
  }
  if (is.list(out$manual)) out$manual <- out$manual[intersect(
    c("status", "artifact_sha256", "proposal_hash"), names(out$manual))]
  if (is.null(out$kind)) out$kind <- "unknown"
  out
}

.sc_run_joint_evidence <- function(row, supplied, local_evidence, source,
                                    historical = NULL, options = NULL) {
  options <- .sc_run_reference_options(options)
  if (!is.list(supplied) || !identical(supplied$clusterId, row$clusterId))
    stop("Joint annotation evidence cluster binding differs.", call. = FALSE)
  current <- .sc_run_joint_row(row, supplied); current$source <- .sc_run_joint_source(source)
  provenance <- local_evidence$provenance
  local <- local_evidence
  if (!is.null(local_evidence$per_cluster)) {
    selected <- Filter(function(x) identical(x$clusterId, row$clusterId), local_evidence$per_cluster)
    if (length(selected) != 1L) stop("Joint reference evidence cluster binding differs.", call. = FALSE)
    local <- selected[[1]]
  }
  if (!is.list(local) || !identical(local$clusterId, row$clusterId))
    stop("Joint reference evidence requires a matching cluster record.", call. = FALSE)
  database <- list(status = local$status, candidates = local$candidates,
    all_candidates = local$all_candidates, provenance = provenance,
    marker_symbols = local$marker_symbols, scoring = .sc_run_reference_scoring())
  history <- list(status = "not_supplied", row = NULL, provenance = NULL, eligible_for_comparison = FALSE)
  comparison_row <- current; comparison_source <- "current_proposal"
  if (!is.null(historical)) {
    if (!is.list(historical) || !is.list(historical$provenance))
      stop("Historical evidence requires a row or annotations and declared provenance.", call. = FALSE)
    if ("row" %in% names(historical) ||
        (is.null(historical$annotations) && "source" %in% names(historical))) {
      selected <- if (is.null(historical$row)) list() else list(historical$row)
      if (length(selected) && !identical(selected[[1]]$clusterId, row$clusterId))
        stop("Historical evidence cluster binding differs.", call. = FALSE)
    } else {
      if (!is.list(historical$annotations))
        stop("Historical evidence requires a row or annotations.", call. = FALSE)
      selected <- Filter(function(x) is.list(x) && identical(x$clusterId, row$clusterId), historical$annotations)
    }
    if (length(selected) > 1L) stop("Duplicate historical evidence cluster.", call. = FALSE)
    history$provenance <- historical$provenance[intersect(c("kind", "provider", "model", "response_sha256",
      "source_object_sha256", "scope_status", "reference_dependency", "declaration"),
      names(historical$provenance))]
    if (is.list(history$provenance$provider))
      history$provenance$provider <- .sc_run_annotation_review_provider(history$provenance$provider)
    if (!is.null(historical$source)) history$source <- .sc_run_joint_source(historical$source)
    if (length(selected)) {
      history$status <- "supplied"; history$row <- .sc_run_joint_row(selected[[1]], supplied)
      history$eligible_for_comparison <- identical(history$provenance$scope_status, "verified") &&
        !.sc_run_reference_normalize(history$row$label) %in% c("unknown", "unannotated")
      if (isTRUE(history$eligible_for_comparison)) {
        comparison_row <- history$row; comparison_source <- "historical_model_response"
      }
    } else history$status <- "cluster_not_supplied"
  }
  positive <- Filter(function(x) is.numeric(x$score) && length(x$score) == 1L &&
      is.finite(x$score) && x$score > 0 && x$overlap > 0, local$all_candidates)
  related <- lapply(positive, function(candidate) c(list(label = candidate$label, score = candidate$score),
    .sc_run_joint_label_relation(comparison_row$label, candidate$label, options)))
  best <- Filter(function(x) isTRUE(x$tiedBest), positive)
  raw_best <- vapply(best, `[[`, character(1), "label")
  canonical_best <- unique(.sc_run_reference_resolve(raw_best, options$label_map, TRUE))
  best_relations <- lapply(best, function(x) .sc_run_joint_label_relation(comparison_row$label, x$label, options))
  status <- "missing_information"; reason <- "no_positive_scoped_reference_evidence"
  ambiguous <- length(canonical_best) > 1L
  if (.sc_run_reference_normalize(comparison_row$label) %in% c("unknown", "unannotated")) {
    reason <- "annotation_label_unresolved"
  } else if (length(best_relations)) {
    statuses <- vapply(best_relations, `[[`, character(1), "status")
    if (ambiguous && !all(statuses %in% c("exact_label", "mapped_name", "granularity"))) {
      reason <- "best_label_tie"
    } else {
      status <- if ("granularity" %in% statuses) "granularity" else if ("mapped_name" %in% statuses)
        "mapped_name" else statuses[1]
      reason <- if (ambiguous) "explicitly_related_best_label_tie" else "label_comparison"
    }
  }
  counter <- supplied$counterevidence
  if (is.null(counter)) counter <- list()
  if (!is.list(counter) || !is.null(names(counter)))
    stop("Counterevidence must be an explicitly supplied array of records.", call. = FALSE)
  .sc_project_json_check(counter)
  actual_mode <- current$source$reference_dependency
  if (is.null(actual_mode)) actual_mode <- if (identical(current$source$kind, "manual"))
    "not_dispatched" else "unknown"
  if (!is.character(actual_mode) || length(actual_mode) != 1L || is.na(actual_mode) ||
      !actual_mode %in% c("independent", "guided", "unknown", "not_dispatched"))
    stop("Recorded reference_dependency must be independent, guided, unknown or not_dispatched.", call. = FALSE)
  dependency <- list(mode = options$ai_mode, planned_mode = options$ai_mode, actual_mode = actual_mode,
    dependent_on_database = if (actual_mode == "guided") TRUE else if (actual_mode == "independent") FALSE else NULL,
    historical_mode = if (is.null(history$provenance)) NULL else history$provenance$reference_dependency,
    declaration = paste0("Configured proposal mode: ", options$ai_mode,
      "; recorded current request mode: ", actual_mode,
      ". Guided requests depend on saved database candidates; prompt separation is not biological confirmation."))
  list(schema = "scagentkit.joint-annotation-evidence.v1", clusterId = row$clusterId,
    database = database, current = current, historical = history,
    dependency = dependency,
    comparison = list(status = status, source = comparison_source, label = comparison_row$label,
      label_normalized = .sc_run_reference_resolve(comparison_row$label, options$label_map, TRUE),
      reference_labels = .sc_project_array(raw_best), related_candidates = related,
      ambiguous = ambiguous, raw_label_tie = length(raw_best) > 1L, reason = reason,
      relationships = options$label_relations, label_map = as.list(options$label_map)),
    counterevidence = list(status = if (length(counter)) "supplied" else "not_supplied", records = counter),
    limitations = .sc_project_array(c(
      "Coverage scores are descriptive, not calibrated probabilities or biological quality scores.",
      "Unmeasured genes, zero overlap and absence from top markers do not establish negative expression.",
      "Confidence is a qualitative supplied label, not a calibrated probability.",
      "Label equivalence, ancestry and lineage differences require the displayed explicit declarations.",
      "Historical response import is not a new model request; unavailable current citations remain unavailable.")))
}
