test_that("Fisher uses eligible background, retains all cells and adjusts all labels", {
  sets <- list(A=c("g1","g2","UNMEASURED"),B=c("g2","g3"))
  value <- .sc_run_marker_enrichment(c("g1","g2"),sets,paste0("g",1:10))
  a <- value$records[[1]]
  expect_identical(unlist(a[c("a","b","c","d")]),c(a=2L,b=0L,c=0L,d=8L))
  expect_equal(a$p_value,stats::fisher.test(matrix(c(2,0,0,8),2,byrow=TRUE),alternative="greater")$p.value)
  expect_equal(a$p_adjusted,stats::p.adjust(vapply(value$records,`[[`,0,"p_value"),"BH")[[1]])
  expect_equal(a$universe_size,10)
  expect_identical(.sc_run_marker_enrichment("g1",sets)$status,"unavailable")
  expect_error(.sc_run_marker_enrichment("g1",sets,c("g1","g1")),"unique")
})
test_that("eligible background uses Seurat detection rounding at prefilter boundaries", {
  counts <- Matrix::Matrix(matrix(c(1,0,0,0,0,0, 1,1,1,1,1,1, 0,0,0,1,0,0),3,6,byrow=TRUE,
    dimnames=list(c("G1","G2","G3"),letters[1:6])),sparse=TRUE)
  obj <- Seurat::CreateSeuratObject(counts)
  obj <- Seurat::NormalizeData(obj,verbose=FALSE)
  SeuratObject::Idents(obj) <- rep(c("0","1"),each=3)
  background <- .sc_run_marker_background(obj,"RNA",list(logfc_threshold=0,only_pos=FALSE,min_pct=.3332))
  expect_false("G1" %in% background[["0"]])
  expect_true("G2" %in% background[["0"]])
  background2 <- .sc_run_marker_background(obj,"RNA",list(logfc_threshold=0,only_pos=FALSE,min_pct=.333))
  expect_true("G1" %in% background2[["0"]])
})
