# Public pbmc_small software acceptance only. Never a biological benchmark.
# Approvals use the existing public review API and are explicitly scripted.
react_three_gate_mock <- function(project_dir, input_path) {
  stopifnot(!dir.exists(project_dir), !file.exists(input_path))
  e <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = e)
  saveRDS(e$pbmc_small, input_path)
  confirmation <- list(mode = "project", confirmed = TRUE,
    reviewer = "benchmark-policy:accept_drafts",
    reason = "Offline public fixture; no external model or biological conclusion.",
    categories = c("study_context", "aggregate_qc", "aggregate_design", "aggregate_markers", "aggregate_expression"))
  service <- scAgentKit::sc_start(input_path, project_dir,
    context = list(species = "human", tissue = "blood",
      research_goal = "Validate three approval gates with mock drafts; not biological inference."),
    provider = "mock", react = "all", browse = FALSE, doublet = "off",
    review = list(allow_external = TRUE, transfer_consent = confirmation))
  on.exit(if (is.numeric(service$pid)) tools::pskill(service$pid), add = TRUE)
  proposals <- list()
  for (gate in seq_len(3L)) {
    preview <- scAgentKit::sc_run_suggest(project_dir, simulate = TRUE)
    stopifnot(preview$can_request, preview$can_auto_request,
      preview$kind == if (gate < 3L) "strategy" else "annotation")
    candidate <- scAgentKit::sc_run_suggest(project_dir, "request",
      project_id = preview$project_id, input_hash = preview$input_hash,
      expected_revision = preview$revision, suggestion_hash = preview$suggestion_hash,
      simulate = TRUE)
    stopifnot(candidate$status == "candidate")
    scAgentKit::sc_run_suggest(project_dir, "adopt",
      project_id = candidate$project_id, input_hash = candidate$input_hash,
      expected_revision = candidate$revision, suggestion_hash = candidate$suggestion_hash,
      simulate = TRUE, reviewer = "benchmark-policy:accept_drafts",
      reason = "Adopt the complete mock candidate for separate scientific review.")
    review <- scAgentKit::sc_review(project_dir)
    proposals[[gate]] <- review$view$review_node$proposal_hash
    final <- scAgentKit::sc_review(review, "approve",
      reviewer = "benchmark-policy:accept_drafts",
      reason = "Explicit scripted acceptance of the public mock draft, without edits.",
      continue = TRUE)
  }
  stopifnot(final$view$status == "complete")
  object <- scAgentKit::sc_result(final)
  replay <- scAgentKit::sc_react_replay(project_dir)
  stopifnot(replay$matches)
  list(project = final, result = object, replay = replay,
    receipt = list(gates = 3L, provider = "mock", real_api_calls = 0L,
      policy = "accept_drafts", cells = ncol(object), proposal_hashes = proposals))
}
