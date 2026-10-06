#!/usr/bin/env Rscript
# Fresh synthetic, manual software control. No install, download, key read,
# provider call or automatic approval. Source for functions, or use:
# Rscript --vanilla parameter-context-demo.R PROJECT_DIR MODE [any|all for start]
# Modes: start, inspect, approve, reject, resume, propose-unknown, output.

suppressPackageStartupMessages(library(scAgentKit))
if (!"sc_run_set_child_context" %in% getNamespaceExports("scAgentKit"))
  stop("Use the installed parameter-context checkout in your selected R library.", call. = FALSE)
parameter_context_helper_path <- system.file("examples", "analysis-strategy.R", package = "scAgentKit")
if (!nzchar(parameter_context_helper_path))
  stop("The installed package must include examples/analysis-strategy.R.", call. = FALSE)
.parameter_context_helpers <- new.env(parent = globalenv())
sys.source(parameter_context_helper_path, envir = .parameter_context_helpers)
rm(parameter_context_helper_path)

parameter_context_demo_start <- function(project_dir, remove_if = c("any", "all"),
                                          pcs_fraction = .80, resolution = .4,
                                          diagnostic_resolutions = c(.2, .4, .6)) {
  remove_if <- match.arg(remove_if)
  h <- .parameter_context_helpers
  input <- h$strategy_example_input()
  context <- h$strategy_example_context()
  original_hash <- digest::digest(input, algo = "sha256")
  # These are actual values from the fresh object's declared metadata roles.
  # No donor, biological condition or technical-batch identity is inferred.
  metadata <- input[[]]
  selector <- list(sample = as.character(metadata[[context$columns$sample]][1L]),
                   capture = as.character(metadata[[context$columns$capture]][1L]))
  plan <- list(schema = "scagentkit.strategy.v1",
    rationale = "Manual synthetic control: review explicit QC failure rules, computed-PC fraction and clustering parameters together.",
    risks = list("Inclusive bounds deliberately retain this synthetic fixture; these are not recommended biological thresholds.",
      "PC fraction, clustering resolution and planted expression programs have no biological accuracy claim."),
    inferences = list(),
    qc = list(schema = "scagentkit.qc.rules.v1",
      rationale = "Review one global range and one range scoped to an actual sample/capture pair.",
      risks = list("AND combines failure predicates, not passing predicates; cells outside a rule's selected group do not fail that rule."),
      remove_if = remove_if,
      rules = list(list(op = "range", metric = "nCount", min = 1L),
                   list(op = "range", metric = "nFeature", min = 1L, group = selector))),
    analysis = list(normalization_method = "LogNormalize", scale_factor = 10000,
      nfeatures = 60L, npcs = 12L, seed = 17L),
    pcs = list(method = "computed_variance", threshold = pcs_fraction),
    batch = list(method = "none", reason = "No correction is authorized by this software-control plan; biological conditions are not inferred technical batches."),
    clustering = list(resolution = resolution, diagnostic_resolutions = diagnostic_resolutions),
    umap = list(run = TRUE, n_neighbors = 15L))
  result <- h$strategy_example_start(input, project_dir, context,
    strategy_proposal = plan, annotation_column = "parameter_reviewed_identity")
  stopifnot(identical(original_hash, digest::digest(input, algo = "sha256")))
  invisible(result)
}

parameter_context_demo_inspect <- function(project_dir, save_snapshot = FALSE) {
  view <- .parameter_context_helpers$strategy_example_inspect(project_dir, save_snapshot)
  if (!is.null(view$computed_diagnostics)) print(view$computed_diagnostics)
  if (!is.null(view$child_context)) {
    cat("Child context generation:", view$child_context$generation,
        "Hash:", view$child_context$hash, "\n")
    print(view$child_context)
  }
  invisible(view)
}

