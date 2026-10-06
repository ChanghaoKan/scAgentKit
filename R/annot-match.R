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

#' Score cluster markers against a reference database
#'
#' For each cluster's top marker list, computes an overlap score against
#' each cell type in the reference. The score is reference-marker coverage:
#' `|cluster_markers intersect celltype_markers| / |celltype_markers|`.
#' This rewards cell types whose characteristic markers appear prominently
#' in the cluster's top-N list.
#'
#' @param obj An AgentSeurat object after [sc_markers_summary()].
#' @param reference A reference data frame from [annot_load_reference()].
#' @param top_n_candidates Integer, how many top-scoring cell types to
#'   return per cluster. Default 5.
#' @param rationale Optional LLM-supplied rationale.
#'
#' @return Updated AgentSeurat; a data frame of matches (columns:
#'   cluster, cell_type, overlap_count, celltype_size, score,
#'   matched_markers) is stored at `obj@@params$reference_matches`. All scored
#'   candidates, including zero-overlap entries, are retained at
#'   `obj@@params$reference_matches_all` for offline evidence review. An empty
#'   reference produces empty tables rather than an annotation. The reference
#'   table and source provenance are saved in the object's parameters. When
#'   current Seurat cluster metadata exists, `reference_match_input_cells`
#'   retains its exact cell-ID to cluster mapping for later alignment checks.
#' @export
annot_match_reference <- function(obj,
                                  reference,
                                  top_n_candidates = 5,
                                  rationale        = NULL) {

  stopifnot(methods::is(obj, "AgentSeurat"))
  reference <- .validate_marker_reference(reference)
  if (!is.numeric(top_n_candidates) || length(top_n_candidates) != 1L ||
      is.na(top_n_candidates) || !is.finite(top_n_candidates) ||
      top_n_candidates < 1 || top_n_candidates != floor(top_n_candidates)) {
    stop("`top_n_candidates` must be one positive integer.")
  }
  filtered <- obj@params$markers_filtered
  if (is.null(filtered)) {
    stop("No filtered markers found; run sc_markers_summary() first.")
  }
  if (!is.data.frame(filtered) ||
      !all(c("cluster", "gene") %in% names(filtered)) ||
      anyNA(filtered$cluster) || anyNA(filtered$gene) ||
      any(!nzchar(trimws(as.character(filtered$cluster)))) ||
      any(!nzchar(trimws(as.character(filtered$gene))))) {
    stop("`markers_filtered` must contain non-empty cluster and gene IDs.")
  }

  clusters <- unique(as.character(filtered$cluster))

  # Pre-index reference by cell type
  ref_by_type <- split(reference$marker, reference$cell_type)

  match_rows <- list()
  all_rows <- list()
  for (cid in clusters) {
    if (!length(ref_by_type)) next
    cluster_genes <- trimws(as.character(
      filtered$gene[as.character(filtered$cluster) == cid]))
    scores <- lapply(names(ref_by_type), function(ct) {
      ct_genes <- unique(ref_by_type[[ct]])
      hits <- intersect(cluster_genes, ct_genes)
      list(
        cell_type       = ct,
        overlap_count   = length(hits),
        celltype_size   = length(ct_genes),
        score           = length(hits) / max(length(ct_genes), 1),
        matched_markers = paste(hits, collapse = ",")
      )
    })
    scores_df <- do.call(rbind, lapply(scores, as.data.frame,
                                       stringsAsFactors = FALSE))
    scores_df <- scores_df[order(-scores_df$score, -scores_df$overlap_count,
                                 scores_df$cell_type), , drop = FALSE]
    scores_df$cluster <- cid
    all_rows[[cid]] <- scores_df
    top <- head(scores_df[scores_df$overlap_count > 0, , drop = FALSE],
                top_n_candidates)
    if (nrow(top) > 0) {
      match_rows[[cid]] <- top
    }
  }

  assemble <- function(rows) {
    if (!length(rows)) return(.empty_reference_matches())
    out <- do.call(rbind, rows)
    rownames(out) <- NULL
    out[, names(.empty_reference_matches()), drop = FALSE]
  }
  matches <- assemble(match_rows)
  all_matches <- assemble(all_rows)
  provenance <- list(source_path = attr(reference, "source_path"),
                     source_md5 = attr(reference, "source_md5"),
                     source_url = attr(reference, "source_url"),
                     requested_url = attr(reference, "requested_url"),
                     source_url_verified = attr(reference, "source_url_verified"),
                     source_version = attr(reference, "source_version"),
                     marker_column = attr(reference, "marker_column"),
                     n_input_rows = attr(reference, "n_input_rows"),
                     tissue_filter = attr(reference, "tissue_filter"),
                     species = attr(reference, "species"))
  input_cells <- .reference_input_cells(obj)

  script <- sprintf(
'# ---- Reference-matching (top %d candidates / cluster) ----
# Reference loaded from external file; see annot_load_reference().
# Overlap score = |cluster_markers intersect celltype_markers| / |celltype_markers|',
    top_n_candidates)

  if (is.null(rationale)) {
    rationale <- sprintf(
      "Matched top markers against reference (%d entries covering %d cell types); top %d candidates per cluster.",
      nrow(reference), length(ref_by_type), top_n_candidates
    )
  }

  obj <- .record_step(
    obj            = obj,
    step_name      = "annot_match_reference",
    function_name  = "annot_match_reference",
    params         = list(
      n_reference_rows   = nrow(reference),
      n_celltypes        = length(ref_by_type),
      top_n_candidates   = top_n_candidates,
      reference_provenance = provenance,
      reference_match_input_cells = input_cells,
      tissue_filter      = attr(reference, "tissue_filter"),
      species            = attr(reference, "species")
    ),
    rationale      = rationale,
    script_snippet = script,
    new_stage      = "reference_matched"
  )
  obj@params$reference_matches <- matches
  obj@params$reference_matches_all <- all_matches
  obj@params$reference_data <- reference
  obj@params$reference_provenance <- provenance
  obj@params$reference_match_input_cells <- input_cells
  obj
}

