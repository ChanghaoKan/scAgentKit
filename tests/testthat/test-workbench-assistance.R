test_that("worksheet facts are local exact-cluster projections with unchanged authority/model summary", {
  data("pbmc_small",package="SeuratObject",envir=environment())
  pbmc_small$seurat_clusters <- as.character(SeuratObject::Idents(pbmc_small))
  reference <- data.frame(cell_type="Synthetic coarse candidate",marker=rownames(pbmc_small),species="human",tissue="software fixture")
  root <- tempfile()
  suppressWarnings(sc_run(pbmc_small,root,start_stage="processed",processed_reason="Public software fixture only",
    context=list(species="human",tissue="software fixture"),reference=reference,provider=NULL))
  view <- sc_run_inspect(root);before <- .sc_project_sha_file(file.path(root,"state.rds"))
  state <- .sc_run_load(root);evidence <- .sc_run_get(root,state,"annotation_evidence")
  projected <- .sc_ui_annotation_assistance(root,view)
  expect_identical(.sc_project_sha_file(file.path(root,"state.rds")),before)
  expect_identical(.sc_run_get(root,state,"annotation_evidence")$summary,evidence$summary)
  expect_null(evidence$summary$reference_candidates)
  for (cluster in projected$annotation_preparation$clusters) {
    expect_identical(cluster$assistance$clusterId,cluster$clusterId)
    expect_true(all(vapply(cluster$assistance$reference$candidates,function(x)identical(x$clusterId,cluster$clusterId),logical(1))))
    expect_null(cluster$label)
    expect_null(cluster$assistance$provenance$source_path)
  }
  expect_true(any(vapply(projected$annotation_preparation$clusters,function(x)length(x$assistance$reference$candidates)>0L,logical(1))))
  stale <- view;stale$annotation_preparation$expected_revision <- view$revision+1
  expect_error(.sc_ui_annotation_assistance(root,stale),"stale")
  other <- view;other$project_id <- "foreign"
  expect_error(.sc_ui_annotation_assistance(root,other),"stale")
})
