# Reference comparison is a descriptive name/marker check. A guided follow-up
# is a separate bounded request; neither agreement nor a model grants approval.
.sc_run_annotation_candidate_comparison <- function(candidate,evidence,options) {
  if(is.null(candidate)||is.null(evidence$private$reference_evidence))return(list())
  options<-.sc_run_reference_options(options)
  lapply(candidate$annotations,function(row) {
    supplied<-Filter(function(x)identical(x$clusterId,row$clusterId),evidence$summary$clusters)[[1L]]
    joint<-.sc_run_joint_evidence(row,supplied,evidence$private$reference_evidence,
      list(kind="provider_response",reference_dependency="independent"),options=options)
    c(list(clusterId=row$clusterId),joint$comparison)
  })
}
.sc_run_annotation_guidance <- function(root,state,evidence,summary) {
  guidance<-state$annotation_guidance
  if(is.null(guidance)||!identical(guidance$evidence,state$files$annotation_evidence))return(list(summary=summary,guidance=NULL))
  if(!identical(guidance$schema,"scagentkit.annotation-guidance.v1")||
      !identical(guidance$hash,.sc_run_hash(guidance[setdiff(names(guidance),"hash")]))||
      !identical(guidance$independent_suggestion,state$files$annotation_independent_suggestion))
    stop("Saved independent/guided annotation binding changed; inspect the protected evidence.",call.=FALSE)
  independent<-.sc_run_get(root,state,"annotation_independent_suggestion")
  summary$reference_mode<-"guided"
  summary$independent_candidate<-independent$candidate
  summary$reference_comparison<-guidance$comparison
  summary$reference_candidates<-lapply(evidence$private$reference_evidence$per_cluster,function(row)
    list(clusterId=row$clusterId,status=row$status,candidates=row$candidates))
  summary$reference_dependency<-paste("One optional guided recheck of the saved independent marker-only draft.",
    "Reference names are not ground truth. Keep justified independent labels or Unknown when evidence is weak; no forced agreement.")
  list(summary=summary,guidance=guidance)
}
.sc_run_annotation_guidance_prepare <- function(root,state,context,reviewer,reason) {
  saved<-state$suggestion
  current<-!is.null(saved)&&identical(saved$suggestion_hash,context$suggestion_hash)
  if(!is.null(state$annotation_guidance))stop("Only one guided annotation review may be staged for this project.",call.=FALSE)
  if(!identical(context$kind,"annotation")||!current||!identical(saved$status,"candidate")||
      !identical(saved$reference_mode,"independent"))
    stop("First request a complete independent marker-only annotation candidate.",call.=FALSE)
  comparison<-.sc_run_annotation_candidate_comparison(saved$candidate,context$evidence,state$config$reference_review)
  conflicts<-Filter(function(row)row$status%in%c("unresolved_label_difference","lineage_disagreement")||identical(row$reason,"best_label_tie"),comparison)
  if(!length(conflicts))stop("No saved reference label difference requires a guided review. Keep reviewing the independent draft.",call.=FALSE)
  state<-.sc_run_put(root,state,"annotation_independent_suggestion",saved)
  guidance<-list(schema="scagentkit.annotation-guidance.v1",evidence=state$files$annotation_evidence,
    independent_suggestion=state$files$annotation_independent_suggestion,comparison=comparison,
    reviewer=reviewer,reason=reason,maximum_guided_requests=1L)
  guidance$hash<-.sc_run_hash(guidance)
  state$annotation_guidance<-guidance
  .sc_run_event(state,"annotation_guided_review_prepared",list(guidance_hash=guidance$hash,
    independent_suggestion=guidance$independent_suggestion,maximum_guided_requests=1L,
    reviewer=reviewer,reason=reason,provider_dispatch="not_sent"))
}
