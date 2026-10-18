.legacy_workflow_routes <- function() {
  routes <- list()
  add <- function(names, route) for (name in names) routes[[name]] <<- route
  add(c("qc_add_metrics","qc_threshold","qc_plot"),
    "Use sc_run(input, project_dir) -> sc_run_qc_preview() -> sc_run_qc_review() -> sc_run_approve() -> sc_run_resume(); inspect and approve the saved QC proposal. This is not a same-signature replacement.")
  add("qc_mad", "Use sc_run(..., strategy=TRUE, qc_mad=<explicit grouping/configuration>) and review the complete strategy with sc_run_review() before approval and sc_run_resume().")
  add("qc_doublet", "Use sc_run(..., strategy=TRUE, doublet_diagnostics=<explicit capture/rate configuration>), then sc_run_review()/sc_run_approve()/sc_run_resume(). Capture declarations and version acceptance remain required.")
  add(c("qc_split","qc_merge"), "Use sc_run(input, project_dir, context=<explicit sample/capture facts>, strategy=TRUE) for a reviewed project. There is no one-to-one replacement for manual split/merge operations; declare physical captures explicitly for doublet diagnostics.")
  add("qc_remove_genes", "sc_run() preserves input counts and has no automatic gene-removal equivalent. Prepare a separate input explicitly if needed, then inspect QC using sc_run_qc_review(); do not infer a deletion policy from this migration notice.")
  add(c("sc_normalize","sc_find_hvg","sc_scale","sc_pca","sc_find_neighbors",
        "sc_cluster","sc_cluster_sweep","sc_umap","sc_plot_umap","sc_find_markers","sc_markers_summary"),
    "Use sc_run(..., strategy=TRUE, strategy_proposal=<complete analysis/PC/clustering/UMAP settings>) -> sc_run_review() -> sc_run_approve() -> sc_run_resume(). Markers and figures are derived from that approved analysis; this is not a one-call replacement.")
  add(c("sc_select_pcs","sc_select_pcs_visual","sc_resolution_recommend"),
    "Use sc_run(..., strategy=TRUE), inspect saved evidence with sc_run_review(), and explicitly revise/approve the complete PC/clustering strategy before sc_run_resume(). There is no automatic one-to-one model recommendation replacement.")
  add(c("sc_select_batch_var","sc_harmony"),
    "Use sc_run(..., strategy=TRUE, strategy_proposal=<explicit batch design/settings>, context=<declared column roles>) and sc_run_review()/sc_run_approve()/sc_run_resume(). Batch choice is explicit; no automatic metadata-column selection is implied.")
  add(c("sc_cellcycle_score","sc_cellcycle_regress"),
    "Use sc_run(..., strategy=TRUE, cycle_diagnostics=<explicit gene set/settings>) and review the cycle choice in sc_run_review() before approval/resume. Diagnostic scoring does not automatically authorize regression.")
  add("annot_match_reference", "Use sc_run(..., reference=<declared local reference>) and inspect annotation evidence with sc_run_prepare_annotation()/sc_run_review(). Reference candidates remain evidence, not approved labels.")
  add("annot_review_evidence", "Use sc_run(..., reference=<declared local reference>, reference_review=<explicit evidence policy>), then sc_run_prepare_annotation()/sc_run_review(). This reviews saved evidence rather than applying labels.")
  add("annot_clean_celltypes", "Use sc_run() annotation review and explicit sc_run_propose()/sc_run_approve() decisions. There is no one-to-one coordinator equivalent for automatic label-size deletion or plural-label cleanup; this notice does not authorize either operation.")
  add(c("annot_llm_annotate","annot_apply"),
    "Use sc_run() with an optional explicitly configured provider or manual annotation_proposal, then sc_run_review()/sc_run_propose()/sc_run_approve()/sc_run_resume(). Saving a proposal is separate from approval; no implicit provider retry or label application is implied.")
  add("annot_subcluster", "Use sc_run_subcluster() to create an explicitly scoped child project, review it, then sc_run_subcluster_apply(). This is not equivalent to the legacy automatic per-lineage loop.")
  routes
}

.legacy_workflow_warn <- function(name) {
  lifecycle::deprecate_warn("0.5.1", what=paste0(name,"()"),
    details=.legacy_workflow_routes()[[name]], id=paste0("scAgentKit-legacy-",name))
  invisible(NULL)
}
