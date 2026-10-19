test_that("sample comparison distinguishes group medians from cell MAD and guards small N", {
  x <- data.frame(sample=rep(letters[1:6],each=3),nCount=rep(c(100,110,120,130,140,10000),each=3),
    nFeature=rep(c(20,21,22,23,24,200),each=3),percent_mt=rep(c(1,2,3,4,5,40),each=3))
  value <- .sc_run_sample_qc_comparison(x)
  expect_identical(value$unit,"one median per explicitly declared sample")
  expect_identical(value$groups[[6]]$medians$nCount,10000)
  expect_true(value$cross_sample[[1]]$samples[[6]]$flagged)
  expect_identical(.sc_run_sample_qc_comparison(x[x$sample %in% letters[1:2],])$cross_sample[[1]]$status,"unavailable")
  x$nCount <- 1
  expect_identical(.sc_run_sample_qc_comparison(x)$cross_sample[[1]]$status,"unavailable")
  expect_identical(.sc_run_sample_qc_comparison(x[,setdiff(names(x),"sample")])$status,"unavailable")
})
