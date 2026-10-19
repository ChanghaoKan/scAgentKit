recommend_resolution_fixture <- function() {
  membership <- list(`0.2` = c(a="0",b="0",c="1",d="1"),
    `0.5` = c(a="a",b="b",c="c",d="c"), `0.8` = c(a="a",b="b",c="c",d="c"))
  marker <- function(cluster) list(clusterId=cluster,gene=paste0("G",cluster),avgLog2FC=2,pct1=.8,pct2=.1,pAdj=.01)
  list(schema="scagentkit.cluster-scan.v1",resolutions=c(.2,.5,.8),
    tree=.sc_run_cluster_tree(membership,c("S1","S2","S1","S2")),
    membership_hashes=lapply(membership,.sc_run_hash),
    markers=list(`0.2`=list(status="measured",markers=list(marker("0"),marker("1"))),
      `0.5`=list(status="measured",markers=list(marker("a"),marker("c"))),
      `0.8`=list(status="no_markers_passed",markers=list())),
    candidates=list(list(resolution=.2,n_clusters=2L,ari_vs_previous=NULL),
      list(resolution=.5,n_clusters=3L,ari_vs_previous=.57),
      list(resolution=.8,n_clusters=3L,ari_vs_previous=1)))
}

test_that("resolution recommendations wait for measured scans without fabricating options", {
  result <- .sc_run_recommend_resolution(NULL,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(result$id,"resolution")
  expect_identical(result$status,"recommend_execute")
  expect_identical(result$assessment,"pending_computation")
  expect_length(result$candidates,0)
  expect_match(result$next_decision,"scan.*review")
  reuse <- .sc_run_recommend_resolution(NULL,list(proposal=list(clustering=NULL)))
  expect_identical(reuse$status,"recommend_skip")
})

test_that("actual transitions markers and samples explain alternatives without a ranking", {
  scan <- recommend_resolution_fixture()
  result <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(result$assessment,"assessed")
  expect_length(result$candidates,3)
  expect_equal(vapply(result$candidates,function(x)x$changes$clustering$resolution,numeric(1)),c(.2,.5,.8))
  expect_equal(result$candidates[[1]]$impact$marker_supported_clusters,2L)
  expect_identical(result$candidates[[2]]$impact$marker_missing_clusters,"b")
  expect_equal(result$candidates[[2]]$impact$incoming_split_sources,1L)
  expect_equal(result$candidates[[2]]$impact$single_sample_clusters,2L)
  expect_true(.8 %in% result$candidates[[2]]$impact$equivalent_options)
  expect_equal(result$candidates[[3]]$impact$marker_supported_clusters,0L)
  expect_true(all(vapply(result$candidates,`[[`,logical(1),"available")))
  expect_true(length(result$candidates[[2]]$conflicts)>0)
  expect_match(paste(result$uncertainty,collapse=" "),"not.*stability")
  expect_false(any(c("score","rank","best") %in% names(result)))
  expect_identical(scan,recommend_resolution_fixture())
})

test_that("missing sample and marker evidence stay explicit and malformed scans cannot invent choices", {
  scan <- recommend_resolution_fixture(); scan$tree$nodes <- lapply(scan$tree$nodes,function(n){n$sample_counts<-list();n})
  scan$markers <- NULL
  result <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(result$candidates[[1]]$impact$sample_status,"unavailable")
  expect_null(result$candidates[[1]]$impact$marker_supported_clusters)
  expect_true(length(result$missing)>0)
  bad <- scan; bad$resolutions <- c(.2,NA_real_)
  failed <- .sc_run_recommend_resolution(bad,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(failed$status,"insufficient_information")
  expect_length(failed$candidates,0)
})

test_that("partition equivalence survives label permutations but not crossing reassignments", {
  scan <- recommend_resolution_fixture()
  membership <- list(`0.2`=c(a="0",b="0",c="1",d="1"),
    `0.5`=c(a="a",b="b",c="c",d="c"),`0.8`=c(a="x",b="y",c="z",d="z"))
  scan$tree <- .sc_run_cluster_tree(membership,c("S1","S2","S1","S2"))
  scan$membership_hashes <- lapply(membership,.sc_run_hash)
  result <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_true(.8 %in% result$candidates[[2]]$impact$equivalent_options)
  expect_identical(result$candidates[[2]]$role,"equivalent")
  membership <- list(`0.2`=c(a="0",b="0",c="1",d="1"),`0.5`=c(a="0",b="1",c="0",d="1"))
  scan$resolutions <- c(.2,.5);scan$tree <- .sc_run_cluster_tree(membership)
  scan$membership_hashes <- lapply(membership,.sc_run_hash)
  result <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_length(result$candidates[[1]]$impact$equivalent_options,0)
  expect_identical(result$candidates[[2]]$impact$incoming_split_sources,2L)
  scan$tree$edges <- scan$tree$edges[-1]
  invalid <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(invalid$status,"insufficient_information")
  expect_length(invalid$candidates,0)
})


test_that("general cautions do not make clean measured choices unresolved forever", {
  scan <- recommend_resolution_fixture()
  membership <- list(`0.2`=c(a="0",b="0",c="1",d="1"),
    `0.5`=c(a="0",b="0",c="1",d="1"))
  scan$resolutions <- c(.2,.5)
  scan$tree <- .sc_run_cluster_tree(membership,c("S1","S2","S1","S2"))
  scan$membership_hashes <- lapply(membership,.sc_run_hash)
  scan$markers <- list(`0.2`=scan$markers[["0.2"]],`0.5`=scan$markers[["0.2"]])
  result <- .sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.5))))
  expect_identical(result$assessment,"assessed")
  expect_length(result$conflicts,0)
  expect_true(all(vapply(result$candidates,function(candidate) length(candidate$conflicts)==0L,logical(1))))
  expect_match(paste(result$uncertainty,collapse=" "),"mixing")
  expect_match(paste(result$uncertainty,collapse=" "),"biolog")
})
