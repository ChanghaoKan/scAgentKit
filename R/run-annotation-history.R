# Historical aggregate annotation imports are evidence, never a provider call.
.sc_run_annotation_history_import <- function(value, evidence) {
  allowed <- c("annotations", "response_paths", "source_object_path", "source_cluster_column",
               "provider", "model", "reference_dependency", "note")
  if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
      anyDuplicated(names(value)) || any(!names(value) %in% allowed))
    stop("Unsupported historical annotation import fields.", call. = FALSE)
  paths <- value$response_paths
  if (!is.character(paths) || !length(paths) || length(paths) > 1000L || anyNA(paths) || any(!nzchar(paths)))
    stop("Historical imports require explicit readonly response_paths.", call. = FALSE)
  paths <- vapply(paths, function(path) normalizePath(path.expand(path), mustWork = TRUE), character(1))
  hashes <- vapply(paths, function(path) {
    if (dir.exists(path) || file.info(path)$size > 5e6)
      stop("Historical response must be a bounded local JSON file.", call. = FALSE)
    text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (!jsonlite::validate(text)) stop("Historical response JSON is corrupted.", call. = FALSE)
    .sc_project_sha_file(path)
  }, character(1))
  for (name in c("provider", "model")) .sc_project_string(value[[name]], paste("historical", name))
  mode <- value$reference_dependency
  if (is.null(mode)) mode <- "unknown"
  if (!is.character(mode) || length(mode) != 1L || !mode %in% c("independent", "guided", "unknown"))
    stop("Historical reference_dependency must be independent, guided or unknown.", call. = FALSE)
  note <- value$note
  if (is.null(note)) note <- "Caller-extracted historical rows; no new model request."
  .sc_project_string(note, "historical note")
  if (nchar(note) > 4000L) stop("Historical note exceeds the local evidence bound.", call. = FALSE)
  ids <- vapply(evidence$summary$clusters, `[[`, character(1), "clusterId")
  rows <- value$annotations
  if (!is.list(rows) || !length(rows) || !is.null(names(rows)))
    stop("Historical annotations must be a nonempty array.", call. = FALSE)
  normalized <- lapply(rows, function(row) {
    if (!is.list(row) || !setequal(names(row), c("clusterId", "label", "confidence", "rationale", "markers")) || anyDuplicated(names(row)))
      stop("Historical rows require clusterId,label,confidence,rationale,markers.", call. = FALSE)
    if (!row$clusterId %in% ids) stop("Historical annotation refers to a foreign cluster ID.", call. = FALSE)
    parsed <- .validate_annotation_response(list(cluster = row$clusterId,
      primary_annotation = row$label, confidence = row$confidence,
      supporting_markers = row$markers, contradicting_markers = list(),
      alternative_annotations = list(), proportion_assessment = "reasonable",
      recommended_action = "flag_for_review", reasoning = row$rationale), expected_cluster = row$clusterId)
    list(clusterId = row$clusterId, label = parsed$primary_annotation,
      confidence = parsed$confidence, rationale = parsed$reasoning,
      markers = .sc_project_array(parsed$supporting_markers))
  })
  imported_ids <- vapply(normalized, `[[`, character(1), "clusterId")
  if (anyDuplicated(imported_ids)) stop("Duplicate historical cluster IDs.", call. = FALSE)
  scope <- "unverified"
  source_hash <- source_path <- NULL
  if (!is.null(value$source_object_path)) {
    .sc_project_string(value$source_object_path, "historical source_object_path")
    source_path <- normalizePath(path.expand(value$source_object_path), mustWork = TRUE)
    source_hash <- .sc_project_sha_file(source_path)
    object <- .sc_project_unwrap(readRDS(source_path))
    column <- value$source_cluster_column
    if (is.null(column)) column <- evidence$private$cluster_column
    .sc_project_string(column, "historical source_cluster_column")
    metadata <- object[[]]
    if (!column %in% names(metadata)) stop("Historical source cluster column is absent.", call. = FALSE)
    input <- data.frame(cell_id = colnames(object), cluster = as.character(metadata[colnames(object), column]),
                        stringsAsFactors = FALSE)
    scope <- if (identical(.review_input_alignment(input, evidence$private$input_cells), "verified")) "verified" else "mismatch"
  }
  list(annotations = normalized, provenance = list(kind = "historical_model_response",
    provider = value$provider, model = value$model,
    response_sha256 = unname(hashes), response_paths = unname(paths),
    source_object_sha256 = source_hash, source_object_path = source_path,
    scope_status = scope, missing_clusters = .sc_project_array(setdiff(ids, imported_ids)),
    reference_dependency = mode, note = note,
    extraction = "caller-extracted rows; file SHA256 verifies source bytes, not the interpretation",
    new_request = FALSE))
}

.sc_run_annotation_history_row <- function(history, cluster, supplied) {
  if (is.null(history)) return(NULL)
  rows <- Filter(function(x) identical(x$clusterId, cluster), history$annotations)
  if (!length(rows)) return(list(row = NULL, source = list(kind = "historical_model_response"),
                                provenance = history$provenance))
  row <- rows[[1]]
  admissible <- vapply(supplied$markers, `[[`, character(1), "gene")
  provenance <- history$provenance
  provenance$cited_genes_missing_from_current_marker_list <- .sc_project_array(
    setdiff(unlist(row$markers, use.names = FALSE), admissible))
  provenance$marker_absence_interpretation <- "Not in the supplied marker list; no negative expression inference."
  list(row = row, source = list(kind = "historical_model_response", new_request = FALSE),
       provenance = provenance)
}
