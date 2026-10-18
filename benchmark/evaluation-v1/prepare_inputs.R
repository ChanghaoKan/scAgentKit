# Provision only. No predictions or parameter tuning; input labels stay separate.
a <- commandArgs(TRUE); stopifnot(length(a)==3L)
.libPaths(c(a[3],.libPaths()))
source <- normalizePath(a[1]); out <- a[2]
stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
library(Seurat);library(Matrix);library(scAgentKit)
sha <- function(p) digest::digest(file=p,algo="sha256")
select_ids <- function(ids,accession) {
  h <- vapply(ids,function(id) digest::digest(paste0("evaluation-v1|",accession,"|",id),algo="sha256",serialize=FALSE),character(1))
  if(length(ids)>5000L) ids[order(h,ids,method="radix")][seq_len(5000L)] else ids
}
write_input <- function(counts,metadata,name,source_receipt) {
  stopifnot(inherits(counts,"sparseMatrix"),identical(colnames(counts),rownames(metadata)),!anyDuplicated(rownames(counts)),!anyDuplicated(colnames(counts)))
  original_features <- rownames(counts)
  keys <- original_features; invalid <- grepl("[_|]",keys)
  keys[invalid] <- paste0("feature-",vapply(original_features[invalid],function(key) substr(digest::digest(key,algo="sha256",serialize=FALSE),1,16),character(1)))
  stopifnot(!anyDuplicated(keys));rownames(counts)<-keys
  x <- CreateSeuratObject(counts,min.cells=0,min.features=0,meta.data=metadata)
  x[["RNA"]] <- SeuratObject::AddMetaData(x[["RNA"]],data.frame(feature_name=original_features,analysis_key=keys,row.names=keys))

  stopifnot(identical(dimnames(counts),dimnames(x)))
  dir.create(file.path(out,name)); path<-file.path(out,name,"input.rds");saveRDS(x,path,version=2L)
  jsonlite::write_json(c(list(dataset=name,source=source_receipt,input_sha256=sha(path),cells=ncol(x),genes=nrow(x),
    analysis_metadata=names(metadata),truth_in_analysis=FALSE,raw_counts_hash=digest::digest(counts,algo="sha256")),list()),
    file.path(out,name,"manifest.json"),auto_unbox=TRUE,pretty=TRUE)
}
# Same verified 10x bytes and one declared sample. No tutorial labels are read.
dir.create(file.path(out,"pbmc-files"));untar(file.path(source,"pbmc3k-filtered.tar.gz"),exdir=file.path(out,"pbmc-files"))
mex <- getFromNamespace(".sc_ui_tenx_read","scAgentKit")(file.path(out,"pbmc-files","filtered_gene_bc_matrices","hg19"),"name")
counts <- mex$counts
write.csv(mex$features,file.path(out,"pbmc-feature-map.csv"),row.names=FALSE)
stopifnot(ncol(counts)==2700L)
write_input(counts,data.frame(sample_id=rep("PBMC3k",ncol(counts)),row.names=colnames(counts)),"pbmc3k",list(url="official 10x filtered hg19",sha256=sha(file.path(source,"pbmc3k-filtered.tar.gz"))))
# The distributed IFNB labels are evaluation-only, not independently verified truth.
dir.create(file.path(out,"ifnb-files"));untar(file.path(source,"ifnb.SeuratData_3.0.0.tar.gz"),exdir=file.path(out,"ifnb-files"))
files <- list.files(file.path(out,"ifnb-files"),pattern="[.](rda|RData)$",full.names=TRUE,recursive=TRUE)
stopifnot(length(files)==1L); e<-new.env();load(files[1],envir=e)
original <- e[[ls(e)[1]]]
counts <- if("counts" %in% methods::slotNames(original@assays[["RNA"]])) methods::slot(original@assays[["RNA"]],"counts") else SeuratObject::LayerData(original,assay="RNA",layer="counts")
ids <- select_ids(colnames(counts),"ifnb");writeLines(ids,file.path(out,"ifnb-selected-cells.txt"))
stopifnot("stim" %in% names(original[[]]),"seurat_annotations" %in% names(original[[]]))
metadata <- data.frame(condition=as.character(original[[]][ids,"stim"]),row.names=ids)
write_input(counts[,ids,drop=FALSE],metadata,"ifnb",list(url="official SeuratData ifnb3.0.0",sha256=sha(file.path(source,"ifnb.SeuratData_3.0.0.tar.gz")),sample_mapping="not_available; condition is not donor or sample"))
write.csv(data.frame(cell_id=ids,label=as.character(original[[]][ids,"seurat_annotations"]),status="distributed_author_label"),file.path(out,"ifnb","truth.csv"),row.names=FALSE)
cat("Prepared PBMC3k and IFNB counts; labels excluded from analysis objects.\n")

# Independently prepared sparse Baron matrix; author labels stay in truth.csv.
baron <- file.path(dirname(source),"baron-prepared")
counts <- as(Matrix::readMM(file.path(baron,"matrix.mtx")),"dgCMatrix")
dimnames(counts)<-list(readLines(file.path(baron,"genes.txt")),readLines(file.path(baron,"barcodes.txt")))
metadata<-read.csv(file.path(baron,"metadata.csv"),stringsAsFactors=FALSE,check.names=FALSE)
metadata<-metadata[match(colnames(counts),metadata$cell_id),,drop=FALSE];rownames(metadata)<-metadata$cell_id;metadata$cell_id<-NULL
write_input(counts,metadata,"baron",list(source="Four explicit GEO accessions GSM2230757..GSM2230760",sha256=sha(file.path(baron,"matrix.mtx")),selection_sha256=sha(file.path(baron,"selected-cells.json"))))
file.copy(file.path(baron,"truth.csv"),file.path(out,"baron","truth.csv"))
