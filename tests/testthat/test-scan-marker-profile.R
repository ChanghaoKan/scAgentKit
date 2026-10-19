test_that("diagnostic native settings are separate from final marker parameters", {
  config<-list(markers=list(only_pos=FALSE,min_pct=.1,logfc_threshold=0,log2fc_cut=1,top_n=40L),context=list(species="human"))
  before<-config;scan<-.sc_run_scan_marker_config(config)
  expect_identical(config,before)
  expect_true(scan$markers$only_pos);expect_equal(scan$markers$min_pct,.25)
  expect_equal(scan$markers$logfc_threshold,.25);expect_equal(scan$markers$log2fc_cut,.25)
  expect_identical(scan$markers$top_n,30L)
  expect_identical(.sc_run_scan_marker_config(config,10L)$markers$top_n,10L)
})

test_that("within-parent contrasts use exact child cells and native top-ten settings", {
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  seu<-env$pbmc_small;cells<-colnames(seu)
  assignments<-list(`0.2`=setNames(rep(c("parent A","parent B"),each=40),cells),
    `0.4`=setNames(rep(c("child 1","child 2","child 3","child 4"),each=20),cells))
  before<-.sc_run_hash(seu);calls<-list()
  local_mocked_bindings(.sc_run_markers=function(working,config) {
    calls[[length(calls)+1L]]<<-list(cells=colnames(working),groups=as.character(working$literal_cluster),settings=config$markers)
    list(markers=data.frame(),marker_summary=.sc_run_empty_markers(),parameters=config$markers)
  },.package="scAgentKit")
  out<-.sc_run_adjacent_split_markers(seu,list(cluster_column="literal_cluster"),assignments)
  expect_length(calls,2L);expect_identical(calls[[1L]]$cells,cells[1:40]);expect_identical(calls[[2L]]$cells,cells[41:80])
  expect_identical(unique(calls[[1L]]$groups),c("child 1","child 2"))
  expect_identical(calls[[1L]]$settings$top_n,10L);expect_true(calls[[1L]]$settings$only_pos)
  expect_identical(out$records[[1L]]$status,"no_markers_passed")
  expect_identical(.sc_run_hash(seu),before)
  assignments[[2L]][[1L]]<-"rare child"
  small<-.sc_run_adjacent_split_markers(seu,list(cluster_column="literal_cluster"),assignments)
  expect_identical(small$records[[1L]]$status,"unavailable_small_child")
})

test_that("marker program fractions disclose unrecognized identifiers and unsupported cycle species", {
  markers<-data.frame(cluster="0",gene=c("RPL13A","MT-CO1","MKI67","CD3D"),avg_log2FC=4:1,pct.1=.8,pct.2=.1)
  human<-.sc_run_scan_marker_programs(markers,list(species="human"))$rows[[1L]]
  expect_equal(human$ribosomal_fraction,.25);expect_equal(human$mitochondrial_fraction,.25)
  expect_equal(human$cycle_fraction,.25)
  mouse<-.sc_run_scan_marker_programs(markers,list(species="mouse"))$rows[[1L]]
  expect_null(mouse$cycle_fraction);expect_match(mouse$cycle_status,"unavailable")
  markers$gene[[1L]]<-"ENSG00000123456"
  unknown<-.sc_run_scan_marker_programs(markers,list(species="human"))$rows[[1L]]
  expect_null(unknown$ribosomal_fraction);expect_null(unknown$cycle_fraction)
})
