#' Review database and LLM annotation evidence offline
#'
#' Compares database candidates and a separately saved LLM initial annotation.
#' This function never calls a provider, applies labels, or removes cells. It
#' records lexical label agreement, conflict, or unknown evidence for subsequent
#' analyst review; agreement is not a biological accuracy claim.
#'
#' Labels are trimmed and compared case-insensitively. No lineages are merged
#' automatically. Supply an explicit named `label_map` to compare different
#' granularities. Different normalized labels tied for the highest positive
#' database score are ambiguous. Missing labels, failed LLM annotation, absent
#' supporting evidence, or marker citations missing from the supplied evidence
#' result in `unknown`. Database support for the LLM label is checked against
#' every available candidate, including lower-ranked candidates.
#' Saved initial-annotation cell-ID/cluster mappings, when present, must match
#' the current Seurat object exactly (cell order may differ). A mismatch or a
#' saved cluster absent from the current object makes the result unknown.
#' Legacy/manual tables without mappings have `alignment_status = "unverified"`;
#' their label comparison is retained but their input alignment is not proven.
#'
#' @param obj An AgentSeurat with saved reference matches, filtered markers,
#'   and optional `llm_annotations`. Missing branches remain unknown.
#' @param label_map Optional named character vector mapping original labels to
#'   a shared vocabulary, for example `c("CD4 T cell" = "T cell")`. Names and
#'   targets are trimmed and compared case-insensitively.
#' @param rationale Optional analyst rationale recorded in the decision log.
#'
#' @return Updated AgentSeurat. `obj@@params$annotation_evidence_review` is a
#'   per-cluster evidence table with `review_outcome` (`agreement`, `conflict`,
#'   or `unknown`) and `review_status = "pending"`. Full inputs and label mapping
#'   are retained in `obj@@params$annotation_evidence_review_inputs`, and
#'   `obj@@params$annotation_evidence_review_cell_ids` preserves cluster cell IDs.
#'   The table includes database/LLM normalized labels, supporting/contradicting
#'   markers, missing citations, ambiguity, and label-specific reference scores.
#' @export
annot_review_evidence <- function(obj, label_map = NULL, rationale = NULL) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  normalize <- .review_label_normalizer(label_map)
  all_candidates <- obj@params$reference_matches_all
  candidates <- if (!is.null(all_candidates)) all_candidates
                else obj@params$reference_matches
  candidate_scope <- if (!is.null(all_candidates)) "all_scored"
                     else "provided_candidates"
  if (is.null(candidates)) candidates <- .empty_reference_matches()
  required <- c("cluster", "cell_type", "score", "overlap_count", "matched_markers")
  if (!is.data.frame(candidates) || !all(required %in% names(candidates))) {
    stop("Reference candidates must contain cluster, cell_type, score, overlap_count, matched_markers.")
  }
  if (!is.numeric(candidates$score) || !is.numeric(candidates$overlap_count) ||
      anyNA(candidates$score) || any(!is.finite(candidates$score)) ||
      any(candidates$score < 0 | candidates$score > 1) ||
      anyNA(candidates$overlap_count) || any(!is.finite(candidates$overlap_count)) ||
      any(candidates$overlap_count < 0 |
          candidates$overlap_count != floor(candidates$overlap_count))) {
    stop("Reference scores must be finite in [0, 1] and overlap counts non-negative integers.")
  }
  .review_cluster_ids(candidates$cluster, "Reference")
  ann <- obj@params$llm_annotations
  if (is.null(ann)) {
    ann <- data.frame(cluster = character(), primary_annotation = character(),
                      stringsAsFactors = FALSE)
  }
  if (!is.data.frame(ann) ||
      !all(c("cluster", "primary_annotation") %in% names(ann))) {
    stop("LLM annotations must contain cluster and primary_annotation.")
  }
  .review_cluster_ids(ann$cluster, "LLM")
  if (anyDuplicated(as.character(ann$cluster))) {
    stop("LLM annotations must contain at most one row per cluster.")
  }
  filtered <- obj@params$markers_filtered
  if (is.null(filtered)) {
    filtered <- data.frame(cluster = character(), gene = character())
  }
  if (!is.data.frame(filtered) || !all(c("cluster", "gene") %in% names(filtered))) {
    stop("Filtered markers must contain cluster and gene.")
  }
  .review_cluster_ids(filtered$cluster, "Marker")
  current_cells <- .reference_input_cells(obj)
  cell_ids <- if (is.null(current_cells)) {
    data.frame(cell_id = character(), cluster = character())
  } else current_cells
  reference_cells <- obj@params$reference_match_input_cells
  llm_cells <- obj@params$llm_annotation_input_cells
  ref_alignment <- .review_input_alignment(reference_cells, current_cells)
  llm_alignment <- .review_input_alignment(llm_cells, current_cells)
  alignment <- if ("mismatch" %in% c(ref_alignment, llm_alignment)) "mismatch"
               else if (all(c(ref_alignment, llm_alignment) == "verified")) "verified"
               else "unverified"
  clusters <- sort(unique(c(as.character(filtered$cluster),
                            as.character(candidates$cluster),
                            as.character(ann$cluster), cell_ids$cluster)))
  responses <- obj@params$llm_annotation_responses
  rows <- lapply(clusters, function(cid) {
    ref <- candidates[as.character(candidates$cluster) == cid, , drop = FALSE]
    ref <- ref[ref$score > 0 & ref$overlap_count > 0, , drop = FALSE]
    ref_norm <- normalize(ref$cell_type)
    known_ref <- !is.na(ref_norm) & !ref_norm %in% c("unknown", "unannotated")
    ref <- ref[known_ref, , drop = FALSE]
    ref_norm <- ref_norm[known_ref]
    best <- if (nrow(ref)) which(abs(ref$score - max(ref$score)) < 1e-12)
            else integer()
    best_labels <- unique(ref_norm[best])
    ambiguous <- length(best_labels) > 1L
    db_norm <- if (length(best_labels) == 1L) best_labels else NA_character_
    db_label <- if (length(best_labels) == 1L) {
      paste(unique(as.character(ref$cell_type[best])), collapse = " | ")
    } else NA_character_
    db_genes <- .review_genes(ref$matched_markers[best])
    a <- ann[as.character(ann$cluster) == cid, , drop = FALSE]
    llm_label <- if (nrow(a)) as.character(a$primary_annotation[1]) else NA_character_
    llm_norm <- normalize(llm_label)
    field <- function(name, default = "") {
      if (nrow(a) && name %in% names(a)) a[[name]][1] else default
    }
    support <- .review_genes(field("supporting_markers"))
    contradict <- .review_genes(field("contradicting_markers"))
    llm_status <- as.character(field("annotation_status", "not_recorded"))
    differential <- .review_genes(filtered$gene[as.character(filtered$cluster) == cid])
    bundle <- if (is.list(responses) && cid %in% names(responses)) {
      responses[[cid]]$marker_evidence
    } else NULL
    llm_evidence <- if (!is.null(bundle$citation_genes)) {
      .review_genes(bundle$citation_genes)
    } else differential
    absent <- function(genes, evidence) {
      genes[!toupper(genes) %in% toupper(evidence)]
    }
    missing_db <- absent(db_genes, differential)
    missing_llm <- absent(unique(c(support, contradict)), llm_evidence)
    matching_label <- if (!is.na(llm_norm)) which(ref_norm == llm_norm) else integer()
    matching_genes <- .review_genes(ref$matched_markers[matching_label])
    reasons <- character()
    if (!is.null(current_cells) && !cid %in% current_cells$cluster) {
      reasons <- c(reasons, "cluster_not_in_current_data")
    }
    if (identical(alignment, "mismatch")) {
      reasons <- c(reasons, "input_alignment_mismatch")
    }
    if (!length(best)) reasons <- c(reasons, "no_reference_evidence")
    if (length(best) && !length(db_genes)) reasons <- c(reasons, "no_reference_supporting_markers")
    if (ambiguous) reasons <- c(reasons, "reference_label_tie")
    if (is.na(llm_norm) || llm_norm %in% c("unknown", "unannotated")) {
      reasons <- c(reasons, "llm_label_missing_or_unknown")
    }
    if (identical(llm_status, "failed")) reasons <- c(reasons, "llm_annotation_failed")
    if (!length(support)) reasons <- c(reasons, "no_llm_supporting_markers")
    if (length(missing_db)) reasons <- c(reasons, "reference_markers_missing")
    if (length(missing_llm)) reasons <- c(reasons, "llm_markers_missing")
    outcome <- if (length(reasons)) "unknown"
               else if (identical(db_norm, llm_norm)) "agreement" else "conflict"
    data.frame(
      cluster = cid, reference_annotation = db_label,
      reference_normalized = db_norm, llm_annotation = llm_label,
      llm_normalized = llm_norm, review_outcome = outcome,
      review_status = "pending", reviewed_annotation = NA_character_,
      unknown_reason = paste(reasons, collapse = ";"),
      alignment_status = alignment,
      reference_alignment_status = ref_alignment,
      llm_alignment_status = llm_alignment,
      reference_ambiguous = ambiguous,
      reference_best_candidates = paste(unique(as.character(ref$cell_type[best])), collapse = " | "),
      reference_score = if (length(best)) max(ref$score[best]) else NA_real_,
      reference_supporting_markers = paste(db_genes, collapse = ","),
      llm_supporting_markers = paste(support, collapse = ","),
      llm_contradicting_markers = paste(contradict, collapse = ","),
      llm_annotation_status = llm_status,
      llm_label_in_reference = length(matching_label) > 0L,
      llm_reference_score = if (length(matching_label)) max(ref$score[matching_label]) else NA_real_,
      llm_reference_supporting_markers = paste(matching_genes, collapse = ","),
      reference_markers_missing = paste(missing_db, collapse = ","),
      llm_markers_missing = paste(missing_llm, collapse = ","),
      markers_missing = paste(unique(c(missing_db, missing_llm)), collapse = ","),
      reference_candidates_scope = candidate_scope,
      stringsAsFactors = FALSE
    )
  })
  if (!length(rows)) stop("No cluster IDs are available for evidence review.")
  review <- do.call(rbind, rows)
  inputs <- list(reference_candidates = candidates,
                 reference_matches = obj@params$reference_matches,
                 reference_data = obj@params$reference_data,
                 reference_provenance = obj@params$reference_provenance,
                 reference_match_input_cells = reference_cells,
                 llm_annotation_input_cells = llm_cells,
                 llm_annotations = ann, markers_filtered = filtered,
                 llm_annotation_responses = responses, label_map = label_map,
                 reference_mode = obj@params$reference_mode,
                 normalization = "trimws + tolower; explicit label_map only")
  if (is.null(rationale)) {
    rationale <- sprintf("Offline evidence review: %d agreement, %d conflict, %d unknown; all pending analyst review.",
                         sum(review$review_outcome == "agreement"),
                         sum(review$review_outcome == "conflict"),
                         sum(review$review_outcome == "unknown"))
  }
  obj <- .record_step(
    obj, step_name = "annot_review_evidence", function_name = "annot_review_evidence",
    params = list(label_map = label_map, n_clusters_reviewed = nrow(review),
                  review_outcome_counts = as.list(table(review$review_outcome)),
                  reference_candidates_scope = candidate_scope,
                  input_alignment_status = alignment,
                  evidence_review_inputs = inputs),
    rationale = rationale,
    script_snippet = "# Offline database/LLM evidence review; saved inputs and results require analyst review.",
    new_stage = "annotation_evidence_reviewed"
  )
  obj@params$annotation_evidence_review <- review
  obj@params$annotation_evidence_review_inputs <- inputs
  obj@params$annotation_evidence_review_cell_ids <- cell_ids
  obj
}

