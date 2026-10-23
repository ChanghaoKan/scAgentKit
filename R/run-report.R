# Portable projections of verified records. They never become review authority.
.sc_run_output_audit <- function(root, state, seu, review, strategy = NULL) {
  ledger <- .sc_run_provider_read(file.path(root, "provider", "ledger.json"))
  requests <- lapply(ledger$entries, function(entry) entry[intersect(names(entry),
    c("request_hash", "purpose", "status", "provider", "model_reported", "created_at",
      "usage", "cost_state", "cost_usd", "accounting_issue", "delivery", "response_hash"))])
  decisions <- lapply(Filter(function(event) event$action %in%
    c("approved", "rejected", "annotation_undone", "result_accepted"), state$history),
    function(event) event[c("sequence", "created_at", "action", "details", "hash")])
  labels <- table(as.character(seu[[state$config$annotation_column, drop = TRUE]]))
  packages <- sort(loadedNamespaces())
  versions <- stats::setNames(lapply(packages, function(package)
    as.character(utils::packageVersion(package))), packages)
  checkpoints <- state$files[!startsWith(names(state$files), "output:")]
  list(schema = "scagentkit.output-audit.v1", project_id = state$project_id,
    input_hash = state$input_hash, config_hash = state$config_hash,
    implementation_hash = state$implementation_hash,
    projection_revision = state$revision,
    history_head = if (length(state$history)) tail(state$history, 1)[[1]]$hash else NULL,
    context = state$config$context, start_stage = state$config$start_stage,
    processed_reason = state$config$processed_reason,
    subcluster = if (is.null(state$config$subcluster_origin)) NULL else list(
      parent_project_id = state$config$subcluster_origin$parent$project_id,
      parent_scope_hash = state$config$subcluster_origin$parent_scope_hash,
      selected_scope_hash = state$config$subcluster_origin$scope_hash),
    cell_counts = list(supplied = state$diagnostics$cell_count, final = ncol(seu),
      excluded = state$diagnostics$cell_count - ncol(seu)),
    reviewed_plan = if (is.null(strategy)) list(analysis=state$config$analysis) else strategy$details$canonical_proposal,
    reviewed_qc_retention = if (is.null(state$files$qc_preview)) NULL else .sc_run_get(root,state,"qc_preview")$details$retention,
    observed_execution = if (identical(state$config$start_stage,"processed")) list(foundation_reused=TRUE) else
      list(foundation_reused=FALSE, active_reduction=seu@misc$strategy_execution$neighbors$reduction,
        selected_pcs=seu@misc$strategy_execution$neighbors$pcs,
        selected_resolution=seu@misc$strategy_execution$cluster$resolution),
    final_features = nrow(seu), annotation_column = state$config$annotation_column,
    annotation_counts = as.list(labels), annotation_review_hash = review$hash,
    cell_scope_hash = review$cell_scope_hash, annotation_source = review$details$source,
    reference_provenance = .sc_run_get(root, state, "annotation_evidence")$private$reference_provenance,
    decisions = decisions, provider_requests = requests,
    environment = list(R = as.character(getRversion()), platform = R.version$platform,
      packages = versions), checkpoint_index = checkpoints,
    notice = paste("Derived at finalization from verified saved evidence; not an approval ledger or a reopenable project.",
      "The final commit adds its own event after this projection. Keep the whole original project and matching environment.",
      "Recorded labels, confidence and completion do not establish biological accuracy."))
}

