#!/usr/bin/env Rscript
# Source for an explicit local study; the CLI creates synthetic data only.
# Rscript --vanilla unified-model-review.R PROJECT_DIR demo|inspect|approve-request|request|adopt|discard|approve|reject|continue|output
# Every CLI model action is an explicit offline simulation, never a live API.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run_suggest", "sc_run_review", "sc_run_continue") %in%
         getNamespaceExports("scAgentKit")))
  stop("Install this checkout's unified model-review package in the selected R library first.", call. = FALSE)

unified_review_start <- function(input, project_dir, context, strategy_proposal = NULL,
                                 provider = NULL, chat_fn = NULL, budget = 0,
                                 review = list(allow_external = FALSE), ...) {
  sc_run(input, project_dir, context = context, strategy = TRUE,
    strategy_proposal = strategy_proposal, provider = provider, chat_fn = chat_fn,
    budget = budget, review = review, ...)
}

unified_review_inspect <- function(project_dir, simulate = FALSE, save_snapshot = FALSE) {
  current <- sc_run_inspect(project_dir)
  # Explicit simulation gets its own preview/cache identity even before the
  # first saved simulation action. This preview is readonly, with no dispatch.
  current$suggestion <- sc_run_suggest(project_dir, "preview", simulate = simulate)
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  cat("Model channel; payload approval does not approve science:\n")
  print(current$suggestion)
  if (!is.null(current$strategy_review)) {
    cat("Whole scientific strategy and exact local impact:\n")
    print(current$strategy_review$details)
  }
  if (!is.null(current$annotation_review)) {
    cat("Whole scientific annotation review:\n")
    print(current$annotation_review$details)
  }
  if (!is.null(current$review_node)) print(current$review_node)
  if (!is.null(current$failure)) print(current$failure)
  if (!is.null(current$output)) print(current$output)
  if (isTRUE(save_snapshot)) {
    temporary <- tempfile(".unified-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, file.path(project_dir, "unified-example-displayed-snapshot.rds")))
      stop("Cannot save the displayed convenience snapshot.", call. = FALSE)
  }
  invisible(current)
}

unified_review_suggest <- function(project_dir, snapshot, action,
                                   reviewer = NULL, reason = NULL,
                                   simulate = FALSE, chat_fn = NULL) {
  suggestion <- snapshot$suggestion
  if (is.null(suggestion) || !isTRUE(suggestion$available))
    stop("Inspect an available current model preview before this action.", call. = FALSE)
  sc_run_suggest(project_dir, action = action, project_id = suggestion$project_id,
    input_hash = suggestion$input_hash, expected_revision = suggestion$revision,
    suggestion_hash = suggestion$suggestion_hash, reviewer = reviewer,
    reason = reason, simulate = simulate, chat_fn = chat_fn)
  # Display the fresh saved result; the next decision uses this seen snapshot.
  unified_review_inspect(project_dir, simulate = simulate)
}

unified_review_science <- function(project_dir, snapshot, action, reviewer, reason) {
  node <- snapshot$review_node
  if (is.null(node) || !isTRUE(node$can_decide) ||
      !node$kind %in% c("strategy", "qc", "annotation") ||
      !action %in% c("approve", "reject"))
    stop("Inspect a current whole scientific proposal before deciding.", call. = FALSE)
  do.call(sc_run_review, c(list(project_dir = project_dir, action = action,
    reviewer = reviewer, reason = reason),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")]))
}

unified_review_continue <- function(project_dir, snapshot, retry = FALSE) {
  sc_run_continue(project_dir, project_id = snapshot$project_id,
    input_hash = snapshot$input_hash, expected_revision = snapshot$revision, retry = retry)
}

.unified_review_demo_seed <- function(input) {
  # Explicit synthetic software settings, not learned or recommended biology.
  list(schema = "scagentkit.strategy.v1",
    rationale = "Synthetic software-control starting strategy; retain all cells and review these finite demonstration settings.",
    risks = list("No scientific quality threshold, optimal PC/resolution choice or cell identity is established."),
    inferences = list(),
    qc = list(schema = "scagentkit.qc.v1",
      rationale = "Explicit synthetic keep-all rule; no model-derived quality filter.",
      risks = list("Retaining all toy cells is a software control, not real-data QC guidance."),
      filters = list(list(op = "range", metric = "nFeature", min = 0,
        max = nrow(input), group = NULL))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 60L, npcs = 6L, seed = 17L),
    pcs = list(method = "fixed", ndim = 4L),
    batch = list(method = "none", reason = "No correction authorized by this synthetic control."),
    clustering = list(resolution = 0.4, diagnostic_resolutions = NULL),
    umap = list(run = TRUE, n_neighbors = 15L))
}

unified_review_demo <- function(project_dir) {
  helper_path <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
  if (!nzchar(helper_path)) stop("Install the bundled synthetic strategy example.", call. = FALSE)
  helper <- new.env(parent = globalenv()); sys.source(helper_path, envir = helper)
  input <- helper$strategy_example_input()
  before <- digest::digest(input, algo = "sha256")
  result <- unified_review_start(input, project_dir, helper$strategy_example_context(),
    strategy_proposal = .unified_review_demo_seed(input),
    provider = list(name = "mock", model = "SIMULATED-control", external = FALSE),
    budget = 0, review = list(allow_external = FALSE),
    annotation_column = "unified_reviewed_identity")
  stopifnot(identical(before, digest::digest(input, algo = "sha256")))
  invisible(result)
}

unified_review_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "approve-request", "request", "adopt", "discard",
    "approve", "reject", "continue", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: unified-model-review.R PROJECT_DIR demo|inspect|approve-request|request|adopt|discard|approve|reject|continue|output", call. = FALSE)
  project_dir <- args[[1L]]; mode <- args[[2L]]; reviewer <- "synthetic-example-analyst"
  if (mode == "demo") {
    unified_review_demo(project_dir)
    return(unified_review_inspect(project_dir, simulate = TRUE))
  }
  if (mode == "inspect")
    return(unified_review_inspect(project_dir, simulate = TRUE, save_snapshot = TRUE))
  if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete")) stop("Approve annotation and Continue before reading output.", call. = FALSE)
    final <- readRDS(current$output$seurat)
    cat("Final object:", current$output$seurat, "\n")
    print(table(final$unified_reviewed_identity))
    return(invisible(final))
  }
  path <- file.path(project_dir, "unified-example-displayed-snapshot.rds")
  if (!file.exists(path)) stop("Inspect and read the displayed snapshot before this operation.", call. = FALSE)
  snapshot <- readRDS(path)
  if (mode %in% c("approve-request", "request", "adopt", "discard")) {
    action <- if (mode == "approve-request") "approve" else mode
    unified_review_suggest(project_dir, snapshot, action = action, reviewer = reviewer,
      reason = switch(action,
        approve = "Approve only this exact offline simulated request; scientific authority remains separate.",
        request = NULL,
        adopt = "Adopt this simulated candidate for a fresh whole scientific review; no computation is approved.",
        discard = "Discard this simulated candidate without changing the scientific proposal."),
      simulate = TRUE)
  } else if (mode %in% c("approve", "reject")) {
    unified_review_science(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve") "Approve this exact whole synthetic scientific proposal after inspecting local evidence and limitations."
        else "Reject this exact synthetic scientific proposal; do not execute it.")
  } else unified_review_continue(project_dir, snapshot)
  invisible(unified_review_inspect(project_dir, simulate = TRUE))
}

if (sys.nframe() == 0L) unified_review_main()
