args<-commandArgs(TRUE)
suppressPackageStartupMessages(library(scAgentKit))
root<-args[1];dir.create(root,recursive=TRUE)
ns<-asNamespace("scAgentKit"); pids<-integer()
on.exit_cleanup<-function(){for(pid in unique(pids))try(tools::pskill(pid),silent=TRUE)}
main<-function(){
 on.exit(on.exit_cleanup(),add=TRUE)
 fixture<-function(path) {
  dir.create(path)
  set.seed(5);counts<-Matrix::Matrix(matrix(rpois(80*30,3),80),sparse=TRUE)
  # Duplicate/invalid gene symbols and one different modality are intentional.
  genes<-c("MT-ND1","G","G","Gene_A",paste0("G",5:80))
  features<-data.frame(id=c(paste0("ID",1:80),"ADT1"),name=c(genes,"G"),type=c(rep("Gene Expression",80),"Antibody Capture"))
  Matrix::writeMM(rbind(counts,rep(2,30)),file.path(path,"matrix.mtx"))
  utils::write.table(features,file.path(path,"features.tsv"),sep="\t",quote=FALSE,row.names=FALSE,col.names=FALSE)
  writeLines(paste0("BC",1:30,"-1"),file.path(path,"barcodes.tsv"))
 }
 a<-file.path(root,"a");b<-file.path(root,"b");fixture(a);fixture(b)
 sources<-c(list.files(a,full.names=TRUE),list.files(b,full.names=TRUE))
 hash<-function(paths)vapply(paths,get(".sc_project_sha_file",ns),character(1))
 before<-hash(sources)
 context<-list(species="human",tissue="Synthetic",research_goal="Offline import entry verification")
 single<-file.path(root,"single")
 one<-sc_start(a,single,context,sample_id="S1",matrix_kind="filtered",browse=FALSE);pids<<-c(pids,one$pid)
 two<-sc_start(a,single,sample_id="S1",matrix_kind="filtered",browse=FALSE)
 stopifnot(isTRUE(two$reused),identical(one$pid,two$pid))
 saved<-get(".sc_run_load",ns)(single);stopifnot(!file.exists(saved$source$path))
 samples<-data.frame(sample_id=c("S1","S2"),path=c(a,b),matrix_kind=c("filtered","raw"),donor=c("D1","D2"),condition=c("C","T"))
 cells<-data.frame(sample_id=rep(samples$sample_id,each=30),barcode=rep(paste0("BC",1:30,"-1"),2),preparation=as.character(1:60))
 cells<-cells[60:1,]
 multi<-file.path(root,"multi")
 three<-sc_start(samples,multi,context,cell_metadata=cells,browse=FALSE);pids<<-c(pids,three$pid)
 four<-sc_start(samples,multi,cell_metadata=cells,browse=FALSE)
 stopifnot(isTRUE(four$reused),identical(three$pid,four$pid))
 st<-get(".sc_run_load",ns)(multi);obj<-get(".sc_run_get",ns)(multi,st,"input")
 stopifnot(identical(unname(obj$preparation),as.character(1:60)),!anyDuplicated(colnames(obj)),
  identical(unname(obj$donor),rep(c("D1","D2"),each=30)),
  identical(st$config$context$columns$condition,"condition"),
  obj@misc$scagentkit_tenx_import$cell_metadata$reordered_by_key,
  identical(hash(sources),before))
 original<-hash(file.path(multi,"state.rds"))
 bad<-try(sc_start(samples,multi,cell_metadata=cells[-1,],browse=FALSE),silent=TRUE)
 stopifnot(inherits(bad,"try-error"),grepl("every imported",as.character(bad)),identical(hash(file.path(multi,"state.rds")),original))
 changed<-cells;changed$preparation[1]<-"different"
 bad<-try(sc_start(samples,multi,cell_metadata=changed,browse=FALSE),silent=TRUE)
 stopifnot(inherits(bad,"try-error"),identical(hash(file.path(multi,"state.rds")),original))
 # Ordinary RDS inputs still require the exact original source path.
 input<-file.path(root,"original.rds");copy<-file.path(root,"same-bytes-other-path.rds")
 saveRDS(obj,input);file.copy(input,copy)
 project<-file.path(root,"rds")
 five<-sc_start(input,project,context=list(species="human",tissue="Synthetic",research_goal="RDS binding regression"),browse=FALSE);pids<<-c(pids,five$pid)
 bad<-try(sc_start(copy,project,browse=FALSE),silent=TRUE)
 stopifnot(inherits(bad,"try-error"),grepl("different original RDS binding",as.character(bad)))
 cat("PASS native 10x entry: direct single and multi-sample, shuffled metadata, protected reopen, changed metadata refusal, original RDS exact path preserved; no provider calls\n")
}
main()
