test_that("development exports expose one project workflow and retained utilities", {
  # Retired-export assertions belong in tests; no API inventory is installed.
  retired<-c(
    "qc_threshold", "qc_mad", "qc_doublet", "qc_remove_genes",
    "sc_normalize", "sc_find_hvg", "sc_scale", "sc_pca",
    "sc_select_pcs", "sc_select_pcs_visual", "sc_select_batch_var", "sc_harmony",
    "sc_cellcycle_score", "sc_cellcycle_regress", "sc_find_neighbors", "sc_cluster",
    "sc_cluster_sweep", "sc_resolution_recommend", "sc_umap", "annot_llm_annotate",
    "annot_apply", "annot_subcluster", "annot_review_evidence", "annot_clean_celltypes",
    "AgentSeurat", "save_checkpoint", "load_checkpoint", "upgrade_checkpoint",
    "get_seurat", "get_script", "get_figures", "get_decisions",
    "export_decisions", "export_script", "get_token_usage", "report_html"
  )
  exports<-getNamespaceExports("scAgentKit")
  expect_length(intersect(exports,retired),0L)
  expect_false(exists("AgentSeurat",asNamespace("scAgentKit"),inherits=FALSE))
  required<-c("sc_start","sc_analyze","sc_review","sc_result","sc_open",
    "sc_run_subcluster","sc_run_suggest","sc_project_prepare","sc_project_export",
    "sc_review_validate","sc_review_apply","qc_plot","sc_plot_umap",
    "sc_find_markers","sc_markers_summary","annot_load_reference",
    "annot_match_reference","annot_import_act","annot_map_to_cl","cl_lookup","annot_compare_with_reference")
  expect_true(all(required %in% exports))
  expect_true(all(vapply(required,function(name)is.function(getExportedValue("scAgentKit",name)),logical(1))))
})