parameter_context_demo_approve <- function(project_dir, snapshot, reviewer, reason) {
  .parameter_context_helpers$strategy_example_decide(project_dir, snapshot,
    action = "approve", reviewer = reviewer, reason = reason)
}
parameter_context_demo_resume <- function(project_dir, snapshot, retry = FALSE) {
  # Existing exact-bound local Continue; no model request is dispatched.
  .parameter_context_helpers$strategy_example_continue(project_dir, snapshot, retry)
}
parameter_context_demo_unknown <- function(project_dir, snapshot, reviewer,
                                            reason = "Keep unresolved synthetic identities as Unknown/low.") {
  .parameter_context_helpers$strategy_example_unknown(project_dir, snapshot, reviewer, reason)
}
parameter_context_demo_output <- function(project_dir) {
  view <- sc_run_inspect(project_dir)
  if (!identical(view$status, "complete"))
    stop("Inspect, approve annotation, and resume before reading the final object.", call. = FALSE)
  cat("Final Seurat RDS:", view$output$seurat, "\n")
  invisible(readRDS(view$output$seurat))
}

parameter_context_demo_processed <- function(input, project_dir, context,
                                              processed_reason, cluster_column,
                                              annotation_column = "parameter_reused_identity") {
  # Typed reuse configuration only; analysis is handled by the existing entry.
  reuse <- list(schema = "scagentkit.strategy.v1",
    rationale = paste("Explicit processed reuse:", processed_reason),
    risks = list("Supplied analysis choices and their biological validity remain unresolved."),
    inferences = list(), qc = NULL, analysis = NULL, pcs = NULL,
    batch = list(method = "none", reason = "Reuse the supplied processed object without new correction."),
    clustering = NULL, umap = NULL)
  .parameter_context_helpers$strategy_example_start(input, project_dir, context,
    strategy_proposal = reuse, start_stage = "processed", processed_reason = processed_reason,
    cluster_column = cluster_column, annotation_column = annotation_column)
}

parameter_context_demo_correct_child <- function(child_project, snapshot, context,
                                                  reviewer, reason, request_id) {
  if (is.null(snapshot$child_context))
    stop("Inspect a fresh scoped child with saved parent context first.", call. = FALSE)
  sc_run_set_child_context(child_project, context = context,
    project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    expected_revision = snapshot$revision,
    expected_context_hash = snapshot$child_context$hash,
    reviewer = reviewer, reason = reason, request_id = request_id)
}

parameter_context_demo_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("start", "inspect", "approve", "reject", "resume", "propose-unknown", "output")
  if (!length(args) %in% c(2L, 3L) || !args[[2L]] %in% modes ||
      (length(args) == 3L && (args[[2L]] != "start" || !args[[3L]] %in% c("any", "all"))))
    stop("Usage: parameter-context-demo.R PROJECT_DIR start|inspect|approve|reject|resume|propose-unknown|output [any|all for start]", call. = FALSE)
  project_dir <- args[[1L]]; mode <- args[[2L]]
  reviewer <- "parameter-context-demo-analyst"
  if (mode == "start") parameter_context_demo_start(project_dir,
    remove_if = if (length(args) == 3L) args[[3L]] else "any")
  else if (mode == "inspect") return(parameter_context_demo_inspect(project_dir, save_snapshot = TRUE))
  else if (mode == "output") return(parameter_context_demo_output(project_dir))
  else {
    path <- file.path(project_dir, "strategy-example-displayed-snapshot.rds")
    if (!file.exists(path)) stop("Run inspect and read the displayed proposal first.", call. = FALSE)
    snapshot <- readRDS(path)
    if (mode == "approve") parameter_context_demo_approve(project_dir, snapshot, reviewer,
      "Explicit approval of this displayed synthetic software-control proposal; biological identity remains unresolved.")
    else if (mode == "reject") .parameter_context_helpers$strategy_example_decide(
      project_dir, snapshot, "reject", reviewer, "Reject the displayed proposal without computation.")
    else if (mode == "resume") parameter_context_demo_resume(project_dir, snapshot)
    else parameter_context_demo_unknown(project_dir, snapshot, reviewer)
  }
  # Display/save the fresh result for a later, separately invoked operation.
  # Only an explicit approve command can save an approval.
  invisible(parameter_context_demo_inspect(project_dir, save_snapshot = TRUE))
}

if (sys.nframe() == 0L) parameter_context_demo_main()