.reference_filter_input <- function(x, name) {
  if (!is.null(x) && (!is.character(x) || !length(x) || anyNA(x) ||
                     any(!nzchar(trimws(x))))) {
    stop("`", name, "` must contain non-empty character values or NULL.")
  }
}

.validate_marker_reference <- function(reference) {
  required <- c("cell_type", "marker")
  if (!is.data.frame(reference) || !all(required %in% names(reference))) {
    stop("Reference must be a data frame containing cell_type and marker columns.")
  }
  for (name in required) {
    x <- reference[[name]]
    if ((length(x) && !is.character(x) && !is.factor(x)) || anyNA(x) ||
        any(!nzchar(trimws(as.character(x))))) {
      stop("Reference ", name, " must contain non-empty character values.")
    }
    reference[[name]] <- trimws(as.character(x))
  }
  reference
}

.empty_reference_matches <- function() {
  data.frame(cluster = character(), cell_type = character(),
             overlap_count = integer(), celltype_size = integer(),
             score = numeric(), matched_markers = character(),
             stringsAsFactors = FALSE)
}

.reference_input_cells <- function(obj) {
  if (!methods::is(obj@data, "Seurat") ||
      !"seurat_clusters" %in% names(obj@data@meta.data)) return(NULL)
  cells <- data.frame(cell_id = colnames(obj@data),
                      cluster = as.character(obj@data$seurat_clusters),
                      stringsAsFactors = FALSE)
  if (anyNA(cells) || any(!nzchar(trimws(cells$cell_id))) ||
      any(!nzchar(trimws(cells$cluster))) || anyDuplicated(cells$cell_id)) {
    stop("Current Seurat cell IDs and cluster IDs must be non-empty and non-missing.")
  }
  cells
}
