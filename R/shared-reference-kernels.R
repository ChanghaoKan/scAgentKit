# Shared reference-overlap kernel; no AgentSeurat, decisions or file writes.
.sc_reference_match <- function(filtered, reference, top_n_candidates=5) {
  reference <- .validate_marker_reference(reference)
  if (!is.numeric(top_n_candidates) || length(top_n_candidates) != 1L ||
      is.na(top_n_candidates) || !is.finite(top_n_candidates) ||
      top_n_candidates < 1 || top_n_candidates != floor(top_n_candidates)) {
    stop("`top_n_candidates` must be one positive integer.")
  }
  if (!is.data.frame(filtered) ||
      !all(c("cluster", "gene") %in% names(filtered)) ||
      anyNA(filtered$cluster) || anyNA(filtered$gene) ||
      any(!nzchar(trimws(as.character(filtered$cluster)))) ||
      any(!nzchar(trimws(as.character(filtered$gene))))) {
    stop("`markers_filtered` must contain non-empty cluster and gene IDs.")
  }

  clusters <- unique(as.character(filtered$cluster))

  # Pre-index reference by cell type
  ref_by_type <- split(reference$marker, reference$cell_type)

  match_rows <- list()
  all_rows <- list()
  for (cid in clusters) {
    if (!length(ref_by_type)) next
    cluster_genes <- trimws(as.character(
      filtered$gene[as.character(filtered$cluster) == cid]))
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
    scores_df <- scores_df[order(-scores_df$score, -scores_df$overlap_count,
                                 scores_df$cell_type), , drop = FALSE]
    scores_df$cluster <- cid
    all_rows[[cid]] <- scores_df
    top <- head(scores_df[scores_df$overlap_count > 0, , drop = FALSE],
                top_n_candidates)
    if (nrow(top) > 0) {
      match_rows[[cid]] <- top
    }
  }

  assemble <- function(rows) {
    if (!length(rows)) return(.empty_reference_matches())
    out <- do.call(rbind, rows)
    rownames(out) <- NULL
    out[, names(.empty_reference_matches()), drop = FALSE]
  }
  matches <- assemble(match_rows)
  all_matches <- assemble(all_rows)
  list(reference=reference,matches=matches,all_matches=all_matches,n_celltypes=length(ref_by_type))
}
