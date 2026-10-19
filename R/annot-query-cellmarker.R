#' Import a locally obtained CellMarker 2.0 table with explicit scope
#'
#' Automatic retrieval is waiting for a verified fixed official HTTPS asset.
#' The package does not bundle or redistribute the CellMarker database and does
#' not use HTTP, IP mirrors, arbitrary URLs, latest URLs or first-use hash trust.
#' If permitted by the source, download through the official browser page and
#' pass its local path. A local digest identifies your input; it does not prove
#' publisher authenticity or grant redistribution rights.
#' @param species One of "human" or "mouse"; applied to the table's species column.
#' @param tissue Required nonempty literal tissue filter (case insensitive).
#' @param cancer_only Restrict to non-Normal cancer context when TRUE.
#' @param cache_dir Retained for call compatibility; caches are not silently trusted.
#' @param force_refresh Retained for compatibility; automatic refresh is unavailable.
#' @param url Only the documented fixed official HTTPS URL is recognized; no mirrors.
#' @param local_file Explicit path to a lawfully obtained local XLSX file.
#' @param sha256 Optional expected local file SHA256. This is a user input check,
#'   not a verified publisher pin.
#' @return Scoped marker reference with local provenance and explicit zero-match status.
#' @export
annot_query_cellmarker <- function(species, tissue = NULL, cancer_only = FALSE,
                                   cache_dir = NULL, force_refresh = FALSE, url = NULL,
                                   local_file = NULL, sha256 = NULL) {
  if (missing(species) || !is.character(species) || length(species) != 1L ||
      is.na(species) || !species %in% c("human", "mouse"))
    stop('species must be "human" or "mouse". Set the actual reference species before importing.', call. = FALSE)
  if (!is.character(tissue) || length(tissue) != 1L || is.na(tissue) || !nzchar(trimws(tissue)))
    stop("Set one explicit tissue before importing CellMarker; no all-tissue fallback is used.", call. = FALSE)
  tissue <- trimws(tissue)
  if (!is.logical(cancer_only) || length(cancer_only) != 1L || is.na(cancer_only))
    stop("cancer_only must be TRUE or FALSE.", call. = FALSE)
  official <- "https://bio-bigdata.hrbmu.edu.cn/CellMarker2.0/CellMarker_download_files/file/Cell_marker_All.xlsx"
  page <- "https://bio-bigdata.hrbmu.edu.cn/CellMarker2.0/CellMarker_download.html"
  if (!is.null(url) && !identical(url, official))
    stop("Only the fixed official HTTPS CellMarker URL is recognized; HTTP, IP and alternate mirror URLs are disabled. Supply a local_file obtained through the official source instead.", call. = FALSE)
  if (is.null(local_file) || isTRUE(force_refresh))
    stop(paste("Automatic CellMarker download is waiting for a verified fixed official file checksum; the official endpoint returned HTTP 403 during validation.",
      "No database is bundled and no alternate database is substituted.",
      "If you have lawful access, open", page, "in your browser, download the table, and pass local_file with explicit species and tissue.",
      "Local import records its SHA256 without claiming verified publisher provenance."), call. = FALSE)
  .sc_project_string(local_file, "local_file")
  cache_file <- normalizePath(local_file, mustWork = TRUE)
  if (dir.exists(cache_file)) stop("local_file must name the downloaded XLSX file.", call. = FALSE)
  digest <- digest::digest(file = cache_file, algo = "sha256")
  if (!is.null(sha256) && (!is.character(sha256) || length(sha256) != 1L || is.na(sha256) ||
      !grepl("^[0-9a-f]{64}$", sha256) || !identical(sha256, digest)))
    stop("Local CellMarker SHA256 does not match. Check the selected file; no reference was imported.", call. = FALSE)
  if (!requireNamespace("readxl", quietly = TRUE))
    stop("The optional readxl package is unavailable. Configure that dependency before importing the local XLSX file.", call. = FALSE)
  url <- official
  recorded_url <- character() # A user local file/sidecar cannot authenticate a publisher URL.
  raw <- suppressMessages(.cellmarker_read_excel(cache_file))
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # CellMarker 2.0 column names. The canonical ones are:
  #   cell_name, marker, Symbol, tissue_type, cancer_type, species, ...
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
  cn_marker   <- col(c("Symbol", "gene_symbol", "marker"))
  cn_tissue   <- col(c("tissue_type", "tissueType", "tissue"))
  cn_cancer   <- col(c("cancer_type", "cancerType", "cancer"))
  cn_species <- col(c("species", "Species"))
  actual_species <- tolower(trimws(as.character(raw[[cn_species]])))
  actual_species[actual_species == "homo sapiens"] <- "human"
  actual_species[actual_species == "mus musculus"] <- "mouse"
  raw <- raw[!is.na(actual_species) & actual_species == species, , drop = FALSE]

  ref <- data.frame(
    cell_type = raw[[cn_celltype]],
    marker    = raw[[cn_marker]],
    tissue    = raw[[cn_tissue]],
    cancer    = raw[[cn_cancer]],
    species   = rep(species, nrow(raw)),
    source    = rep("CellMarker2.0", nrow(raw)),
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

  # Apply tissue filter (literal substring match, case-insensitive): "blood"
  # deliberately includes peripheral/cord/venous blood. Matching is literal so
  # characters such as "(" or "+" in a tissue name are not regex syntax.
  if (!is.null(tissue)) {
    ref <- ref[grepl(tolower(tissue), tolower(ref$tissue), fixed = TRUE), , drop = FALSE]
  }

  # Some CellMarker entries list multiple markers comma- or slash-separated
  # in a single cell. Explode those.
  ref <- .explode_markers(ref)

  # Keep the cancer/normal context so callers can still separate them.
  ref <- unique(ref[, c("cell_type", "marker", "tissue", "cancer", "species", "source")])
  rownames(ref) <- NULL

  attr(ref, "species")       <- species
  attr(ref, "tissue_filter") <- tissue
  attr(ref, "cancer_only")   <- cancer_only
  attr(ref, "n_celltypes")   <- length(unique(ref$cell_type))
  attr(ref, "source_path") <- normalizePath(cache_file, mustWork = TRUE)
  attr(ref, "source_md5") <- unname(tools::md5sum(cache_file))
  attr(ref, "source_url") <- if (length(recorded_url)) recorded_url else NA_character_
  attr(ref, "requested_url") <- url
  attr(ref, "source_url_verified") <- length(recorded_url) == 1L
  attr(ref, "source_version") <- "CellMarker2.0-user-local-file"
  attr(ref, "source_sha256") <- digest
  attr(ref, "source_mode") <- "explicit_local_import_unverified_publisher"
  attr(ref, "scope_status") <- if (nrow(ref)) "matched" else "zero_matches"
  attr(ref, "scope_notice") <- if (nrow(ref)) "Reference filtered to the explicit species and tissue; no scientific identity is inferred." else
    "No CellMarker records match the selected species and tissue. Check those fields or supply another correctly scoped local table; no all-tissue fallback is used."
  attr(ref, "marker_column") <- cn_marker
  attr(ref, "n_input_rows") <- nrow(raw)

  message(sprintf(
    "[annot_query_cellmarker] %d (cell_type, marker) pairs across %d cell types%s.",
    nrow(ref), length(unique(ref$cell_type)),
    if (is.null(tissue)) "" else sprintf(" (tissue = '%s')", tissue)
  ))
  ref
}

.cellmarker_read_excel <- function(path) readxl::read_excel(path)


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
#' Removes every file in the scAgentKit reference cache: cached CellMarker
#' XLSX tables with their source-URL records and the cached Cell Ontology
#' (`cl.obo`). Use if you suspect a cached table is corrupt or outdated.
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
