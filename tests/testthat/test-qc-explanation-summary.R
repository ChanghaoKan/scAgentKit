test_that("quality pattern summary counts disjoint flags without high-RNA deletion", {
  flags<-expand.grid(low_count=c(FALSE,TRUE),low_feature=c(FALSE,TRUE),high_mt=c(FALSE,TRUE))
  flags$high_rna_count<-TRUE
  x<-.sc_run_mad_flag_summary(flags,1:8)
  expect_true(x$available);expect_identical(x$denominator,8L)
  expect_equal(unlist(x$patterns),rep(1L,8),ignore_attr=TRUE)
  expect_identical(x$any_quality_flag,7L)
  expect_identical(x$multiple_quality_flags,4L)
  flags$high_mt[1]<-NA
  missing<-.sc_run_mad_flag_summary(flags,1:8)
  expect_false(missing$available);expect_identical(missing$unknown_cells,1L)
  expect_null(missing$any_quality_flag)
  expect_true(all(vapply(missing$patterns,is.null,logical(1))))
  empty<-.sc_run_mad_flag_summary(flags,integer())
  expect_true(empty$available);expect_identical(empty$denominator,0L)
})

test_that("explanatory summaries preserve grouped OR AND keep-all choices and tiny positive mt MAD", {
  n<-120L
  metrics<-data.frame(cell_id=paste0("c",seq_len(n)),nCount=rep(200:259,2),
    nFeature=rep(100:159,2),percent_mt=.04+rep((1:60)%%7,2)*1e-7,
    percent_ribo=NA_real_,percent_hb=NA_real_)
  metrics$nCount[c(1,4,5,7)]<-1
  metrics$nFeature[c(2,4,6,7)]<-1
  metrics$percent_mt[c(3,5,6,7)]<-1
  metrics$nCount[8]<-1e6;metrics$nFeature[8]<-10000
  groups<-stats::setNames(rep(c("S1","S2"),each=60L),metrics$cell_id)
  opts<-list(k=3,mad_constant=1.4826,min_group_cells=30L)
  x<-.sc_run_mad_compute(metrics,groups,metrics$cell_id,opts)
  expect_identical(x$selections$keep_all,metrics$cell_id)
  for(g in x$groups) {
    patterns<-g$flag_summary
    expect_identical(patterns$denominator,g$pre_score)
    expect_equal(sum(unlist(patterns$patterns)),g$pre_score)
    expect_equal(patterns$any_quality_flag,g$pre_score-sum(x$selections$any_quality3 %in% metrics$cell_id[groups==g$value]))
    expect_equal(patterns$patterns$all_three,g$pre_score-sum(x$selections$conservative_and3 %in% metrics$cell_id[groups==g$value]))
    expect_true(g$metrics$percent_mt$available)
    expect_gt(g$metrics$percent_mt$exact$scaled_mad,0)
    expect_lt(g$metrics$percent_mt$exact$upper_raw-g$metrics$percent_mt$exact$median,1e-4)
  }
  expect_true("c8" %in% x$selections$any_quality3)
  metrics$percent_mt[groups=="S2"]<-NA_real_
  missing<-.sc_run_mad_compute(metrics,groups,metrics$cell_id,opts)
  expect_identical(missing$selections$keep_all,metrics$cell_id)
  expect_false(missing$groups[[2]]$flag_summary$available)
  expect_identical(missing$groups[[2]]$flag_summary$unknown_cells,60L)
  expect_null(missing$selections$any_quality3)
})
