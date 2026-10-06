#!/usr/bin/env Rscript
# Source for your own local inputs; the CLI uses synthetic data only.
# Rscript --vanilla cm2-evidence-review.R PROJECT_DIR demo|inspect|revise|approve|reject|continue|refresh-reference|output
# No provider, credential, download or historical public data is used by the CLI.

suppressPackageStartupMessages(library(scAgentKit))
if (!all(c("sc_run_set_reference", "sc_run_review", "sc_run_continue") %in%
         getNamespaceExports("scAgentKit")))
  stop("Install this checkout's CM2 evidence-review package in the selected R library first.", call. = FALSE)

# A single starting call. reference must be your supplied local reference;
# NULL is valid and leaves that evidence explicitly unavailable.
cm2_evidence_start <- function(input, project_dir, context, reference = NULL,
                               reference_review = list(ai_mode = "independent", top_n = 5L),
                               annotation_history = NULL, start_stage = "processed",
                               processed_reason = NULL, provider = NULL, chat_fn = NULL,
                               budget = 0, review = list(allow_external = FALSE), ...) {
  sc_run(input, project_dir, context = context, reference = reference,
    reference_review = reference_review, annotation_history = annotation_history,
    start_stage = start_stage, processed_reason = processed_reason,
    provider = provider, chat_fn = chat_fn, budget = budget, review = review, ...)
}

# Caller-extracted historical rows are evidence, not a current typed proposal.
# The coordinator checks local JSON bytes and source cell/cluster scope.
cm2_evidence_history <- function(annotations, response_paths, source_object_path,
                                 provider, model, reference_dependency = "unknown",
                                 source_cluster_column = "seurat_clusters",
                                 note = "Caller-extracted historical rows; no new model request.") {
  list(annotations = annotations, response_paths = response_paths,
    source_object_path = source_object_path, source_cluster_column = source_cluster_column,
    provider = provider, model = model, reference_dependency = reference_dependency,
    note = note)
}

cm2_evidence_unknown <- function(snapshot,
  rationale = "Manual review retains unresolved identity; no biological label is accepted.") {
  if (!identical(snapshot$stage, "annotation_propose"))
    stop("Inspect saved annotation evidence at annotation_propose first.", call. = FALSE)
  clusters <- if (!is.null(snapshot$annotation_review))
    snapshot$annotation_review$details$annotations else snapshot$evidence$clusters
  if (!length(clusters)) stop("Saved annotation cluster scope is unavailable.", call. = FALSE)
  list(schema = "scagentkit.annotation.v1", annotations = lapply(clusters, function(row)
    list(clusterId = row$clusterId, label = "Unknown", confidence = "low",
      rationale = rationale, markers = list())))
}

cm2_evidence_inspect <- function(project_dir, save_snapshot = TRUE) {
  current <- sc_run_inspect(project_dir)
  cat("Status:", current$status, "Stage:", current$stage, "Revision:", current$revision, "\n")
  if (!is.null(current$annotation_review)) {
    details <- current$annotation_review$details
    cat("Current proposal source:", details$source$kind, "\n")
    cat("Exact scope:", details$cell_count, "cells;", details$cluster_count, "clusters.\n")
    for (row in details$annotations) {
      cat("\nLiteral cluster:", row$clusterId, "Cells:", row$cell_count, "\n")
      print(row$proposal)
      cat("Saved supplied marker statistics:\n"); print(row$supplied_marker_stats)
      cat("Local database, current proposal, historical source and comparison:\n")
      print(row$joint_evidence)
    }
    cat("\nConfidence is qualitative; coverage scores are not probabilities.\n")
    cat("Missing markers do not establish absent expression.\n")
  } else if (!is.null(current$evidence)) {
    cat("Evidence saved; supply a typed proposal if configuration is needed:\n")
    print(current$evidence)
  }
  if (!is.null(current$review_node)) print(current$review_node)
  if (!is.null(current$output)) print(current$output)
  if (isTRUE(save_snapshot)) {
    path <- file.path(project_dir, "cm2-example-reviewed-snapshot.rds")
    temporary <- tempfile(".cm2-example-snapshot-", tmpdir = project_dir)
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(current, temporary)
    if (!file.rename(temporary, path)) stop("Cannot save the displayed snapshot.", call. = FALSE)
    cat("Displayed convenience snapshot saved; it is separate from authoritative state.\n")
  }
  invisible(current)
}

cm2_evidence_decide <- function(project_dir, snapshot, action, reviewer, reason,
                                proposal = NULL) {
  node <- snapshot$review_node
  if (is.null(node) || !identical(node$kind, "annotation"))
    stop("Inspect an annotation review snapshot before deciding.", call. = FALSE)
  arguments <- c(list(project_dir = project_dir, action = action,
    reviewer = reviewer, reason = reason),
    node[c("kind", "project_id", "input_hash", "proposal_hash", "review_hash", "expected_revision")])
  if (!is.null(proposal)) arguments$proposal <- proposal
  do.call(sc_run_review, arguments)
}

cm2_evidence_continue <- function(project_dir, snapshot, retry = FALSE) {
  sc_run_continue(project_dir, project_id = snapshot$project_id,
    input_hash = snapshot$input_hash, expected_revision = snapshot$revision, retry = retry)
}

