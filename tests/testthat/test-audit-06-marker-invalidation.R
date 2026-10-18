test_that("same-count membership changes invalidate marker-derived caches", {
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  old <- as.character(SeuratObject::Idents(obj@data))
  obj@data$seurat_clusters <- old
  replacement <- c(tail(old,1),head(old,-1))
  expect_equal(sort(as.integer(table(old))),sort(as.integer(table(replacement))))
  expect_false(identical(old,replacement))
  fields <- c("all_markers","markers_filtered","markers_summary","cluster_cycling_score",
    "reference_matches","reference_matches_all","llm_annotations")
  for (field in fields) obj@params[[field]] <- data.frame(stale="old membership")
  obj@params$llm_annotation_responses <- list(historical="retained audit")
  testthat::local_mocked_bindings(FindClusters=function(object,...) {
    object$seurat_clusters <- replacement
    SeuratObject::Idents(object) <- replacement
    object
  },.package="Seurat")
  for (apply in list(function(x) sc_cluster(x,.5),
                    function(x) suppressWarnings(sc_cluster_sweep(x,c(.2,.5),tempfile())))) {
    changed <- apply(obj)
    expect_identical(as.character(changed@data$seurat_clusters),replacement)
    for (field in fields) expect_null(changed@params[[field]],info=field)
    expect_identical(changed@params$llm_annotation_responses,obj@params$llm_annotation_responses)
    expect_error(sc_markers_summary(changed,output_path=NULL),"No marker table")
  }
})
