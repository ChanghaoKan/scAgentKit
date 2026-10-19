# Inspect the annotation worksheet of the same reviewed project.
# Edit labels/confidence/reasons/markers, then sc_review(snapshot,"revise",annotations=...).
annotation_example <- function(project_dir) {
  snapshot<-scAgentKit::sc_review(scAgentKit::sc_open(project_dir))
  if(!identical(snapshot$view$stage,"annotation_propose"))
    stop("Complete the pending scientific review before preparing annotation.",call.=FALSE)
  snapshot
}
