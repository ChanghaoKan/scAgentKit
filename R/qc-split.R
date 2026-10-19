#' Split a Seurat copy by an explicitly supplied metadata column
#' @param obj Seurat object.
#' @param split_by Explicit complete metadata column; no role inference.
#' @return Named list of Seurat objects. Does not fit models or approve QC.
#' @export
qc_split <- function(obj,split_by) {
  obj<-.sc_project_unwrap(obj);.sc_project_string(split_by,"split_by")
  if(!split_by %in% names(obj[[]]))stop("Explicit split column is absent.",call.=FALSE)
  values<-as.character(obj[[]][[split_by]])
  if(anyNA(values)||any(!nzchar(values)))stop("Split values must be complete.",call.=FALSE)
  Seurat::SplitObject(obj,split.by=split_by)
}
