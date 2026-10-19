# Preregistered counts-only workflow; evaluator labels are never read here.
a<-commandArgs(TRUE);stopifnot(length(a)==6L)
input_path<-normalizePath(a[1]);root<-a[2];lib<-normalizePath(a[3]);variant<-a[4]
reference_path<-normalizePath(a[5]);dataset<-a[6]
stopifnot(!dir.exists(root),variant %in% c("baseline","after","after-no-diagnostics","after-qc-or","after-sample-hvg"))
.libPaths(c(lib,.libPaths()));library(scAgentKit)
stopifnot(identical(normalizePath(find.package("scAgentKit")),file.path(lib,"scAgentKit")))
dir.create(root,recursive=TRUE);root<-normalizePath(root);project<-file.path(root,"project")
started<-proc.time();started_utc<-format(Sys.time(),tz="UTC",usetz=TRUE)
message("START ",dataset," / ",variant," / ",started_utc)
input<-readRDS(input_path);metadata<-input[[]]
context<-list(species="human",tissue=if(dataset=="baron") "Pancreas" else "Blood",
 research_goal="Frozen public offline development comparison; Unknown reviewed labels; no truth claim",columns=list())
if("sample_id" %in% names(metadata))context$columns$sample<-"sample_id"
if("condition" %in% names(metadata))context$columns$condition<-"condition"
if(!length(context$columns))context$columns<-NULL
plan<-list(rationale="Preregistered fixed comparison, not outcome optimization",
 analysis=list(normalization_method="LogNormalize",scale_factor=10000,nfeatures=2000L,npcs=50L,seed=42L),
 pcs=list(method="computed_top50",threshold=.8),resolution=.6,diagnostic_resolutions=c(.2,.4,.8,1,1.2),umap=FALSE)
if(variant=="after-qc-or")plan$qc_preset<-"any_quality3"
if(variant=="after-sample-hvg") {
 if(!"sample_id" %in% names(metadata) || length(unique(metadata$sample_id))<2L || any(table(metadata$sample_id)<30L))stop("Sample-HVG ablation is ineligible")
 plan$analysis$hvg_method<-"sample_consensus";plan$analysis$hvg_column<-"sample_id"
}
extra<-list()
if(variant %in% c("after","after-qc-or","after-sample-hvg"))extra$scientific_review<-list(pc_sensitivity=TRUE,resampling=TRUE,
 resolution_extension=TRUE,panels=if(dataset=="baron") "pancreas" else "blood",cross_sample=TRUE,mixed_lineage=TRUE)
