#!/usr/bin/env Rscript
# Local CLI only: paths and study facts never come from browser requests.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
request <- jsonlite::fromJSON(args[1], simplifyVector = FALSE)
suppressPackageStartupMessages(library(scAgentKit))
ns <- asNamespace("scAgentKit")
get(".sc_start_runtime_check",ns)(request$runtime,request$checkout)
provider_metadata <- function(root) {
  state <- get(".sc_run_load",ns)(get(".sc_run_root",ns)(root))
  list(name=state$config$provider$name,api_key_env=state$config$provider$api_key_env)
}
input <- readRDS(request$input)
if (inherits(input, "Seurat") && (length(input@reductions) || "seurat_clusters" %in% colnames(input[[]])))
  message("Input contains saved reductions or clusters. They do not establish analysis quality. Selected entry: ", request$entry)
if (file.exists(request$project)) {
  if (!isTRUE(request$reopen)) stop("Use a new project path; open saved projects explicitly.")
  root <- get(".sc_run_root", ns)(request$project)
  state <- get(".sc_run_load", ns)(root)
  if (!identical(state$source$type, "local_rds") ||
      !identical(state$source$path, normalizePath(request$input, mustWork = TRUE)) ||
      !identical(state$source$rds_sha256, get(".sc_project_sha_file", ns)(request$input)))
    stop("Existing project has a different original RDS binding; open the intended project without replacing its input.")
  if (!identical(state$config$start_stage, if (identical(request$entry, "processed")) "processed" else "qc"))
    stop("Existing project entry differs; reopening never replaces its saved configuration.")
  for (field in names(request$context)) if (!identical(request$context[[field]],state$config$context[[field]]))
    stop("Reopening cannot replace saved study facts.")
  if (!identical(request$cluster_column,state$config$cluster_column) ||
      (identical(request$entry,"processed") && !identical(request$processed_reason,state$config$processed_reason)))
    stop("Reopening cannot replace saved reuse settings.")
  view <- scAgentKit::sc_run_inspect(root)
  jsonlite::write_json(list(project_id=view$project_id,status=view$status,stage=view$stage,provider=provider_metadata(root)),args[2],auto_unbox=TRUE)
  quit(status=0L)
}
# Validate counts/layers and declared context before sc_run creates a directory.
# This reads the input only and uses the same scientific input validation.
invisible(get(".sc_run_input", ns)(request$input, context = request$context,
  start_stage = if (identical(request$entry, "processed")) "processed" else "qc",
  processed_reason = if (identical(request$entry, "processed")) request$processed_reason else NULL,
  cluster_column = request$cluster_column))
if (identical(request$entry, "processed")) {
  scAgentKit::sc_run(request$input, request$project, context = request$context,
    start_stage = "processed", processed_reason = request$processed_reason,
    cluster_column = request$cluster_column, provider = NULL, budget = 0)
} else scAgentKit::sc_analyze(request$input, request$project, context = request$context,
  provider = NULL, budget = 0)
view <- scAgentKit::sc_run_inspect(request$project)
jsonlite::write_json(list(project_id = view$project_id, status = view$status, stage = view$stage,
  provider = provider_metadata(request$project)),
  args[2], auto_unbox = TRUE)
