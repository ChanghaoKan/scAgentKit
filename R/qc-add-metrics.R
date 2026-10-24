#' Add explicitly declared count-based QC measurements to a Seurat copy
#' @param obj Seurat object with a single explicit counts layer.
#' @param species Declared human/mouse; required unless all patterns are explicit.
#' @param mt_pattern,ribo_pattern,hb_pattern Optional explicit gene regexes.
#' @param assay,counts_layer Exact source assay/layer.
#' @return Seurat copy with percent.mt, percent.ribo and percent.hb; unavailable
#'   gene families and zero-total cells are NA. Default patterns use existing
#'   aligned gene-symbol annotations; explicit patterns match literal feature IDs.
#' @export
qc_add_metrics <- function(obj,species=NULL,mt_pattern=NULL,ribo_pattern=NULL,hb_pattern=NULL,
  assay="RNA",counts_layer="counts") {
  obj<-.sc_project_unwrap(obj)
  supplied <- c(!is.null(mt_pattern), !is.null(ribo_pattern), !is.null(hb_pattern))
  custom<-!is.null(mt_pattern)&&!is.null(ribo_pattern)&&!is.null(hb_pattern)
  if(!custom) species<-.sc_run_species(species)
  if(is.null(mt_pattern))mt_pattern<-if(species=="mouse")"^mt-" else "^MT-"
  if(is.null(ribo_pattern))ribo_pattern<-.sc_run_ribo_pattern(species)
  if(is.null(hb_pattern))hb_pattern<-if(species=="mouse")"^Hb[ab]" else "^HB[AB]"
  patterns<-list(percent.mt=mt_pattern,percent.ribo=ribo_pattern,percent.hb=hb_pattern)
  for(key in names(patterns)) .sc_project_string(patterns[[key]],key)
  counts<-.sc_project_layer(obj,assay,counts_layer,raw_counts=TRUE)
  total<-as.numeric(Matrix::colSums(counts))
  metrics <- list()
  for(key in names(patterns)) {
    index <- match(key, names(patterns))
    family <- c("mitochondrial", "ribosomal", "hemoglobin")[index]
    resolved <- if (supplied[index]) {
      genes <- rownames(counts)[grepl(patterns[[key]], rownames(counts))]
      list(features = genes, summary = list(available = length(genes) > 0L,
        feature_count = length(genes), pattern = patterns[[key]], mapping_source = "explicit_feature_pattern",
        unavailable_reason = if (!length(genes)) "No features match the explicit pattern; percentage is unavailable, not zero." else NULL))
    } else .sc_run_gene_family_features(obj, assay, rownames(counts), species, patterns[[key]], family)
    value <- if (length(resolved$features))
      100*as.numeric(Matrix::colSums(counts[resolved$features,,drop=FALSE]))/total else rep(NA_real_, length(total))
    value[total==0]<-NA_real_;obj[[key]]<-stats::setNames(value,colnames(counts))
    metrics[[key]] <- resolved$summary
  }
  obj@misc$qc_metric_source<-list(species=species,assay=assay,counts_layer=counts_layer,patterns=patterns,metrics=metrics)
  obj
}
