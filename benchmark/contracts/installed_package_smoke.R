# Install a built archive in a NEW library first; run outside its source tree.
# All fixture data are synthetic, and scientific approvals stay explicit.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value=TRUE)))
http_helper <- file.path(dirname(script), "installed_continue.py")
stopifnot(file.exists(http_helper))
private_library <- normalizePath(args[[1L]], mustWork=TRUE)
receipt <- file.path(normalizePath(dirname(args[[2L]]), mustWork=TRUE), basename(args[[2L]]))
.libPaths(c(private_library, .libPaths()))
options(scAgentKit.checkout=NULL)
suppressPackageStartupMessages(library(scAgentKit))
package <- normalizePath(find.package("scAgentKit"))
stopifnot(identical(dirname(package), private_library))
runtime <- normalizePath(system.file("workbench", package="scAgentKit"))
stopifnot(identical(dirname(runtime), package))
getFromNamespace(".sc_start_runtime_check", "scAgentKit")(runtime)
local({
  root <- tempfile("installed-runtime-contract-"); dir.create(root)
  old <- setwd(root); pids <- integer()
  on.exit({for(pid in pids) try(tools::pskill(as.integer(pid), signal=15L),silent=TRUE)
    setwd(old); unlink(root,recursive=TRUE)}, add=TRUE)
  stopifnot(!dir.exists("R"), !dir.exists("inst"), !dir.exists("workbench"))
  set.seed(17)
  counts <- matrix(rpois(300L*60L,1.5),300L,60L)
  for (i in 1:3) counts[(i-1L)*15L+seq_len(15L),(i-1L)*20L+seq_len(20L)] <-
    counts[(i-1L)*15L+seq_len(15L),(i-1L)*20L+seq_len(20L)]+8L
  dimnames(counts) <- list(paste0("G",seq_len(300L)),paste0("C",seq_len(60L)))
  object <- Seurat::CreateSeuratObject(Matrix::Matrix(counts,sparse=TRUE))
  saveRDS(object,"a.rds")
  context <- list(species="human", tissue="Synthetic fixture",
    research_goal="Check installed archive, explicit approvals and background execution")
  first <- sc_start("a.rds","rds-project",context=context,browse=FALSE)
  pids <- c(pids,first$pid)
  initial <- sc_run_inspect("rds-project")
  stopifnot(identical(initial$status,"awaiting_review"))
  before <- tools::md5sum("rds-project/state.rds")
  again <- sc_start("a.rds","rds-project",browse=FALSE)
  stopifnot(again$reused,identical(first$pid,again$pid),
    identical(before,tools::md5sum("rds-project/state.rds")))
  # Two MEX sources share literal barcodes; only explicit sample prefixes differ.
  for(i in 1:2) {
    directory <- paste0("sample",i);dir.create(directory)
    cols <- (i-1L)*30L+seq_len(30L)
    Matrix::writeMM(Matrix::Matrix(counts[,cols],sparse=TRUE),file.path(directory,"matrix.mtx"))
    utils::write.table(data.frame(id=paste0("ID",seq_len(300L)),name=rownames(counts),type="Gene Expression"),
      file.path(directory,"features.tsv"),sep="\t",quote=FALSE,row.names=FALSE,col.names=FALSE)
    writeLines(paste0("BC",seq_len(30L),"-1"),file.path(directory,"barcodes.tsv"))
  }
  samples <- data.frame(sample_id=c("S1","S2"),path=c("sample1","sample2"),
    matrix_kind=c("filtered","raw"),donor=c("D1","D2"),condition=c("control","treated"))
  metadata <- data.frame(sample_id=rep(samples$sample_id,each=30L),
    barcode=rep(paste0("BC",seq_len(30L),"-1"),2),measurement=as.character(seq_len(60L)))
  metadata <- metadata[60:1,]
  service <- sc_start(samples,"table-project",context=context,cell_metadata=metadata,browse=FALSE)
  pids <- c(pids,service$pid)
  shown <- sc_review(sc_open("table-project"))
  draft <- sc_review(shown,"revise",plan=list(analysis=list(nfeatures=80,npcs=5),pcs=5,umap=TRUE),
    reviewer="installed software control",reason="Fixed synthetic strategy; no biological conclusions")
  ready <- sc_review(draft,"approve",reviewer="installed software control",
    reason="Reviewed complete synthetic strategy before execution")
  stopifnot(ready$view$status=="ready")
  background <- function(stage) {
    output <- tempfile(fileext=".json")
    status <- system2(Sys.which("python3"),c(shQuote(http_helper),shQuote(service$url),shQuote(stage),shQuote(output)),stdout=TRUE,stderr=TRUE)
    if(!is.null(attr(status,"status")) && attr(status,"status")!=0L)
      stop(paste("Installed background worker failed:",paste(status,collapse="\n")),call.=FALSE)
    jsonlite::fromJSON(output,simplifyVector=FALSE)
  }
  analysis_job <- background("strategy_propose")
  measured <- sc_review(sc_open("table-project"))
  scan <- measured$view$strategy_review$details$cluster_diagnostics
  stopifnot(measured$view$status=="awaiting_review",!is.null(scan),
    identical(scan$schema,"scagentkit.cluster-scan.v1"),length(scan$resolutions)>1L,
    measured$plan$clustering$resolution %in% scan$resolutions)
  # A measured scan is a distinct scientific decision, never an automatic pass.
  selected <- sc_review(measured,"approve",reviewer="installed software control",
    reason="Reviewed actual fixed synthetic scan; retain the explicit measured resolution")
  stopifnot(selected$view$status=="ready")
  annotation_job <- background("annotation_propose")
  annotation <- sc_review(sc_open("table-project"))
  stopifnot(annotation$view$status=="awaiting_configuration")
  labels <- annotation$annotations
  labels$label <- "Unknown"; labels$confidence <- "low"
  labels$rationale <- "Synthetic software control; identity unresolved"; labels$markers <- ""
  proposal <- sc_review(annotation,"revise",annotations=labels,reviewer="installed software control",
    reason="Explicit unresolved labels for every supplied cluster")
  stopifnot(proposal$view$status=="awaiting_review",is.null(proposal$view$output))
  approved <- sc_review(proposal,"approve",reviewer="installed software control",
    reason="Reviewed complete annotation proposal before application")
  stopifnot(approved$view$status=="ready")
  final_job <- background("complete")
  result <- sc_result("table-project")
  expected <- paste(rep(c("S1","S2"),each=30L),rep(paste0("BC",seq_len(30L),"-1"),2),sep="::")
  stopifnot(identical(colnames(result),expected),all(result$sc_annotation=="Unknown"),
    identical(unname(result$measurement),as.character(seq_len(60L))),
    identical(unname(result$donor),rep(c("D1","D2"),each=30L)),"umap"%in%names(result@reductions))
  saved_counts <- SeuratObject::LayerData(result[["RNA"]],layer="counts")
  stopifnot(inherits(saved_counts,"sparseMatrix"),isTRUE(all.equal(unname(as.matrix(saved_counts)),unname(counts))))
  state_hash <- tools::md5sum("table-project/state.rds")
  complete <- sc_start(samples,"table-project",cell_metadata=metadata,browse=FALSE)
  stopifnot(complete$reused,identical(complete$pid,service$pid))
  # Restart the installed service after completion, without recomputing authority.
  tools::pskill(as.integer(service$pid),signal=15L);pids <- setdiff(pids,service$pid)
  restarted <- sc_start(samples,"table-project",cell_metadata=metadata,browse=FALSE)
  pids <- c(pids,restarted$pid)
  stopifnot(!restarted$reused,restarted$pid!=service$pid,
    identical(state_hash,tools::md5sum("table-project/state.rds")))
  service <- restarted
  view <- background("result")
  stopifnot(view$run_status=="complete",isTRUE(view$evidence_complete))
  single <- sc_start("sample1","single-project",context=context,
    sample_id="S1",matrix_kind="filtered",browse=FALSE)
  pids <- c(pids,single$pid)
  stopifnot(sc_run_inspect("single-project")$status=="awaiting_review")
  jsonlite::write_json(list(status="passed",role="installed archive source-independent complete synthetic workflow",
    completed_analysis=TRUE,source_checkout_argument=FALSE,runtime=runtime,
    source_commit=Sys.getenv("SCAGENTKIT_SOURCE_SHA",unset=NA_character_),
    source_archive_sha256=Sys.getenv("SCAGENTKIT_ARCHIVE_SHA256",unset=NA_character_),
    working_directory_role="fresh temporary directory outside source checkout",
    input_entries=c("RDS","single 10x MEX","multi-sample 10x table with shuffled cell metadata"),
    rds_initial_status=initial$status,rds_service_reused=again$reused,
    background_jobs=list(analysis_job,annotation_job,final_job),scientific_approvals=3L,
    complete_service_reused=complete$reused,complete_service_restarted=!restarted$reused,
    result_http_status=view$run_status,result_evidence_complete=view$evidence_complete,
    cells=ncol(result),features=nrow(result),provider_calls=0L,
    actual_browser=FALSE,dependency_libraries=.libPaths(),R=R.version.string,
    platform=R.version$platform,Python=unname(Sys.which("python3")),
    package_version=as.character(packageVersion("scAgentKit")),
    session_info=capture.output(sessionInfo())),receipt,auto_unbox=TRUE,pretty=TRUE)
})
