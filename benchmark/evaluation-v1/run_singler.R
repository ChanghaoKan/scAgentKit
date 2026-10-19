# Fixed external comparator; reads counts-derived normalized expression, not truth.
a<-commandArgs(TRUE);stopifnot(length(a)==3L)
input<-normalizePath(a[1]);reference<-normalizePath(a[2]);out<-a[3]
stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
library(SeuratObject);library(SummarizedExperiment);library(SingleR)
x<-readRDS(input);ref<-readRDS(reference)
mat<-LayerData(x,assay="RNA",layer="data");stopifnot(ncol(mat)>0L,!anyDuplicated(rownames(mat)))
genes<-intersect(rownames(mat),rownames(ref));stopifnot(length(genes)>=100L)
t<-proc.time()
pred<-SingleR(test=mat[genes,,drop=FALSE],ref=ref[genes,],labels=ref$label.main,
 de.method="classic",prune=TRUE,num.threads=1L)
saveRDS(pred,file.path(out,"prediction.rds"),version=2L)
stopifnot(identical(rownames(pred),colnames(mat)))
write.csv(data.frame(cell_id=rownames(pred),raw_label=as.character(pred$labels),
 label=ifelse(is.na(pred$pruned.labels),"Unknown",as.character(pred$pruned.labels)),
 status=ifelse(is.na(pred$pruned.labels),"unknown","reference_prediction")),file.path(out,"predictions.csv"),row.names=FALSE)
jsonlite::write_json(list(method="SingleR",version=as.character(packageVersion("SingleR")),reference_sha256=digest::digest(file=reference,algo="sha256"),
 input_sha256=digest::digest(file=input,algo="sha256"),common_genes=length(genes),cells=ncol(mat),pruned_unknown=sum(is.na(pred$pruned.labels)),
 elapsed=unname((proc.time()-t)[["elapsed"]]),num_threads=1L,de_method="classic",prune=TRUE,query_truth_used=FALSE,
 interpretation="Independent public reference classifier; reference predictions are not biological truth. No tutorial labels or model API.",
 provider_calls=0L,model_cost_usd=0),file.path(out,"run.json"),auto_unbox=TRUE,pretty=TRUE)
