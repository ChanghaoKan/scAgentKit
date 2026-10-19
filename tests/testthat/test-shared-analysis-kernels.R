test_that("project markers and references do not construct legacy workflow objects", {
  obj<-SeuratObject::pbmc_small
  obj$seurat_clusters<-as.character(SeuratObject::Idents(obj))
  before<-.sc_run_hash(obj)
  testthat::local_mocked_bindings(
    AgentSeurat=function(...)stop("legacy constructor called"),
    sc_find_markers=function(...)stop("legacy marker wrapper called"),
    sc_markers_summary=function(...)stop("legacy summary wrapper called"),
    annot_match_reference=function(...)stop("legacy reference wrapper called"))
  markers<-suppressWarnings(.sc_run_markers(obj,list()))
  expect_gt(nrow(markers$marker_summary),0L)
  ref<-data.frame(cell_type="candidate",marker=markers$marker_summary$gene[1],species="human",tissue="all")
  evidence<-.sc_run_annotation_evidence(obj,markers,list(species="human",tissue="blood"),reference=ref)
  expect_gt(nrow(evidence$private$candidates_all),0L)
  expect_identical(.sc_run_hash(obj),before)
})

test_that("shared marker table preserves strict filtering ranking and cycling statistics", {
  table<-data.frame(cluster=c("0","0","0","0","1"),
    gene=c("CD3D","MKI67","FC_BOUNDARY","P_BOUNDARY","MS4A1"),
    avg_log2FC=c(2,2,1,2,2),p_val_adj=c(.001,.001,.001,.05,.001),
    pct.1=c(.8,.9,1,1,.7),pct.2=c(.1,.1,0,0,.2))
  before<-table
  value<-.sc_marker_summary(table,top_n=1)
  expect_identical(as.character(value$filtered$gene),c("MKI67","MS4A1"))
  expect_identical(value$summary_lines,c("cluster0:MKI67","cluster1:MS4A1"))
  expect_equal(value$cycling_score$cc_frac,c(1,0))
  expect_identical(value$cycling_score$cycling_dominant,c(TRUE,FALSE))
  expect_identical(table,before)
  expect_identical(nrow(.sc_marker_summary(table[FALSE,])$filtered),0L)
})

test_that("shared overlap keeps exact hit denominators ordering and zero-hit evidence", {
  query<-data.frame(cluster=c("0","0","0"),gene=c("g1","g2","g1"))
  ref<-data.frame(cell_type=c("small","large","large","large","large","zero"),
    marker=c("g1","g1","g2","g3","g4","absent"))
  before<-ref
  value<-.sc_reference_match(query,ref,top_n_candidates=1)
  expect_identical(value$matches$cell_type,"small")
  expect_identical(value$all_matches$cell_type,c("small","large","zero"))
  expect_equal(value$all_matches$score,c(1,.5,0))
  expect_equal(value$all_matches$overlap_count,c(1,2,0))
  expect_equal(value$all_matches$celltype_size,c(1,4,1))
  expect_identical(ref,before)
  expect_error(.sc_reference_match(query,ref,0),"positive integer")
  expect_error(.sc_reference_match(data.frame(cluster="0",gene=NA_character_),ref),"non-empty")
})

test_that("shared ARI retains permutation and degenerate partition behavior", {
  expect_equal(.adjusted_rand_index(c(1,1,2,2),c("B","B","A","A")),1)
  expect_equal(.adjusted_rand_index(c(1,1,2,2),c(1,2,1,2)),-.5)
  expect_equal(.adjusted_rand_index(rep(1,4),rep("A",4)),1)
  expect_true(is.na(.adjusted_rand_index("A","A")))
})
