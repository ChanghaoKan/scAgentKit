#' Merge explicitly prepared Seurat inputs without guessing cell prefixes
#' @param obj Nonempty Seurat list with matching literal feature IDs.
#' @param add_cell_ids Optional explicit unique cell prefixes; NULL preserves IDs.
#' @param join_layers Whether to join the selected assay's layers after merging.
#' @param assay Explicit assay.
#' @return New Seurat; original objects are unchanged. No sample-role inference.
#' @export
qc_merge <- function(obj,add_cell_ids=NULL,join_layers=TRUE,assay="RNA") {
  if(!is.list(obj)||!length(obj)||!all(vapply(obj,inherits,logical(1),"Seurat")))stop("Supply a nonempty Seurat list.",call.=FALSE)
  features<-lapply(obj,function(x)rownames(x[[assay]]))
  if(!all(vapply(features,setequal,logical(1),features[[1]])))stop("Merge feature IDs must match exactly; no union or intersection is inferred.",call.=FALSE)
  if(!is.null(add_cell_ids)) {
    if(!is.character(add_cell_ids)||length(add_cell_ids)!=length(obj)||anyNA(add_cell_ids)||any(!nzchar(add_cell_ids))||anyDuplicated(add_cell_ids))stop("Declare one unique prefix per object.",call.=FALSE)
  } else if(anyDuplicated(unlist(lapply(obj,colnames),use.names=FALSE)))stop("Duplicate cell IDs; supply explicit add_cell_ids.",call.=FALSE)
  if(!is.logical(join_layers)||length(join_layers)!=1||is.na(join_layers))stop("join_layers must be TRUE/FALSE.",call.=FALSE)
  out<-if(length(obj)==1L)obj[[1]] else merge(obj[[1]],y=obj[-1],add.cell.ids=add_cell_ids)
  if(length(obj)==1L&&!is.null(add_cell_ids))out<-Seurat::RenameCells(out,add.cell.id=add_cell_ids[1])
  if(join_layers&&inherits(out[[assay]],"Assay5"))out[[assay]]<-SeuratObject::JoinLayers(out[[assay]])
  out
}
