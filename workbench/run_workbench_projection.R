# Pure display projection. Existing current-review previews are never changed.
.sc_wb_fields <- function(value, fields) {
  if (is.null(value)) return(NULL)
  value[intersect(fields, names(value))]
}
.sc_wb_qc_details <- function(value) {
  out <- .sc_wb_fields(value, c("schema", "evidence_hash", "canonical_parameters", "retention",
    "keep_cell_hash", "remove_cell_hash", "interpretation", "mad_panel"))
  out$filter_impacts <- lapply(value$filter_impacts, .sc_wb_fields, fields = c("id", "filter", "scoped",
    "low", "high", "unavailable", "independently_removed", "exclusively_removed",
    "primary_retained_in_scope", "primary_removed_in_scope"))
  out$patterns <- lapply(value$patterns, .sc_wb_fields,
    fields = c("filter_ids", "reason_ids", "unavailable_filter_ids", "count", "retained", "removed"))
  out$overlap <- .sc_wb_fields(value$overlap, c("filter_ids", "counts", "interpretation"))
  # These are saved population counts/quantiles, not the per-cell metrics frame.
  out$distributions <- .sc_wb_fields(value$distributions, c("global", "groups"))
  unavailable <- value$unavailable
  out$unavailable <- .sc_wb_fields(unavailable, c("mitochondrial", "gene_panels"))
  out$unavailable$metrics <- lapply(unavailable$metrics, .sc_wb_fields, fields = c("metric", "count"))
  if (!is.null(unavailable$zero_count_cells)) out$unavailable$zero_count_count <- length(unavailable$zero_count_cells)
  out$sensitivity <- lapply(value$sensitivity, function(candidate) {
    row <- .sc_wb_fields(candidate, c("id", "proposal", "retention", "keep_cell_hash", "intersection",
      "added", "removed_from_primary", "jaccard"))
    row$groups <- lapply(candidate$groups, function(group) {
      result <- .sc_wb_fields(group, c("group_id", "selector", "before", "primary_retained", "retained"))
      if (!is.null(group$added_cells)) result$added <- length(group$added_cells)
      if (!is.null(group$removed_from_primary_cells)) result$removed_from_primary <- length(group$removed_from_primary_cells)
      result
    })
    row
  })
  out$display_boundary <- paste("Saved aggregate QC projection. Per-cell measurements, MAD flags and every",
    "QC cell-ID list are excluded; original complete previews remain in the current review and fixed artifacts.")
  out
}
.sc_wb_plain <- function(value) {
  if (!is.list(value)) return(value)
  if (is.data.frame(value) && any(grepl("(^|_)cell_(id|ids)$|^cellId(s)?$", names(value)))) return(NULL)
  if (identical(value$schema, "scagentkit.qc.preview.v1")) value <- .sc_wb_qc_details(value)
  if (identical(value$schema, "scagentkit.qc.review.v1")) value <- .sc_wb_fields(value,
    c("schema", "input_hash", "config_hash", "implementation_hash", "calculation_scope_hash", "evidence_hash",
      "rules_hash", "parameters_hash", "cell_scope_hash", "details", "plots", "hash"))
  if (!is.null(names(value))) {
    fields <- names(value)
    secret <- grepl("key|password|secret|credential|authorization|token$", fields, ignore.case = TRUE)
    private <- grepl("(^|_)cell_(id|ids)$|^cellId(s)?$|_cells$", fields) |
      fields %in% c("metadata", "raw_counts", "raw_matrix", "mad_flags")
    count <- vapply(value, function(item) is.numeric(item) && length(item) == 1L &&
      is.finite(item) && item >= 0, logical(1))
    # All existing *_cells numeric scalars are cohort/impact counts. Literal
    # identifiers are character vectors, and per-cell frames are handled above.
    private[grepl("_cells$", fields) & count] <- FALSE
    value <- value[!secret & !private]
  }
  lapply(value, .sc_wb_plain)
}
