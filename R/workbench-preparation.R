# Local browser projection only: never add reference labels to the independent
# model summary or change the scientific execution fingerprint.
.sc_ui_annotation_assistance <- function(project_dir, view) {
  preparation <- view$annotation_preparation
  if (is.null(preparation)) return(view)
  root <- .sc_run_root(project_dir); state <- .sc_run_load(root)
  if (!identical(view$project_id,state$project_id) ||
      as.numeric(preparation$expected_revision) != as.numeric(state$revision) ||
      !identical(preparation$evidence_hash,state$files$annotation_evidence$sha256))
    stop("Annotation assistance has a stale evidence binding.",call.=FALSE)
  evidence <- .sc_run_get(root,state,"annotation_evidence")
  local <- evidence$private$reference_evidence
  provenance <- local$provenance
  # Paths, cell IDs and unrelated metadata are never needed by this worksheet.
  provenance <- provenance[intersect(names(provenance),c("status","mode","species","tissue_filter",
    "scope","license","source_md5","source_sha256","source_url","source_url_verified",
    "source_version","retrieved_at","source_file_status","scoring","n_scoped_rows"))]
  preparation$clusters <- lapply(preparation$clusters,function(cluster) {
    rows <- Filter(function(row)identical(row$clusterId,cluster$clusterId),local$per_cluster)
    if (length(rows)>1L) stop("Ambiguous annotation assistance cluster.",call.=FALSE)
    reference <- if (length(rows)) rows[[1]] else list(clusterId=cluster$clusterId,status="not_recorded",candidates=list())
    if (!identical(reference$clusterId,cluster$clusterId) ||
        any(vapply(reference$candidates,function(row)!identical(row$clusterId,cluster$clusterId),logical(1))))
      stop("Annotation reference evidence belongs to another cluster.",call.=FALSE)
    cluster$assistance <- list(schema="scagentkit.annotation-assistance.v1",clusterId=cluster$clusterId,
      reference=reference,provenance=provenance,
      boundary="Saved local reference facts only; candidates are not labels, probabilities or independent biological confirmation.")
    cluster
  })
  view$annotation_preparation <- preparation
  view
}
