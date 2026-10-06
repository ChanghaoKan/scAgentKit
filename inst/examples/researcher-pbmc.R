# Public PBMC tutorial, entirely offline. Sourcing this file only defines helpers.
# pbmc_small is a 230-feature/80-cell tutorial subset, not a complete capture.
# nCount >= 1 below is a software control, NOT a scientifically chosen QC cutoff.
# Mock output is explicitly marked; Unknown/low labels do not establish identity.
# No credentials, network requests, package installation, or automatic approval.

researcher_pbmc_plan <- function() {
  list(schema = "scagentkit.strategy.v1",
    rationale = "Offline tutorial: retain count-positive cells and review explicit local settings.",
    risks = list("This is a software control, not recommended QC thresholds.",
      "The tutorial subset does not describe a complete called-cell capture.",
      "Clustering and annotation require scientific review; identities remain Unknown."),
    inferences = list(),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "Keep count-positive tutorial cells for the mechanism demonstration.",
      risks = list("nCount >= 1 is a software control, not a biologically validated QC rule."),
      filters = list(list(op = "range", metric = "nCount", min = 1L))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 100L, npcs = 10L, seed = 20261006L),
    pcs = list(method = "fixed", ndim = 5L),
    batch = list(method = "none", reason = "No technical batch or identifiable capture design was supplied."),
    clustering = list(resolution = 0.4, diagnostic_resolutions = c(0.2, 0.6)),
    umap = list(run = TRUE, n_neighbors = 10L))
}

make_researcher_pbmc_mock <- function(request_counter = NULL) {
  force(request_counter)
  function(system_prompt, user_prompt) {
    payload <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)
    if (grepl("scagentkit.strategy.v1", system_prompt, fixed = TRUE)) {
      if (!is.null(request_counter)) request_counter$strategy <- request_counter$strategy + 1L
      proposal <- researcher_pbmc_plan()
      proposal$rationale <- paste0("Offline mock sees ", payload$evidence$input$cells,
        " tutorial cells and ", payload$evidence$input$features,
        " features; the explicit count-positive software control is not optimized QC.")
    } else if (grepl("scagentkit.annotation.v1", system_prompt, fixed = TRUE)) {
      if (!is.null(request_counter)) request_counter$annotation <- request_counter$annotation + 1L
      proposal <- list(schema = "scagentkit.annotation.v1",
        annotations = lapply(payload$evidence$clusters, function(row)
          list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
            rationale = "Offline tutorial mock: biological identity remains unresolved.",
            markers = list())))
    } else stop("The offline tutorial mock supports only typed strategy and annotation requests.", call. = FALSE)
    as.character(jsonlite::toJSON(proposal, auto_unbox = TRUE, null = "null"))
  }
}

researcher_pbmc_start <- function(project_dir, chat_fn = make_researcher_pbmc_mock(),
                                 input = SeuratObject::pbmc_small) {
  scAgentKit::sc_run(input, project_dir,
    context = list(species = "human", tissue = "PBMC",
      columns = list(sample = "orig.ident"),
      research_goal = "Learn the offline reviewed analysis workflow, not establish biological labels.",
      notes = "Public tutorial subset. orig.ident is a project label; donor and capture are unknown. No complete called-cell cohort is claimed."),
    provider = list(name = "mock", model = "protocol-mock-v1", external = FALSE),
    chat_fn = chat_fn, budget = 0, review = list(allow_external = FALSE),
    strategy = TRUE, annotation_column = "protocol_annotation")
}

researcher_pbmc_inspect <- function(project_dir) scAgentKit::sc_run_inspect(project_dir)

researcher_pbmc_decide <- function(project_dir, snapshot, action = "approve",
                                  reviewer, reason, proposal = NULL, decision_id = NULL) {
  node <- snapshot$review_node
  if (is.null(node)) stop("Inspect a saved strategy or annotation review node before deciding.", call. = FALSE)
  args <- c(list(project_dir = project_dir, action = action,
    reviewer = reviewer, reason = reason),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")])
  if (!is.null(proposal)) args$proposal <- proposal
  if (!is.null(decision_id)) args$decision_id <- decision_id
  do.call(scAgentKit::sc_run_review, args)
}

researcher_pbmc_resume <- function(project_dir, chat_fn = make_researcher_pbmc_mock(), retry = FALSE) {
  scAgentKit::sc_run_resume(project_dir, chat_fn = chat_fn, retry = retry)
}

# Copy and run the following steps deliberately. Stop to inspect each snapshot.
# library(scAgentKit)
# source(system.file("examples", "researcher-pbmc.R", package = "scAgentKit"))
# project_dir <- "pbmc-tutorial"  # choose a new local/server-side directory
# mock <- make_researcher_pbmc_mock()
# run <- researcher_pbmc_start(project_dir, chat_fn = mock)
# snapshot <- researcher_pbmc_inspect(project_dir)
# print(snapshot$strategy_review)
# researcher_pbmc_decide(project_dir, snapshot, reviewer = "analyst",
#   reason = "I reviewed this exact offline tutorial control and its retained-cell scope.")
# run <- researcher_pbmc_resume(project_dir, chat_fn = mock)
# snapshot <- researcher_pbmc_inspect(project_dir)  # fresh annotation snapshot
# print(snapshot$annotation_review)
# researcher_pbmc_decide(project_dir, snapshot, reviewer = "analyst",
#   reason = "Retain unresolved tutorial identities as Unknown after marker review.")
# done <- researcher_pbmc_resume(project_dir, chat_fn = mock)
# stopifnot(done$status == "complete")
# final <- readRDS(done$output$seurat)
# done$output  # server-side RDS, tables, plots, parameters, journal and bundle
# Execution completion is not scientific RESULT_ACCEPTED.
