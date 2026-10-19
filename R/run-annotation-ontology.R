# Dictionary support is saved before review; reading or applying the approved
# proposal uses this immutable record and never re-resolves ontology labels.
.sc_run_annotation_ontology <- function(proposal) {
  labels <- vapply(proposal$annotations, `[[`, character(1), "label")
  ids <- vapply(proposal$annotations, `[[`, character(1), "clusterId")
  record <- list(schema="scagentkit.annotation-ontology.v1",
    proposal_hash=.sc_run_hash(.sc_run_annotation_review_plain(proposal)),
    status="unavailable", source=NULL,
    notice="The optional ontologyIndex dependency is unavailable. CL IDs remain blank; configure that dependency and save a new annotation draft to resolve exact dictionary entries.")
  rows <- data.frame(clusterId=ids,label=labels,cl_id=NA_character_,cl_name=NA_character_,
    status="unavailable",stringsAsFactors=FALSE)
  if (requireNamespace("ontologyIndex",quietly=TRUE)) {
    cl <- .get_cl_ontology()
    unique_labels <- unique(labels)
    resolved <- lapply(unique_labels,function(label) .cl_match_one(label,cl))
    names(resolved) <- unique_labels
    for (i in seq_along(labels)) {
      hit <- resolved[[labels[[i]]]]
      rows$cl_id[[i]] <- hit$cl_id;rows$cl_name[[i]] <- hit$cl_name
      rows$status[[i]] <- if (is.na(hit$cl_id)) "unresolved_exact_or_ambiguous" else "unique_exact_dictionary_match"
    }
    record$status <- "resolved_exact_dictionary"
    record$source <- attr(cl,"scAgentKit_source")
    record$notice <- "Only unique non-obsolete exact CL names/EXACT synonyms receive IDs. Unmatched, ambiguous and fuzzy labels remain blank for review. A dictionary match does not validate biological identity."
  }
  record$rows <- rows;record$hash <- .sc_run_hash(record);record
}

.sc_run_annotation_ontology_check <- function(record, proposal) {
  if (!is.list(record) || !identical(record$schema,"scagentkit.annotation-ontology.v1") ||
      !identical(record$hash,.sc_run_hash(record[setdiff(names(record),"hash")])) ||
      !identical(record$proposal_hash,.sc_run_hash(.sc_run_annotation_review_plain(proposal))))
    stop("Saved ontology mapping differs from the annotation draft. Save and review a new complete proposal.",call.=FALSE)
  rows <- record$rows
  if (!is.data.frame(rows) || !identical(rows$clusterId,vapply(proposal$annotations,`[[`,character(1),"clusterId")) ||
      !identical(rows$label,vapply(proposal$annotations,`[[`,character(1),"label")) ||
      !is.character(rows$cl_id) || any(!is.na(rows$cl_id) & !grepl("^CL:[0-9]{7}$",rows$cl_id)))
    stop("Saved ontology rows do not match the exact annotation clusters and labels.",call.=FALSE)
  record
}

.sc_run_annotation_ontology_get <- function(root,state,proposal) {
  if (is.null(state$config$input_policy)) return(NULL)
  file <- state$files$annotation_ontology
  if (is.null(file)) stop("Save the complete annotation draft to prepare its local ontology record before approval.",call.=FALSE)
  path <- file.path(root,file$path)
  if (!file.exists(path) || nzchar(Sys.readlink(path)) || !identical(file$sha256,.sc_project_sha_file(path)))
    stop("The saved ontology mapping checkpoint changed; approval is stale.",call.=FALSE)
  .sc_run_annotation_ontology_check(.sc_run_get(root,state,"annotation_ontology"),proposal)
}
