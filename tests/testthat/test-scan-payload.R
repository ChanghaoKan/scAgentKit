test_that("bounded scan projections keep complete split blocks and expose every omission", {
  marker<-function(cluster,index)list(clusterId=cluster,gene=paste0("GENE",index),avgLog2FC=2,pct1=.8,pct2=.1,pAdj=.001)
  records<-lapply(1:12,function(i)list(from_resolution=.2,to_resolution=.5,parent_cluster=paste0("P",i),cells=as.integer(1000-i),status="measured",
    child_sizes=list(list(clusterId="A",cells=500L),list(clusterId="B",cells=400L)),contrast="within parent",
    markers=c(lapply(1:10,function(j)marker("A",i*100+j)),lapply(1:10,function(j)marker("B",i*100+20+j)))))
  scan<-list(hash=strrep("a",64),resolutions=c(.2,.5),tree=list(nodes=list(),edges=list()),markers=list(),adjacent_splits=list(records=records))
  before<-serialize(scan,NULL);value<-.sc_run_cluster_scan_payload(scan,max_bytes=9000L)
  expect_lte(nchar(.sc_run_provider_json(value),type="bytes"),9000L)
  expect_length(value$adjacent_split_inventory,12L)
  expect_gt(value$projection$omitted_split_blocks,0L)
  expect_gt(value$projection$included_split_blocks,0L)
  expect_true(all(vapply(value$adjacent_splits_top10,function(row)length(row$markers)==20L,logical(1))))
  expect_identical(value$source_scan_hash,scan$hash)
  expect_identical(serialize(scan,NULL),before)
})

test_that("the resolution rule fallback never invents an unscanned 0.5", {
  assignments<-list(`0.2`=c(a="0",b="0",c="1",d="1"),`0.4`=c(a="0",b="0",c="1",d="1"))
  scan<-list(schema="scagentkit.cluster-scan.v1",hash=strrep("b",64),resolutions=c(.2,.4),tree=.sc_run_cluster_tree(assignments),
    membership_hashes=lapply(assignments,.sc_run_hash),markers=list(),candidates=list())
  step<-.sc_run_recommend_resolution(scan,list(proposal=list(clustering=list(resolution=.4))))
  expect_identical(step$fallback$status,"conflict_unscanned_default")
  expect_null(step$fallback$resolution)
  expect_match(paste(step$conflicts,collapse=" "),"not scanned")
  expect_equal(vapply(step$candidates,function(row)row$changes$clustering$resolution,numeric(1)),c(.2,.4))
  expect_identical(.sc_run_prompt_version(),"aggregate-review.v3")
})
