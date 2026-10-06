#!/usr/bin/env Rscript
# Source to work from an existing completed parent. No provider, key read,
# download, install, parent mutation or automatic annotation is performed.
# CLI: Rscript --vanilla subcluster-review.R PARENT CHILD MODE [CLUSTER_IDS...]
# scope [literal IDs...] -> create -> inspect -> approve -> inspect -> continue
# -> inspect -> unknown -> inspect -> approve -> inspect -> continue -> inspect
# -> apply -> output. Decisions always use a previously displayed snapshot.

suppressPackageStartupMessages(library(scAgentKit))
subcluster_example_exports <- c("sc_run_subcluster", "sc_run_subcluster_scope",
  "sc_run_subcluster_inspect", "sc_run_subcluster_unknown", "sc_run_subcluster_apply",
  "sc_run_subcluster_undo", "sc_run_review", "sc_run_continue")
if (!all(subcluster_example_exports %in% getNamespaceExports("scAgentKit")))
  stop("Install this checkout's scoped-subcluster package in the selected R library first.", call. = FALSE)
rm(subcluster_example_exports)

subcluster_example_scope <- function(parent_project, clusters = NULL, cluster_column = NULL) {
  view <- sc_run_subcluster_scope(parent_project, clusters = clusters,
    cluster_column = cluster_column)
  cat("Parent revision:", view$expected_parent_revision, "\n")
  cat("Parent binding:", view$parent_scope_hash, "\n")
  print(view$clusters)
  if (!is.null(view$selected)) print(view$selected)
  invisible(view)
}

subcluster_example_create <- function(parent_project, child_project, parent_snapshot,
                                       reviewer, reason, strategy_proposal = NULL,
                                       choices = list(qc = "retain_selected", doublet = "keep",
                                         batch = "none", cycle = "none", reference = "none"),
                                       cycle_diagnostics = NULL, annotation_column = "sc_subtype",
                                       request_id = "example-create-001") {
  clusters <- unlist(parent_snapshot$selected$clusters, use.names = FALSE)
  if (!is.character(clusters) || !length(clusters))
    stop("Inspect one or more literal parent clusters before creating a child.", call. = FALSE)
  sc_run_subcluster(parent_project, child_project, clusters = clusters,
    parent_scope_hash = parent_snapshot$parent_scope_hash,
    expected_parent_revision = parent_snapshot$expected_parent_revision,
    strategy_proposal = strategy_proposal, choices = choices,
    cycle_diagnostics = cycle_diagnostics, annotation_column = annotation_column,
    reviewer = reviewer, reason = reason, request_id = request_id)
}

subcluster_example_inspect <- function(child_project, column = "sc_subtype",
                                        outside = "NA", supersedes = NULL) {
  view <- sc_run_subcluster_inspect(child_project, column = column,
    outside = outside, supersedes = supersedes)
  run <- view$run
  cat("Child:", run$project_id, "Status:", run$status, "Stage:", run$stage,
    "Revision:", run$revision, "\n")
  cat("Parent current:", view$parent_current, "Integration revision:",
    view$integration_revision, "\n")
  print(view$origin)
  if (!is.null(run$strategy_review)) print(run$strategy_review$details)
  if (!is.null(run$annotation_review)) print(run$annotation_review$details)
  else if (!is.null(run$evidence)) print(run$evidence)
  if (!is.null(run$failure)) print(run$failure)
  if (!is.null(view$parent_error)) print(view$parent_error)
  if (!is.null(view$apply_error)) print(view$apply_error)
  if (!is.null(view$apply_snapshot)) print(view$apply_snapshot)
  if (length(view$applications)) print(view$applications)
  invisible(view)
}

subcluster_example_decide <- function(child_project, snapshot, action, reviewer, reason) {
  if (!is.character(action) || length(action) != 1L ||
      !action %in% c("approve", "reject"))
    stop("Use approve or reject for the displayed whole child review.", call. = FALSE)
  node <- snapshot$run$review_node
  fields <- c("kind", "project_id", "input_hash", "proposal_hash", "review_hash",
    "expected_revision")
  if (is.null(node) || any(!fields %in% names(node)))
    stop("Inspect an actual pending child review first.", call. = FALSE)
  do.call(sc_run_review, c(list(project_dir = child_project, action = action,
    reviewer = reviewer, reason = reason), node[fields]))
}

subcluster_example_continue <- function(child_project, snapshot, retry = FALSE) {
  run <- snapshot$run
  sc_run_continue(child_project, project_id = run$project_id,
    input_hash = run$input_hash, expected_revision = run$revision, retry = retry)
}

subcluster_example_unknown <- function(child_project, snapshot, reviewer, reason,
                                        request_id = "example-unknown-001") {
  run <- snapshot$run
  sc_run_subcluster_unknown(child_project, project_id = run$project_id,
    input_hash = run$input_hash, expected_revision = run$revision,
    reviewer = reviewer, reason = reason, request_id = request_id)
}

subcluster_example_apply <- function(child_project, snapshot, reviewer, reason,
                                      request_id = "example-apply-001") {
  # Display-only counts/output summaries are deliberately not DO.call arguments.
  fields <- c("project_id", "input_hash", "expected_revision", "parent_scope_hash",
    "expected_parent_revision", "annotation_hash", "apply_hash", "column",
    "outside", "supersedes")
  saved <- snapshot$apply_snapshot
  if (is.null(saved) || any(!fields %in% names(saved)))
    stop("Inspect a completed child with its exact apply snapshot first.", call. = FALSE)
  do.call(sc_run_subcluster_apply, c(list(child_project = child_project,
    reviewer = reviewer, reason = reason, request_id = request_id), saved[fields]))
}

