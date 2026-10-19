#' Add explicitly declared count-based QC measurements to a Seurat copy
#' @param obj Seurat object with a single explicit counts layer.
#' @param species Declared human/mouse; required unless all patterns are explicit.
#' @param mt_pattern,ribo_pattern,hb_pattern Optional explicit gene regexes.
#' @param assay,counts_layer Exact source assay/layer.
#' @return Seurat copy with percent.mt, percent.ribo and percent.hb; no filtering.
#' @export
qc_add_metrics <- function(obj,species=NULL,mt_pattern=NULL,ribo_pattern=NULL,hb_pattern=NULL,
  assay="RNA",counts_layer="counts") {
  obj<-.sc_project_unwrap(obj)
  custom<-!is.null(mt_pattern)&&!is.null(ribo_pattern)&&!is.null(hb_pattern)
  if(!custom) species<-.sc_run_species(species)
  if(is.null(mt_pattern))mt_pattern<-if(species=="mouse")"^mt-" else "^MT-"
  if(is.null(ribo_pattern))ribo_pattern<-.sc_run_ribo_pattern(species)
  if(is.null(hb_pattern))hb_pattern<-if(species=="mouse")"^Hb[ab]" else "^HB[AB]"
  patterns<-list(percent.mt=mt_pattern,percent.ribo=ribo_pattern,percent.hb=hb_pattern)
  for(key in names(patterns)) .sc_project_string(patterns[[key]],key)
  counts<-.sc_project_layer(obj,assay,counts_layer,raw_counts=TRUE)
  total<-as.numeric(Matrix::colSums(counts))
  for(key in names(patterns)) {
    selected<-grepl(patterns[[key]],rownames(counts))
    value<-100*as.numeric(Matrix::colSums(counts[selected,,drop=FALSE]))/total
    value[total==0]<-NA_real_;obj[[key]]<-stats::setNames(value,colnames(counts))
  }
  obj@misc$qc_metric_source<-list(species=species,assay=assay,counts_layer=counts_layer,patterns=patterns)
  obj
}
