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
#' @param species Optional character. If the table has a `species` column,
#'   keep case-insensitive exact matches; otherwise record it as context.
#'
#' @return Data frame of the reference, with columns at least
#'   `cell_type` and `marker`. Source path, file MD5, and input row count are
#'   preserved as attributes for audit and offline reproduction.
#' @export
annot_load_reference <- function(path, tissue_filter = NULL, species = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be one non-empty file path.")
  }
  .reference_filter_input(tissue_filter, "tissue_filter")
  .reference_filter_input(species, "species")
  if (!file.exists(path)) stop("Reference file not found: ", path)
  sep <- if (grepl("\\.tsv$", path, ignore.case = TRUE)) "\t" else ","
  ref <- utils::read.table(path, header = TRUE, sep = sep,
                           stringsAsFactors = FALSE,
                           quote = "\"", fill = TRUE)

  ref <- .validate_marker_reference(ref)
  n_input <- nrow(ref)

  if (!is.null(tissue_filter) && "tissue" %in% colnames(ref)) {
    ref <- ref[tolower(trimws(as.character(ref$tissue))) %in%
                 tolower(trimws(c(tissue_filter, "all"))), ,
               drop = FALSE]
  }
  if (!is.null(species) && "species" %in% colnames(ref)) {
    ref <- ref[tolower(trimws(as.character(ref$species))) %in%
                 tolower(trimws(species)), , drop = FALSE]
  }

  attr(ref, "species")       <- species
  attr(ref, "tissue_filter") <- tissue_filter
  attr(ref, "source_path") <- normalizePath(path, mustWork = TRUE)
  attr(ref, "source_md5") <- unname(tools::md5sum(path))
  attr(ref, "n_input_rows") <- n_input
  ref
}

#' Match an explicit marker table against a local reference
#' @param obj Filtered marker data.frame with cluster and gene columns.
#' @param reference Local reference data.frame with cell_type and marker columns.
#' @param top_n_candidates Maximum positive-overlap candidates per cluster.
#' @return Candidate data.frame, with all_matches and reference_provenance attributes.
#'   Scores are reference-marker coverage, not label confidence or approval.
#' @export
annot_match_reference <- function(obj,reference,top_n_candidates=5) {
  result<-.sc_reference_match(obj,reference,top_n_candidates)
  out<-result$matches;attr(out,"all_matches")<-result$all_matches
  fields<-c("source_path","source_md5","source_url","requested_url","source_url_verified","source_version","marker_column","n_input_rows","species","tissue_filter","source_sha256","source_mode","scope_status","scope_notice")
  attr(out,"reference_provenance")<-stats::setNames(lapply(fields,function(key)attr(reference,key)),fields)
  out
}
