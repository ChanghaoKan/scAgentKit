# The modern entry preserves prior metadata separately, without renaming roles
# or treating old annotations as an approved result of the new analysis.
.sc_run_input_policy <- function(value) {
  if (is.null(value)) return(list(preserve_metadata = FALSE))
  if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) ||
      length(setdiff(names(value), "preserve_metadata")) ||
      !all(vapply(value, function(flag) is.logical(flag) && length(flag) == 1L && !is.na(flag), logical(1))))
    stop("input_policy accepts preserve_metadata=TRUE/FALSE.", call. = FALSE)
  list(preserve_metadata = isTRUE(value$preserve_metadata))
}

.sc_run_preserve_input_metadata <- function(seu) {
  metadata <- seu[[]]
  if (anyDuplicated(rownames(metadata)) || !setequal(rownames(metadata), colnames(seu)))
    stop("Input metadata must follow the exact input cell IDs before preservation.", call. = FALSE)
  key <- tail(make.unique(c(names(seu@misc), "scagentkit_input_metadata")), 1L)
  record <- list(schema = "scagentkit.input-metadata.v1", metadata = metadata,
    cell_id_map = data.frame(input_cell_id = rownames(metadata), analysis_cell_id = rownames(metadata),
      stringsAsFactors = FALSE),
    column_map = data.frame(input_field = names(metadata),
      preserved_path = paste0("misc/", key, "/metadata/", names(metadata)), stringsAsFactors = FALSE))
  record$hash <- .sc_run_hash(record)
  seu@misc[[key]] <- record
  list(seu = seu, key = key, hash = record$hash)
}

.sc_run_preserved_metadata_verify <- function(seu, key) {
  .sc_project_string(key, "preserved metadata key")
  record <- seu@misc[[key]]
  if (!is.list(record) || !identical(record$schema, "scagentkit.input-metadata.v1"))
    stop("Original metadata preservation record is missing; restore the protected checkpoint.", call. = FALSE)
  before <- record; before$hash <- NULL
  if (!identical(record$hash, .sc_run_hash(before)) || !is.data.frame(record$metadata) ||
      !is.data.frame(record$cell_id_map) ||
      !identical(record$cell_id_map$input_cell_id, rownames(record$metadata)) ||
      !identical(record$cell_id_map$analysis_cell_id, rownames(record$metadata)) ||
      !all(colnames(seu) %in% rownames(record$metadata)))
    stop("Original metadata preservation record changed or has a different cell scope; restore the protected checkpoint.", call. = FALSE)
  record
}
