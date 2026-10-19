# Provider-only guards: do not mutate counts, metadata or local scientific
# evidence. Unsafe metadata summaries disable the optional request, not review.
.sc_run_metadata_transfer_policy <- function(seu, context) {
  columns <- unique(unlist(context$columns, use.names = FALSE))
  metadata <- seu[[]]
  cells <- colnames(seu)
  ids <- unique(c(cells, sub("^.*::", "", cells)))
  rare <- identifying <- character()
  for (column in columns) {
    values <- as.character(metadata[[column]])
    counts <- table(values)
    if (any(counts < 5L)) rare <- c(rare, column)
    if (any(values %in% ids)) identifying <- c(identifying, column)
  }
  text <- paste(unlist(context[c("species", "tissue", "research_goal", "notes")], use.names = FALSE), collapse = " ")
  too_long <- nchar(enc2utf8(text), type = "bytes") > 100000L
  tokens <- if (too_long) character() else unlist(strsplit(text, "[^[:alnum:]_.:-]+"), use.names = FALSE)
  tokens <- sub("[.:-]+$", "", tokens)
  mentions <- any(tokens %in% ids[nchar(ids) >= 4L])
  blocked <- length(rare) > 0L || length(identifying) > 0L || mentions || too_long
  list(schema = "scagentkit.metadata-transfer-policy.v1", minimum_group_cells = 5L,
    rare_role_columns = unique(rare), cell_id_role_columns = unique(identifying),
    context_mentions_cell_ids = mentions, context_too_long = too_long, blocked = blocked,
    notice = if (blocked) paste("No model request was sent: declared metadata includes rare groups or cell-ID labels, or the supplied context is identifying/too large.",
      "Continue with local review, or create a new project using an appropriate nonidentifying summary without merging scientific groups.") else
      "Declared role summaries passed the rare-group and literal cell-ID checks; arbitrary metadata columns are not included.")
}

.sc_run_transfer_privacy_check <- function(config) {
  if (isTRUE(config$metadata_transfer_policy$blocked))
    stop(structure(list(message = config$metadata_transfer_policy$notice, call = NULL),
      class = c("sc_run_transfer_privacy_unavailable", "error", "condition")))
  invisible(TRUE)
}
