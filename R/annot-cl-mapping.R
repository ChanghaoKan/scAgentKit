#' Map supplied labels to exact Cell Ontology names or synonyms
#' @param obj Label data.frame or Seurat copy with a saved label column.
#' @param obo_path Explicit local CL OBO path; NULL uses the bundled, checksum-pinned v2026-06-08 base ontology without downloading.
#' @param column Label column, default label for a table or sc_annotation for Seurat.
#' @param map_cells Whether to append IDs to the returned Seurat copy (never project state).
#' @return Table with cl_id/cl_name, or a Seurat copy with cl_id/cl_name metadata.
#'   Matching is dictionary support, not semantic validation or scientific approval.
#' @export
annot_map_to_cl <- function(obj,obo_path=NULL,column=NULL,map_cells=TRUE) {
  seurat<-inherits(obj,"Seurat")
  if(!seurat&&!is.data.frame(obj))stop("Supply a Seurat object or label table.",call.=FALSE)
  if(is.null(column))column<-if(seurat)"sc_annotation" else "label"
  table<-if(seurat)obj[[]] else obj
  if(!column %in% names(table))stop("Explicit label column is absent.",call.=FALSE)
  if(!requireNamespace("ontologyIndex",quietly=TRUE))stop("ontologyIndex is required; configure this optional dependency explicitly.",call.=FALSE)
  cl<-.get_cl_ontology(obo_path);source<-attr(cl,"scAgentKit_source")
  unique_labels<-unique(as.character(table[[column]]))
  lookup<-lapply(unique_labels,function(label).cl_match_one(label,cl))
  matched<-lookup[match(as.character(table[[column]]),unique_labels)]
  table$cl_id<-vapply(matched,function(x)if(is.null(x$cl_id))NA_character_ else x$cl_id,"")
  table$cl_name<-vapply(matched,function(x)if(is.null(x$cl_name))NA_character_ else x$cl_name,"")
  if(seurat) {
    if(map_cells){obj$cl_id<-stats::setNames(table$cl_id,rownames(table));obj$cl_name<-stats::setNames(table$cl_name,rownames(table))}
    obj@misc$cell_ontology<-list(source=source,label_column=column,matched=sum(!is.na(table$cl_id)),total=nrow(table))
    return(obj)
  }
  attr(table,"ontology_source")<-source;table
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
  fixed <- is.null(obo_path)
  provenance <- NULL
  if (fixed) {
    directory <- system.file("extdata", "references", package = "scAgentKit")
    obo_path <- file.path(directory, "cl-base-v2026-06-08.obo")
    if (!nzchar(directory) || !file.exists(obo_path))
      stop("The fixed local Cell Ontology is unavailable. Reinstall the complete package or supply an explicit local obo_path; no network fallback is used.", call. = FALSE)
    expected <- "c6274fb65cdf740b983a06b74cb678814249d7f8e580c2ec9de54bf204a2b1c7"
    if (!identical(digest::digest(file = obo_path, algo = "sha256"), expected))
      stop("The fixed Cell Ontology checksum changed. Restore the package's original reference before mapping labels.", call. = FALSE)
    provenance <- jsonlite::read_json(file.path(directory, "CL-PROVENANCE.json"), simplifyVector = TRUE)
  }
  obo_path <- normalizePath(obo_path, mustWork = TRUE)
  sha <- digest::digest(file = obo_path, algo = "sha256")
  key <- paste(obo_path, sha, fixed)
  # Key the session cache by path and content: a different OBO must not
  # silently return the ontology loaded first.
  if (identical(.cl_env$key, key)) return(.cl_env$cl)
  cl <- ontologyIndex::get_ontology(obo_path,
                                     propagate_relationships = "is_a",
                                     extract_tags = "everything")
  attr(cl, "scAgentKit_source") <- list(path = obo_path, sha256 = sha, mode = if (fixed) "fixed_bundled_release" else "explicit_local_file", provenance = provenance)
  .cl_env$cl <- cl; .cl_env$key <- key
  cl
}

# Candidate terms: non-obsolete CL identifiers only.
.cl_candidates <- function(cl) {
  ids <- names(cl$name)
  keep <- startsWith(ids, "CL:")
  if (!is.null(cl$obsolete)) keep <- keep & !(cl$obsolete[ids] %in% TRUE)
  ids[keep]
}

# Parse an OBO synonym value ('"text" SCOPE [TYPE] [xrefs]') into its text
# and scope; NULL when malformed.
.cl_synonym <- function(value) {
  m <- regmatches(value, regexec('^"((?:[^"\\\\]|\\\\.)*)"\\s+([A-Z]+)\\b', value, perl = TRUE))[[1]]
  if (length(m) != 3L) return(NULL)
  list(text = gsub("\\\\(.)", "\\1", m[2], perl = TRUE), scope = m[3])
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
  ids <- .cl_candidates(cl)
  # Collect every exact label/synonym hit before choosing. An ambiguous
  # dictionary entry is unresolved; iteration order must never choose its ID.
  norm_names <- vapply(unname(cl$name[ids]), .cl_normalise, character(1))
  hits <- ids[norm_names == q]
  syn <- cl$synonym
  if (!is.null(syn)) for (id in ids) for (value in syn[[id]]) {
    parsed <- .cl_synonym(value)
    if (!is.null(parsed) && identical(parsed$scope, "EXACT") &&
        identical(.cl_normalise(parsed$text), q)) hits <- c(hits, id)
  }
  hits <- unique(hits)
  if (length(hits) == 1L) return(list(cl_id = hits[[1L]], cl_name = cl$name[[hits[[1L]]]]))
  list(cl_id = NA_character_, cl_name = NA_character_)
}
