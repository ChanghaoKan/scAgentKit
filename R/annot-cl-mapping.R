#' Map cell type labels to Cell Ontology (CL) identifiers
#'
#' Resolves free-text cell type names (the LLM's `primary_annotation`
#' field, or a user-supplied vector) to Cell Ontology IDs (CL:XXXXXXX)
#' using exact name and synonym matching. Annotations matching neither
#' get NA, which is biologically honest: scAgentKit will not guess at
#' a CL ID without literal evidence.
#'
#' Match logic (in order):
#' \enumerate{
#'   \item Lower-case, whitespace-collapsed exact match against CL term names.
#'   \item Same against the CL synonyms list.
#'   \item Stop. No fuzzy matching, no embedding similarity. Reviewers
#'     of methods papers consistently flag fuzzy CL mapping as a source
#'     of silent label drift; better to report NA than to introduce it.
#' }
#'
#' Adds a `cl_id` column (and `cl_name` if the match resolved through
#' a synonym, recording the canonical CL label) to `obj@@params$llm_annotations`
#' and to `obj@@data@@meta.data$cl_id` (mapped per-cell from `cell_type`).
#'
#' The Cell Ontology is loaded lazily from the `ontologyIndex` package's
#' bundled `go.obo`-style file, or from a user-supplied OBO path. The
#' first call may take a few seconds; subsequent calls reuse the cache.
#'
#' @param obj An AgentSeurat object after [annot_llm_annotate()] (or
#'   after [annot_apply()] if you want the cell-level `cl_id` column).
#' @param obo_path Optional path to a CL OBO file. If `NULL` (default),
#'   the function downloads the latest CL release from OBO Foundry
#'   (cached under `tools::R_user_dir("scAgentKit", "cache")`) on first
#'   use.
#' @param column Character. The annotation column on
#'   `obj@@params$llm_annotations` to map. Defaults to
#'   `"primary_annotation"`.
#' @param map_cells Logical. If `TRUE` (default), also writes
#'   `obj@@data@@meta.data$cl_id` by joining on `cell_type`. Requires
#'   `annot_apply()` to have been run first.
#'
#' @return Updated AgentSeurat with new columns. Two new fields are
#'   added to `obj@@params$llm_annotations`:
#'   \itemize{
#'     \item `cl_id`: e.g. `"CL:0000084"` or `NA` if no match
#'     \item `cl_name`: the canonical CL label (may differ from the
#'       LLM's wording when a synonym matched)
#'   }
#'
#' @section Why exact match only:
#' Existing tools (CyteType, others) do fuzzy / embedding-based CL
#' mapping. We deliberately don't, because LLM-driven annotation paired
#' with fuzzy CL mapping silently launders soft mismatches as canonical
#' identifiers. With exact match, a non-NA CL ID is a verifiable claim
#' the reader can check; an NA is an honest "no canonical equivalent
#' was found, the LLM label stands on its own". Use [cl_lookup()] for
#' interactive fuzzy exploration when you actually want it.
#'
#' @export
annot_map_to_cl <- function(obj,
                            obo_path  = NULL,
                            column    = "primary_annotation",
                            map_cells = TRUE) {
  stopifnot(methods::is(obj, "AgentSeurat"))
  ann <- obj@params$llm_annotations
  if (is.null(ann) || nrow(ann) == 0) {
    stop("No LLM annotations found. Run annot_llm_annotate() first.")
  }
  if (!column %in% colnames(ann)) {
    stop(sprintf("Column '%s' not found in obj@params$llm_annotations.",
                 column))
  }
  if (!requireNamespace("ontologyIndex", quietly = TRUE)) {
    stop("Package 'ontologyIndex' is required. ",
         "Install with install.packages('ontologyIndex').")
  }

  cl <- .get_cl_ontology(obo_path)

  labels <- as.character(ann[[column]])
  res    <- vapply(labels, function(lab) {
    m <- .cl_match_one(lab, cl)
    paste(m$cl_id %||% NA_character_,
          m$cl_name %||% NA_character_,
          sep = "\t")
  }, character(1))
  parts <- do.call(rbind, strsplit(res, "\t", fixed = TRUE))
  ann$cl_id   <- ifelse(parts[, 1] == "NA", NA_character_, parts[, 1])
  ann$cl_name <- ifelse(parts[, 2] == "NA", NA_character_, parts[, 2])

  n_total   <- nrow(ann)
  n_matched <- sum(!is.na(ann$cl_id))
  rationale <- sprintf(
    "Mapped %d / %d annotations to Cell Ontology IDs (exact name/synonym match).",
    n_matched, n_total
  )

  obj@params$llm_annotations <- ann

  if (isTRUE(map_cells)) {
    md <- obj@data@meta.data
    if ("cell_type" %in% colnames(md)) {
      lookup <- setNames(ann$cl_id, ann$primary_annotation)
      obj@data@meta.data$cl_id <- lookup[as.character(md$cell_type)]
    } else {
      message("[annot_map_to_cl] obj@data@meta.data$cell_type not present; ",
              "skipping per-cell CL mapping. Run annot_apply() first to enable.")
    }
  }

  .record_step(
    obj            = obj,
    step_name      = "annot_map_to_cl",
    function_name  = "annot_map_to_cl",
    params         = list(
      column         = column,
      map_cells      = map_cells,
      n_total        = n_total,
      n_matched      = n_matched,
      match_rate     = n_matched / max(n_total, 1)
    ),
    rationale      = rationale,
    script_snippet = sprintf(
'# ---- Map annotations to Cell Ontology IDs ----
# Exact name/synonym match against CL; %d / %d (%.0f%%) matched.
obj <- annot_map_to_cl(obj%s)',
      n_matched, n_total, 100 * n_matched / max(n_total, 1),
      if (is.null(obo_path)) "" else sprintf(", obo_path = \"%s\"", obo_path)
    )
  )
}