.review_label_normalizer <- function(label_map) {
  if (!is.null(label_map)) {
    if (!is.character(label_map) || !length(label_map) || is.null(names(label_map)) ||
        anyNA(label_map) || anyNA(names(label_map)) ||
        any(!nzchar(trimws(label_map))) || any(!nzchar(trimws(names(label_map))))) {
      stop("`label_map` must be a named character vector with non-empty labels and targets.")
    }
    keys <- tolower(trimws(names(label_map)))
    if (anyDuplicated(keys)) stop("`label_map` names must be unique after normalization.")
    label_map <- stats::setNames(tolower(trimws(label_map)), keys)
  }
  function(x) {
    out <- tolower(trimws(as.character(x)))
    out[is.na(out) | !nzchar(out)] <- NA_character_
    if (!is.null(label_map)) {
      hit <- !is.na(out) & out %in% names(label_map)
      out[hit] <- unname(label_map[out[hit]])
    }
    out
  }
}

.review_genes <- function(x) {
  x <- unlist(x, use.names = FALSE)
  if (!length(x)) return(character())
  genes <- trimws(unlist(strsplit(as.character(x[!is.na(x)]), "[,;]+", perl = TRUE),
                         use.names = FALSE))
  unique(genes[nzchar(genes)])
}

.review_cluster_ids <- function(x, source) {
  if (anyNA(x) || any(!nzchar(trimws(as.character(x))))) {
    stop(source, " cluster IDs must be non-empty and non-missing.")
  }
}

.review_input_alignment <- function(saved, current) {
  if (is.null(saved) || is.null(current)) return("unverified")
  if (!is.data.frame(saved) || !all(c("cell_id", "cluster") %in% names(saved))) {
    return("mismatch")
  }
  saved <- saved[, c("cell_id", "cluster"), drop = FALSE]
  saved$cell_id <- as.character(saved$cell_id)
  saved$cluster <- as.character(saved$cluster)
  if (anyNA(saved) || any(!nzchar(trimws(saved$cell_id))) ||
      any(!nzchar(trimws(saved$cluster))) || anyDuplicated(saved$cell_id)) {
    return("mismatch")
  }
  saved <- saved[order(saved$cell_id), , drop = FALSE]
  current <- current[order(current$cell_id), , drop = FALSE]
  rownames(saved) <- rownames(current) <- NULL
  if (identical(saved, current)) "verified" else "mismatch"
}
