#!/usr/bin/env Rscript
# Fixed local IPC: typed data only, no provider or arbitrary R source.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(5L, 6L) || !args[[1L]] %in% c("readiness", "inspect", "resolve", "operation")) quit(status = 2L)
inherit_model <- if (length(args) == 6L) {
  if (!args[[6L]] %in% c("true", "false")) quit(status = 2L)
  identical(args[[6L]], "true")
} else FALSE
operation <- args[[1L]]; parent <- args[[2L]]; workspace <- args[[3L]]
request_file <- args[[4L]]; response_file <- args[[5L]]
suppressPackageStartupMessages(library(scAgentKit))
answer <- tryCatch({
  request <- jsonlite::fromJSON(request_file, simplifyVector = FALSE)
  if (!is.list(request)) stop("Subanalysis request must be a typed object.")
  if (identical(operation, "readiness")) {
    # State and artifact checks remain in the R coordinator. status.json is a
    # convenience projection and must never grant parent write authority.
    run <- tryCatch(scAgentKit::sc_run_inspect(parent), error = identity)
    if (inherits(run, "error")) {
      # Completed source projects can carry a review from an older runtime.
      # The dedicated immutable-source inspector validates them without
      # reopening their scientific approvals under the current runtime.
      checked <- scAgentKit::sc_run_subcluster_scope(parent)
      run <- list(schema = "scagentkit.run.v1", project_id = checked$parent_project_id,
        input_hash = checked$input_hash, status = "complete", stage = "complete",
        revision = checked$expected_parent_revision, output = NULL)
    }
    ready <- identical(run$status, "complete") && identical(run$stage, "complete")
    run <- run[intersect(names(run), c("schema", "project_id", "input_hash", "status", "stage", "revision", "output"))]
    if (!ready) {
      result <- list(schema = "scagentkit.subcluster.bridge.v1", ready = FALSE, parent_run = run,
        parent = list(schema = "scagentkit.subcluster.parent-waiting.v1",
          parent_project_id = run$project_id, expected_parent_revision = run$revision),
        children = list(), child = NULL, child_path = NULL)
    } else {
      scope <- scAgentKit::sc_run_subcluster_scope(parent)
      listing <- scAgentKit::sc_run_subcluster_list(parent, workspace)
      children <- listing$children
      public_children <- lapply(children, function(item) item[setdiff(names(item), c("project_dir", "path", "child_project"))])
      result <- list(schema = "scagentkit.subcluster.bridge.v1", ready = TRUE,
        parent_run = run, parent = scope, children = public_children, child = NULL, child_path = NULL)
    }
    return_value <- list(ok = TRUE, result = result, error = NULL)
  } else {
  scope <- scAgentKit::sc_run_subcluster_scope(parent)
  listing <- scAgentKit::sc_run_subcluster_list(parent, workspace)
  children <- if (is.list(listing) && !is.null(listing$children)) listing$children else listing
  if (!is.list(children)) stop("Child registry is unavailable.")
  context_fields <- c("enabled", "lineage_hint", "identity_status", "tissue", "notes")
  context_edit <- function(checked) {
    run <- checked$run; current <- run$child_context
    valid <- is.list(current) && identical(current$schema, "scagentkit.child-context.v1") &&
      is.character(current$hash) && length(current$hash) == 1L &&
      grepl("^[a-f0-9]{64}$", current$hash) && is.numeric(current$generation) &&
      length(current$generation) == 1L && !is.na(current$generation) && current$generation >= 0
    enabled <- valid && isTRUE(checked$parent_current) && is.null(checked$review_error) &&
      run$stage %in% c("annotation_propose", "annotation_apply") &&
      !run$status %in% c("running", "complete") && !"annotation_apply" %in% unlist(run$completed) &&
      "markers" %in% unlist(run$completed) && is.null(run$output) &&
      identical(run$computed_diagnostics$stage_counts$analysis$status, "saved") && !is.null(run$evidence)
    checked$context_edit <- list(schema = "scagentkit.child-context-edit.v1", enabled = isTRUE(enabled),
      reason = if (isTRUE(enabled)) "Stopped before annotation writeback. Saving changes only soft context and requires fresh annotation and outgoing-payload approvals."
        else "Context is read-only here. Use a current registered child stopped at annotation proposal/application before writeback; undo an executed annotation in R first.",
      allowed_fields = as.list(context_fields), context_hash = if (valid) current$hash else NULL,
      generation = if (valid) current$generation else NULL,
      binding = if (isTRUE(enabled)) list(project_id = run$project_id, input_hash = run$input_hash,
        expected_revision = run$revision, expected_context_hash = current$hash,
        parent_scope_hash = scope$parent_scope_hash, expected_parent_revision = scope$expected_parent_revision) else NULL)
    checked
  }
  context_receipt <- function(path, submitted, checked) {
    # Reuse the coordinator's checksum/history/artifact verification. The JSON
    # history projection is not commit authority and is never used as a receipt.
    get <- function(name) base::get(name, envir = asNamespace("scAgentKit"), inherits = FALSE)
    state_path <- file.path(path, "state.rds")
    before <- get(".sc_project_sha_file")(state_path)
    state <- get(".sc_run_load")(path)
    run <- checked$run
    head <- if (length(state$history)) tail(state$history, 1L)[[1L]]$hash else NULL
    if (!identical(run$project_id, state$project_id) || !identical(run$input_hash, state$input_hash) ||
        !identical(run$revision, state$revision) || !identical(run$history_head, head) ||
        !identical(run$child_context, get(".sc_run_child_context_public")(state$config$annotation_context)))
      stop("Child changed while reading its durable correction receipt; inspect and retry the exact request.")
    core_request <- list(project_id = submitted$project_id, input_hash = submitted$input_hash,
      expected_revision = submitted$expected_revision, expected_context_hash = submitted$expected_context_hash,
      context = submitted$context, reviewer = submitted$reviewer, reason = submitted$reason,
      request_id = submitted$request_id)
    request_hash <- get(".sc_run_hash")(core_request)
    prior <- state$child_context_requests[[submitted$request_id]]
    events <- Filter(function(event) identical(event$action, "child_context_corrected") &&
      identical(event$details$request_id, submitted$request_id), state$history)
    if (!is.list(prior) || !identical(prior$request_hash, request_hash) || length(events) != 1L)
      stop("No unique durable receipt matches this child context correction request.")
    event <- events[[1L]]; details <- event$details
    if (!identical(details$request_hash, request_hash) ||
        !identical(details$previous_context_hash, submitted$expected_context_hash) ||
        !identical(details$context_hash, prior$context_hash) ||
        !identical(details$reviewer, submitted$reviewer) || !identical(details$reason, submitted$reason) ||
        !is.numeric(prior$revision) || length(prior$revision) != 1L || prior$revision <= submitted$expected_revision ||
        !is.numeric(details$generation) || length(details$generation) != 1L || details$generation < 1L ||
        !identical(details$provider_dispatch, "not_sent") ||
        !identical(details$calculation_reused, c("analysis", "markers")))
      stop("Durable child context correction receipt differs from its submitted payload or saved journal.")
    # A replay can refer to an earlier generation. Preserve its historical
    # commit fields instead of presenting the current generation as its result.
    receipt <- list(schema = "scagentkit.child-context-receipt.v1", action = "context", outcome = "committed",
      request_id = submitted$request_id, request_hash = request_hash,
      payload_sha256 = get(".sc_project_sha_file")(request_file),
      project_id = submitted$project_id, input_hash = submitted$input_hash,
      expected_revision = submitted$expected_revision, parent_scope_hash = submitted$parent_scope_hash,
      expected_parent_revision = submitted$expected_parent_revision,
      previous_context_hash = details$previous_context_hash, context_hash = details$context_hash,
      generation = details$generation, committed_revision = prior$revision, context = submitted$context,
      reviewer = details$reviewer, reason = details$reason, journal_event_hash = event$hash,
      is_current = identical(prior$context_hash, run$child_context$hash))
    if (!identical(before, get(".sc_project_sha_file")(state_path)))
      stop("Child changed while reading its durable correction receipt; inspect and retry the exact request.")
    receipt
  }
  resolve <- function(id, column = "sc_subtype", supersedes = NULL) {
    if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) stop("Select a literal child project ID.")
    matches <- Filter(function(item) is.list(item) && identical(item$project_id, id), children)
    if (length(matches) != 1L || !is.character(matches[[1L]]$project_dir) || length(matches[[1L]]$project_dir) != 1L)
      stop("Child project is not uniquely registered to this parent and workspace.")
    path <- matches[[1L]]$project_dir
    if (nzchar(Sys.readlink(path))) stop("Child registry cannot use a symlink.")
    path <- normalizePath(path, mustWork = TRUE)
    if (!identical(dirname(path), normalizePath(workspace, mustWork = TRUE))) stop("Child is outside the immediate workspace.")
    checked <- scAgentKit::sc_run_subcluster_inspect(path, column = column, outside = "NA", supersedes = supersedes)
    if (!identical(checked$run$project_id, id)) stop("Child registry identity does not match its authoritative inspector.")
    list(path = path, inspector = context_edit(checked))
  }
  selected <- NULL; selected_path <- NULL
  if (operation == "operation") {
    action <- request$action; request$action <- NULL
    if (identical(action, "create")) {
      # Stable private name from literal request identity, never a browser path.
      name <- paste0("child-", digest::digest(list(scope$parent_project_id, request$request_id), algo = "sha256"))
      path <- file.path(workspace, name)
      clusters <- request$clusters
      if (!is.list(clusters) || !all(vapply(clusters, function(x) is.character(x) && length(x) == 1L && !is.na(x), logical(1))))
        stop("Cluster selection must contain literal strings.")
      request$clusters <- vapply(clusters, identity, character(1))
      # This flag comes only from fixed server argv, never HTTP data.
      do.call(scAgentKit::sc_run_subcluster, c(list(parent_project = parent, child_project = path,
        inherit_model = inherit_model), request))
      selected <- scAgentKit::sc_run_subcluster_inspect(path)
      selected_path <- path
    } else {
      id <- request$child_id; request$child_id <- NULL
      resolved <- resolve(id); selected_path <- resolved$path
      if (identical(action, "context")) {
        required <- c("reviewer", "reason", "request_id", "project_id", "input_hash", "expected_revision",
          "expected_context_hash", "parent_scope_hash", "expected_parent_revision", "context")
        if (is.null(names(request)) || anyDuplicated(names(request)) || !setequal(names(request), required))
          stop("Child context request has missing or unsupported fields.")
        parent_revision <- request$expected_parent_revision
        if (!is.numeric(parent_revision) || length(parent_revision) != 1L || is.na(parent_revision) ||
            !is.finite(parent_revision) || parent_revision < 0 || parent_revision != floor(parent_revision) ||
            !identical(request$project_id, id) || !isTRUE(resolved$inspector$parent_current) ||
            !identical(request$parent_scope_hash, scope$parent_scope_hash) ||
            !identical(as.numeric(parent_revision), as.numeric(scope$expected_parent_revision)))
          stop("Foreign or stale registered child/parent context scope; inspect before saving.")
        # Fixed arguments call the public R authority. In particular, do not
        # pre-reject its old revision on a retry: R owns exact request_id replay.
        scAgentKit::sc_run_set_child_context(project_dir = selected_path, context = request$context,
          project_id = request$project_id, input_hash = request$input_hash,
          expected_revision = request$expected_revision, expected_context_hash = request$expected_context_hash,
          reviewer = request$reviewer, reason = request$reason, request_id = request$request_id)
        selected <- scAgentKit::sc_run_subcluster_inspect(selected_path)
        selected$context_receipt <- context_receipt(selected_path, request, selected)
      } else {
        fun <- switch(action, unknown = scAgentKit::sc_run_subcluster_unknown,
          apply = scAgentKit::sc_run_subcluster_apply, undo = scAgentKit::sc_run_subcluster_undo,
          stop("Unsupported subanalysis operation."))
        selected <- do.call(fun, c(list(child_project = selected_path), request))
      }
    }
    selected <- context_edit(selected)
    listing <- scAgentKit::sc_run_subcluster_list(parent, workspace)
    children <- if (is.list(listing) && !is.null(listing$children)) listing$children else listing
  } else if (!is.null(request$child_id)) {
    resolved <- resolve(request$child_id, column = if (is.null(request$column)) "sc_subtype" else request$column,
      supersedes = request$supersedes); selected <- resolved$inspector; selected_path <- resolved$path
  }
  # Directory paths are local bridge authority only. Public summaries never
  # become new browser execution or import paths.
  public_children <- lapply(children, function(item) item[setdiff(names(item), c("project_dir", "path", "child_project"))])
  result <- list(schema = "scagentkit.subcluster.bridge.v1", parent = scope,
    children = public_children, child = selected, child_path = selected_path)
  return_value <- list(ok = TRUE, result = result, error = NULL)
  }
  return_value
}, error = function(problem) list(ok = FALSE, result = NULL, error = conditionMessage(problem)))
writeLines(as.character(jsonlite::toJSON(answer, auto_unbox = TRUE, null = "null", na = "null",
  digits = NA, force = TRUE)), response_file, useBytes = TRUE)
quit(status = if (isTRUE(answer$ok)) 0L else 1L)