x<-do.call(sc_analyze,c(list(input=input_path,project_dir=project,context=context,plan=plan,provider=NULL,budget=0,reference=reference_path),extra))
message("Initial review prepared")
review_logs<-list();review_sequence<-0L
logged_review<-function(label,fn) {
 review_sequence<<-review_sequence+1L;sequence<-review_sequence
 path<-file.path(root,sprintf("review-%02d-%s.txt",sequence,label))
 connection<-file(path,open="wt");depth<-sink.number();operation_started<-proc.time()
 sink(connection)
 on.exit({
  while(sink.number()>depth)sink()
  close(connection)
  time<-proc.time()-operation_started
  review_logs[[length(review_logs)+1L]]<<-list(sequence=sequence,operation=label,
   elapsed=unname(time[["elapsed"]]),user=unname(time[["user.self"]]),system=unname(time[["sys.self"]]),
   output_file=basename(path),output_bytes=unname(file.info(path)$size),
   timing_scope="Public review API including integrity checks, optional continuation and complete rendering to a file; not isolated numerical kernel time")
  jsonlite::write_json(review_logs,file.path(root,"review-operation-timings.json"),auto_unbox=TRUE,pretty=TRUE)
 },add=TRUE)
 fn()
}
review<-function(x)logged_review("show",function()sc_review(x))
approve<-function(x,reason){
 displayed<-review(x)
 logged_review("approve",function()sc_review(displayed,"approve",reviewer="Preregistered offline policy",reason=reason,continue=TRUE))
}
x<-approve(x,"Execute fixed counts-only software comparison; no provider or inferred truth")
message("Foundation and measured scan returned: ",x$view$stage)
if(identical(x$view$stage,"strategy_propose")) {
 scan<-x$view$strategy_review$details$cluster_diagnostics
 stopifnot(!is.null(scan),.6 %in% scan$resolutions)
 x<-approve(x,"Review actual measured grid; retain predeclared resolution0.6")
 message("Measured selection explicitly approved: ",x$view$stage)
}
stopifnot(identical(x$view$stage,"annotation_propose"))
x<-review(x);labels<-x$annotations
labels$label<-"Unknown";labels$confidence<-"low";labels$rationale<-"No human or model identity review; explicit abstention control";labels$markers<-""
p<-logged_review("revise",function()sc_review(x,"revise",annotations=labels,reviewer="Offline policy",reason="Explicit abstention for every cluster"))
done<-approve(p,"Approve only complete Unknown control labels")
message("Final explicit annotation approval returned: ",done$view$status)
stopifnot(identical(done$view$status,"complete"))
result<-sc_result(project);saveRDS(result,file.path(root,"analysis.rds"),version=2L)
ns<-asNamespace("scAgentKit");state<-get(".sc_run_load",ns)(project)
get_artifact<-function(name)if(is.null(state$files[[name]]))NULL else get(".sc_run_get",ns)(project,state,name)
markers<-get_artifact("markers");evidence<-get_artifact("annotation_evidence");scan<-get_artifact("cluster_scan")
write.csv(markers$marker_summary,file.path(root,"marker-summary.csv"),row.names=FALSE)
saveRDS(list(markers=markers,evidence=evidence,scan=scan,assessment=done$view$scientific_assessment),file.path(root,"evidence.rds"),version=2L)
membership<-as.character(result[[]][[state$config$cluster_column]])
write.csv(data.frame(cell_id=colnames(result),cluster=membership,reviewed_label=as.character(result$sc_annotation)),file.path(root,"membership.csv"),row.names=FALSE)
all<-evidence$private$candidates_all
candidate<-lapply(seq_len(ncol(result)),function(i){
 rows<-all[as.character(all$cluster)==membership[i] & all$overlap_count>0,,drop=FALSE]
 if(nrow(rows))rows<-rows[order(-rows$score,-rows$overlap_count,rows$cell_type,method="radix"),,drop=FALSE]
 data.frame(cell_id=colnames(result)[i],label=if(nrow(rows))rows$cell_type[1] else "Unknown",status="candidate_only_not_reviewed",
 tied=if(nrow(rows))sum(rows$score==rows$score[1])>1L else FALSE)
})
write.csv(do.call(rbind,candidate),file.path(root,"reference-candidates.csv"),row.names=FALSE)
jsonlite::write_json(list(status="complete",variant=variant,dataset=dataset,started_utc=started_utc,
 elapsed=unname((proc.time()-started)[["elapsed"]]),user=unname((proc.time()-started)[["user.self"]]),system=unname((proc.time()-started)[["sys.self"]]),
 input_sha256=digest::digest(file=input_path,algo="sha256"),input_cells=ncol(input),retained_cells=ncol(result),unknown_reviewed=ncol(result),source_library=lib,
 package_version=as.character(packageVersion("scAgentKit")),R=R.version.string,cluster_count=length(unique(membership)),cluster_column=state$config$cluster_column,
 implementation_hash=state$implementation_hash,runtime_manifest_sha256=digest::digest(file=system.file("workbench","runtime-manifest.json",package="scAgentKit"),algo="sha256"),
 logging_policy="Complete public review rendering to separate file-backed sinks; no growing capture.output text vector",
 timing_comparability="Do not directly compare total wall time against original PBMC baseline/after attempts using in-memory capture.output; operation timings include API checks, continuation and rendering",
 counts_hash=get(".sc_project_sparse_hash",ns)(SeuratObject::LayerData(result,assay="RNA",layer="counts")),reference_sha256=digest::digest(file=reference_path,algo="sha256"),
 provider_calls=0L,model_cost_usd=0,human_time_seconds=NULL,human_time_saved=NULL,biological_accuracy=NULL,
 accuracy_reason="No independent truth; author-label and shared-reference agreement scored separately",
 science_status=if(is.null(scan$scientific_diagnostics))"not_enabled" else "recorded; inspect per-method status",approvals=length(state$approvals),
 dependency_versions=as.list(vapply(c("Seurat","SeuratObject","Matrix","digest"),function(p)as.character(packageVersion(p)),character(1)))),
 file.path(root,"run.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
