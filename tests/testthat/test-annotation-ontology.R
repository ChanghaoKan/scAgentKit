ontology_proposal <- function(labels=c("T cell","T cel","Unknown")) {
  list(schema="scagentkit.annotation.v1",annotations=lapply(seq_along(labels),function(i)
    list(clusterId=as.character(i),label=labels[[i]],confidence="low",rationale="Software-control dictionary test.",markers=list())))
}

test_that("exact cluster ontology mapping is versioned and no fuzzy labels receive IDs", {
  skip_if_not_installed("ontologyIndex")
  proposal<-ontology_proposal()
  mapping<-.sc_run_annotation_ontology(proposal)
  expect_identical(mapping$rows$cl_id,c("CL:0000084",NA_character_,NA_character_))
  expect_identical(mapping$source$sha256,"c6274fb65cdf740b983a06b74cb678814249d7f8e580c2ec9de54bf204a2b1c7")
  expect_identical(.sc_run_annotation_ontology_check(mapping,proposal),mapping)
  changed<-proposal;changed$annotations[[1L]]$label<-"B cell"
  expect_error(.sc_run_annotation_ontology_check(mapping,changed),"differs")
  changed<-mapping;changed$rows$cl_id[[1L]]<-"CL:0000236"
  expect_error(.sc_run_annotation_ontology_check(changed,proposal),"differs")
})

test_that("missing optional ontology parsing keeps explicit blank IDs without network", {
  local_mocked_bindings(requireNamespace=function(...) FALSE,.package="base")
  result<-.sc_run_annotation_ontology(ontology_proposal())
  expect_identical(result$status,"unavailable");expect_true(all(is.na(result$rows$cl_id)))
  expect_match(result$notice,"optional ontologyIndex dependency")
})

test_that("approved dictionary writeback preserves input counts, metadata and cell order", {
  skip_if_not_installed("ontologyIndex")
  env<-new.env();utils::data("pbmc_small",package="SeuratObject",envir=env)
  before<-env$pbmc_small;before$literal_cluster<-rep(c("1","2"),each=40)
  preserved<-.sc_run_preserve_input_metadata(before)
  proposal<-ontology_proposal(c("T cell","Unknown"))
  attr(proposal,"input_cells")<-data.frame(cell_id=colnames(before),cluster=before$literal_cluster)
  attr(proposal,"cluster_column")<-"literal_cluster";class(proposal)<-c("sc_run_annotation_proposal","list")
  mapping<-.sc_run_annotation_ontology(proposal)
  hash<-.sc_run_hash(SeuratObject::LayerData(before,assay="RNA",layer="counts"))
  result<-.sc_run_annotation_apply(preserved$seu,proposal,preserve_key=preserved$key,ontology=mapping)
  expect_identical(unname(result$sc_annotation_cl_id),c(rep("CL:0000084",40),rep(NA_character_,40)))
  expect_identical(colnames(result),colnames(before))
  expect_identical(result[[]][,names(before[[]]),drop=FALSE],before[[]])
  expect_identical(.sc_run_hash(SeuratObject::LayerData(result,assay="RNA",layer="counts")),hash)
  expect_identical(.sc_run_preserved_metadata_verify(result,preserved$key)$metadata,before[[]])
  changed<-mapping;changed$rows$label[[1L]]<-"B cell"
  expect_error(.sc_run_annotation_apply(preserved$seu,proposal,preserve_key=preserved$key,ontology=changed),"differs")
})
