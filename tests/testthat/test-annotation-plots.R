test_that("saved citation changes rebuild real PNG evidence and stale approvals cannot reuse it", {
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  seu<-env$pbmc_small;seu$seurat_clusters<-as.character(SeuratObject::Idents(seu))
  root<-tempfile();on.exit(unlink(root,recursive=TRUE))
  suppressWarnings(sc_run(seu,root,context=list(species="human",tissue="blood"),provider="manual",
    start_stage="processed",processed_reason="Public fixture isolates bound annotation image evidence.",
    input_policy=list(preserve_metadata=TRUE)))
  x<-sc_open(root);labels<-x$annotations
  evidence<-.sc_run_get(root,.sc_run_load(root),"annotation_evidence")
  expect_true(length(evidence$summary$clusters[[1L]]$markers)>=2L)
  genes<-vapply(evidence$summary$clusters[[1L]]$markers,`[[`,character(1),"gene")
  labels$label<-"Unknown";labels$confidence<-"low";labels$rationale<-"No biological identity claim; review plot evidence.";labels$markers<-""
  labels$markers[[1L]]<-genes[[1L]]
  reviewed<-function(x,...) {invisible(capture.output(out<-sc_review(x,...)));out}
  first<-reviewed(reviewed(x),"revise",annotations=labels,reviewer="offline-human",reason="Save the complete cited-gene worksheet.")
  state<-.sc_run_load(root);record<-first$view$annotation_review$details$plot_evidence
  expect_identical(record$dotplot_status,"saved");expect_identical(record$citation_status,"saved")
  expect_true(any(vapply(record$plots,function(x)x$kind=="dotplot",logical(1))))
  expect_true(any(vapply(record$plots,function(x)x$kind=="featureplot",logical(1))))
  expect_identical(record$parameters$dotplot_scale,FALSE)
  expect_true(all(vapply(record$plots,function(x)identical(x$sha256,.sc_project_sha_file(file.path(root,x$path))),logical(1))))
  dot<-Filter(function(x)x$kind=="dotplot",record$plots)[[1L]]
  expect_false(anyDuplicated(unlist(dot$genes))>0L)
  path<-file.path(root,record$plots[[1L]]$path);bytes<-readBin(path,"raw",n=file.info(path)$size)
  expect_identical(bytes[1:8],as.raw(c(137,80,78,71,13,10,26,10)))
  writeBin(c(bytes,as.raw(0)),path)
  expect_error(sc_run_inspect(root),"checkpoint changed")
  expect_error(reviewed(first,"approve",reviewer="offline-human",reason="Must reject modified PNG."),"checkpoint changed")
  writeBin(bytes,path)
  labels$markers[[1L]]<-genes[[2L]]
  second<-reviewed(first,"revise",annotations=labels,reviewer="offline-human",reason="Save another exact citation; rebuild its image evidence.")
  next_record<-second$view$annotation_review$details$plot_evidence
  expect_false(identical(next_record$selection_hash,record$selection_hash))
  expect_false(identical(second$view$annotation_review$hash,first$view$annotation_review$hash))
  expect_error(reviewed(first,"approve",reviewer="offline-human",reason="Old citation review must fail."),"Stale")
  expect_identical(.sc_project_sha_file(path),record$plots[[1L]]$sha256)
  event<-tail(Filter(function(x)x$action=="annotation_plot_evidence_prepared",.sc_run_load(root)$history),1L)[[1L]]
  expect_identical(event$details$plot_hash,next_record$hash)
  expect_length(.sc_run_load(root)$approvals,0L)
  approved<-reviewed(second,"approve",reviewer="offline-human",reason="Approve the rebuilt exact citation and plot evidence.")
  state<-.sc_run_load(root)
  event<-tail(Filter(function(x)x$action=="approved",state$history),1L)[[1L]]
  expect_identical(event$details$plot_evidence_hash,next_record$hash)
  expect_identical(event$details$review_hash,second$view$annotation_review$hash)
  expect_identical(approved$view$status,"ready")

})
