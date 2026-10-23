# Pure display projection. Existing current-review previews are never changed.
.sc_wb_fields <- function(value, fields) {
  if (is.null(value)) return(NULL)
  value[intersect(fields, names(value))]
}
.sc_wb_quality_summary <- function(rows) {
  distribution <- function(field) {
    values <- vapply(rows,function(row) if(is.numeric(row[[field]]) && length(row[[field]])==1L &&
      is.finite(row[[field]])) row[[field]] else NA_real_,numeric(1))
    values <- values[is.finite(values)]
    if(!length(values)) return(NULL)
    as.list(stats::setNames(as.numeric(stats::quantile(values,c(0,.25,.5,.75,1),names=FALSE)),
      c("min","q25","median","q75","max")))
  }
  list(measured_cells=length(rows),total_umi=distribution("total_umi"),
    detected_features=distribution("detected_features"),
    high_count_flags_available=sum(vapply(rows,function(row)is.logical(row$high_count_flag)&&length(row$high_count_flag)==1L&&!is.na(row$high_count_flag),logical(1))),
    high_count_flagged=sum(vapply(rows,function(row)isTRUE(row$high_count_flag),logical(1))))
}
.sc_wb_expression <- function(value, cluster = NULL) {
  out <- .sc_wb_fields(value,c("status","panels","measured_genes","missing_genes","clusters",
    "common_marker_review","high_count_interpretation","ambient_status","interpretation"))
  if(!is.null(cluster)) {
    out$clusters <- Filter(function(row)identical(as.character(row$cluster),as.character(cluster)),value$clusters)
    out$display_cluster <- cluster
  }
  out$cell_quality_summary <- .sc_wb_quality_summary(value$cell_quality)
  out$mixed_lineage <- lapply(value$mixed_lineage,function(row) {
    result <- .sc_wb_fields(row,c("panels","status","lineage_relationship","threshold"))
    result$coexpressing_cells <- if(identical(row$status,"measured"))length(row$coexpressing_cells) else NULL
    result$coexpressing_quality_summary <- .sc_wb_quality_summary(row$coexpressing_cell_quality)
    result
  })
  out$display_boundary <- paste("Aggregate local expression display; annotation rows show their exact cluster's expression contrasts.",
    "Full per-cell counts, flags, coexpression IDs and panel-gene counts remain unchanged in the hashed R artifacts and full R review.",
    "Quality/coexpression summaries describe the complete saved cohort, not inferred cluster-specific totals.")
  out
}
.sc_wb_qc_details <- function(value) {
  out <- .sc_wb_fields(value, c("schema", "evidence_hash", "canonical_parameters", "retention",
    "keep_cell_hash", "remove_cell_hash", "interpretation", "mad_panel"))
  out$filter_impacts <- lapply(value$filter_impacts, .sc_wb_fields, fields = c("id", "filter", "scoped",
    "low", "high", "unavailable", "independently_removed", "exclusively_removed",
    "primary_retained_in_scope", "primary_removed_in_scope"))
  out$rule_logic <- .sc_wb_fields(value$rule_logic, c("schema", "remove_if", "rule_ids",
    "prefilter_applied", "prefilter_removed", "prior_removed", "quality_removed", "final_retained"))
  out$patterns <- lapply(value$patterns, .sc_wb_fields,
    fields = c("filter_ids", "reason_ids", "unavailable_filter_ids", "prefilter_excluded", "prior_excluded", "count", "retained", "removed"))
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
  if(all(c("cell_quality","clusters","measured_genes","panels") %in% names(value)))
    value <- .sc_wb_expression(value)
  if(identical(value$schema,"scagentkit.scientific-diagnostics.v1")) {
    if(!is.null(value$cells)) {
      value$measured_cells <- length(value$cells)
      value$cells <- NULL
    }
    if(!is.null(value$resampling$replicates))value$resampling$replicates <- lapply(value$resampling$replicates,function(row) {
      row$sampled_cells <- length(row$cells);row$cells <- NULL;row
    })
    value$display_boundary <- "Saved aggregate diagnostics; exact per-cell scope and resampling IDs remain in the original hashed scientific diagnostic artifact."
  }
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
