#' Collapse fine cell type labels to broad categories
#'
#' Maps fine-grained cell type labels (e.g. "CD8 T cell", "Plasma cell",
#' "Hepatic stellate cell") to broad categories (e.g. "T/NK", "B",
#' "Fibroblast"). Uses a built-in mapping curated for common immune
#' / stromal / parenchymal lineages; users can extend it via `extra_map`.
#'
#' This is helpful when the LLM annotation produced finer labels than
#' the author's broad categories -- see [annot_compare_with_reference()]
#' which uses this internally.
#'
#' @param x Character vector of cell type labels.
#' @param extra_map Optional named character vector to extend / override
#'   the built-in map. Names are fine labels, values are broad labels.
#' @param keep_unmapped Logical. If TRUE (default), labels not in the
#'   map are returned as-is (e.g. "Fibroblast" stays "Fibroblast"
#'   because it's already broad). If FALSE, unmapped labels become
#'   `NA_character_`.
#'
#' @return Character vector of broad labels, same length as `x`.
#' @export
#'
#' @examples
#' \dontrun{
#'   broad <- annot_collapse_to_broad(c("CD8 T cell", "Plasma cell",
#'                                       "CAF", "LSEC"))
#'   #   "T/NK"  "B"  "Fibroblast"  "Endothelial"
#' }
annot_collapse_to_broad <- function(x,
                                    extra_map     = NULL,
                                    keep_unmapped = TRUE) {
  default_map <- .default_broad_map()
  if (!is.null(extra_map)) {
    if (is.null(names(extra_map))) {
      stop("`extra_map` must be a NAMED character vector.")
    }
    default_map[names(extra_map)] <- extra_map
  }

  out <- ifelse(x %in% names(default_map),
                default_map[x],
                if (isTRUE(keep_unmapped)) x else NA_character_)
  unname(out)
}

#' Compare saved labels to an explicitly selected reference by exact cell ID
#' @param obj Seurat object; this function never modifies it.
#' @param reference_col Explicit reference metadata column, or NULL for external labels.
#' @param author_celltype Named external reference vector covering current literal cell IDs.
#' @param collapse_llm Explicit logical choice to apply the broad-label utility; default FALSE.
#' @param extra_map Optional explicit broad-label mapping.
#' @param label_col Explicit predicted/reviewed label column, default sc_annotation.
#' @return Descriptive comparison list, not biological accuracy or identity validation.
#' @export
annot_compare_with_reference <- function(obj,reference_col=NULL,author_celltype=NULL,
  collapse_llm=FALSE,extra_map=NULL,label_col="sc_annotation") {
  obj<-.sc_project_unwrap(obj);meta<-obj[[]];cells<-colnames(obj)
  .sc_project_string(label_col,"label_col")
  if(!label_col %in% names(meta))stop("Explicit label column is absent.",call.=FALSE)
  if(!is.logical(collapse_llm)||length(collapse_llm)!=1L||is.na(collapse_llm))stop("collapse_llm must be explicit TRUE/FALSE.",call.=FALSE)
  if(!is.null(author_celltype)) {
    if(!is.null(reference_col))stop("Choose exactly one reference source.",call.=FALSE)
    ref<-.align_external_celltype(obj,author_celltype);source<-"external exact-ID vector"
  } else {
    .sc_project_string(reference_col,"reference_col")
    if(!reference_col %in% names(meta)||identical(reference_col,label_col))stop("Select a separate explicit reference column.",call.=FALSE)
    ref<-as.character(meta[cells,reference_col]);names(ref)<-cells;source<-reference_col
  }
  predicted<-as.character(meta[cells,label_col]);names(predicted)<-cells
  if(collapse_llm)predicted<-annot_collapse_to_broad(predicted,extra_map=extra_map)
  reference<-as.character(ref[cells])
  known<-!is.na(predicted)&nzchar(predicted)&!is.na(reference)&nzchar(reference)
  confusion<-table(Label=predicted[known],Reference=reference[known])
  list(confusion=confusion,overall_concordance=if(any(known))round(100*mean(predicted[known]==reference[known]),1)else NULL,
    n_input_cells=length(cells),n_cells_compared=sum(known),n_missing=sum(!known),
    unresolved_labels=sum(!is.na(predicted)&tolower(predicted) %in% c("unknown","unannotated")),
    collapse_used=collapse_llm,reference_source=source,label_column=label_col,
    interpretation="Literal label agreement on the stated denominator; reference and predicted labels are not independent identity truth. No labels, approvals or project data are changed.")
}

.align_external_celltype <- function(obj,author_celltype) {
  cells<-colnames(obj);ids<-names(author_celltype)
  if(!is.character(author_celltype)&&!is.factor(author_celltype))stop("Reference labels must be text.",call.=FALSE)
  if(is.null(ids)||anyNA(ids)||any(!nzchar(ids))||anyDuplicated(ids))stop("Reference requires unique nonempty literal cell IDs.",call.=FALSE)
  if(!all(cells %in% ids))stop("Reference must cover every current exact cell ID; prefixes and barcodes are not guessed.",call.=FALSE)
  stats::setNames(as.character(author_celltype[match(cells,ids)]),cells)
}
