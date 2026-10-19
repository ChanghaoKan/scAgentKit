test_that("development exports expose one project workflow and retained utilities", {
  path<-system.file("api-contract.json",package="scAgentKit")
  if(!nzchar(path))path<-testthat::test_path("..","..","inst","api-contract.json")
  contract<-jsonlite::read_json(path,simplifyVector=TRUE)
  exports<-getNamespaceExports("scAgentKit")
  expect_length(intersect(exports,contract$exports),0L)
  expect_false(exists("AgentSeurat",asNamespace("scAgentKit"),inherits=FALSE))
  required<-c("sc_start","sc_analyze","sc_review","sc_result","sc_open",
    "sc_run_subcluster","sc_run_suggest","sc_project_prepare","sc_project_export",
    "sc_review_validate","sc_review_apply","qc_plot","sc_plot_umap",
    "sc_find_markers","sc_markers_summary","annot_load_reference",
    "annot_match_reference","annot_map_to_cl","cl_lookup","annot_compare_with_reference")
  expect_true(all(required %in% exports))
  expect_true(all(vapply(required,function(name)is.function(getExportedValue("scAgentKit",name)),logical(1))))
})