.sc_run_report_lines <- function(audit) {
  plain <- function(value) {
    if (is.null(value) || !length(value)) return("not recorded")
    value <- paste(as.character(value), collapse = ", ")
    value <- gsub("[\r\n|]", " ", value)
    for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;")))
      value <- gsub(pair[1], pair[2], value, fixed = TRUE)
    value
  }
  decisions <- unlist(lapply(audit$decisions, function(event) {
    row <- event$details
    paste0("| ", event$sequence, " | ", plain(event$action), " | ", plain(row$kind),
      " | ", plain(row$reviewer), " | ", plain(row$reason), " | ", plain(event$created_at), " |")
  }), use.names = FALSE)
  label_rows <- vapply(names(audit$annotation_counts), function(label)
    paste0("| ", plain(label), " | ", audit$annotation_counts[[label]], " |"), character(1))
  unknown <- sum(unlist(audit$annotation_counts[tolower(trimws(names(audit$annotation_counts))) %in% c("unknown", "unannotated")]))
  plan <- audit$reviewed_plan
  methods <- c(normalization=plain(plan$analysis$normalization_method),
    scale_factor=plain(plan$analysis$scale_factor), variable_features=plain(plan$analysis$nfeatures),
    variable_feature_method=plain(plan$analysis$hvg_method), basis_PCs=plain(plan$analysis$npcs),
    PC_policy=plain(plan$pcs$method), batch_choice=plain(plan$batch$method),
    clustering_resolution=plain(plan$clustering$resolution), cycle_choice=plain(plan$cycle$method),
    doublet_choice=plain(plan$doublet$method))
  method_rows <- paste0("| ",names(methods)," | ",methods," |")
  requests <- audit$provider_requests
  known <- vapply(requests, function(row) identical(row$cost_state, "known") && is.numeric(row$cost_usd) && length(row$cost_usd) == 1L, logical(1))
  total <- sum(vapply(requests[known], function(row) row$cost_usd, numeric(1)))
  c("# Researcher evidence summary", "",
    paste("Project:", audit$project_id), "",
    paste("Study species:", plain(audit$context$species)),
    paste("Study tissue:", plain(audit$context$tissue)),
    paste("Research goal:", plain(audit$context$research_goal)), "",
    paste("Entry:", audit$start_stage, if (audit$start_stage == "processed") paste("— supplied foundation reused:", plain(audit$processed_reason)) else "— locally computed raw-count analysis"),
    paste("Cells supplied:", audit$cell_counts$supplied, "; saved result:", audit$cell_counts$final, "; excluded:", audit$cell_counts$excluded, "; final features:", audit$final_features),
    paste("Unknown/unannotated cells retained:", unknown, ". These are unresolved populations, not proven negative identities."), "",
    "## Reviewed methods and observed execution", "",
    "| Reviewed choice | Saved value |", "| --- | --- |", method_rows, "",
    paste("Observed active reduction:",plain(audit$observed_execution$active_reduction),
      "; selected PCs:",plain(audit$observed_execution$selected_pcs),
      "; executed clustering resolution:",plain(audit$observed_execution$selected_resolution),"."),
    paste("Reviewed QC projection: before",plain(audit$reviewed_qc_retention$before),
      "; retained",plain(audit$reviewed_qc_retention$retained),
      "; removed",plain(audit$reviewed_qc_retention$removed),". The actual final cell count above includes all approved exclusions."),
    "Unrecorded values are not reconstructed. Processed entry reuses its supplied foundation; it does not claim a new method execution.", "",
    "## Recorded decisions", "", "The normal raw workflow separates plan, measured clustering and annotation review. The entries below reflect this project's actual history, including revisions or undo; they are not a fixed gate count.", "",
    "| Event | Action | Scope | Reviewer | Reason | Recorded at |", "| --- | --- | --- | --- | --- | --- |", decisions, "",
    "## Final label distribution", "", "Labels and qualitative confidence are analyst-reviewed claims. They are not calibrated probabilities or an accuracy measurement.", "",
    "| Saved label | Cells |", "| --- | ---: |", label_rows, "",
    "## Model activity and limitations", "",
    paste(length(requests), "saved provider attempts; known recorded cost USD", format(total, scientific = FALSE), ";", sum(!known), "attempts with unknown accounting. Mock/local attempts are not external model inference."),
    "Proposal origin, matching current versus historical responses, ReAct traces and reference provenance are recorded in audit.json and annotation_evidence_summary.json. A configured provider alone does not establish a model call.", "",
    "## Reproducibility and artifact index", "",
    paste("Input SHA256:", audit$input_hash), paste("Config SHA256:", audit$config_hash),
    paste("Implementation SHA256:", audit$implementation_hash), paste("R:", audit$environment$R, "; platform:", audit$environment$platform), "",
    "- seurat.rds: result with a portable scAgentKit audit projection in misc.",
    "- markers.csv and metadata.csv: saved measurements and labels.",
    "- parameters.json: actual saved configuration and analysis choices.",
    "- audit.json: decisions, origins, package versions, accounting and checkpoint hashes.",
    "- strategy_summary.json and method summaries, when present: reviewed choices and actual execution.",
    "- annotation_evidence_summary.json: scoped marker/reference comparison and source limits.",
    "- ../decision_history.json and ../provider/: complete project decision and request records.", "",
    audit$notice, "")
}
