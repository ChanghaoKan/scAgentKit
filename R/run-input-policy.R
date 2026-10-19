# The modern entry preserves prior metadata separately, without renaming roles
# or treating old annotations as an approved result of the new analysis.
.sc_run_input_policy <- function(value) {
  flags <- c("preserve_metadata", "automatic_metadata", "automatic_mad", "automatic_cycle")
  if (is.null(value)) return(c(stats::setNames(as.list(rep(FALSE, length(flags))), flags), list(doublet_mode = NULL)))
  if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) ||
      length(setdiff(names(value), c(flags, "doublet_mode"))) ||
      !all(vapply(value[intersect(names(value), flags)], function(flag) is.logical(flag) && length(flag) == 1L && !is.na(flag), logical(1))))
    stop("input_policy needs logical preservation/automatic flags and optional doublet_mode auto/off/flag/remove.", call. = FALSE)
  mode <- value$doublet_mode
  if (!is.null(mode) && (!is.character(mode) || length(mode) != 1L || is.na(mode) || !mode %in% c("auto", "off", "flag", "remove")))
    stop("doublet_mode must be auto, off, flag or remove.", call. = FALSE)
  c(stats::setNames(lapply(flags, function(key) isTRUE(value[[key]])), flags), list(doublet_mode = mode))
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
