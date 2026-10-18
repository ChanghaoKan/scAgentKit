# Bound execution/review intervals from sealed coordinator events. These are
# wall-time API segments, not pure kernel costs or measured human effort.
a<-commandArgs(TRUE);stopifnot(length(a)==2L)
envelope<-readRDS(file.path(a[1],"project","state.rds"))
stopifnot(identical(envelope$schema,"scagentkit.run-state.v1"),
 identical(envelope$hash,digest::digest(envelope$state,algo="sha256",serializeVersion=2L)))
s<-envelope$state
when<-function(x)as.POSIXct(x,format="%Y-%m-%dT%H:%M:%OSZ",tz="UTC")
events<-s$history
selected<-function(action,stage=NULL,kind=NULL)Filter(function(x)identical(x$action,action)&&
 (is.null(stage)||identical(x$details$stage,stage))&&(is.null(kind)||identical(x$details$kind,kind)),events)
strategy<-selected("approved",kind="strategy");annotation<-selected("approved",kind="annotation")
end<-function(x)if(length(x))tail(x,1)[[1]]$created_at else NULL
start<-function(x)if(length(x))x[[1]]$created_at else NULL
interval<-function(label,first,last,scope)list(name=label,start=first,end=last,
 seconds=if(is.null(first)||is.null(last))NULL else as.numeric(difftime(when(last),when(first),units="secs")),scope=scope)
scan<-end(selected("resolution_scan_review_required"));evidence<-end(selected("executed",stage="annotation_evidence"))
segments<-list(
 interval("approved_foundation_to_measured_review",start(strategy),scan,"Approved computation plus integrity/artifact persistence/review publication; excludes subsequent printed review collection"),
 interval("measured_review_to_selection_approval",scan,if(length(strategy)>=2L)strategy[[2]]$created_at else NULL,"API review/integrity/rendering and automated policy; includes collector overhead, no human participant"),
 interval("selection_approval_to_annotation_evidence",if(length(strategy)>=2L)strategy[[2]]$created_at else NULL,evidence,"Marker/reference/expression work plus API integrity/persistence"),
 interval("annotation_evidence_to_approval",evidence,start(annotation),"API show/revise/validation/rendering and automated policy; includes collector overhead, not human effort"),
 interval("annotation_approval_to_finalization",start(annotation),end(selected("executed",stage="finalize")),"Approved label application/export plus integrity/persistence"))
jsonlite::write_json(list(project_status=s$status,stage=s$stage,implementation_hash=s$implementation_hash,
 authoritative_state_sha256=digest::digest(file=file.path(a[1],"project","state.rds"),algo="sha256"),
 segments=segments,warning="Timestamp-bounded wall-time segments are descriptive under concurrent local load. Review intervals include API validation and collector rendering; do not equate them with pure logging time, algorithm cost or human time saved."),a[2],auto_unbox=TRUE,pretty=TRUE,null="null")