subcluster_example_undo <- function(child_project, snapshot, application_id,
                                     reviewer, reason, request_id = "example-undo-001") {
  run <- snapshot$run
  sc_run_subcluster_undo(child_project, application_id = application_id,
    project_id = run$project_id, input_hash = run$input_hash,
    expected_revision = run$revision, integration_revision = snapshot$integration_revision,
    reviewer = reviewer, reason = reason, request_id = request_id)
}

# CLI convenience snapshots live beside the child, never inside the parent.
# They are conveniences, not approval authorities: every public operation
# checks its exact IDs/hashes/revision under the project lock.
subcluster_example_snapshot_dir <- function(child_project) {
  file.path(dirname(path.expand(child_project)),
    paste0(basename(path.expand(child_project)), "-example-snapshots"))
}

subcluster_example_save <- function(child_project, name, value) {
  directory <- subcluster_example_snapshot_dir(child_project)
  if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE))
    stop("Could not create the sibling convenience-snapshot directory.")
  path <- file.path(directory, paste0(name, ".rds"))
  temporary <- tempfile(".subcluster-example-", tmpdir = directory)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(value, temporary)
  if (!file.rename(temporary, path)) stop("Could not atomically save the displayed snapshot.")
  invisible(value)
}

subcluster_example_load <- function(child_project, name) {
  path <- file.path(subcluster_example_snapshot_dir(child_project), paste0(name, ".rds"))
  if (!file.exists(path)) stop("Run scope/inspect and review the displayed snapshot first.")
  readRDS(path)
}

subcluster_example_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  modes <- c("scope", "create", "inspect", "approve", "reject", "continue",
    "unknown", "apply", "undo", "output")
  if (length(args) < 3L || !args[[3L]] %in% modes)
    stop("Usage: subcluster-review.R PARENT CHILD scope|create|inspect|approve|reject|continue|unknown|apply|undo|output [literal cluster IDs for scope; application ID for undo]")
  parent <- args[[1L]]; child <- args[[2L]]; mode <- args[[3L]]
  # Validate the convenience-file boundary before saving even a scope preview.
  # The containing workspace must already exist, as required by creation.
  parent_root <- normalizePath(path.expand(parent), mustWork = TRUE)
  child_parent <- normalizePath(dirname(path.expand(child)), mustWork = TRUE)
  child_root <- file.path(child_parent, basename(path.expand(child)))
  child_link <- Sys.readlink(path.expand(child))
  if (basename(path.expand(child)) %in% c("", ".", "..") ||
      (!is.na(child_link) && nzchar(child_link)) || identical(parent_root, child_root) ||
      startsWith(child_root, paste0(parent_root, "/")) ||
      startsWith(parent_root, paste0(child_root, "/")))
    stop("Use a separate new child directory outside the completed parent.")
  extra <- if (length(args) > 3L) args[seq.int(4L, length(args))] else character()
  if (!mode %in% c("scope", "undo") && length(extra)) stop("This mode accepts no additional arguments.")
  reviewer <- "subcluster-example-analyst"
  if (mode == "scope") {
    view <- subcluster_example_scope(parent, if (length(extra)) extra else NULL)
    return(subcluster_example_save(child, "parent-displayed", view))
  }
  if (mode == "create") {
    parent_view <- subcluster_example_load(child, "parent-displayed")
    subcluster_example_create(parent, child, parent_view, reviewer,
      "Create a separately reviewed raw-count child for these exact displayed parent clusters.")
  } else if (mode == "inspect") {
    view <- subcluster_example_inspect(child)
    return(subcluster_example_save(child, "child-displayed", view))
  } else {
    view <- subcluster_example_load(child, "child-displayed")
    if (mode %in% c("approve", "reject"))
      subcluster_example_decide(child, view, mode, reviewer,
        paste("Explicit", mode, "of the displayed whole child snapshot; biological identities remain the analyst's responsibility."))
    else if (mode == "continue") subcluster_example_continue(child, view)
    else if (mode == "unknown") subcluster_example_unknown(child, view, reviewer,
      "Manual unresolved Unknown/low labels for the actual child clusters; no provider call.")
    else if (mode == "apply") {
      applied <- subcluster_example_apply(child, view, reviewer,
        "Apply the inspected reviewed child annotations to a new parent copy only.")
      subcluster_example_save(child, "latest-output", applied$application)
      cat("New derived parent RDS:", applied$application$output_path, "\n")
    } else if (mode == "undo") {
      if (length(extra) != 1L) stop("Supply one literal application ID to undo.")
      undone <- subcluster_example_undo(child, view, extra[[1L]], reviewer,
        "Withdraw this exact application; keep both parent and derived RDS files.")
      subcluster_example_save(child, "latest-output", undone$undo)
      cat("Restored derived parent RDS:", undone$undo$output_path, "\n")
    } else {
      output <- subcluster_example_load(child, "latest-output")
      cat("Derived parent RDS:", output$output_path, "\n")
      return(invisible(readRDS(output$output_path)))
    }
  }
  invisible(subcluster_example_inspect(child))
}

if (sys.nframe() == 0L) subcluster_example_main()
