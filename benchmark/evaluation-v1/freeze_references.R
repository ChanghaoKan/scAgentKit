a <- commandArgs(TRUE);stopifnot(length(a)==1L);root<-normalizePath(a[1])
library(SummarizedExperiment)
receipts <- lapply(c("blueprint-encode","hpca"),function(name) {
  path<-file.path(root,paste0(name,".rds")); x<-readRDS(path)
  labels<-as.character(x$label.main);mat<-as.matrix(assay(x,"logcounts"))
  stopifnot(all(is.finite(mat)),!anyNA(labels),!anyDuplicated(rownames(mat)))
  means<-vapply(sort(unique(labels),method="radix"),function(label) rowMeans(mat[,labels==label,drop=FALSE]),numeric(nrow(mat)))
  reference<-do.call(rbind,lapply(seq_len(ncol(means)),function(i) {
    contrast<-means[,i]-rowMeans(means[,-i,drop=FALSE]);eligible<-which(contrast>1)
    genes<-head(rownames(mat)[eligible[order(-contrast[eligible],rownames(mat)[eligible],method="radix")]],30L)
    data.frame(cell_type=rep(colnames(means)[i],length(genes)),marker=genes,species="human",tissue="all")
  }))
  marker_path<-file.path(root,paste0(name,"-markers.csv"));write.csv(reference,marker_path,row.names=FALSE)
  list(name=name,source="Official celldex1.12.0 legacy ExperimentHub reference; no query-derived labels",
    data_sha256=digest::digest(file=path,algo="sha256"),assay_hash=digest::digest(mat,algo="sha256"),
    samples=ncol(mat),genes=nrow(mat),labels=sort(unique(labels)),marker_sha256=digest::digest(file=marker_path,algo="sha256"),
    marker_rule="Top30 positive bulk mean-log expression contrast>1 versus average other reference types; frozen independently of query",
    shared_reference_dependency="SingleR and marker coverage use the same reference; their agreement is not independent confirmation")
})
jsonlite::write_json(list(protocol="evaluation-v1",references=receipts,query_outcomes_read=FALSE),file.path(root,"frozen-manifest.json"),auto_unbox=TRUE,pretty=TRUE)
