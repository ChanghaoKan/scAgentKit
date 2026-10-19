compare_object <- function() {
  x<-SeuratObject::pbmc_small[,1:4]
  x$sc_annotation<-c("T","B","NK","Unknown")
  x$reference<-c("T","B","NK","Monocyte")
  x
}
test_that("reference comparisons require explicit roles and exact cell IDs", {
  x<-compare_object();before<-.sc_run_hash(x)
  labels<-stats::setNames(x$reference,colnames(x))
  value<-annot_compare_with_reference(x,author_celltype=labels[4:1])
  expect_equal(value$overall_concordance,75)
  expect_identical(value$n_cells_compared,4L)
  expect_identical(value$unresolved_labels,1L)
  expect_false(value$collapse_used)
  expect_identical(.sc_run_hash(x),before)
  expect_error(annot_compare_with_reference(x),"reference_col")
  expect_error(annot_compare_with_reference(x,reference_col="sc_annotation"),"separate")
  expect_error(annot_compare_with_reference(x,author_celltype=unname(labels)),"unique")
  names(labels)<-paste0("PREFIX_",names(labels))
  expect_error(annot_compare_with_reference(x,author_celltype=labels),"exact cell ID")
  expect_error(annot_compare_with_reference(x,reference_col="reference",collapse_llm="auto"),"explicit TRUE/FALSE")
})
test_that("coarsening is an explicit utility instead of a guessed comparison rule", {
  expect_identical(annot_collapse_to_broad(c("CD8 T cell","unmapped"),extra_map=c("CD8 T cell"="T")),c("T","unmapped"))
  x<-compare_object();x$sc_annotation<-c("fine T","B","NK",NA_character_)
  x$reference<-c("T","B","T/NK","Monocyte")
  value<-annot_compare_with_reference(x,reference_col="reference",collapse_llm=TRUE,extra_map=c("fine T"="T"))
  expect_true(value$collapse_used);expect_equal(value$overall_concordance,100)
  expect_identical(value$n_missing,1L);expect_identical(value$n_input_cells,4L)
})
