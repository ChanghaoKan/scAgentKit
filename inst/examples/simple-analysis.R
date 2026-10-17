# Runnable before/after comparison, public pbmc_small SOFTWARE CONTROL ONLY.
# Source this file, then call either function with a NEW project directory.
# No provider, API, study-identity inference or automatic real-study approval.
# Each scripted decision below explicitly tests fixture behavior. For a real
# study, inspect each returned sc_review snapshot and make your own decision.

simple_analysis_after <- function(project_dir) {
  e <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = e)
  x <- scAgentKit::sc_analyze(e$pbmc_small, project_dir,
    context = list(species = "human", tissue = "Public PBMC software fixture"),
    plan = list(rationale = "Explicit software-control plan, not biological recommendations.",
      analysis = list(nfeatures = 100, npcs = 6), pcs = 4, umap = FALSE))
  shown <- scAgentKit::sc_review(x)
  annotation <- scAgentKit::sc_review(shown, "approve", reviewer = "fixture-test",
    reason = "Explicitly exercise this public software-control strategy", continue = TRUE)
  labels <- annotation$annotations
  labels$label <- "Unknown"; labels$confidence <- "low"
  labels$rationale <- "Software-control abstention; no biological identity asserted."
  proposal <- scAgentKit::sc_review(annotation, "revise", annotations = labels,
    reviewer = "fixture-test", reason = "Retain all unresolved fixture labels")
  done <- scAgentKit::sc_review(proposal, "approve", reviewer = "fixture-test",
    reason = "Explicitly exercise unknown-only fixture annotation", continue = TRUE)
  scAgentKit::sc_result(done)
}

simple_analysis_before <- function(project_dir) {
  e <- new.env(); utils::data("pbmc_small", package = "SeuratObject", envir = e)
  plan <- list(schema = "scagentkit.strategy.v1",
    rationale = "Explicit software-control plan, not biological recommendations.",
    risks = list("Software controls do not establish study parameters or identity."), inferences = list(),
    qc = list(schema = "scagentkit.qc.v1", rationale = "Retain count-positive fixture cells.",
      risks = list(), filters = list(list(op = "range", metric = "nCount", min = 1))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 100, npcs = 6, seed = 17), pcs = list(method = "fixed", ndim = 4),
    batch = list(method = "none", reason = "No correction authorized for the software fixture."),
    clustering = list(resolution = .5, diagnostic_resolutions = NULL),
    umap = list(run = FALSE, n_neighbors = 30))
  scAgentKit::sc_run(e$pbmc_small, project_dir,
    context = list(species = "human", tissue = "Public PBMC software fixture"),
    strategy_proposal = plan)
  shown <- scAgentKit::sc_run_inspect(project_dir)
  print(shown$strategy_review$details)
  node <- shown$review_node
  approved <- scAgentKit::sc_run_review(project_dir, action = "approve", kind = node$kind,
    project_id = node$project_id, input_hash = node$input_hash,
    proposal_hash = node$proposal_hash, review_hash = node$review_hash,
    expected_revision = node$expected_revision, reviewer = "fixture-test",
    reason = "Explicitly exercise this public software-control strategy")
  scAgentKit::sc_run_continue(project_dir, approved$project_id, approved$input_hash, approved$revision)
  annotation <- scAgentKit::sc_run_inspect(project_dir)
  proposal <- list(schema = "scagentkit.annotation.v1",
    annotations = lapply(annotation$evidence$clusters, function(cl)
      list(clusterId = cl$clusterId, label = "Unknown", confidence = "low",
        rationale = "Software-control abstention; no biological identity asserted.", markers = list())))
  scAgentKit::sc_run_propose(project_dir, proposal, "fixture-test", "Retain unresolved fixture labels")
  shown <- scAgentKit::sc_run_inspect(project_dir)
  print(shown$annotation_review$details)
  node <- shown$review_node
  approved <- scAgentKit::sc_run_review(project_dir, action = "approve", kind = node$kind,
    project_id = node$project_id, input_hash = node$input_hash,
    proposal_hash = node$proposal_hash, review_hash = node$review_hash,
    expected_revision = node$expected_revision, reviewer = "fixture-test",
    reason = "Explicitly exercise unknown-only fixture annotation")
  scAgentKit::sc_run_continue(project_dir, approved$project_id, approved$input_hash, approved$revision)
  done <- scAgentKit::sc_run_inspect(project_dir)
  readRDS(done$output$seurat)
}
