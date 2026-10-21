# Only these candidate column names and a fixed nonidentifying value vocabulary
# enter an automatic model summary. Arbitrary metadata, IDs and rare labels do not.
.sc_run_metadata_roles <- function(seu, context, select_single = FALSE) {
  if (!is.list(context)) return(list(context = context, summary = NULL))
  metadata <- seu[[]]
  allowed_columns <- c("orig.ident", "sample", "batch", "donor", "condition")
  candidates <- intersect(allowed_columns, names(metadata))
  safe_vocabulary <- c("control", "healthy", "disease", "case", "treated", "untreated", "stimulated", "unstimulated")
  rows <- lapply(candidates, function(column) {
    values <- metadata[[column]]
    atomic <- is.character(values) || is.factor(values) || is.numeric(values) || is.logical(values)
    complete <- atomic && !anyNA(values) && all(nzchar(trimws(as.character(values)))) &&
      (!is.numeric(values) || all(is.finite(values)))
    counts <- if (atomic) table(as.character(values), useNA = "no") else integer()
    common <- counts[counts >= 5L]
    safe <- common[tolower(names(common)) %in% safe_vocabulary]
    list(column = column, complete = complete, cells = nrow(metadata), distinct_values = length(counts),
      missing = if (atomic) sum(is.na(values)) else nrow(metadata),
      common_groups = length(common), rare_groups_suppressed = sum(counts < 5L),
      common_group_sizes = if (length(common)) list(min = unname(min(common)), median = unname(stats::median(common)),
        max = unname(max(common))) else NULL,
      safe_value_counts = unname(lapply(seq_along(safe), function(i) list(value = names(safe)[[i]], cells = unname(safe[[i]])))))
  })
  columns <- context$columns
  if (is.null(columns)) columns <- list()
  if (is.character(columns)) columns <- as.list(columns)
  selected <- columns$sample
  source <- if (!is.null(selected)) "user_declared" else "none"
  if (is.null(selected) && isTRUE(select_single) && length(rows) == 1L && isTRUE(rows[[1L]]$complete)) {
    selected <- rows[[1L]]$column
    columns$sample <- selected; context$columns <- columns
    source <- "single_candidate_rule"
  }
  status <- if (!is.null(selected)) "selected" else if (length(rows)) "needs_selection" else "unavailable"
  notice <- if (source == "single_candidate_rule") paste(
    "The only complete candidate column is used as the sample grouping by an explicit input rule.",
    "This is not donor/capture provenance or evidence of a technical batch; correct the role before approval if needed.") else
    if (status == "needs_selection") paste(
      "Choose the sample column in the study-facts editor. Candidate names and group-size summaries are a draft, not biological or technical provenance.",
      "Automatic pooled MAD is disabled until a sample or quality-group role is explicitly selected.") else
    if (status == "unavailable") "No candidate sample column is available. Declare a quality/sample role to enable grouped MAD; otherwise QC remains unassessed and no grouped MAD is applied." else
      "The saved explicit sample role is used; metadata names alone never establish a technical batch."
  list(context = context, summary = list(schema = "scagentkit.metadata-role-candidates.v1",
    status = status, selection_source = source, selected_sample_column = selected, candidates = rows,
    privacy = list(min_group_cells = 5L, column_policy = "five-name whitelist",
      value_policy = "fixed nonidentifying vocabulary only", cell_ids_included = FALSE,
      per_cell_values_included = FALSE), notice = notice))
}

.sc_run_mad_group_defaults <- function(context) {
  columns <- context$columns
  if (is.character(columns)) columns <- as.list(columns)
  role <- if (!is.null(columns$qc_group)) "qc_group" else if (!is.null(columns$sample)) "sample" else NULL
  if (is.null(role)) return(FALSE)
  grouping <- list(method = "column", column = columns[[role]], declared_role = role,
      source = paste0("Explicit context$columns$", role, " declaration; no donor or capture role inferred."))
  list(grouping = grouping)
}
