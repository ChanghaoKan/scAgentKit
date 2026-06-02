#' Query CellMarker 2.0 by tissue/species and build a reference in-place
#'
#' Fetches marker-to-celltype records from the CellMarker 2.0 download
#' page and returns a reference data frame compatible with
#' [annot_match_reference()]. Avoids the chore of maintaining a local
#' reference TSV.
#'
#' CellMarker 2.0 does not expose a clean REST endpoint; instead it
#' publishes the full curated table as a single XLSX file. We mirror the
#' full table on first use (\code{~50 MB}), cache it locally, and apply
#' tissue / species filters in R. Subsequent calls are fast and offline.
#'
#' Source: Hu et al., CellMarker 2.0, Nucleic Acids Research 2023.
#' Use stable mirror address (original yikedaxue.slwshop.cn often returned 502 Bad Gateway):
#' \url{http://117.50.127.228/CellMarker/CellMarker_download_files/file/Cell_marker_Mouse.xlsx}
#' \url{http://117.50.127.228/CellMarker/CellMarker_download_files/file/Cell_marker_Human.xlsx}
#'
#' @section Format of the returned reference:
#' A data frame with columns `cell_type`, `marker`, `tissue`, `species`,
#' `source` -- the same shape produced by [annot_load_reference()], so it
#' plugs directly into [annot_match_reference()].
#'
#' @param species Character, one of `"human"` or `"mouse"`.
#' @param tissue Optional character. Case-insensitive substring match
#'   against CellMarker's `tissue_type` field (e.g. `"colon"`,
#'   `"liver"`, `"bone marrow"`). If NULL, no tissue filter is applied.
#' @param cancer_only Logical. If TRUE, restrict to cancer / tumor
#'   entries. If FALSE (default), include both normal and cancer entries.
#' @param cache_dir Directory where the CellMarker XLSX is cached.
#'   Default is `tools::R_user_dir("scAgentKit", "cache")`.
#' @param force_refresh Logical. If TRUE, re-download even if the cache
#'   exists. Default FALSE.
#' @param url Override the source URL (for mirrors or pinned versions).
#'
#' @return Data frame shaped for [annot_match_reference()], with the
#'   `species` and `tissue_filter` attributes set.
#' @export
#'
#' @examples
#' \dontrun{
#'   ref <- annot_query_cellmarker(species = "mouse", tissue = "colon")
#'   obj <- annot_match_reference(obj, reference = ref)
#' }
annot_query_cellmarker <- function(species,
                                   tissue        = NULL,
                                   cancer_only   = FALSE,
                                   cache_dir     = NULL,
                                   force_refresh = FALSE,
                                   url           = NULL) {

  if (missing(species) || !species %in% c("human", "mouse")) {
    stop('species must be "human" or "mouse".')
  }
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("Install 'readxl' for annot_query_cellmarker: install.packages('readxl')")
  }

  if (is.null(url)) {
    # CellMarker 2.0 "all" tables.
    # Use stable mirror address (original yikedaxue.slwshop.cn often 502)
    url <- switch(
      species,
      human = "http://117.50.127.228/CellMarker/CellMarker_download_files/file/Cell_marker_Human.xlsx",
      mouse = "http://117.50.127.228/CellMarker/CellMarker_download_files/file/Cell_marker_Mouse.xlsx"
    )
  }

  if (is.null(cache_dir)) {
    cache_dir <- tryCatch(
      tools::R_user_dir("scAgentKit", which = "cache"),
      error = function(e) tempdir()
    )
  }
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  cache_file <- file.path(cache_dir,
                          sprintf("CellMarker2_%s.xlsx", species))

  if (force_refresh || !file.exists(cache_file)) {
    message(sprintf("[annot_query_cellmarker] downloading %s table ...", species))
    tryCatch(
      utils::download.file(url, destfile = cache_file, mode = "wb", quiet = TRUE),
      error = function(e) {
        stop("Failed to download CellMarker table from ", url,
             "\nIf this URL is unreachable from your network, download the",
             "\nXLSX manually and place it at: ", cache_file,
             "\n(Original error: ", conditionMessage(e), ")")
      }
    )
  }

  raw <- suppressMessages(readxl::read_excel(cache_file))
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # CellMarker 2.0 column names. The canonical ones are:
  #   cell_name, marker, tissue_type, cancer_type, species, ...
  # Map to our simpler schema.
  col <- function(candidates) {
    hit <- intersect(candidates, colnames(raw))
    if (length(hit) == 0) {
      stop("Expected column not found in CellMarker XLSX. Columns present: ",
           paste(colnames(raw), collapse = ", "))
    }
    hit[1]
  }
  cn_celltype <- col(c("cell_name", "cellName", "cell_type"))
  cn_marker   <- col(c("marker", "Symbol", "gene_symbol"))
  cn_tissue   <- col(c("tissue_type", "tissueType", "tissue"))
  cn_cancer   <- col(c("cancer_type", "cancerType", "cancer"))

  ref <- data.frame(
    cell_type = raw[[cn_celltype]],
    marker    = raw[[cn_marker]],
    tissue    = raw[[cn_tissue]],
    cancer    = raw[[cn_cancer]],
    species   = species,
    source    = "CellMarker2.0",
    stringsAsFactors = FALSE
  )

  # Drop rows with missing marker or cell_type
  ref <- ref[nzchar(ref$marker) & !is.na(ref$marker) &
               nzchar(ref$cell_type) & !is.na(ref$cell_type), , drop = FALSE]

  # Apply cancer filter
  if (isTRUE(cancer_only)) {
    ref <- ref[!is.na(ref$cancer) & nzchar(ref$cancer) &
                 !grepl("Normal", ref$cancer, ignore.case = TRUE), , drop = FALSE]
  }

  # Apply tissue filter (substring match, case-insensitive)
  if (!is.null(tissue)) {
    ref <- ref[grepl(tissue, ref$tissue, ignore.case = TRUE), , drop = FALSE]
  }

  # Some CellMarker entries list multiple markers comma- or slash-separated
  # in a single cell. Explode those.
  ref <- .explode_markers(ref)

  ref <- unique(ref[, c("cell_type", "marker", "tissue", "species", "source")])
  rownames(ref) <- NULL

  attr(ref, "species")       <- species
  attr(ref, "tissue_filter") <- tissue
  attr(ref, "cancer_only")   <- cancer_only
  attr(ref, "n_celltypes")   <- length(unique(ref$cell_type))

  message(sprintf(
    "[annot_query_cellmarker] %d (cell_type, marker) pairs across %d cell types%s.",
    nrow(ref), length(unique(ref$cell_type)),
    if (is.null(tissue)) "" else sprintf(" (tissue = '%s')", tissue)
  ))
  ref
}


