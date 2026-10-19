# Validate saved native correction outputs; never repeat or replace a fit.
a<-commandArgs(TRUE);stopifnot(length(a)==3L)
.libPaths(c(normalizePath(a[1]),.libPaths()));library(scAgentKit)
input<-readRDS(a[2]);root<-normalizePath(a[3]);ns<-asNamespace("scAgentKit")
counts<-get(".sc_project_layer",ns)(input,"RNA","counts",raw_counts=TRUE)
original<-get(".sc_project_sparse_hash",ns)(counts);input_hash<-get(".sc_run_hash",ns)(input)
results<-lapply(c("SoupX","decontX"),function(method) {
 path<-file.path(root,method);corrected_path<-file.path(path,"corrected-counts.rds")
 corrected<-readRDS(corrected_path);receipt<-jsonlite::read_json(file.path(path,"comparison.json"),simplifyVector=TRUE)
 stopifnot(identical(receipt$input_hash,input_hash),identical(receipt$original_counts_hash,original),
  identical(receipt$corrected_counts_hash,get(".sc_project_sparse_hash",ns)(corrected)),
  identical(dimnames(corrected),dimnames(counts)),!isTRUE(receipt$authoritative_input_changed))
 panels<-get(".sc_run_classic_panels",ns)("blood")
 summary<-do.call(rbind,lapply(names(panels),function(panel) do.call(rbind,lapply(intersect(panels[[panel]],rownames(counts)),function(gene)
  data.frame(panel=panel,gene=gene,before_umi=sum(counts[gene,]),after_umi=sum(corrected[gene,]),
   before_detected=sum(counts[gene,]>0),after_detected=sum(corrected[gene,]>0))))))
 write.csv(summary,file.path(path,"expression-comparison.csv"),row.names=FALSE)
 object<-Seurat::CreateSeuratObject(corrected,min.cells=0,min.features=0,meta.data=input[[]])
 object<-Seurat::NormalizeData(object,normalization.method="LogNormalize",scale.factor=10000,verbose=FALSE)
 saveRDS(object,file.path(path,"normalized-corrected.rds"),version=2L)
 list(method=method,status="verified_saved_native_fit",version=receipt$version,cells=ncol(counts),original_input_unchanged=TRUE,
  original_counts_hash=original,corrected_counts_hash=receipt$corrected_counts_hash,
  contamination_range=range(as.numeric(receipt$contamination)),
  corrected_artifact_sha256=digest::digest(file=corrected_path,algo="sha256"),
  biological_accuracy=NULL,corrected_input_automatically_adopted=FALSE,
  verification_note="Native fit outputs from attempt1 reused exactly. Initial downstream harness compared canonical sorted order to native Seurat order; exact literal IDs now aligned by the same canonical layer reader as the adapter. Original failed harness record preserved; neither algorithm rerun nor authoritative input modified.")
})
jsonlite::write_json(results,file.path(root,"postverified-run.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
