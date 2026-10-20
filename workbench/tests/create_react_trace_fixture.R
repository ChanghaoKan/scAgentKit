suppressPackageStartupMessages(library(scAgentKit))
fn <- function(system_prompt,user_prompt) {
 e<-jsonlite::fromJSON(user_prompt,simplifyVector=FALSE)$evidence
 ids<-vapply(e$clusters,`[[`,"","clusterId")
 risks<-lapply(ids,function(id) {r<-scAgentKit:::.sc_run_react_risks(NULL,id,character(),legacy=TRUE);r$fields<-lapply(r$fields,function(f){f$source<-"model";f});r})
 jsonlite::toJSON(list(schema="scagentkit.annotation-draft.v1",proposal=list(schema="scagentkit.annotation.v1",annotations=lapply(ids,function(id)list(clusterId=id,label="Unknown",confidence="low",rationale="Mock browser acceptance",markers=list()))),risk_flags=risks),auto_unbox=TRUE,null="null")
}
data("pbmc_small", package="SeuratObject")
pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(pbmc_small))
project <- commandArgs(TRUE)[1]
if (dir.exists(project)) stop("Fresh project required")
x <- sc_run(pbmc_small, project, provider="mock", chat_fn=fn,
 context=list(species="human", tissue="blood", research_goal="Public software acceptance only"),
 start_stage="processed", processed_reason="Public PBMC fixture; no accuracy claim", react=list(mode="all"))
stopifnot(x$status=="awaiting_review")