# Explode rows whose marker field lists multiple genes
# (comma / slash / semicolon / whitespace separated).
.explode_markers <- function(df) {
  parts <- strsplit(df$marker, "[,;/\\s]+", perl = TRUE)
  lens  <- lengths(parts)
  expanded <- df[rep(seq_len(nrow(df)), lens), , drop = FALSE]
  expanded$marker <- unlist(parts, use.names = FALSE)
  expanded$marker <- trimws(expanded$marker)
  expanded <- expanded[nzchar(expanded$marker), , drop = FALSE]
  expanded
}


#' Clear the scAgentKit reference cache
#'
#' Removes cached CellMarker XLSX files. Use if you suspect the cached
#' table is corrupt or outdated.
#'
#' @param cache_dir Directory to clear. Defaults to scAgentKit's user
#'   cache.
#' @return Invisibly returns the number of files removed.
#' @export
annot_clear_cache <- function(cache_dir = NULL) {
  if (is.null(cache_dir)) {
    cache_dir <- tryCatch(
      tools::R_user_dir("scAgentKit", which = "cache"),
      error = function(e) tempdir()
    )
  }
  if (!dir.exists(cache_dir)) return(invisible(0L))
  files <- list.files(cache_dir, full.names = TRUE)
  n <- sum(file.remove(files))
  message(sprintf("[annot_clear_cache] removed %d file(s) from %s", n, cache_dir))
  invisible(n)
}
