# Standalone table utilities; project execution uses the same shared kernels.
#' Find markers from explicit prepared Seurat clusters
#' @param obj Prepared Seurat with seurat_clusters metadata and normalized data.
#' @param only_pos,min_pct,logfc_threshold Native Seurat marker options.
#' @return Full marker data.frame; no labels, review or project mutation.
#' @export
sc_find_markers <- function(obj, only_pos=FALSE, min_pct=0.25, logfc_threshold=0) {
  .sc_marker_test(.sc_project_unwrap(obj),only_pos,min_pct,logfc_threshold)
}
#' Filter and rank a supplied marker table
#' @param obj Full marker data.frame.
#' @param top_n,log2fc_cut,padj_cut Existing strict summary settings.
#' @param output_path Optional explicit summary text file; default writes nothing.
#' @return Filtered data.frame with summary_lines and cycling_score attributes.
#' @export
sc_markers_summary <- function(obj,top_n=30,log2fc_cut=1,padj_cut=0.05,output_path=NULL) {
  if(!is.data.frame(obj)) stop("Supply a marker data.frame.",call.=FALSE)
  out<-.sc_marker_summary(obj,top_n,log2fc_cut,padj_cut)
  if(!is.null(output_path)) {dir.create(dirname(output_path),recursive=TRUE,showWarnings=FALSE);writeLines(out$summary_lines,output_path)}
  value<-out$filtered;attr(value,"summary_lines")<-out$summary_lines
  attr(value,"cycling_score")<-out$cycling_score;value
}
