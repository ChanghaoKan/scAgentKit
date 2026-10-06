#!/usr/bin/env Rscript
# Source this file for your supplied local matrix/Seurat/RDS.
# CLI: Rscript --vanilla analysis-strategy.R PROJECT_DIR MODE
# Modes: demo, inspect, approve, reject, continue, propose-unknown, output,
#        revise-resolution, revise-pcs, defer-batch.
# The CLI creates synthetic software-test data only. No provider key, download,
# database, dependency installation or external model request is used.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run_strategy_revise", "sc_run_review", "sc_run_continue") %in%
         getNamespaceExports("scAgentKit")))
  stop("Install this checkout's strategy package in the selected R library first.", call. = FALSE)

strategy_example_start <- function(input, project_dir, context, chat_fn = NULL,
                                   strategy_proposal = NULL,
                                   provider = if (is.null(chat_fn)) NULL else
                                     list(name = "mock", model = "aggregate-quantile-software-fixture", external = FALSE),
                                   ...) {
  sc_run(input, project_dir, context = context, strategy = TRUE,
    strategy_proposal = strategy_proposal, provider = provider, chat_fn = chat_fn,
    budget = 0, review = list(allow_external = FALSE), ...)
}

strategy_example_processed <- function(input, project_dir, context, processed_reason,
                                       cluster_column = "seurat_clusters") {
  if (missing(processed_reason) || !nzchar(trimws(processed_reason)))
    stop("Give the source/provenance reason for reusing the processed analysis.", call. = FALSE)
  reuse <- list(schema = "scagentkit.strategy.v1",
    rationale = paste("Explicitly reuse the supplied processed analysis:", processed_reason),
    risks = list("Existing analysis choices remain the analyst's responsibility; no foundation is recomputed."),
    inferences = list(), qc = NULL, analysis = NULL, pcs = NULL,
    batch = list(method = "none", reason = "Reuse the supplied object without new batch correction; this does not establish absence of batch effects."),
    clustering = NULL, umap = NULL)
  strategy_example_start(input, project_dir, context, strategy_proposal = reuse,
    start_stage = "processed", processed_reason = processed_reason,
    cluster_column = cluster_column)
}

# This deterministic mock exercises the provider/typed-proposal mechanism.
# Its quantile rule is a software-test policy, not an AI scientific decision or
# a recommended cleaning threshold. Every derived rule still requires review.
strategy_example_mock <- function(resolution = 0.4, npcs = 6L, ndim = 4L) {
  force(resolution); force(npcs); force(ndim)
  function(system_prompt, user_prompt) {
    if (!grepl("scagentkit.strategy.v1", system_prompt, fixed = TRUE))
      stop("This mock only proposes strategies; annotation requires separate manual review.")
    evidence <- jsonlite::fromJSON(user_prompt, simplifyVector = FALSE)$evidence
    if (!identical(evidence$schema, "scagentkit.strategy.evidence.v1"))
      stop("The mock requires the coordinator's actual aggregate strategy evidence.")
    if (!identical(evidence$start_stage, "qc"))
      stop("Use strategy_example_processed() for an explicit processed reuse plan.")
    filters <- lapply(evidence$quality$groups, function(group) {
      summary <- group$metrics$nFeature
      if (is.null(summary$p05) || is.null(summary$p99) ||
          !is.finite(summary$p05) || !is.finite(summary$p99))
        stop("The software-test quantile rule needs measured feature counts.")
      list(op = "range", metric = "nFeature", min = floor(summary$p05),
        max = ceiling(summary$p99), group = group$selector)
    })
    plan <- list(schema = "scagentkit.strategy.v1",
      rationale = "Deterministic mock for software validation: propose inclusive nFeature p05/p99 bounds within the supplied actual sample/capture groups; inspect retained cells before approving.",
      risks = list("This quantile rule can remove valid rare or large cells and is not a scientific recommendation.",
        "Mitochondrial filtering, cycle, doublet and automatic batch correction are not proposed.",
        "Fixed PCs and resolution are demonstration choices; their biological suitability remains unresolved."),
      inferences = list("Software-test policy only: no inferred cell type, donor identity or technical batch fact."),
      qc = list(schema = "scagentkit.qc.v1", rationale = "Mock test rule derived from the supplied actual aggregate p05/p99 feature distributions.",
        risks = list("Quantile tails may contain valid biological populations."), filters = filters),
      analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
        nfeatures = min(60L, evidence$input$expressed_features), npcs = npcs, seed = 17L),
      pcs = list(method = "fixed", ndim = ndim),
      batch = list(method = "none", reason = "No automatic correction is authorized by this mock; inspect declared batch/group design and unresolved effects."),
      clustering = list(resolution = resolution, diagnostic_resolutions = c(0.2, 0.4, 0.6)),
      umap = list(run = TRUE, n_neighbors = 15L))
    # JSON is the same interface used by a configured provider. Budget is zero.
    jsonlite::toJSON(plan, auto_unbox = TRUE, null = "null", digits = NA)
  }
}