cm2_evidence_set_reference <- function(project_dir, reference, snapshot, reviewer,
                                       reason, reference_review = NULL,
                                       annotation_history = NULL) {
  arguments <- list(project_dir = project_dir, reference = reference,
    project_id = snapshot$project_id, input_hash = snapshot$input_hash,
    expected_revision = snapshot$revision, reviewer = reviewer, reason = reason,
    reference_review = reference_review)
  # Omission and an explicit NULL may have different update meanings.
  if (!missing(annotation_history)) arguments$annotation_history <- annotation_history
  do.call(sc_run_set_reference, arguments)
}

.cm2_evidence_demo_reference <- function() {
  # Planted software-program features; this is not a CellMarker database subset.
  reference <- data.frame(cell_type = rep(c("Toy program A", "Toy program B", "Toy program C"), each = 4),
    marker = paste0("MARK-", rep(c("A", "B", "C"), each = 4), rep(1:4, 3)),
    tissue = "synthetic planted programs", species = "human",
    source = "synthetic software fixture", stringsAsFactors = FALSE)
  reference
}

.cm2_evidence_demo_options <- function(top_n = 5L) {
  list(ai_mode = "independent", top_n = top_n,
    symbol_aliases = stats::setNames(character(), character()),
    label_map = stats::setNames(character(), character()),
    label_relations = data.frame(child = character(), parent = character(),
      lineage = character(), stringsAsFactors = FALSE),
    provenance = list(version = "synthetic-fixture-v1", license = "synthetic example only",
      preparation_note = "Planted toy programs; not CellMarker data or biological identities."))
}

cm2_evidence_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("demo", "inspect", "revise", "approve", "reject", "continue", "refresh-reference", "output")
  if (length(args) != 2L || !args[[2L]] %in% modes)
    stop("Usage: cm2-evidence-review.R PROJECT_DIR demo|inspect|revise|approve|reject|continue|refresh-reference|output", call. = FALSE)
  project_dir <- args[[1L]]; mode <- args[[2L]]
  snapshot_path <- file.path(project_dir, "cm2-example-reviewed-snapshot.rds")
  reviewer <- "synthetic-example-analyst"
  if (mode == "demo") {
    helper_path <- system.file("examples", "annotation-review.R", package = "scAgentKit")
    if (!nzchar(helper_path)) stop("Install the bundled processed synthetic input example.", call. = FALSE)
    helper <- new.env(parent = globalenv()); sys.source(helper_path, envir = helper)
    input <- helper$make_annotation_review_input()
    original_hash <- digest::digest(input, algo = "sha256")
    cm2_evidence_start(input, project_dir,
      context = list(species = "human", tissue = "synthetic planted programs",
        columns = list(sample = "sample_id", capture = "capture_id", condition = "condition"),
        notes = "Synthetic planted programs only; no CellMarker or historical model response, no donor inference and no automatic batch integration."),
      reference = .cm2_evidence_demo_reference(), reference_review = .cm2_evidence_demo_options(),
      start_stage = "processed", cluster_column = "toy_cluster",
      processed_reason = "Reuse the processed synthetic input generated before coordinator entry; preserve its explicit toy cluster membership.",
      annotation_column = "cm2_reviewed_identity")
    stopifnot(identical(original_hash, digest::digest(input, algo = "sha256")))
    current <- sc_run_inspect(project_dir)
    sc_run_propose(project_dir, cm2_evidence_unknown(current), reviewer = reviewer,
      reason = "Manual Unknown synthetic proposal; no model request or external transmission.")
  } else if (mode == "inspect") return(cm2_evidence_inspect(project_dir))
  else if (mode == "output") {
    current <- sc_run_inspect(project_dir)
    if (!identical(current$status, "complete")) stop("Approve and Continue before reading final output.", call. = FALSE)
    final <- readRDS(current$output$seurat)
    cat("Final object:", current$output$seurat, "\n")
    print(table(final$cm2_reviewed_identity))
    return(invisible(final))
  } else {
    if (!file.exists(snapshot_path)) stop("Inspect and review the project before this operation.", call. = FALSE)
    snapshot <- readRDS(snapshot_path)
    if (mode == "continue") cm2_evidence_continue(project_dir, snapshot)
    else if (mode == "refresh-reference") {
      cm2_evidence_set_reference(project_dir, .cm2_evidence_demo_reference(), snapshot,
        reviewer = reviewer, reason = "Explicit synthetic candidate-count update; revoke the old annotation approval.",
        reference_review = .cm2_evidence_demo_options(top_n = 3L))
      cat("Reference update saved. Inspect the new evidence and proposal before deciding.\n")
    } else if (mode == "revise") {
      cm2_evidence_decide(project_dir, snapshot, "revise", reviewer,
        reason = "Keep unresolved synthetic identities after reviewing the local candidate evidence.",
        proposal = cm2_evidence_unknown(snapshot,
          rationale = "Reviewed the supplied toy markers and local reference; biological identity remains unresolved."))
      cat("Revision saved. Inspect its fresh snapshot before approval.\n")
    } else cm2_evidence_decide(project_dir, snapshot, mode, reviewer,
      reason = if (mode == "approve") "Approve this exact whole synthetic Unknown proposal and its evidence limitations."
        else "Reject this exact synthetic proposal; do not apply labels.")
  }
  invisible(cm2_evidence_inspect(project_dir, save_snapshot = FALSE))
}

if (sys.nframe() == 0L) cm2_evidence_main()
