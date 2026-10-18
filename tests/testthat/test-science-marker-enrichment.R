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
