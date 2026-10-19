test_that("public subcluster results preserve grounded counterevidence review fields after reload", {
  withr::local_options(lifecycle_verbosity="quiet")
  withr::local_seed(42)
  root<-tempfile();dir.create(root);withr::local_dir(root)
  seu<-SeuratObject::pbmc_small;seu$cell_type<-"Lineage"
  input<-AgentSeurat(seu);before<-.sc_run_hash(input)
  calls<-0L
  callback<-function(system_prompt,user_prompt) {
    calls<<-calls+1L
    lines<-strsplit(user_prompt,"\n",fixed=TRUE)[[1]]
    genes<-sub("^  (.*) \\(avg_log2FC=.*$","\\1",grep("^  .* \\(avg_log2FC=",lines,value=TRUE))
    stopifnot(length(genes)>0L)
    as.character(jsonlite::toJSON(list(primary_annotation="candidate subtype",confidence="high",
      supporting_markers=as.list(genes[1]),contradicting_markers=as.list(genes[min(2L,length(genes))]),
      alternative_annotations=list(),proportion_assessment="reasonable",recommended_action="accept",
      reasoning="Grounded software-control support and counterevidence; not a biological validation."),auto_unbox=TRUE))
  }
  out<-suppressWarnings(annot_subcluster(input,callback,target="Lineage",subcluster_resolution=.8,
    n_hvg=100L,n_pcs=5L,min_cells_per_broad=1L,min_cells_per_subcluster=1L,
    top_n_markers=5L,max_retries=0L,verbose=FALSE))
  rows<-out@params$subcluster_results$Lineage$annotations
  expect_gt(calls,0L)
  expect_true(all(c("citation_status","review_required","review_reasons") %in% names(rows)))
  expect_length(rows$citation_status,nrow(rows))
  expect_length(rows$review_required,nrow(rows))
  expect_length(rows$review_reasons,nrow(rows))
  used<-rows$label_usable
  expect_true(any(used))
  expect_true(all(rows$citation_status[used]=="valid"))
  expect_true(all(rows$review_required[used]))
  expect_true(all(grepl("declared_counterevidence",rows$review_reasons[used])))
  expect_true(any(out@data$cell_type_fine=="candidate subtype"))
  saveRDS(out,"result.rds");restored<-readRDS("result.rds")
  expect_identical(restored@params$subcluster_results$Lineage$annotations,rows)
  expect_identical(.sc_run_hash(input),before)
})