#' Look up Cell Ontology IDs interactively
#'
#' Helper for human-in-the-loop annotation: given a free-text query,
#' return candidate CL terms ranked by string proximity. Useful when
#' [annot_map_to_cl()] returned NA and you want to find what the canonical
#' label *could* be.
#'
#' @param query Character. The label to look up (e.g. `"hepatocyte"`).
#' @param n Integer. Number of candidates to return. Default 10.
#' @param obo_path Optional CL OBO path; see [annot_map_to_cl()].
#'
#' @return Data frame with columns `cl_id`, `cl_name`, `score`.
#' @export
cl_lookup <- function(query, n = 10, obo_path = NULL) {
  if (!requireNamespace("ontologyIndex", quietly = TRUE)) {
    stop("Package 'ontologyIndex' is required.")
  }
  cl <- .get_cl_ontology(obo_path)
  q  <- .cl_normalise(query)
  names_norm <- vapply(cl$name, .cl_normalise, character(1))
  # Simple substring + Levenshtein hybrid score
  contains <- grepl(q, names_norm, fixed = TRUE)
  dist <- utils::adist(q, names_norm, ignore.case = TRUE)[1, ]
  score <- ifelse(contains, 0, dist)
  ord <- order(score)[seq_len(min(n, length(score)))]
  data.frame(
    cl_id   = names(cl$name)[ord],
    cl_name = cl$name[ord],
    score   = score[ord],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}


# ---- Internal helpers ------------------------------------------------------

.cl_env <- new.env(parent = emptyenv())

# Lazy loader for the CL ontology. Caches per session.
.get_cl_ontology <- function(obo_path = NULL) {
  if (!is.null(.cl_env$cl)) return(.cl_env$cl)
  if (is.null(obo_path)) {
    cache_dir <- tools::R_user_dir("scAgentKit", which = "cache")
    if (!dir.exists(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    }
    obo_path <- file.path(cache_dir, "cl.obo")
    if (!file.exists(obo_path)) {
      url <- "http://purl.obolibrary.org/obo/cl.obo"
      message("[scAgentKit] downloading Cell Ontology from ", url,
              " to ", obo_path, " (first time only)...")
      utils::download.file(url, obo_path, mode = "wb", quiet = TRUE)
    }
  }
  cl <- ontologyIndex::get_ontology(obo_path,
                                     propagate_relationships = "is_a",
                                     extract_tags = "everything")
  .cl_env$cl <- cl
  cl
}

.cl_normalise <- function(s) {
  s <- tolower(s)
  s <- gsub("[[:space:]]+", " ", s)
  s <- gsub("^\\s+|\\s+$", "", s)
  s
}

.cl_match_one <- function(label, cl) {
  if (is.na(label) || !nzchar(label)) {
    return(list(cl_id = NA_character_, cl_name = NA_character_))
  }
  q <- .cl_normalise(label)
  # 1. Exact name match
  norm_names <- vapply(cl$name, .cl_normalise, character(1))
  hit <- which(norm_names == q)
  if (length(hit) > 0) {
    id <- names(cl$name)[hit[1]]
    return(list(cl_id = id, cl_name = cl$name[[id]]))
  }
  # 2. Synonym match — cl$synonym is a list of character vectors
  syn <- cl$synonym
  if (!is.null(syn)) {
    for (i in seq_along(syn)) {
      s_list <- syn[[i]]
      if (length(s_list) == 0) next
      # OBO synonym format: '"PRIMARY NAME" EXACT [...]'. Strip quotes/tags.
      s_clean <- vapply(s_list, function(s) {
        s <- sub('^"', '', s)
        s <- sub('"\\s+[A-Z]+\\s*\\[.*$', '', s)
        s <- sub('"$', '', s)
        .cl_normalise(s)
      }, character(1))
      if (any(s_clean == q)) {
        id <- names(syn)[i]
        return(list(cl_id = id, cl_name = cl$name[[id]]))
      }
    }
  }
  list(cl_id = NA_character_, cl_name = NA_character_)
}
