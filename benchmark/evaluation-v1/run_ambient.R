# Explicit full-capture adapter acceptance, separate from original project counts.
a<-commandArgs(TRUE);stopifnot(length(a)==5L)
.libPaths(c(normalizePath(a[1]),.libPaths()));library(scAgentKit);library(SeuratObject)
input_path<-normalizePath(a[2]);analysis_path<-normalizePath(a[3]);raw_archive<-normalizePath(a[4]);out<-a[5]
stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
x<-readRDS(input_path);analysis<-readRDS(analysis_path)
stopifnot(setequal(colnames(x),colnames(analysis)))
workflow_receipt<-jsonlite::read_json(file.path(dirname(analysis_path),"run.json"),simplifyVector=TRUE)
cluster_column<-workflow_receipt$cluster_column
stopifnot(is.character(cluster_column),length(cluster_column)==1L)
stopifnot(cluster_column %in% names(analysis[[]]))
clusters<-stats::setNames(as.character(analysis[[]][[cluster_column]]),colnames(analysis))
raw_dir<-file.path(out,"raw-source");dir.create(raw_dir);untar(raw_archive,exdir=raw_dir)
matrices<-list.files(raw_dir,pattern="^matrix[.]mtx([.]gz)?$",recursive=TRUE,full.names=TRUE)
stopifnot(length(matrices)==1L)
raw<-getFromNamespace(".sc_ui_tenx_read","scAgentKit")(dirname(matrices),"name")$counts
counts<-getFromNamespace(".sc_project_layer","scAgentKit")(x,"RNA","counts",raw_counts=TRUE)
stopifnot(setequal(rownames(counts),rownames(raw)),all(colnames(counts) %in% colnames(raw)))
before<-digest::digest(x,algo="sha256")
results<-lapply(c("SoupX","decontX"),function(method) {
 t<-proc.time()
 tryCatch({
  result<-sc_run_ambient_correction(x,method=method,
   capture=list(id="PBMC3k",source="Official matched complete 10x pbmc3k raw/filtered capture; 2700 called cells",complete=TRUE),
   clusters=clusters,raw_counts=raw,seed=42L,round_counts=FALSE,output_dir=file.path(out,method))
  stopifnot(identical(before,digest::digest(x,algo="sha256")),identical(dimnames(result$corrected_counts),dimnames(counts)))
  panels<-getFromNamespace(".sc_run_classic_panels","scAgentKit")("blood")
  summary<-do.call(rbind,lapply(names(panels),function(panel) {
   genes<-intersect(panels[[panel]],rownames(counts))
   do.call(rbind,lapply(genes,function(gene) data.frame(panel=panel,gene=gene,
    before_umi=sum(counts[gene,]),after_umi=sum(result$corrected_counts[gene,]),
    before_detected=sum(counts[gene,]>0),after_detected=sum(result$corrected_counts[gene,]>0))))
  }))
  write.csv(summary,file.path(out,method,"expression-comparison.csv"),row.names=FALSE)
  corrected<-Seurat::CreateSeuratObject(result$corrected_counts,min.cells=0,min.features=0,meta.data=x[[]])
  corrected<-Seurat::NormalizeData(corrected,normalization.method="LogNormalize",scale.factor=10000,verbose=FALSE)
  saveRDS(corrected,file.path(out,method,"normalized-corrected.rds"),version=2L)
  list(method=method,status="completed",elapsed=unname((proc.time()-t)[["elapsed"]]),cells=ncol(counts),
   input_unchanged=TRUE,corrected_input_automatically_adopted=FALSE,original_input_sha256=digest::digest(file=input_path,algo="sha256"),
   raw_archive_sha256=digest::digest(file=raw_archive,algo="sha256"),biological_accuracy=NULL,
   interpretation="Native method acceptance and descriptive expression/UMI comparison only; no contamination truth or improved annotation accuracy is established.")
 },error=function(e)list(method=method,status="failed",elapsed=unname((proc.time()-t)[["elapsed"]]),error=conditionMessage(e)))
})
jsonlite::write_json(results,file.path(out,"run.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
stopifnot(identical(before,digest::digest(x,algo="sha256")))
if(any(vapply(results,function(r)r$status!="completed",logical(1))))quit(status=1L)
