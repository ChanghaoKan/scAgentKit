audit_subcluster_json <- function(...) {
  value <- list(primary_annotation="T cell",confidence="medium",supporting_markers=list("CD3D"),
    contradicting_markers=list(),alternative_annotations=list(),proportion_assessment="reasonable",
    recommended_action="accept",reasoning="CD3D supports the lineage.")
  for (key in names(list(...))) value[key] <- list(...)[key]
  jsonlite::toJSON(value,auto_unbox=TRUE)
}

test_that("subcluster replies use annotation schema, cluster binding and marker grounding", {
  markers <- data.frame(gene="CD3D",avg_log2FC=2,pct.1=.9,pct.2=.1)
  invoke <- function(raw) scAgentKit:::.annotate_one_subcluster_with_llm("T","0",80,1,
    markers,"PBMC",chat_fn=function(...) raw,max_retries=0)
  for (raw in c('{"label":"T cell","confidence":"high","reasoning":"x"}',
    audit_subcluster_json(confidence="certain"),audit_subcluster_json(cluster="9"))) {
    out <- invoke(raw)
    expect_identical(out$annotation_status,"failed")
    expect_true(is.na(out$label))
    expect_true(nzchar(out$annotation_error))
    expect_length(out$response_audit,1)
  }
  valid <- invoke(audit_subcluster_json())
  expect_identical(valid$annotation_status,"ok")
  expect_identical(valid$label,"T cell")
  expect_equal(valid$hallucination_rate,0)
  unsupported <- invoke(audit_subcluster_json(supporting_markers=list("INVENTED")))
  expect_identical(unsupported$hallucinated_markers,"INVENTED")
  expect_equal(unsupported$hallucination_rate,1)
  expect_identical(unsupported$recommended_action,"flag_for_review")
})

test_that("subcluster failure states survive the actual result annotation table", {
  obj <- AgentSeurat(SeuratObject::pbmc_small)
  obj@data$cell_type <- "T"
  root <- tempfile();dir.create(root);old <- getwd();on.exit(setwd(old),add=TRUE);setwd(root)
  result <- suppressWarnings(annot_subcluster(obj,function(...) NULL,target="T",
    subcluster_resolution=.8,n_hvg=100,n_pcs=5,min_cells_per_broad=50,min_cells_per_subcluster=1,
    tissue="PBMC",max_retries=2,verbose=FALSE))
  out <- result@params$subcluster_results$T
  expect_true(nrow(out$annotations)>0)
  expect_identical(unique(out$annotations$annotation_status),"failed")
  expect_identical(unique(out$annotations$annotation_attempts),1L)
  expect_true(all(is.na(out$annotations$cell_type_fine)))
  expect_true(all(lengths(out$annotations$response_audit)==1))
  expect_identical(out$batch_processing,"none; per-lineage processing without batch correction")
  expect_false(tail(result@decisions,1)[[1]]$success)
})
