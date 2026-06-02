#' Load a marker-to-celltype reference database
#'
#' Loads a reference table mapping marker genes to cell types. The table
#' must have at minimum two columns: `cell_type` and `marker`. One row per
#' (cell_type, marker) pair. Users can assemble this from CellMarker 2.0,
#' PanglaoDB, ACT exports, or their own curated list.
#'
#' Example format (tab- or comma-separated):
#' \preformatted{
#' cell_type         marker    tissue   source
#' Hepatocyte        ALB       liver    CellMarker
#' Hepatocyte        AFP       liver    CellMarker
#' Kupffer cell      CD68      liver    CellMarker
#' T cell            CD3D      all      PanglaoDB
#' }
#'
#' @param path Path to CSV or TSV file.
#' @param tissue_filter Optional character. If supplied, restricts the
#'   reference to entries where `tissue` is either the requested tissue or
#'   `"all"`. Recommended to avoid hits from irrelevant tissues
#'   contaminating the score.
#' @param species Optional character; preserved as an attribute for
#'   documentation.
#'
#' @return Data frame of the reference, with columns at least
#'   `cell_type` and `marker`.
#' @export
annot_load_reference <- function(path, tissue_filter = NULL, species = NULL) {
  if (!file.exists(path)) stop("Reference file not found: ", path)
  sep <- if (grepl("\\.tsv$", path, ignore.case = TRUE)) "\t" else ","
  ref <- utils::read.table(path, header = TRUE, sep = sep,
                           stringsAsFactors = FALSE,
                           quote = "\"", fill = TRUE)

  required <- c("cell_type", "marker")
  missing_cols <- setdiff(required, colnames(ref))
  if (length(missing_cols) > 0) {
    stop("Reference must contain columns: ",
         paste(required, collapse = ", "),
         ". Missing: ", paste(missing_cols, collapse = ", "))
  }

  if (!is.null(tissue_filter) && "tissue" %in% colnames(ref)) {
    ref <- ref[tolower(ref$tissue) %in% tolower(c(tissue_filter, "all")), ,
               drop = FALSE]
  }

  attr(ref, "species")       <- species
  attr(ref, "tissue_filter") <- tissue_filter
  ref
}

#' Score cluster markers against a reference database
#'
#' For each cluster's top marker list, computes an overlap score against
#' each cell type in the reference. The score is simple overlap (Jaccard-
#' style): `|cluster_markers intersect celltype_markers| / |celltype_markers|`.
#' This rewards cell types whose characteristic markers appear prominently
#' in the cluster's top-N list.
#'
#' @param obj An AgentSeurat object after [sc_markers_summary()].
#' @param reference A reference data frame from [annot_load_reference()].
#' @param top_n_candidates Integer, how many top-scoring cell types to
#'   return per cluster. Default 5.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; a data frame of matches (columns:
#'   cluster, cell_type, overlap_count, celltype_size, score,
#'   matched_markers) is stored at `obj@@params$reference_matches`.
#' @export
annot_match_reference <- function(obj,
                                  reference,
                                  top_n_candidates = 5,
                                  rationale        = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  filtered <- obj@params$markers_filtered
  if (is.null(filtered)) {
    stop("No filtered markers found; run sc_markers_summary() first.")
  }

  clusters <- unique(as.character(filtered$cluster))

  # Pre-index reference by cell type
  ref_by_type <- split(reference$marker, reference$cell_type)

  match_rows <- list()
  for (cid in clusters) {
    cluster_genes <- filtered$gene[as.character(filtered$cluster) == cid]
    scores <- lapply(names(ref_by_type), function(ct) {
      ct_genes <- unique(ref_by_type[[ct]])
      hits <- intersect(cluster_genes, ct_genes)
      list(
        cell_type       = ct,
        overlap_count   = length(hits),
        celltype_size   = length(ct_genes),
        score           = length(hits) / max(length(ct_genes), 1),
        matched_markers = paste(hits, collapse = ",")
      )
    })
    scores_df <- do.call(rbind, lapply(scores, as.data.frame,
                                       stringsAsFactors = FALSE))
    scores_df <- scores_df[order(-scores_df$score, -scores_df$overlap_count), ]
    top <- head(scores_df[scores_df$overlap_count > 0, , drop = FALSE],
                top_n_candidates)
    if (nrow(top) > 0) {
      top$cluster <- cid
      match_rows[[cid]] <- top
    }
  }

  matches <- do.call(rbind, match_rows)
  rownames(matches) <- NULL
  if (!is.null(matches)) {
    matches <- matches[, c("cluster", "cell_type", "overlap_count",
                           "celltype_size", "score", "matched_markers")]
  }

  script <- sprintf(
'# ---- Reference-matching (top %d candidates / cluster) ----
# Reference loaded from external file; see annot_load_reference().
# Overlap score = |cluster_markers intersect celltype_markers| / |celltype_markers|',
    top_n_candidates)

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Matched top markers against reference (%d entries covering %d cell types); top %d candidates per cluster.",
      nrow(reference), length(ref_by_type), top_n_candidates
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "annot_match_reference",
    function_name  = "annot_match_reference",
    params         = list(
      n_reference_rows   = nrow(reference),
      n_celltypes        = length(ref_by_type),
      top_n_candidates   = top_n_candidates,
      tissue_filter      = attr(reference, "tissue_filter"),
      species            = attr(reference, "species")
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "reference_matched"
  )
  obj@params$reference_matches <- matches
  obj
}