strategy_example_inspect <- function(project_dir, save_snapshot = FALSE) {
  current <- sc_run_inspect(project_dir)
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  if (!is.null(current$strategy_review)) {
    cat("User facts, missing facts, proposed inferences, applicability and exact QC impact:\n")
    print(current$strategy_review$details)
  }
  if (!is.null(current$annotation_review)) print(current$annotation_review$details)
  else if (!is.null(current$evidence)) print(current$evidence)
  if (!is.null(current$review_node)) print(current$review_node)
  if (!is.null(current$failure)) print(current$failure)
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "strategy-example-displayed-snapshot.rds")
    temporary <- tempfile(".strategy-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Could not save the displayed convenience snapshot.")
  }
  invisible(current)
}

strategy_example_decide <- function(project_dir, snapshot, action, reviewer, reason) {
  node <- snapshot$review_node
  if (is.null(node) || !isTRUE(node$can_decide) ||
      !node$kind %in% c("strategy", "annotation") || !action %in% c("approve", "reject"))
    stop("Inspect and read a current strategy/annotation review before deciding.", call. = FALSE)
  do.call(sc_run_review, c(list(project_dir = project_dir, action = action,
    reviewer = reviewer, reason = reason),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")]))
}

strategy_example_continue <- function(project_dir, snapshot, retry = FALSE) {
  sc_run_continue(project_dir, project_id = snapshot$project_id,
    input_hash = snapshot$input_hash, expected_revision = snapshot$revision, retry = retry)
}

strategy_example_revise <- function(project_dir, snapshot, proposal, reviewer, reason) {
  sc_run_strategy_revise(project_dir, proposal = proposal,
    project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    expected_revision = snapshot$revision, reviewer = reviewer, reason = reason)
}

strategy_example_revise_resolution <- function(project_dir, snapshot, resolution,
                                               reviewer, reason) {
  proposal <- snapshot$strategy_review$details$canonical_proposal
  if (is.null(proposal$clustering)) stop("Processed reuse does not authorize reclustering.")
  proposal$clustering$resolution <- resolution
  # QC, normalization/HVG/PCA and neighbor checkpoints can be retained.
  # Clustering, markers and affected annotation evidence require new authority.
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

strategy_example_revise_pcs <- function(project_dir, snapshot, ndim, reviewer, reason) {
  proposal <- snapshot$strategy_review$details$canonical_proposal
  if (is.null(proposal$pcs)) stop("Processed reuse does not authorize selecting new PCs.")
  proposal$pcs <- list(method = "fixed", ndim = ndim)
  # QC and normalization/HVG/PCA are retained. Neighbors/UMAP, clustering,
  # markers and dependent annotation evidence need new computation/review.
  strategy_example_revise(project_dir, snapshot, proposal, reviewer, reason)
}

strategy_example_unknown <- function(project_dir, snapshot, reviewer,
                                      reason = "Manual software-test annotation: identities remain unresolved.") {
  if (!identical(snapshot$stage, "annotation_propose"))
    stop("Continue approved strategy to saved annotation evidence first.", call. = FALSE)
  clusters <- if (!is.null(snapshot$annotation_review))
    snapshot$annotation_review$details$annotations else snapshot$evidence$clusters
  if (!length(clusters)) stop("Saved annotation cluster evidence is unavailable.")
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(clusters,
    function(row) list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = "Unresolved identity retained after review; no biological annotation claim.", markers = list())))
  sc_run_propose(project_dir, proposal, reviewer = reviewer, reason = reason)
}

strategy_example_input <- function() {
  # Three planted expression programs; these are not real cell types/batches.
  set.seed(17)
  values <- matrix(stats::rpois(120L * 120L, lambda = 1), nrow = 120L)
  for (program in seq_len(3L)) {
    genes <- seq.int((program - 1L) * 8L + 1L, program * 8L)
    cells <- seq.int((program - 1L) * 40L + 1L, program * 40L)
    values[genes, cells] <- values[genes, cells] + 12L
  }
  dimnames(values) <- list(paste0("ToyGene", seq_len(nrow(values))),
    paste0("toy-cell-", seq_len(ncol(values))))
  input <- Seurat::CreateSeuratObject(counts = Matrix::Matrix(values, sparse = TRUE),
    min.cells = 0, min.features = 0)
  input$sample_id <- rep(c("toy-sample-A", "toy-sample-B"), each = 60L)
  input$capture_id <- rep(c("toy-capture-1", "toy-capture-2"), each = 60L)
  input$technical_batch <- rep(c("toy-batch-1", "toy-batch-2"), each = 60L)
  input$study_group <- rep(rep(c("toy-Ca", "toy-Ctrl"), each = 30L), 2L)
  input
}

strategy_example_context <- function() {
  list(species = "human", tissue = "synthetic planted expression programs",
    columns = list(sample = "sample_id", capture = "capture_id",
      batch = "technical_batch", group = "study_group"),
    design = list(type = "synthetic crossed design", technical_batch = FALSE,
      notes = "These labels test declared-role/design checks; they do not represent an observed technical effect."),
    research_goal = "Validate typed review, exact cell handling and resumable local computation.",
    notes = "Synthetic software fixture. ToyGene IDs have no mitochondrial convention; that metric is unavailable rather than zero.")
}

strategy_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "approve", "reject", "continue", "propose-unknown",
    "output", "revise-resolution", "revise-pcs", "defer-batch")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: analysis-strategy.R PROJECT_DIR demo|inspect|approve|reject|continue|propose-unknown|output|revise-resolution|revise-pcs|defer-batch")
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-example-analyst"
  if (mode == "demo") {
    input <- strategy_example_input()
    before <- digest::digest(input, algo = "sha256")
    strategy_example_start(input, project_dir, strategy_example_context(),
      chat_fn = strategy_example_mock(), annotation_column = "strategy_reviewed_identity")
    stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  } else if (mode == "inspect") return(strategy_example_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete")) stop("Approve annotation and Continue before reading the final object.")
    cat("Final object:", current$output$seurat, "\n")
    return(invisible(readRDS(current$output$seurat)))
  } else {
    path <- file.path(project_dir, "strategy-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read its displayed evidence before this operation.")
    snapshot <- readRDS(path)
    if (mode == "continue") strategy_example_continue(project_dir, snapshot)
    else if (mode == "propose-unknown") strategy_example_unknown(project_dir, snapshot, reviewer)
    else if (mode == "revise-resolution") strategy_example_revise_resolution(project_dir, snapshot,
      resolution = 0.6, reviewer = reviewer, reason = "Explicit demonstration resolution revision; inspect the fresh whole strategy before approving.")
    else if (mode == "revise-pcs") strategy_example_revise_pcs(project_dir, snapshot,
      ndim = 3L, reviewer = reviewer, reason = "Explicit demonstration PC revision; inspect affected downstream evidence after recomputation.")
    else if (mode == "defer-batch") {
      proposal <- snapshot$strategy_review$details$canonical_proposal
      proposal$batch <- list(method = "manual", reason = "Batch handling is deferred for a separate analyst investigation; execution must stop without integration.")
      strategy_example_revise(project_dir, snapshot, proposal, reviewer,
        reason = "Explicit manual batch boundary; no Harmony or automatic integration is supported.")
    } else strategy_example_decide(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve") "Approve this exact displayed synthetic software-test proposal, with unresolved biology retained."
        else "Reject this exact displayed proposal; do not execute it.")
  }
  invisible(strategy_example_inspect(project_dir))
}

if (sys.nframe() == 0L) strategy_example_main()
